-- =============================================================================
-- Ubuntu/Unhu Rise Foundation — Management & Impact System
-- Migration 0001: Foundation schema (spine + first vertical slice)
--
-- Covers: RBAC, audit logging, reference-code generation, beneficiaries,
--         households, guardians, institutions, needs assessments, documents.
--
-- Deliberately NOT covered yet: donors, donations, projects, volunteers,
--         events, finance. Those come after this slice works end to end.
--
-- Target: PostgreSQL 15+ (Supabase-compatible)
-- =============================================================================

create extension if not exists "pgcrypto";
create extension if not exists "citext";

-- Separate schemas enforce separation of concerns at the database level.
-- `safeguarding` is isolated so that a bug in ordinary application queries
-- cannot reach child-protection records.
create schema if not exists app;
create schema if not exists audit;
create schema if not exists safeguarding;


-- =============================================================================
-- SECTION 1 — REFERENCE CODE GENERATION  (UBF-BEN-000001 etc.)
-- =============================================================================

create table app.ref_sequence (
  prefix       text primary key,          -- 'BEN', 'DON', 'INS', ...
  last_value   bigint not null default 0
);

insert into app.ref_sequence (prefix) values
  ('BEN'), ('DON'), ('VOL'), ('PRJ'), ('GFT'),
  ('INS'), ('EVT'), ('ASM'), ('SAF'), ('HHD')
on conflict do nothing;

-- Atomic; safe under concurrency. Gaps are possible on rollback, which is fine —
-- these are human-facing identifiers, not an accounting sequence.
create or replace function app.next_ref(p_prefix text)
returns text
language plpgsql
as $$
declare
  v_next bigint;
begin
  update app.ref_sequence
     set last_value = last_value + 1
   where prefix = p_prefix
  returning last_value into v_next;

  if v_next is null then
    raise exception 'Unknown reference prefix: %', p_prefix;
  end if;

  return format('UBF-%s-%s', p_prefix, lpad(v_next::text, 6, '0'));
end;
$$;


-- =============================================================================
-- SECTION 2 — IDENTITY, ROLES AND PERMISSIONS
--
-- Permissions live in DATA, not code. Adding a role or changing the access
-- matrix must never require a redeploy.
-- =============================================================================

-- Mirrors Supabase auth.users. If you are not on Supabase, add a
-- password_hash column here and manage credentials yourself.
create table app.user_profile (
  id                uuid primary key,             -- = auth.users.id
  email             citext not null unique,
  full_name         text not null,
  phone             text,
  job_title         text,
  is_active         boolean not null default true,
  mfa_enrolled      boolean not null default false,
  last_login_at     timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);

create table app.role (
  id           uuid primary key default gen_random_uuid(),
  code         text not null unique,     -- 'super_admin', 'safeguarding_officer'
  name         text not null,
  description  text,
  is_system    boolean not null default false,  -- system roles cannot be deleted
  created_at   timestamptz not null default now()
);

insert into app.role (code, name, is_system) values
  ('super_admin',           'Super Administrator',   true),
  ('executive',             'Executive / Board',     true),
  ('foundation_admin',      'Foundation Administrator', true),
  ('program_officer',       'Program Officer',       true),
  ('safeguarding_officer',  'Safeguarding Officer',  true),
  ('finance_officer',       'Finance Officer',       true),
  ('volunteer_coordinator', 'Volunteer Coordinator', true),
  ('comms_officer',         'Communications Officer',true),
  ('field_officer',         'Field Officer',         true)
on conflict do nothing;

-- A permission is a (resource, action) pair: 'beneficiary' + 'read'.
-- Scope narrows it: 'all' | 'assigned' | 'none'.
create table app.permission (
  id           uuid primary key default gen_random_uuid(),
  resource     text not null,   -- 'beneficiary', 'donation', 'safeguarding_case'
  action       text not null,   -- 'create','read','update','delete','export','approve'
  description  text,
  unique (resource, action)
);

create table app.role_permission (
  role_id        uuid not null references app.role(id) on delete cascade,
  permission_id  uuid not null references app.permission(id) on delete cascade,
  scope          text not null default 'all'
                 check (scope in ('all','assigned','own')),
  primary key (role_id, permission_id)
);

create table app.user_role (
  user_id     uuid not null references app.user_profile(id) on delete cascade,
  role_id     uuid not null references app.role(id) on delete cascade,
  granted_by  uuid references app.user_profile(id),
  granted_at  timestamptz not null default now(),
  primary key (user_id, role_id)
);

-- Single source of truth for "can this user do this?".
-- Call it from application code AND from RLS policies so the two never diverge.
create or replace function app.has_permission(
  p_user_id  uuid,
  p_resource text,
  p_action   text
) returns boolean
language sql
stable
as $$
  select exists (
    select 1
      from app.user_role ur
      join app.role_permission rp on rp.role_id = ur.role_id
      join app.permission p       on p.id = rp.permission_id
      join app.user_profile up    on up.id = ur.user_id
     where ur.user_id  = p_user_id
       and p.resource  = p_resource
       and p.action    = p_action
       and up.is_active
       and up.deleted_at is null
  );
$$;


-- =============================================================================
-- SECTION 3 — AUDIT LOG
--
-- Attached as a trigger so it cannot be forgotten. Hand-written audit calls in
-- route handlers WILL be missed, and the missed ones are always the ones that
-- matter in an investigation.
-- =============================================================================

create table audit.log (
  id            bigserial primary key,
  occurred_at   timestamptz not null default now(),
  actor_id      uuid,                    -- null for system/migration actions
  actor_email   text,
  action        text not null,           -- INSERT | UPDATE | DELETE | READ
  schema_name   text not null,
  table_name    text not null,
  record_id     text,
  record_ref    text,                    -- UBF-BEN-000124, for human search
  changed       jsonb,                   -- only the fields that actually changed
  ip_address    inet,
  user_agent    text
);

create index on audit.log (occurred_at desc);
create index on audit.log (table_name, record_id);
create index on audit.log (actor_id, occurred_at desc);
create index on audit.log (record_ref);

-- Nobody edits the audit log. Not even super_admin.
revoke update, delete on audit.log from public;

-- The application must set these per request/transaction:
--   select set_config('app.actor_id',    $1, true);
--   select set_config('app.actor_email', $2, true);
--   select set_config('app.ip_address',  $3, true);
create or replace function audit.current_actor() returns uuid
language sql stable as $$
  select nullif(current_setting('app.actor_id', true), '')::uuid;
$$;

create or replace function audit.track_changes()
returns trigger
language plpgsql
security definer
as $$
declare
  v_changed jsonb;
  v_id      text;
  v_ref     text;
begin
  if tg_op = 'UPDATE' then
    -- Record only the fields that genuinely changed.
    select jsonb_object_agg(key, jsonb_build_object('from', old_j.value, 'to', new_j.value))
      into v_changed
      from jsonb_each(to_jsonb(old)) old_j
      join jsonb_each(to_jsonb(new)) new_j using (key)
     where old_j.value is distinct from new_j.value
       and key not in ('updated_at');

    if v_changed is null then
      return new;  -- nothing meaningful changed; don't log noise
    end if;
  elsif tg_op = 'INSERT' then
    v_changed := to_jsonb(new);
  else
    v_changed := to_jsonb(old);
  end if;

  v_id  := coalesce(to_jsonb(new)->>'id',  to_jsonb(old)->>'id');
  v_ref := coalesce(to_jsonb(new)->>'ref', to_jsonb(old)->>'ref');

  insert into audit.log (
    actor_id, actor_email, action, schema_name, table_name,
    record_id, record_ref, changed, ip_address
  ) values (
    audit.current_actor(),
    nullif(current_setting('app.actor_email', true), ''),
    tg_op, tg_table_schema, tg_table_name,
    v_id, v_ref, v_changed,
    nullif(current_setting('app.ip_address', true), '')::inet
  );

  return coalesce(new, old);
end;
$$;

-- Convenience: attach auditing to a table in one line.
create or replace function audit.attach(p_schema text, p_table text)
returns void
language plpgsql
as $$
begin
  execute format(
    'create trigger trg_audit_%1$s
       after insert or update or delete on %2$I.%1$I
       for each row execute function audit.track_changes()',
    p_table, p_schema
  );
end;
$$;


-- =============================================================================
-- SECTION 4 — GEOGRAPHY
-- Kept as a lookup rather than free text so equality reporting can actually
-- group by district without fighting typos.
-- =============================================================================

create table app.province (
  id    smallint primary key,
  name  text not null unique
);

insert into app.province (id, name) values
  (1,'Bulawayo'), (2,'Harare'), (3,'Manicaland'), (4,'Mashonaland Central'),
  (5,'Mashonaland East'), (6,'Mashonaland West'), (7,'Masvingo'),
  (8,'Matabeleland North'), (9,'Matabeleland South'), (10,'Midlands')
on conflict do nothing;

create table app.district (
  id           serial primary key,
  province_id  smallint not null references app.province(id),
  name         text not null,
  unique (province_id, name)
);


-- =============================================================================
-- SECTION 5 — HOUSEHOLDS AND GUARDIANS
-- Households come BEFORE beneficiaries: a child is understood in context,
-- and this is what prevents duplicate sibling records.
-- =============================================================================

create table app.household (
  id                    uuid primary key default gen_random_uuid(),
  ref                   text not null unique default app.next_ref('HHD'),
  head_name             text not null,
  province_id           smallint references app.province(id),
  district_id           integer  references app.district(id),
  community             text,
  address               text,
  phone                 text,
  economic_status       text check (economic_status in
                          ('no_income','irregular_income','informal_trade',
                           'formal_employment','pension','other','unknown')),
  vulnerability_notes   text,
  assigned_officer_id   uuid references app.user_profile(id),
  created_by            uuid references app.user_profile(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  deleted_at            timestamptz
);

create table app.guardian (
  id             uuid primary key default gen_random_uuid(),
  household_id   uuid references app.household(id) on delete set null,
  full_name      text not null,
  relationship   text,        -- mother, father, grandmother, aunt, guardian...
  phone          text,
  email          citext,
  national_id    text,        -- consider encrypting; see notes at end of file
  is_primary     boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

create index on app.guardian (household_id);


-- =============================================================================
-- SECTION 6 — INSTITUTIONS
-- =============================================================================

create table app.institution (
  id                  uuid primary key default gen_random_uuid(),
  ref                 text not null unique default app.next_ref('INS'),
  name                text not null,
  type                text not null check (type in
                        ('childrens_home','orphanage','school','clinic',
                         'community_org','church','ngo','government','corporate')),
  province_id         smallint references app.province(id),
  district_id         integer  references app.district(id),
  address             text,
  contact_person      text,
  phone               text,
  email               citext,
  beneficiary_count   integer check (beneficiary_count >= 0),
  main_needs          text,
  partnership_status  text not null default 'prospective' check (partnership_status in
                        ('prospective','under_assessment','active','paused','ended')),
  first_visited_on    date,
  last_assessed_on    date,
  next_followup_on    date,
  notes               text,
  created_by          uuid references app.user_profile(id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz
);

create index on app.institution (partnership_status) where deleted_at is null;
create index on app.institution (next_followup_on) where deleted_at is null;


-- =============================================================================
-- SECTION 7 — BENEFICIARIES
--
-- Gender is recorded for EQUALITY MONITORING ONLY (PRD §10). Nothing in this
-- schema or the application above it may use gender to gate eligibility.
-- =============================================================================

create table app.beneficiary (
  id                 uuid primary key default gen_random_uuid(),
  ref                text not null unique default app.next_ref('BEN'),

  first_name         text not null,
  surname            text not null,
  preferred_name     text,
  date_of_birth      date not null,
  gender             text not null check (gender in ('female','male','other','undisclosed')),

  has_disability     boolean not null default false,
  disability_notes   text,

  household_id       uuid references app.household(id) on delete set null,
  institution_id     uuid references app.institution(id) on delete set null,

  school_name        text,
  grade              text,

  province_id        smallint references app.province(id),
  district_id        integer  references app.district(id),
  community          text,

  emergency_contact_name  text,
  emergency_contact_phone text,

  enrolled_on        date not null default current_date,
  status             text not null default 'registered' check (status in
                       ('registered','verified','active','temporarily_inactive',
                        'referred','graduated','relocated','closed')),
  status_changed_at  timestamptz,
  exit_reason        text,

  consent_on_file    boolean not null default false,
  consent_document_id uuid,          -- FK added after app.document is created
  consent_given_by   text,           -- name of guardian who consented
  consent_date       date,

  assigned_officer_id uuid references app.user_profile(id),
  created_by         uuid references app.user_profile(id),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,

  -- A child cannot be enrolled before they were born, and cannot be over 25.
  constraint dob_sane check (date_of_birth > current_date - interval '25 years'
                             and date_of_birth <= current_date)
);

create index on app.beneficiary (household_id);
create index on app.beneficiary (institution_id);
create index on app.beneficiary (status) where deleted_at is null;
create index on app.beneficiary (assigned_officer_id) where deleted_at is null;

-- Fuzzy duplicate detection: same name + same DOB is almost always the same child.
create index on app.beneficiary (lower(first_name), lower(surname), date_of_birth)
  where deleted_at is null;

create or replace view app.beneficiary_with_age as
  select b.*,
         extract(year from age(b.date_of_birth))::int as age
    from app.beneficiary b
   where b.deleted_at is null;


-- =============================================================================
-- SECTION 8 — NEEDS ASSESSMENTS
-- =============================================================================

create table app.need_category (
  code   text primary key,
  label  text not null,
  sort   smallint not null default 0
);

insert into app.need_category (code, label, sort) values
  ('food','Food',1), ('clothing','Clothing',2), ('bedding','Bedding',3),
  ('education','Education',4), ('school_fees','School Fees',5),
  ('uniforms','Uniforms',6), ('stationery','Stationery',7),
  ('toiletries','Toiletries',8), ('medical','Medical Assistance',9),
  ('infrastructure','Infrastructure',10), ('mentorship','Mentorship',11),
  ('counselling','Counselling',12), ('child_protection','Child Protection',13),
  ('recreation','Recreation',14), ('other','Other',15)
on conflict do nothing;

create table app.assessment (
  id                 uuid primary key default gen_random_uuid(),
  ref                text not null unique default app.next_ref('ASM'),
  institution_id     uuid references app.institution(id) on delete set null,
  household_id       uuid references app.household(id) on delete set null,
  assessed_on        date not null default current_date,
  assessor_id        uuid not null references app.user_profile(id),
  summary            text,
  recommended_action text,
  estimated_cost     numeric(14,2),
  currency           char(3) not null default 'USD',
  followup_on        date,
  status             text not null default 'draft' check (status in
                       ('draft','submitted','reviewed','actioned','closed')),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,

  -- An assessment must be anchored to something.
  constraint assessment_target check (
    institution_id is not null or household_id is not null
  )
);

create index on app.assessment (institution_id);
create index on app.assessment (status, followup_on);

create table app.assessment_need (
  id             uuid primary key default gen_random_uuid(),
  assessment_id  uuid not null references app.assessment(id) on delete cascade,
  category_code  text not null references app.need_category(code),
  priority       text not null check (priority in ('critical','high','medium','low')),
  detail         text,
  quantity       numeric(12,2),
  unit           text,
  estimated_cost numeric(14,2),
  is_resolved    boolean not null default false,
  resolved_at    timestamptz,
  unique (assessment_id, category_code)
);


-- =============================================================================
-- SECTION 9 — DOCUMENTS
-- Files live in object storage (Supabase Storage / S3). This table holds the
-- pointer and, critically, the sensitivity classification.
-- =============================================================================

create table app.document (
  id             uuid primary key default gen_random_uuid(),
  storage_path   text not null unique,
  filename       text not null,
  mime_type      text,
  size_bytes     bigint,
  doc_type       text not null check (doc_type in
                   ('consent_form','assessment','agreement','receipt','proposal',
                    'report','minutes','photo','certificate','correspondence','other')),
  sensitivity    text not null default 'internal' check (sensitivity in
                   ('public','internal','confidential','restricted')),

  -- Polymorphic attachment. Kept deliberately loose so documents can hang off
  -- any record without a join table per entity.
  entity_type    text not null,   -- 'beneficiary','institution','assessment',...
  entity_id      uuid not null,

  uploaded_by    uuid not null references app.user_profile(id),
  uploaded_at    timestamptz not null default now(),
  expires_on     date,            -- drives the "expiring documents" notification
  deleted_at     timestamptz
);

create index on app.document (entity_type, entity_id);
create index on app.document (expires_on) where deleted_at is null;

alter table app.beneficiary
  add constraint beneficiary_consent_doc_fk
  foreign key (consent_document_id) references app.document(id) on delete set null;


-- =============================================================================
-- SECTION 10 — SAFEGUARDING (isolated schema)
--
-- Read access is logged here, not just writes. Knowing WHO LOOKED at a case is
-- as important as knowing who edited it.
-- =============================================================================

create table safeguarding.case (
  id                  uuid primary key default gen_random_uuid(),
  ref                 text not null unique default app.next_ref('SAF'),
  beneficiary_id      uuid references app.beneficiary(id) on delete restrict,
  reported_on         date not null default current_date,
  occurred_on         date,
  location            text,
  category            text not null,
  risk_level          text not null check (risk_level in ('critical','high','medium','low')),
  description         text not null,
  immediate_action    text,
  referred_to         text,
  responsible_officer_id uuid not null references app.user_profile(id),
  followup_on         date,
  resolution          text,
  status              text not null default 'open' check (status in
                        ('open','under_investigation','referred','monitoring','closed')),
  closed_on           date,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
  -- Note: no deleted_at. Safeguarding records are never deleted.
);

create table safeguarding.access_log (
  id          bigserial primary key,
  case_id     uuid not null references safeguarding.case(id),
  user_id     uuid not null references app.user_profile(id),
  accessed_at timestamptz not null default now(),
  ip_address  inet
);

create index on safeguarding.access_log (case_id, accessed_at desc);


-- =============================================================================
-- SECTION 11 — updated_at maintenance + attach auditing
-- =============================================================================

create or replace function app.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- The table_type filter is essential: app.beneficiary_with_age is a view built
-- from `select b.*`, so it inherits an updated_at column. Views cannot carry
-- row-level triggers, and without this filter the loop fails on it.
do $$
declare
  r record;
begin
  for r in
    select c.table_schema, c.table_name
      from information_schema.columns c
      join information_schema.tables  t
        on t.table_schema = c.table_schema
       and t.table_name   = c.table_name
     where c.column_name  = 'updated_at'
       and c.table_schema in ('app','safeguarding')
       and t.table_type   = 'BASE TABLE'
  loop
    execute format(
      'create trigger trg_touch_%1$s before update on %2$I.%1$I
         for each row execute function app.touch_updated_at()',
      r.table_name, r.table_schema);

    perform audit.attach(r.table_schema, r.table_name);
  end loop;
end;
$$;


-- =============================================================================
-- NOTES FOR THE NEXT MIGRATION
-- =============================================================================
--
-- 1. SEED THE PERMISSION MATRIX. Section 30 of the PRD becomes rows in
--    app.permission and app.role_permission. Write it as a data migration so
--    the matrix is version-controlled and reviewable.
--
-- 2. ENABLE RLS on every table in `app` and `safeguarding`, with policies
--    calling app.has_permission(). Application-level checks remain primary;
--    RLS is the safety net.
--
-- 3. FIELD-LEVEL ENCRYPTION for guardian.national_id and
--    safeguarding.case.description. Use pgsodium or encrypt in the application
--    before insert. Do not store these in plaintext once real data arrives.
--
-- 4. CONSENT WORKFLOW. Zimbabwe's Data Protection Act (Ch. 11:12) applies to
--    this data. beneficiary.status should not be allowed to reach 'active'
--    while consent_on_file is false — enforce that in a trigger once the
--    workflow is settled.
--
-- 5. NEXT ENTITIES, in order: programs -> projects -> enrollments ->
--    donors -> donations -> distributions. Enrollment is the join that makes
--    equality reporting possible, so do not skip it.
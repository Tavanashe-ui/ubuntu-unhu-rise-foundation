-- =============================================================================
-- Ubuntu/Unhu Rise Foundation
-- Migration 0005: Row-Level Security
--
-- Until now the permission matrix has been descriptive — a table the app could
-- consult. This migration makes it ENFORCING. After this, a query that violates
-- the matrix returns no rows, regardless of what the application code intended.
--
-- Application-level checks remain the primary mechanism because they produce
-- good error messages. This is the layer that catches the bug in those checks.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Fix the audit actor
--
-- audit.current_actor() read a session variable the app had to set on every
-- request — easy to forget, and silently null when forgotten. Supabase gives us
-- auth.uid() from the verified JWT instead: always present, impossible to spoof.
-- -----------------------------------------------------------------------------

create or replace function audit.current_actor()
returns uuid
language plpgsql
stable
as $$
declare
  v_actor uuid;
begin
  -- Explicit override first (used by server-side jobs and data migrations).
  v_actor := nullif(current_setting('app.actor_id', true), '')::uuid;
  if v_actor is not null then
    return v_actor;
  end if;

  -- Otherwise the authenticated caller.
  begin
    v_actor := auth.uid();
  exception when others then
    v_actor := null;   -- auth schema absent (e.g. local psql) — not an error
  end;

  return v_actor;
end;
$$;


-- -----------------------------------------------------------------------------
-- 2. The scope gate
--
-- One function decides every row-level question in the system. Policies call it;
-- application code calls it. There is exactly one place to audit, and one place
-- to fix if it is wrong.
--
--   all      -> every row
--   assigned -> rows where the caller is the assigned officer, or created it
--   own      -> rows the caller created
--   summary  -> no rows at all (aggregate access is via functions, not tables)
-- -----------------------------------------------------------------------------

create or replace function app.may(
  p_resource   text,
  p_action     text,
  p_assigned   uuid default null,
  p_created_by uuid default null
) returns boolean
language plpgsql
stable
security definer
set search_path = app, public
as $$
declare
  v_uid   uuid := auth.uid();
  v_scope text;
begin
  if v_uid is null then
    return false;
  end if;

  v_scope := app.permission_scope(v_uid, p_resource, p_action);

  if v_scope is null then
    return false;              -- no grant at all
  end if;

  return case v_scope
    when 'all'      then true
    when 'assigned' then (p_assigned = v_uid or p_created_by = v_uid)
    when 'own'      then (p_created_by = v_uid)
    when 'summary'  then false -- counts only; never row content
    else false
  end;
end;
$$;

grant execute on function app.may(text, text, uuid, uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 3. Expose the app schema to the API
--
-- The safeguarding schema is deliberately NOT exposed and must never be added
-- here. Child-protection records are reached only through purpose-built
-- functions that log every read.
-- -----------------------------------------------------------------------------

grant usage on schema app to authenticated;

grant select, insert, update on
  app.household, app.guardian, app.beneficiary, app.institution,
  app.assessment, app.assessment_need, app.document
to authenticated;

grant select on
  app.province, app.district, app.need_category, app.role
to authenticated;

-- Sequences used by default values
grant usage on all sequences in schema app to authenticated;

-- next_ref() must run as owner: it writes to app.ref_sequence, which callers
-- have no rights on.
grant execute on function app.next_ref(text) to authenticated;
alter function app.next_ref(text) security definer;


-- -----------------------------------------------------------------------------
-- 4. Enable RLS
--
-- Enabling without policies denies everything. Policies follow immediately.
-- -----------------------------------------------------------------------------

alter table app.household       enable row level security;
alter table app.guardian        enable row level security;
alter table app.beneficiary     enable row level security;
alter table app.institution     enable row level security;
alter table app.assessment      enable row level security;
alter table app.assessment_need enable row level security;
alter table app.document        enable row level security;
alter table app.province        enable row level security;
alter table app.district        enable row level security;
alter table app.need_category   enable row level security;
alter table app.role            enable row level security;
alter table app.user_profile    enable row level security;
alter table app.user_role       enable row level security;

-- Belt and braces: RLS on the safeguarding tables too, even though the schema
-- is not exposed. Two independent barriers, not one.
alter table safeguarding.case       enable row level security;
alter table safeguarding.access_log enable row level security;


-- -----------------------------------------------------------------------------
-- 5. Reference data — readable by any authenticated user
--
-- Province lists and need categories are not sensitive, and every form needs
-- them. No write policies: these change by migration, not by user.
-- -----------------------------------------------------------------------------

create policy ref_read on app.province
  for select to authenticated using (true);

create policy ref_read on app.district
  for select to authenticated using (true);

create policy ref_read on app.need_category
  for select to authenticated using (true);

create policy ref_read on app.role
  for select to authenticated using (true);


-- -----------------------------------------------------------------------------
-- 6. Identity — you may always read yourself
-- -----------------------------------------------------------------------------

create policy self_read on app.user_profile
  for select to authenticated
  using (id = auth.uid() or app.may('user', 'read'));

create policy self_update on app.user_profile
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy own_roles_read on app.user_role
  for select to authenticated
  using (user_id = auth.uid() or app.may('user', 'read'));


-- -----------------------------------------------------------------------------
-- 7. Operational tables
--
-- Pattern is identical throughout:
--   SELECT / UPDATE  -> USING clause, evaluated against the existing row
--   INSERT           -> WITH CHECK, evaluated against the proposed row
--
-- Soft-deleted rows are hidden from everyone except those with 'all' scope, so
-- an officer's list never shows records that were removed from their caseload.
-- -----------------------------------------------------------------------------

-- ---------- HOUSEHOLD ----------
create policy hh_select on app.household
  for select to authenticated
  using (
    app.may('household', 'read', assigned_officer_id, created_by)
    and (deleted_at is null or app.permission_scope(auth.uid(),'household','read') = 'all')
  );

create policy hh_insert on app.household
  for insert to authenticated
  with check (app.may('household', 'create', assigned_officer_id, created_by));

create policy hh_update on app.household
  for update to authenticated
  using (app.may('household', 'update', assigned_officer_id, created_by))
  with check (app.may('household', 'update', assigned_officer_id, created_by));


-- ---------- GUARDIAN ----------
-- No assigned officer of its own; inherits visibility from its household.
create policy gd_select on app.guardian
  for select to authenticated
  using (
    exists (
      select 1 from app.household h
       where h.id = guardian.household_id
         and app.may('household', 'read', h.assigned_officer_id, h.created_by)
    )
    or app.may('guardian', 'read')
  );

create policy gd_insert on app.guardian
  for insert to authenticated
  with check (app.may('guardian', 'create'));

create policy gd_update on app.guardian
  for update to authenticated
  using (app.may('guardian', 'update'))
  with check (app.may('guardian', 'update'));


-- ---------- BENEFICIARY ----------
create policy ben_select on app.beneficiary
  for select to authenticated
  using (
    app.may('beneficiary', 'read', assigned_officer_id, created_by)
    and (deleted_at is null or app.permission_scope(auth.uid(),'beneficiary','read') = 'all')
  );

create policy ben_insert on app.beneficiary
  for insert to authenticated
  with check (app.may('beneficiary', 'create', assigned_officer_id, created_by));

create policy ben_update on app.beneficiary
  for update to authenticated
  using (app.may('beneficiary', 'update', assigned_officer_id, created_by))
  with check (app.may('beneficiary', 'update', assigned_officer_id, created_by));


-- ---------- INSTITUTION ----------
create policy inst_select on app.institution
  for select to authenticated
  using (
    app.may('institution', 'read', null, created_by)
    and (deleted_at is null or app.permission_scope(auth.uid(),'institution','read') = 'all')
  );

create policy inst_insert on app.institution
  for insert to authenticated
  with check (app.may('institution', 'create', null, created_by));

create policy inst_update on app.institution
  for update to authenticated
  using (app.may('institution', 'update', null, created_by))
  with check (app.may('institution', 'update', null, created_by));


-- ---------- ASSESSMENT ----------
create policy asm_select on app.assessment
  for select to authenticated
  using (
    app.may('assessment', 'read', assessor_id, assessor_id)
    and (deleted_at is null or app.permission_scope(auth.uid(),'assessment','read') = 'all')
  );

create policy asm_insert on app.assessment
  for insert to authenticated
  with check (app.may('assessment', 'create', assessor_id, assessor_id));

create policy asm_update on app.assessment
  for update to authenticated
  using (app.may('assessment', 'update', assessor_id, assessor_id))
  with check (app.may('assessment', 'update', assessor_id, assessor_id));


-- ---------- ASSESSMENT NEED ----------
-- Child rows follow the parent assessment exactly.
create policy asmn_select on app.assessment_need
  for select to authenticated
  using (exists (
    select 1 from app.assessment a
     where a.id = assessment_need.assessment_id
       and app.may('assessment', 'read', a.assessor_id, a.assessor_id)
  ));

create policy asmn_insert on app.assessment_need
  for insert to authenticated
  with check (exists (
    select 1 from app.assessment a
     where a.id = assessment_need.assessment_id
       and app.may('assessment', 'update', a.assessor_id, a.assessor_id)
  ));

create policy asmn_update on app.assessment_need
  for update to authenticated
  using (exists (
    select 1 from app.assessment a
     where a.id = assessment_need.assessment_id
       and app.may('assessment', 'update', a.assessor_id, a.assessor_id)
  ));


-- ---------- DOCUMENT ----------
-- 'restricted' documents are safeguarding-adjacent and never visible through
-- the ordinary document path, whatever the caller's document permissions say.
create policy doc_select on app.document
  for select to authenticated
  using (
    deleted_at is null
    and sensitivity <> 'restricted'
    and app.may('document', 'read', uploaded_by, uploaded_by)
  );

create policy doc_insert on app.document
  for insert to authenticated
  with check (
    sensitivity <> 'restricted'
    and app.may('document', 'create', uploaded_by, uploaded_by)
  );


-- ---------- SAFEGUARDING ----------
-- Deny-all at the table level. Reads happen only through functions that write
-- to safeguarding.access_log first. There is no policy permitting direct SELECT.
create policy sg_no_direct_access on safeguarding.case
  for all to authenticated using (false) with check (false);

create policy sg_log_no_direct_access on safeguarding.access_log
  for all to authenticated using (false) with check (false);


-- -----------------------------------------------------------------------------
-- 8. Self-test
--
-- Run after migrating:  select * from app.rls_status();
-- Any row showing rls_enabled = false is a table the matrix cannot protect.
-- -----------------------------------------------------------------------------

create or replace function app.rls_status()
returns table (schema_name text, table_name text, rls_enabled boolean, policy_count bigint)
language sql
stable
as $$
  select n.nspname::text,
         c.relname::text,
         c.relrowsecurity,
         (select count(*) from pg_policy p where p.polrelid = c.oid)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('app','safeguarding')
     and c.relkind = 'r'
   order by n.nspname, c.relname;
$$;


-- =============================================================================
-- AFTER RUNNING THIS MIGRATION
-- =============================================================================
--
-- In the Supabase dashboard: Settings -> API -> Exposed schemas
--   ADD:        app
--   NEVER ADD:  safeguarding, audit
--
-- The audit schema stays closed because a log the application can write to is
-- a log an attacker can edit.
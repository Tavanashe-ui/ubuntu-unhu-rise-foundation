-- =============================================================================
-- Ubuntu/Unhu Rise Foundation
-- Migration 0002: Permission matrix (PRD §30)
--
-- Every access rule in the system is a row in this file. Nothing here is
-- hardcoded in application logic — changing who can do what is a data change,
-- not a redeploy.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Add a 'summary' scope
--
-- PRD §30 gives the Executive "Restricted" access to safeguarding. That does not
-- mean redacted case files — it means counts and trends only, never the content
-- of a child's case. 'summary' is that scope.
-- -----------------------------------------------------------------------------

alter table app.role_permission
  drop constraint if exists role_permission_scope_check;

alter table app.role_permission
  add constraint role_permission_scope_check
  check (scope in ('all','assigned','own','summary'));

comment on column app.role_permission.scope is
  'all = every record; assigned = records where the user is the assigned officer; '
  'own = records the user created; summary = aggregate counts only, never row content.';


-- -----------------------------------------------------------------------------
-- 2. Generate the permission catalogue
--
-- Cross product of resources and the five standard actions, plus 'approve'
-- on the resources that carry a workflow (PRD §29).
-- -----------------------------------------------------------------------------

insert into app.permission (resource, action)
select r.resource, a.action
  from (values
    ('beneficiary'), ('household'), ('guardian'), ('institution'),
    ('assessment'), ('document'), ('safeguarding_case'),
    ('program'), ('project'), ('donor'), ('donation'), ('campaign'),
    ('volunteer'), ('event'), ('distribution'), ('finance'),
    ('report'), ('user'), ('role'), ('audit_log'), ('settings')
  ) as r(resource)
  cross join (values
    ('create'), ('read'), ('update'), ('delete'), ('export')
  ) as a(action)
on conflict (resource, action) do nothing;

insert into app.permission (resource, action)
select r.resource, 'approve'
  from (values
    ('beneficiary'), ('assessment'), ('project'),
    ('donation'), ('finance'), ('institution')
  ) as r(resource)
on conflict (resource, action) do nothing;


-- -----------------------------------------------------------------------------
-- 3. Grant helper
--
-- app.grant_perm('program_officer', 'beneficiary', array['create','read'], 'all')
-- -----------------------------------------------------------------------------

create or replace function app.grant_perm(
  p_role_code text,
  p_resource  text,
  p_actions   text[],
  p_scope     text default 'all'
) returns void
language plpgsql
as $$
declare
  v_role_id uuid;
begin
  select id into v_role_id from app.role where code = p_role_code;

  if v_role_id is null then
    raise exception 'Unknown role code: %', p_role_code;
  end if;

  insert into app.role_permission (role_id, permission_id, scope)
  select v_role_id, p.id, p_scope
    from app.permission p
   where p.resource = p_resource
     and p.action = any(p_actions)
  on conflict (role_id, permission_id)
    do update set scope = excluded.scope;
end;
$$;


-- -----------------------------------------------------------------------------
-- 4. THE MATRIX
-- -----------------------------------------------------------------------------

do $$
declare
  full_access text[] := array['create','read','update','delete','export'];
  view_only   text[] := array['read','export'];
  edit_only   text[] := array['create','read','update','export'];
  r           record;
begin

  -- ===========================================================================
  -- SUPER ADMINISTRATOR — everything, including approvals and audit logs.
  -- ===========================================================================
  for r in select distinct resource from app.permission loop
    perform app.grant_perm('super_admin', r.resource,
      array['create','read','update','delete','export','approve'], 'all');
  end loop;


  -- ===========================================================================
  -- EXECUTIVE / BOARD — oversight, not operation. Reads widely, writes nothing.
  -- ===========================================================================
  perform app.grant_perm('executive', 'beneficiary',   view_only);
  perform app.grant_perm('executive', 'household',     view_only);
  perform app.grant_perm('executive', 'institution',   view_only);
  perform app.grant_perm('executive', 'assessment',    view_only);
  perform app.grant_perm('executive', 'program',       view_only);
  perform app.grant_perm('executive', 'project',       array['read','export','approve']);
  perform app.grant_perm('executive', 'donor',         view_only);
  perform app.grant_perm('executive', 'donation',      view_only);
  perform app.grant_perm('executive', 'campaign',      view_only);
  perform app.grant_perm('executive', 'volunteer',     view_only);
  perform app.grant_perm('executive', 'event',         view_only);
  perform app.grant_perm('executive', 'finance',       view_only);
  perform app.grant_perm('executive', 'report',        view_only);

  -- Aggregate counts only. The board sees that there are 4 open cases.
  -- It does not see which children, or what happened to them.
  perform app.grant_perm('executive', 'safeguarding_case', array['read'], 'summary');


  -- ===========================================================================
  -- FOUNDATION ADMINISTRATOR — runs daily operations. No finance, no safeguarding.
  -- ===========================================================================
  perform app.grant_perm('foundation_admin', 'beneficiary',  full_access);
  perform app.grant_perm('foundation_admin', 'household',    full_access);
  perform app.grant_perm('foundation_admin', 'guardian',     full_access);
  perform app.grant_perm('foundation_admin', 'institution',  full_access);
  perform app.grant_perm('foundation_admin', 'assessment',   full_access);
  perform app.grant_perm('foundation_admin', 'document',     full_access);
  perform app.grant_perm('foundation_admin', 'program',      full_access);
  perform app.grant_perm('foundation_admin', 'project',      full_access);
  perform app.grant_perm('foundation_admin', 'donor',        edit_only);
  perform app.grant_perm('foundation_admin', 'donation',     view_only);
  perform app.grant_perm('foundation_admin', 'campaign',     full_access);
  perform app.grant_perm('foundation_admin', 'volunteer',    full_access);
  perform app.grant_perm('foundation_admin', 'event',        full_access);
  perform app.grant_perm('foundation_admin', 'distribution', full_access);
  perform app.grant_perm('foundation_admin', 'report',       view_only);
  perform app.grant_perm('foundation_admin', 'user',         edit_only);


  -- ===========================================================================
  -- PROGRAM OFFICER — the operational core. Registers children, runs assessments.
  -- ===========================================================================
  perform app.grant_perm('program_officer', 'beneficiary',  edit_only);
  perform app.grant_perm('program_officer', 'household',    edit_only);
  perform app.grant_perm('program_officer', 'guardian',     edit_only);
  perform app.grant_perm('program_officer', 'institution',  edit_only);
  perform app.grant_perm('program_officer', 'assessment',   full_access);
  perform app.grant_perm('program_officer', 'document',     edit_only);
  perform app.grant_perm('program_officer', 'program',      view_only);
  perform app.grant_perm('program_officer', 'project',      edit_only);
  perform app.grant_perm('program_officer', 'distribution', edit_only);
  perform app.grant_perm('program_officer', 'event',        view_only);
  perform app.grant_perm('program_officer', 'report',       view_only);

  -- "Limited" in PRD §30. A program officer must be able to RAISE a concern —
  -- that is the whole point of mandatory reporting. They can see what they
  -- themselves reported, and nothing else. They cannot edit or close a case.
  perform app.grant_perm('program_officer', 'safeguarding_case',
    array['create','read'], 'own');


  -- ===========================================================================
  -- SAFEGUARDING OFFICER — full control of cases, minimal access elsewhere.
  --
  -- Deliberately narrow outside their remit. Someone handling child protection
  -- has no operational reason to browse donations or edit projects.
  -- ===========================================================================
  perform app.grant_perm('safeguarding_officer', 'safeguarding_case',
    array['create','read','update','export','approve'], 'all');
  perform app.grant_perm('safeguarding_officer', 'beneficiary',  view_only);
  perform app.grant_perm('safeguarding_officer', 'household',    view_only);
  perform app.grant_perm('safeguarding_officer', 'guardian',     view_only);
  perform app.grant_perm('safeguarding_officer', 'institution',  view_only);
  perform app.grant_perm('safeguarding_officer', 'document',     edit_only);
  perform app.grant_perm('safeguarding_officer', 'volunteer',    view_only);
  perform app.grant_perm('safeguarding_officer', 'report',       view_only);


  -- ===========================================================================
  -- FINANCE OFFICER — money in, money out. No access to children's records.
  -- ===========================================================================
  perform app.grant_perm('finance_officer', 'donor',    full_access);
  perform app.grant_perm('finance_officer', 'donation', array['create','read','update','delete','export','approve']);
  perform app.grant_perm('finance_officer', 'campaign', edit_only);
  perform app.grant_perm('finance_officer', 'finance',  array['create','read','update','delete','export','approve']);
  perform app.grant_perm('finance_officer', 'project',  view_only);
  perform app.grant_perm('finance_officer', 'document', edit_only);
  perform app.grant_perm('finance_officer', 'report',   view_only);


  -- ===========================================================================
  -- VOLUNTEER COORDINATOR
  -- ===========================================================================
  perform app.grant_perm('volunteer_coordinator', 'volunteer', full_access);
  perform app.grant_perm('volunteer_coordinator', 'event',     edit_only);
  perform app.grant_perm('volunteer_coordinator', 'document',  edit_only);
  perform app.grant_perm('volunteer_coordinator', 'program',   view_only);
  perform app.grant_perm('volunteer_coordinator', 'report',    view_only);


  -- ===========================================================================
  -- COMMUNICATIONS OFFICER — public-facing only.
  --
  -- No beneficiary access at all. Someone writing a fundraising newsletter
  -- must not be able to pull a child's name and photograph out of the database.
  -- Approved stories are curated deliberately, not harvested.
  -- ===========================================================================
  perform app.grant_perm('comms_officer', 'campaign', full_access);
  perform app.grant_perm('comms_officer', 'event',    full_access);
  perform app.grant_perm('comms_officer', 'document', edit_only);
  perform app.grant_perm('comms_officer', 'program',  view_only);
  perform app.grant_perm('comms_officer', 'donor',    array['read']);


  -- ===========================================================================
  -- FIELD OFFICER — mobile data collection, scoped to their own caseload.
  -- ===========================================================================
  perform app.grant_perm('field_officer', 'beneficiary', array['create','read','update'], 'assigned');
  perform app.grant_perm('field_officer', 'household',   array['create','read','update'], 'assigned');
  perform app.grant_perm('field_officer', 'guardian',    array['create','read','update'], 'assigned');
  perform app.grant_perm('field_officer', 'institution',  view_only);
  perform app.grant_perm('field_officer', 'assessment',  array['create','read','update'], 'own');
  perform app.grant_perm('field_officer', 'document',    array['create','read'], 'own');

  -- Same reasoning as program officers: a field officer meeting a child in
  -- distress must be able to report it.
  perform app.grant_perm('field_officer', 'safeguarding_case',
    array['create','read'], 'own');

end;
$$;


-- -----------------------------------------------------------------------------
-- 5. Extend has_permission() to return scope
--
-- Application code needs to know not just "may they read beneficiaries" but
-- "which beneficiaries" — all of them, or only their assigned caseload.
-- -----------------------------------------------------------------------------

create or replace function app.permission_scope(
  p_user_id  uuid,
  p_resource text,
  p_action   text
) returns text
language sql
stable
as $$
  select rp.scope
    from app.user_role ur
    join app.role_permission rp on rp.role_id = ur.role_id
    join app.permission p       on p.id = rp.permission_id
    join app.user_profile up    on up.id = ur.user_id
   where ur.user_id = p_user_id
     and p.resource = p_resource
     and p.action   = p_action
     and up.is_active
     and up.deleted_at is null
   -- A user may hold several roles. The broadest scope wins.
   order by case rp.scope
              when 'all'     then 1
              when 'assigned' then 2
              when 'own'     then 3
              when 'summary' then 4
            end
   limit 1;
$$;


-- -----------------------------------------------------------------------------
-- 6. Readable view of the matrix
--
-- Run `select * from app.permission_matrix;` to see the whole access model
-- as a table. Use this in code review and when onboarding staff.
-- -----------------------------------------------------------------------------

create or replace view app.permission_matrix as
  select r.code as role_code,
         r.name as role_name,
         p.resource,
         string_agg(
           p.action || case when rp.scope <> 'all' then ':' || rp.scope else '' end,
           ', ' order by p.action
         ) as actions
    from app.role r
    join app.role_permission rp on rp.role_id = r.id
    join app.permission p       on p.id = rp.permission_id
   group by r.code, r.name, p.resource
   order by r.code, p.resource;


-- =============================================================================
-- NOTES
-- =============================================================================
--
-- Two rules that must survive every future change to this file:
--
-- 1. NO ROLE GAINS UNRESTRICTED SAFEGUARDING READ ACCESS except
--    safeguarding_officer and super_admin. Convenience is not a reason to widen
--    it. If a report needs case numbers, use the 'summary' scope.
--
-- 2. GENDER IS NEVER A PERMISSION DIMENSION. It is recorded for equality
--    monitoring (PRD §10) and must never appear in an access rule.
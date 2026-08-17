-- =============================================================================
-- Ubuntu/Unhu Rise Foundation
-- Migration 0008: Household context
--
-- The household is what turns a list of children into an understanding of
-- circumstances. PRD §9: "This prevents duplicate records and allows the
-- Foundation to understand the broader circumstances surrounding a child."
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Household summary
--
-- Answers the questions an officer actually asks when opening a household:
-- how many children, how many already supported, who is the guardian.
-- -----------------------------------------------------------------------------

create or replace view app.household_summary as
  select h.id,
         h.ref,
         h.head_name,
         h.community,
         h.phone,
         h.economic_status,
         h.vulnerability_notes,
         h.assigned_officer_id,
         h.created_by,
         h.created_at,
         p.name as province,
         d.name as district,

         (select count(*)
            from app.beneficiary b
           where b.household_id = h.id
             and b.deleted_at is null) as child_count,

         (select count(*)
            from app.beneficiary b
           where b.household_id = h.id
             and b.deleted_at is null
             and b.status in ('active','verified')) as active_child_count,

         (select g.full_name
            from app.guardian g
           where g.household_id = h.id
             and g.deleted_at is null
           order by g.is_primary desc, g.created_at
           limit 1) as primary_guardian

    from app.household h
    left join app.province p on p.id = h.province_id
    left join app.district d on d.id = h.district_id
   where h.deleted_at is null;

alter view app.household_summary set (security_invoker = on);
grant select on app.household_summary to authenticated;


-- -----------------------------------------------------------------------------
-- 2. Possible-sibling detection
--
-- Registering one child of a family and missing the other three is the most
-- common way a Foundation under-serves a household. This surfaces children who
-- share a surname and a community but are NOT yet linked to a household —
-- likely siblings someone registered separately.
--
-- It suggests. It never merges: two unrelated families in one village can share
-- a surname, and wrongly merged records are far harder to untangle than
-- unlinked ones.
-- -----------------------------------------------------------------------------

create or replace function app.possible_siblings(p_beneficiary_id uuid)
returns table (
  id             uuid,
  ref            text,
  full_name      text,
  age            int,
  household_ref  text,
  match_reason   text
)
language sql
stable
security invoker
as $$
  with subject as (
    select surname, community, district_id, household_id
      from app.beneficiary
     where id = p_beneficiary_id
  )
  select b.id,
         b.ref,
         b.first_name || ' ' || b.surname,
         extract(year from age(b.date_of_birth))::int,
         h.ref,
         case
           when b.household_id is not null
                and b.household_id = (select household_id from subject)
             then 'Same household'
           when lower(b.surname) = lower((select surname from subject))
                and b.community is not distinct from (select community from subject)
             then 'Same surname and community'
           else 'Same surname and district'
         end
    from app.beneficiary b
    left join app.household h on h.id = b.household_id
   cross join subject s
   where b.id <> p_beneficiary_id
     and b.deleted_at is null
     and lower(b.surname) = lower(s.surname)
     and (
       b.household_id = s.household_id
       or b.community is not distinct from s.community
       or b.district_id = s.district_id
     )
   order by 6, 4 desc
   limit 20;
$$;

grant execute on function app.possible_siblings(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 3. Consent enforcement (flagged in migration 0001)
--
-- A beneficiary cannot become active without a lawful basis on file. Zimbabwe's
-- Data Protection Act (Ch. 11:12) governs this, and 'we forgot' is not a defence
-- when the data subject is a child.
--
-- Registration without consent is still allowed — an officer meeting a child in
-- the field should record them immediately and obtain consent after. The gate is
-- on activation, not on capture.
-- -----------------------------------------------------------------------------

create or replace function app.enforce_consent_before_active()
returns trigger
language plpgsql
as $$
begin
  if new.status in ('active','verified') and not new.consent_on_file then
    raise exception
      'Cannot set % to % without guardian consent on file (Data Protection Act). Record consent first.',
      new.ref, new.status
      using errcode = 'check_violation';
  end if;

  -- Track when status last changed, for follow-up reporting.
  if new.status is distinct from old.status then
    new.status_changed_at := now();
  end if;

  return new;
end;
$$;

drop trigger if exists trg_consent_gate on app.beneficiary;

create trigger trg_consent_gate
  before update on app.beneficiary
  for each row execute function app.enforce_consent_before_active();


-- -----------------------------------------------------------------------------
-- 4. Link a beneficiary to a household
--
-- Wrapped in a function so the household's child_count and the beneficiary's
-- location stay consistent, and so the operation is a single audited action
-- rather than two independent updates.
-- -----------------------------------------------------------------------------

create or replace function app.link_to_household(
  p_beneficiary_id uuid,
  p_household_id   uuid,
  p_inherit_location boolean default true
) returns text
language plpgsql
security invoker
as $$
declare
  v_ref  text;
  v_hh   app.household%rowtype;
begin
  select * into v_hh from app.household where id = p_household_id and deleted_at is null;
  if not found then
    raise exception 'Household not found';
  end if;

  update app.beneficiary
     set household_id = p_household_id,
         province_id  = case when p_inherit_location and province_id is null
                             then v_hh.province_id else province_id end,
         district_id  = case when p_inherit_location and district_id is null
                             then v_hh.district_id else district_id end,
         community    = case when p_inherit_location and community is null
                             then v_hh.community else community end
   where id = p_beneficiary_id
     and deleted_at is null
  returning ref into v_ref;

  if v_ref is null then
    raise exception 'Beneficiary not found, or you do not have permission to update it';
  end if;

  return format('%s linked to household %s', v_ref, v_hh.ref);
end;
$$;

grant execute on function app.link_to_household(uuid, uuid, boolean) to authenticated;
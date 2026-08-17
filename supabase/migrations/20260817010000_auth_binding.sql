-- =============================================================================
-- Ubuntu/Unhu Rise Foundation
-- Migration 0003: Bind Supabase Auth to app.user_profile
--
-- Supabase manages credentials in auth.users. This system manages identity and
-- roles in app.user_profile. This migration keeps the two in step and gives you
-- a safe way to grant roles.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Create a profile whenever an account is created
--
-- security definer is required: the trigger runs as the auth service, which has
-- no rights on the app schema.
--
-- NOTE: a new account gets NO ROLES. It can log in and see nothing until a
-- super admin grants access. That is deliberate — an account that arrives with
-- permissions already attached is an account that can be abused before anyone
-- notices it exists.
-- -----------------------------------------------------------------------------

create or replace function app.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = app, public
as $$
begin
  insert into app.user_profile (id, email, full_name, phone)
  values (
    new.id,
    new.email,
    coalesce(
      nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
      split_part(new.email, '@', 1)
    ),
    nullif(trim(new.raw_user_meta_data->>'phone'), '')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists trg_on_auth_user_created on auth.users;

create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function app.handle_new_auth_user();


-- -----------------------------------------------------------------------------
-- 2. Keep email in step
--
-- If a user changes their email in Supabase Auth, the profile must follow or
-- the audit trail will show an address that no longer identifies anyone.
-- -----------------------------------------------------------------------------

create or replace function app.handle_auth_user_updated()
returns trigger
language plpgsql
security definer
set search_path = app, public
as $$
begin
  if new.email is distinct from old.email then
    update app.user_profile
       set email = new.email
     where id = new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_on_auth_user_updated on auth.users;

create trigger trg_on_auth_user_updated
  after update on auth.users
  for each row execute function app.handle_auth_user_updated();


-- -----------------------------------------------------------------------------
-- 3. Role assignment helper
--
--   select app.assign_role('lesley@example.com', 'super_admin');
--
-- Raises rather than failing silently if the email or role is unknown — a typo
-- in a role grant should be loud.
-- -----------------------------------------------------------------------------

create or replace function app.assign_role(
  p_email     text,
  p_role_code text,
  p_granted_by uuid default null
) returns text
language plpgsql
as $$
declare
  v_user_id uuid;
  v_role_id uuid;
begin
  select id into v_user_id from app.user_profile where email = lower(p_email);
  if v_user_id is null then
    raise exception 'No user profile for email %. Create the account first.', p_email;
  end if;

  select id into v_role_id from app.role where code = p_role_code;
  if v_role_id is null then
    raise exception 'Unknown role code: %', p_role_code;
  end if;

  insert into app.user_role (user_id, role_id, granted_by)
  values (v_user_id, v_role_id, p_granted_by)
  on conflict (user_id, role_id) do nothing;

  return format('%s now holds role %s', p_email, p_role_code);
end;
$$;


create or replace function app.revoke_role(
  p_email     text,
  p_role_code text
) returns text
language plpgsql
as $$
declare
  v_count int;
begin
  delete from app.user_role ur
   using app.user_profile up, app.role r
   where ur.user_id = up.id
     and ur.role_id = r.id
     and up.email   = lower(p_email)
     and r.code     = p_role_code;

  get diagnostics v_count = row_count;

  if v_count = 0 then
    return format('No change: %s did not hold %s', p_email, p_role_code);
  end if;

  return format('Revoked %s from %s', p_role_code, p_email);
end;
$$;


-- -----------------------------------------------------------------------------
-- 4. Convenience view: who can do what
--
--   select * from app.user_access;
--
-- The first thing to check when someone reports "I can't see X".
-- -----------------------------------------------------------------------------

create or replace view app.user_access as
  select up.email,
         up.full_name,
         up.is_active,
         coalesce(
           string_agg(r.code, ', ' order by r.code),
           '(no roles — cannot access anything)'
         ) as roles
    from app.user_profile up
    left join app.user_role ur on ur.user_id = up.id
    left join app.role r       on r.id = ur.role_id
   where up.deleted_at is null
   group by up.email, up.full_name, up.is_active
   order by up.email;


-- =============================================================================
-- AFTER RUNNING THIS MIGRATION
-- =============================================================================
--
-- 1. In the Supabase dashboard, turn OFF public sign-ups:
--       Authentication -> Sign In / Providers -> Email -> disable "Allow new users to sign up"
--
--    This system must never allow self-registration. Accounts are created by an
--    administrator, because every account is a potential route to a child's record.
--
-- 2. Create your own account: Authentication -> Users -> Add user.
--
-- 3. Grant yourself super admin in the SQL Editor:
--       select app.assign_role('your@email.com', 'super_admin');
--
-- 4. Confirm with:
--       select * from app.user_access;
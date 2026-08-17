-- Second barrier on tables only security-definer functions should touch.
-- These have no GRANTs and are not API-exposed, but "unreachable because
-- ungranted" is weaker than "the database refuses". role_permission defines
-- who can read a child's record — it gets both barriers.
--
-- No policies: no policy means no access. Owner-context functions are unaffected.

alter table app.permission      enable row level security;
alter table app.role_permission enable row level security;
alter table app.ref_sequence    enable row level security;

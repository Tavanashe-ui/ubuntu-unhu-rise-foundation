-- =============================================================================
-- Ubuntu/Unhu Rise Foundation
-- Migration 0006: Zimbabwe districts
--
-- Districts are a lookup rather than free text so that equality and coverage
-- reporting can group by district without fighting spelling variants. "Which
-- communities are we reaching?" (PRD §51) is unanswerable over typed strings.
--
-- Names follow common administrative usage. Verify against the current ZimStat
-- listing before the Foundation relies on this for external reporting — district
-- boundaries and names do change.
-- =============================================================================

insert into app.district (province_id, name)
values
  -- Bulawayo
  (1, 'Bulawayo'),

  -- Harare
  (2, 'Harare'),
  (2, 'Chitungwiza'),
  (2, 'Epworth'),

  -- Manicaland
  (3, 'Buhera'),
  (3, 'Chimanimani'),
  (3, 'Chipinge'),
  (3, 'Makoni'),
  (3, 'Mutare'),
  (3, 'Mutasa'),
  (3, 'Nyanga'),

  -- Mashonaland Central
  (4, 'Bindura'),
  (4, 'Guruve'),
  (4, 'Mazowe'),
  (4, 'Mbire'),
  (4, 'Mount Darwin'),
  (4, 'Muzarabani'),
  (4, 'Rushinga'),
  (4, 'Shamva'),

  -- Mashonaland East
  (5, 'Chikomba'),
  (5, 'Goromonzi'),
  (5, 'Hwedza'),
  (5, 'Marondera'),
  (5, 'Mudzi'),
  (5, 'Murehwa'),
  (5, 'Mutoko'),
  (5, 'Seke'),
  (5, 'Uzumba-Maramba-Pfungwe'),

  -- Mashonaland West
  (6, 'Chegutu'),
  (6, 'Hurungwe'),
  (6, 'Kariba'),
  (6, 'Makonde'),
  (6, 'Mhondoro-Ngezi'),
  (6, 'Sanyati'),
  (6, 'Zvimba'),

  -- Masvingo
  (7, 'Bikita'),
  (7, 'Chiredzi'),
  (7, 'Chivi'),
  (7, 'Gutu'),
  (7, 'Masvingo'),
  (7, 'Mwenezi'),
  (7, 'Zaka'),

  -- Matabeleland North
  (8, 'Binga'),
  (8, 'Bubi'),
  (8, 'Hwange'),
  (8, 'Lupane'),
  (8, 'Nkayi'),
  (8, 'Tsholotsho'),
  (8, 'Umguza'),

  -- Matabeleland South
  (9, 'Beitbridge'),
  (9, 'Bulilima'),
  (9, 'Gwanda'),
  (9, 'Insiza'),
  (9, 'Mangwe'),
  (9, 'Matobo'),
  (9, 'Umzingwane'),

  -- Midlands
  (10, 'Chirumhanzu'),
  (10, 'Gokwe North'),
  (10, 'Gokwe South'),
  (10, 'Gweru'),
  (10, 'Kwekwe'),
  (10, 'Mberengwa'),
  (10, 'Shurugwi'),
  (10, 'Zvishavane')

on conflict (province_id, name) do nothing;


-- A convenience view so forms can populate a single dropdown without a join.
create or replace view app.district_lookup as
  select d.id,
         d.province_id,
         p.name as province,
         d.name as district,
         p.name || ' — ' || d.name as label
    from app.district d
    join app.province p on p.id = d.province_id
   order by p.name, d.name;

grant select on app.district_lookup to authenticated;
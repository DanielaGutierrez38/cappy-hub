begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

insert into auth.users(id,email) values
 ('00000000-0000-4000-8000-000000001401','slots-admin@example.org'),
 ('00000000-0000-4000-8000-000000001402','slots-intro-lead@example.org'),
 ('00000000-0000-4000-8000-000000001403','slots-icpc-lead@example.org'),
 ('00000000-0000-4000-8000-000000001404','slots-officer-a@example.org'),
 ('00000000-0000-4000-8000-000000001405','slots-officer-b@example.org'),
 ('00000000-0000-4000-8000-000000001406','slots-inactive@example.org'),
 ('00000000-0000-4000-8000-000000001407','slots-unlinked@example.org');
insert into officers(id,name,utep_email,position_id,status,application_role,auth_user_id) values
 (-1401,'Slots Admin','slots-admin@example.org',(select id from positions where name='Officer'),'active','admin','00000000-0000-4000-8000-000000001401'),
 (-1402,'Slots Intro Lead','slots-intro-lead@example.org',(select id from positions where name='Lead'),'active','officer','00000000-0000-4000-8000-000000001402'),
 (-1403,'Slots ICPC Lead','slots-icpc-lead@example.org',(select id from positions where name='Lead'),'active','officer','00000000-0000-4000-8000-000000001403'),
 (-1404,'Slots Officer A','slots-officer-a@example.org',(select id from positions where name='Officer'),'active','officer','00000000-0000-4000-8000-000000001404'),
 (-1405,'Slots Officer B','slots-officer-b@example.org',(select id from positions where name='Officer'),'active','officer','00000000-0000-4000-8000-000000001405'),
 (-1406,'Slots Inactive','slots-inactive@example.org',(select id from positions where name='Officer'),'inactive','officer','00000000-0000-4000-8000-000000001406');
insert into officer_branches(officer_id,branch_id)
select -1402,id from branches where name='intro'
union all select -1403,id from branches where name='icpc';
with denver_today as (
  select (now() at time zone 'America/Denver')::date as local_date
), fixtures(id,name,day_offset,status,is_removed) as (
  values
    (-1401,'Slots Intro session',2,'upcoming',false),
    (-1402,'Slots global session',2,'upcoming',false),
    (-1403,'Slots cancelled session',2,'cancelled',false),
    (-1404,'Slots started session',-1,'past',false),
    (-1405,'Slots removed session',2,'upcoming',true)
)
insert into events(id,name,description,location,event_type_id,starts_at,ends_at,status,
 deleted_at,deleted_by)
select f.id,f.name,'Test event','TBA',(select id from event_types where name='Workshop'),
  ((d.local_date+f.day_offset)::timestamp+time '09:00') at time zone 'America/Denver',
  ((d.local_date+f.day_offset)::timestamp+time '11:00') at time zone 'America/Denver',
  f.status,
  case when f.is_removed then now() end,
  case when f.is_removed then '00000000-0000-4000-8000-000000001401'::uuid end
from fixtures f cross join denver_today d;
insert into event_branches(event_id,branch_id)
select e.id,b.id from (values (-1401),(-1403),(-1404),(-1405)) e(id)
cross join branches b where b.name='intro';
-- Closed Events can only hold slots that were enabled before they closed.
insert into presentation_slots(event_id,difficulty) values
 (-1403,'easy'),(-1404,'easy'),(-1405,'easy');

-- Read access and raw writes.
set local role anon;
select throws_ok($$select count(*) from presentation_slots$$,'42501',null,
  'anonymous clients cannot read presenter slots');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001407',true);
select is((select count(*) from presentation_slots),0::bigint,
  'unlinked authenticated account cannot read presenter slots');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001406',true);
select is((select count(*) from presentation_slots),0::bigint,
  'inactive Officer cannot read presenter slots');
select throws_ok($$select set_presenter_slots(-1401,array['easy'])$$,
  'P0001','Unauthorized','inactive Officer cannot enable presenter slots');
select throws_ok($$select change_presenter_slot(-1403,'easy',-1406)$$,
  'P0001','Unauthorized','inactive Officer cannot claim a presenter slot');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001404',true);
select is((select count(*) from presentation_slots where event_id in (-1403,-1404,-1405)),
  3::bigint,'active linked Officer can read presenter slots');
select throws_ok($$insert into presentation_slots(event_id,difficulty) values(-1401,'easy')$$,
  '42501',null,'authenticated clients cannot insert presenter slots directly');
select throws_ok($$update presentation_slots set officer_id=-1404 where event_id=-1403$$,
  '42501',null,'authenticated clients cannot update presenter slots directly');
select throws_ok($$delete from presentation_slots where event_id=-1403$$,
  '42501',null,'authenticated clients cannot delete presenter slots directly');

-- Enabling slots follows Event management scope.
select throws_ok($$select set_presenter_slots(-1401,array['easy','medium','hard'])$$,
  'P0001','Event outside branch scope','ordinary Officer cannot enable presenter slots');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001403',true);
select throws_ok($$select set_presenter_slots(-1401,array['easy'])$$,
  'P0001','Event outside branch scope','Lead of another branch cannot enable presenter slots');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001402',true);
select throws_ok($$select set_presenter_slots(-1402,array['easy'])$$,
  'P0001','Event outside branch scope','Lead cannot enable presenter slots on a global Event');
select throws_ok($$select set_presenter_slots(-1401,array['easy','expert'])$$,
  'P0001','Invalid presenter slot difficulty','unknown difficulty is rejected');
select throws_ok($$select set_presenter_slots(-999999,array['easy'])$$,
  'P0001','Event not found','missing Event is rejected');
select throws_ok($$select set_presenter_slots(-1403,array['easy'])$$,
  'P0001','Presenter slots are closed for this event','cancelled Event cannot change slots');
select throws_ok($$select set_presenter_slots(-1404,array['easy'])$$,
  'P0001','Presenter slots are closed for this event','started Event cannot change slots');
select throws_ok($$select set_presenter_slots(-1405,array['easy'])$$,
  'P0001','Presenter slots are closed for this event','removed Event cannot change slots');
select lives_ok($$select set_presenter_slots(-1401,array['easy','medium','hard','easy'])$$,
  'Lead sharing a branch can enable presenter slots');
select is((select count(*) from presentation_slots where event_id=-1401 and officer_id is null),
  3::bigint,'one open slot exists per requested difficulty');
select lives_ok($$select set_presenter_slots(-1401,array['hard','medium','easy'])$$,
  'repeating the same slot selection is accepted');
reset role;
-- The System Log is admin-only, so audit rows are inspected as the owner.
select is((select count(*) from audit_logs where action='presentation.slots_updated'
  and entity_id='-1401'),1::bigint,'an unchanged slot selection writes no audit entry');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001401',true);
select lives_ok($$select set_presenter_slots(-1402,array['easy'])$$,
  'admin can enable presenter slots on a global Event');

-- Claiming.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001404',true);
select lives_ok($$select change_presenter_slot(-1401,'easy',-1404)$$,
  'Officer can volunteer for an open slot');
select is((select officer_id from presentation_slots where event_id=-1401 and difficulty='easy'),
  -1404::bigint,'the slot records its presenter');
select ok(exists(select 1 from event_officers where event_id=-1401 and officer_id=-1404),
  'claiming a slot signs the presenter up for the Event');
select lives_ok($$select change_presenter_slot(-1401,'easy',-1404)$$,
  'repeating a claim is accepted');
select throws_ok($$select change_presenter_slot(-1401,'medium',-1404)$$,
  'P0001','Officer already has a presenter slot for this event',
  'an Officer cannot hold two slots on one Event');
select throws_ok($$select change_presenter_slot(-1401,'medium',-1405)$$,
  'P0001','Cannot manage another officer presenter slot for this event',
  'ordinary Officer cannot assign another Officer');
select throws_ok($$select change_presenter_slot(-1402,'hard',-1404)$$,
  'P0001','Presenter slot not found','a difficulty that is not enabled cannot be claimed');
select lives_ok($$select change_presenter_slot(-1402,'easy',-1404)$$,
  'Officer can volunteer on a global Event');
select throws_ok($$select change_presenter_slot(-1403,'easy',-1404)$$,
  'P0001','Presenter slots are closed for this event','cancelled Event rejects claims');
select throws_ok($$select change_presenter_slot(-1404,'easy',-1404)$$,
  'P0001','Presenter slots are closed for this event','started Event rejects claims');
select throws_ok($$select change_presenter_slot(-1405,'easy',-1404)$$,
  'P0001','Presenter slots are closed for this event','removed Event rejects claims');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001405',true);
select throws_ok($$select change_presenter_slot(-1401,'easy',-1405)$$,
  'P0001','Presenter slot is already taken','a taken slot cannot be claimed by someone else');
select throws_ok($$select change_presenter_slot(-1401,'easy',-1404,true)$$,
  'P0001','Cannot manage another officer presenter slot for this event',
  'ordinary Officer cannot release another presenter');
select is((select count(*) from event_officers where event_id=-1401 and officer_id=-1405),
  0::bigint,'a rejected claim does not sign the Officer up');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001403',true);
select throws_ok($$select change_presenter_slot(-1401,'medium',-1405)$$,
  'P0001','Cannot manage another officer presenter slot for this event',
  'Lead of another branch cannot assign presenters');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001402',true);
select throws_ok($$select change_presenter_slot(-1401,'medium',-1406)$$,
  'P0001','Target officer is not active','inactive Officer cannot be assigned');
select lives_ok($$select change_presenter_slot(-1401,'medium',-1405)$$,
  'Lead sharing a branch can assign a presenter');
select throws_ok($$select set_presenter_slots(-1401,array['easy','hard'])$$,
  'P0001','Remove the presenter before removing their slot',
  'an assigned slot cannot be removed');
select lives_ok($$select set_presenter_slots(-1401,array['easy','medium'])$$,
  'an open slot can be removed');
select is((select count(*) from presentation_slots where event_id=-1401),2::bigint,
  'only the remaining slots are kept');
reset role;
select ok(exists(select 1 from audit_logs where action='presentation.claimed'
  and entity_type='event' and entity_id='-1401' and details->>'officer_id'='-1404'
  and details->>'difficulty'='easy'
  and actor_id='00000000-0000-4000-8000-000000001404'),
  'a self claim is audited against the Event');
select ok(exists(select 1 from audit_logs where action='presentation.assigned'
  and entity_id='-1401' and details->>'officer_id'='-1405'
  and actor_id='00000000-0000-4000-8000-000000001402'),
  'a manager assignment is audited with the manager as actor');
select is((select count(*) from audit_logs where action='presentation.claimed'
  and entity_id='-1401'),1::bigint,'a repeated claim writes no second audit entry');

-- Problem details.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001404',true);
select throws_ok($$select update_presenter_slot_details(
  (select id from presentation_slots where event_id=-1401 and difficulty='easy'),
  'Two Sum','https://example.org/two-sum',null)$$,
  'P0001','Event outside branch scope','ordinary Officer cannot edit problem details');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001402',true);
select throws_ok($$select update_presenter_slot_details(
  (select id from presentation_slots where event_id=-1401 and difficulty='easy'),
  'Two Sum','javascript:alert(1)',null)$$,
  'P0001','Problem link must be an HTTP(S) URL','non-HTTP problem link is rejected');
select throws_ok($$select update_presenter_slot_details(
  (select id from presentation_slots where event_id=-1401 and difficulty='easy'),
  repeat('x',201),null,null)$$,
  'P0001','Presenter slot details are too long','overlong problem title is rejected');
select throws_ok($$select update_presenter_slot_details(-999999,'Two Sum',null,null)$$,
  'P0001','Presenter slot not found','missing slot is rejected');
select throws_ok($$select update_presenter_slot_details(
  (select id from presentation_slots where event_id=-1403),'Two Sum',null,null)$$,
  'P0001','Presenter slots are closed for this event','closed Event rejects detail edits');
select lives_ok($$select update_presenter_slot_details(
  (select id from presentation_slots where event_id=-1401 and difficulty='easy'),
  '  Two Sum ','https://example.org/two-sum','   ')$$,
  'manager can save problem details');
select is((select problem_title||'|'||problem_url||'|'||coalesce(prep_notes,'<null>')
  from presentation_slots where event_id=-1401 and difficulty='easy'),
  'Two Sum|https://example.org/two-sum|<null>','details are trimmed and blanks stored as null');
reset role;
select ok(exists(select 1 from audit_logs where action='presentation.details_updated'
  and entity_id='-1401' and details->'after'->>'problem_title'='Two Sum'),
  'problem detail edits are audited');

-- Stepping down keeps the Event signup.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001404',true);
select lives_ok($$select change_presenter_slot(-1401,'easy',-1404,true)$$,
  'presenter can step down');
select is((select officer_id from presentation_slots where event_id=-1401 and difficulty='easy'),
  null::bigint,'stepping down reopens the slot');
select ok(exists(select 1 from event_officers where event_id=-1401 and officer_id=-1404),
  'stepping down keeps the Event signup');
select is((select problem_title from presentation_slots
  where event_id=-1401 and difficulty='easy'),'Two Sum',
  'stepping down keeps the problem details');
select lives_ok($$select change_presenter_slot(-1401,'easy',-1404,true)$$,
  'releasing a slot the Officer does not hold is a no-op');
reset role;
select ok(exists(select 1 from audit_logs where action='presentation.released'
  and entity_id='-1401' and details->>'officer_id'='-1404'
  and details->>'reason'='requested'),'stepping down is audited as requested');
select is((select count(*) from audit_logs where action in
  ('presentation.released','presentation.unassigned') and entity_id='-1401'),
  1::bigint,'a no-op release writes no audit entry');

-- Removing the Event signup reopens the slot.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001405',true);
select lives_ok($$select change_event_signup(-1401,-1405,true)$$,
  'a presenter can still sign out of the Event');
select is((select officer_id from presentation_slots where event_id=-1401 and difficulty='medium'),
  null::bigint,'signing out reopens the presenter slot');
reset role;
select ok(exists(select 1 from audit_logs where action='presentation.released'
  and entity_id='-1401' and details->>'officer_id'='-1405'
  and details->>'reason'='signup_removed'),
  'a slot reopened by sign-out is audited with its cause');

-- Deactivating a presenter reopens the slot.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001404',true);
select lives_ok($$select change_presenter_slot(-1401,'easy',-1404)$$,
  'Officer can claim again after stepping down');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001401',true);
select lives_ok($$select save_officer('Slots Officer A',
  (select id from positions where name='Officer'),'inactive',null,-1404,
  'slots-officer-a@example.org')$$,'admin can deactivate a presenter');
select is((select count(*) from presentation_slots where officer_id=-1404),0::bigint,
  'deactivation reopens every upcoming slot the Officer held');
select ok(exists(select 1 from event_officers where event_id=-1401 and officer_id=-1404),
  'deactivation keeps the Event signup');
reset role;
select ok(exists(select 1 from audit_logs where action='presentation.unassigned'
  and entity_id='-1401' and details->>'officer_id'='-1404'
  and details->>'reason'='officer_deactivated'
  and actor_id='00000000-0000-4000-8000-000000001401'),
  'a slot reopened by deactivation is audited with the admin as actor');

-- A full Event cannot take a presenter who is not already signed up.
update events set max_volunteers=(select count(*) from event_officers where event_id=-1401)
  where id=-1401;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001402',true);
select throws_ok($$select change_presenter_slot(-1401,'medium',-1402)$$,
  'P0001','Event is full, so this officer cannot take a presenter slot',
  'a full Event rejects a presenter who would only be waitlisted');
select is((select count(*) from event_waitlist where event_id=-1401 and officer_id=-1402),
  0::bigint,'a rejected presenter claim leaves no waitlist entry');
reset role;
update events set max_volunteers=null where id=-1401;

-- Integrity holds below the RPC layer.
select throws_ok($$insert into presentation_slots(event_id,difficulty) values(-1401,'easy')$$,
  '23505',null,'an Event has at most one slot per difficulty');
select throws_ok($$update presentation_slots set officer_id=-1403
  where event_id=-1401 and difficulty='easy'$$,
  '23503',null,'a presenter must be signed up for the Event');
insert into event_officers(event_id,officer_id) values(-1401,-1403);
update presentation_slots set officer_id=-1403 where event_id=-1401 and difficulty='easy';
select throws_ok($$update presentation_slots set officer_id=-1403
  where event_id=-1401 and difficulty='medium'$$,
  '23505',null,'an Officer holds at most one slot per Event');

select * from finish();
rollback;

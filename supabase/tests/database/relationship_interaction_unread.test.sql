begin;

create extension if not exists pgtap with schema extensions;
select plan(21);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password) values
 ('00000000-0000-0000-0000-000000000701','00000000-0000-0000-0000-000000000000','authenticated','authenticated','unread-a@example.test',''),
 ('00000000-0000-0000-0000-000000000702','00000000-0000-0000-0000-000000000000','authenticated','authenticated','unread-b@example.test',''),
 ('00000000-0000-0000-0000-000000000703','00000000-0000-0000-0000-000000000000','authenticated','authenticated','unread-outsider@example.test','');
insert into public.relationships (id) values ('70000000-0000-0000-0000-000000000001');
insert into public.relationship_members (relationship_id, user_id) values
 ('70000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000701'),
 ('70000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000702');

insert into public.shared_appointments (relationship_id, client_id, creator_user_id, title, starts_at) values
 ('70000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000701','fixture',now() + interval '1 day');
insert into public.shared_items (relationship_id, client_id, creator_user_id, item_kind, text_content) values
 ('70000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000701','message','hello');
insert into public.shared_items (relationship_id, client_id, creator_user_id, item_kind, media_byte_size) values
 ('70000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000701','photo',1);

select is((select count(*)::integer from public.relationship_interaction_events), 3,
 'appointment creation, text, and completed photo each create one event');
select is((select count(*)::integer from public.relationship_interaction_events where event_kind = 'chat_photo_created'), 1,
 'photo is counted only after its server completion metadata exists');
select is((select count(*)::integer from public.relationship_interaction_events where scope_id = '70000000-0000-0000-0000-000000000001'), 2,
 'main chat uses the relationship scope');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000702',true);
select is((select total_unread_count::integer from public.relationship_unread_counts('70000000-0000-0000-0000-000000000001') limit 1), 3,
 'partner total is server-authoritative across chat and appointment scopes');
select lives_ok($$ select public.mark_relationship_interactions_read('70000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001') $$,
 'opening main conversation advances only main scope cursor');
select is((select sum(unread_count)::integer from public.relationship_unread_counts('70000000-0000-0000-0000-000000000001')), 1,
 'appointment lifecycle remains unread after main conversation read');
select lives_ok($$ select public.mark_relationship_interactions_read('70000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001') $$,
 'opening appointment scope advances its cursor');
select is((select count(*)::integer from public.relationship_unread_counts('70000000-0000-0000-0000-000000000001')), 0,
 'all scope cursors converge total unread to zero');

reset role;
delete from public.relationship_interaction_read_states
where relationship_id = '70000000-0000-0000-0000-000000000001'
  and scope_id = '70000000-0000-0000-0000-000000000001'
  and user_id = '00000000-0000-0000-0000-000000000702';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000702',true);
select lives_ok($$ select public.mark_relationship_interactions_read_through_message('70000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000002') $$,
 'a completed photo maps through its shared-item identity');
select is((select count(*)::integer from public.relationship_unread_counts('70000000-0000-0000-0000-000000000001')), 0,
 'reading through the visible photo clears the earlier main-chat events only');

reset role;
insert into public.shared_items (relationship_id, client_id, creator_user_id, item_kind, text_content) values
 ('70000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000701','message','older visible message');
update public.relationship_interaction_events event
set created_at = '2030-01-01 00:00:00+00'
from public.shared_items item
where item.relationship_id = event.relationship_id
  and item.id = event.source_identity
  and item.client_id = '72000000-0000-0000-0000-000000000003';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000702',true);
select lives_ok($$ select public.mark_conversation_read('70000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000003') $$,
 'legacy conversation cursor advances through the visible message');
select lives_ok($$ select public.mark_relationship_interactions_read_through_message('70000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000003') $$,
 'relationship cursor advances through the same visible message');

reset role;
insert into public.shared_items (relationship_id, client_id, creator_user_id, item_kind, text_content) values
 ('70000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000701','message','new arrival');
update public.relationship_interaction_events event
set created_at = '2030-01-01 00:00:01+00'
from public.shared_items item
where item.relationship_id = event.relationship_id
  and item.id = event.source_identity
  and item.client_id = '72000000-0000-0000-0000-000000000004';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000702',true);
select lives_ok($$ select public.mark_relationship_interactions_read_through_message('70000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000003') $$,
 'a delayed read may retry only through its original visible message');
select is(public.conversation_unread_count('70000000-0000-0000-0000-000000000001')::integer, 1,
 'the newer conversation message remains unread');
select is((select total_unread_count::integer from public.relationship_unread_counts('70000000-0000-0000-0000-000000000001') limit 1), 1,
 'the newer relationship interaction remains in the badge total');
select throws_ok($$ select public.mark_relationship_interactions_read_through_message('70000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000003') $$,
 '22023', 'interaction_source_not_found',
 'a main-chat message cannot advance an appointment scope');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000703',true);
select throws_ok($$ select public.mark_relationship_interactions_read_through_message('70000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000003') $$,
 '42501', 'relationship_not_accessible',
 'an outsider cannot advance a relationship interaction cursor');

select ok(has_function_privilege('authenticated','public.enqueue_relationship_interaction_push(uuid)','execute'),
 'authenticated sender may enqueue only a server-created lifecycle event');
select ok(not has_table_privilege('authenticated','public.relationship_interaction_read_states','update'),
 'clients cannot forge interaction read cursors directly');
select ok(not has_function_privilege('authenticated','public.record_relationship_interaction_event(uuid,uuid,uuid,uuid,text)','execute'),
 'authenticated clients cannot forge relationship interaction events');
select ok(not has_function_privilege('anon','public.record_relationship_interaction_event(uuid,uuid,uuid,uuid,text)','execute'),
 'anonymous clients cannot forge relationship interaction events');

select * from finish();
rollback;

begin;

create extension if not exists pgtap with schema extensions;
select plan(20);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-000000000091', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'push-a@example.test', ''),
    ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'push-b@example.test', ''),
    ('00000000-0000-0000-0000-000000000093', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'push-c@example.test', '');

insert into public.relationships (id)
values ('90000000-0000-0000-0000-000000000009'), ('90000000-0000-0000-0000-000000000099');
insert into public.relationship_members (relationship_id, user_id)
values
    ('90000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000091'),
    ('90000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000092'),
    ('90000000-0000-0000-0000-000000000099', '00000000-0000-0000-0000-000000000093');
insert into public.shared_appointments (relationship_id, client_id, creator_user_id, title, starts_at)
values ('90000000-0000-0000-0000-000000000009', '92000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000091', '測試約定', now() + interval '1 day');
insert into public.shared_items (id, relationship_id, client_id, creator_user_id, item_kind, text_content, appointment_client_id)
values
    ('94000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000009', '93000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000091', 'message', '主對話來源', null),
    ('94000000-0000-0000-0000-000000000002', '90000000-0000-0000-0000-000000000009', '93000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000091', 'message', '討論來源', '92000000-0000-0000-0000-000000000001'),
    ('94000000-0000-0000-0000-000000000003', '90000000-0000-0000-0000-000000000009', '93000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000092', 'message', '另一位建立者', null);

select ok(not has_table_privilege('authenticated', 'public.push_devices', 'select'), 'authenticated users cannot read device tokens');
select ok(not has_table_privilege('authenticated', 'public.push_delivery_jobs', 'select'), 'authenticated users cannot read delivery jobs');
select ok(has_table_privilege('service_role', 'public.push_devices', 'select'), 'worker can resolve recipient device tokens');
select ok(has_table_privilege('service_role', 'public.push_delivery_jobs', 'select'), 'worker can read routing metadata');
select ok(not has_table_privilege('service_role', 'public.push_delivery_jobs', 'update'), 'worker cannot bypass completion RPC');
select ok(to_regprocedure('public.enqueue_w1_test_push(uuid,uuid)') is null, 'W1 arbitrary event enqueue is removed');
select ok(has_function_privilege('authenticated', 'public.enqueue_push_event(text,uuid)', 'execute'), 'authenticated sender can use formal enqueue boundary');
select is(
    (select pg_get_function_identity_arguments('public.enqueue_push_event(text,uuid)'::regprocedure)),
    'target_event_kind text, target_source_item_id uuid',
    'client cannot provide a relationship or recipient to the enqueue boundary'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000091', true);
select lives_ok($$ select public.enqueue_push_event('chat_message_created', '94000000-0000-0000-0000-000000000001') $$, 'sender can enqueue main-chat source');
select lives_ok($$ select public.enqueue_push_event('chat_message_created', '94000000-0000-0000-0000-000000000001') $$, 'same source retry is idempotent');
select lives_ok($$ select public.enqueue_push_event('appointment_discussion_message_created', '94000000-0000-0000-0000-000000000002') $$, 'sender can enqueue appointment-discussion source');
select throws_ok($$ select public.enqueue_push_event('appointment_discussion_message_created', '94000000-0000-0000-0000-000000000001') $$, '42501', 'push_event_source_not_accessible', 'main-chat source cannot claim discussion event kind');
select throws_ok($$ select public.enqueue_push_event('status_updated', '94000000-0000-0000-0000-000000000001') $$, '22023', 'unsupported_push_event_kind', 'out-of-scope event is rejected');
select throws_ok($$ select public.enqueue_push_event('chat_message_created', '94000000-0000-0000-0000-000000000003') $$, '42501', 'push_event_source_not_accessible', 'member cannot enqueue a partner-created source');

reset role;
select results_eq(
    $$ select source_item_id::text || '/' || sender_user_id::text || '/' || recipient_user_id::text || '/' || event_kind from public.push_delivery_jobs order by source_item_id $$,
    array[
        '94000000-0000-0000-0000-000000000001/00000000-0000-0000-0000-000000000091/00000000-0000-0000-0000-000000000092/chat_message_created'::text,
        '94000000-0000-0000-0000-000000000002/00000000-0000-0000-0000-000000000091/00000000-0000-0000-0000-000000000092/appointment_discussion_message_created'::text
    ],
    'server derives exactly one recipient from each stable source identity'
);
select is((select count(*)::integer from public.push_delivery_jobs), 2, 'each source and recipient has one job despite retry');
select is((select count(*)::integer from information_schema.columns where table_schema = 'public' and table_name = 'push_delivery_jobs' and column_name in ('relationship_id', 'body', 'content', 'message', 'photo', 'moment', 'answer', 'token')), 0, 'delivery rows contain neither relationship identity, private content, nor device token');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000093', true);
select throws_ok($$ select public.enqueue_push_event('chat_message_created', '94000000-0000-0000-0000-000000000001') $$, '42501', 'push_event_source_not_accessible', 'non-member cannot enqueue another relationship source');

reset role;
update public.push_delivery_jobs
set event_kind = 'appointment_discussion_message_created'
where source_item_id = '94000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000091', true);
select throws_ok($$ select public.enqueue_push_event('chat_message_created', '94000000-0000-0000-0000-000000000001') $$, '23505', 'push_event_identity_collision', 'same source identity cannot be reused with conflicting event metadata');

reset role;
select public.begin_unpairing('90000000-0000-0000-0000-000000000009');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000091', true);
select throws_ok($$ select public.enqueue_push_event('chat_message_created', '94000000-0000-0000-0000-000000000001') $$, '23514', 'relationship_not_active_pair', 'closing relationship cannot enqueue a new event');

select * from finish();
rollback;

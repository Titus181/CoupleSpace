begin;

create extension if not exists pgtap with schema extensions;
select plan(16);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'claim-a@example.test', ''),
    ('00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'claim-b@example.test', '');
insert into public.relationships (id) values ('90000000-0000-0000-0000-000000000010');
insert into public.relationship_members (relationship_id, user_id) values
    ('90000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000101'),
    ('90000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000102');
insert into public.shared_items (id, relationship_id, client_id, creator_user_id, item_kind, text_content)
values ('94000000-0000-0000-0000-000000000010', '90000000-0000-0000-0000-000000000010', '93000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000101', 'message', 'claim source');
insert into public.push_delivery_jobs (id, source_item_id, sender_user_id, recipient_user_id, event_kind)
values ('95000000-0000-0000-0000-000000000001', '94000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000102', 'chat_message_created');

select ok(not has_function_privilege('authenticated', 'public.claim_push_delivery_job(uuid,uuid)', 'execute'), 'clients cannot claim jobs');
select ok(has_function_privilege('service_role', 'public.claim_push_delivery_job(uuid,uuid)', 'execute'), 'worker can claim jobs');
select ok(not has_table_privilege('service_role', 'public.push_delivery_jobs', 'update'), 'worker cannot update jobs directly');

set local role service_role;
select results_eq(
    $$ select job_id::text || '/' || source_item_id::text || '/' || event_kind || '/' || recipient_user_id::text || '/' || attempt_count::text from public.claim_push_delivery_job('95000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000101') $$,
    array['95000000-0000-0000-0000-000000000001/94000000-0000-0000-0000-000000000010/chat_message_created/00000000-0000-0000-0000-000000000102/1'::text],
    'claim returns only source identity, kind, recipient, lease, and attempt'
);
select ok((select claim_token is not null from public.push_delivery_jobs where id = '95000000-0000-0000-0000-000000000001'), 'claim stores an opaque completion lease');
select throws_ok($$ select public.claim_push_delivery_job('95000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000101') $$, '55000', 'push_job_not_claimable', 'in-flight job cannot be claimed twice');
select throws_ok($$ select public.complete_push_delivery_job('95000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000999', true) $$, '55000', 'push_job_not_completable', 'wrong lease cannot complete a claimed job');
select lives_ok($$ select public.complete_push_delivery_job('95000000-0000-0000-0000-000000000001', (select claim_token from public.push_delivery_jobs where id = '95000000-0000-0000-0000-000000000001'), false, 'BadDeviceToken') $$, 'failed delivery releases matching lease');
select results_eq($$ select attempt_count::text || '/' || coalesce(last_error, '') || '/' || (claimed_at is null)::text from public.push_delivery_jobs where id = '95000000-0000-0000-0000-000000000001' $$, array['1/BadDeviceToken/true'::text], 'failure preserves bounded reason and clears lease');
select is((select attempt_count from public.claim_push_delivery_job('95000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000101')), 2, 'released job retries with incremented attempt');

reset role;
select set_config('test.old_claim_token', (select claim_token::text from public.push_delivery_jobs where id = '95000000-0000-0000-0000-000000000001'), true);
update public.push_delivery_jobs set claimed_at = now() - interval '6 minutes' where id = '95000000-0000-0000-0000-000000000001';
set local role service_role;
select is((select attempt_count from public.claim_push_delivery_job('95000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000101')), 3, 'expired claim can be reclaimed');
select ok((select claim_token::text <> current_setting('test.old_claim_token') from public.push_delivery_jobs where id = '95000000-0000-0000-0000-000000000001'), 'reclaim replaces the completion lease');
select throws_ok($$ select public.complete_push_delivery_job('95000000-0000-0000-0000-000000000001', current_setting('test.old_claim_token')::uuid, true) $$, '55000', 'push_job_not_completable', 'timed-out worker cannot complete replacement claim');
select lives_ok($$ select public.complete_push_delivery_job('95000000-0000-0000-0000-000000000001', (select claim_token from public.push_delivery_jobs where id = '95000000-0000-0000-0000-000000000001'), true) $$, 'current lease marks delivery complete');
select throws_ok($$ select public.claim_push_delivery_job('95000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000101') $$, '55000', 'push_job_not_claimable', 'delivered job cannot be claimed');
select throws_ok($$ select public.claim_push_delivery_job('95000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000102') $$, '42501', 'push_job_not_accessible', 'sender mismatch cannot claim');

select * from finish();
rollback;

begin;

create extension if not exists pgtap with schema extensions;
select plan(11);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'claim-a@example.test', ''),
    ('00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'claim-b@example.test', '');

insert into public.relationships (id)
values ('90000000-0000-0000-0000-000000000010');

insert into public.relationship_members (relationship_id, user_id)
values
    ('90000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000101'),
    ('90000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000102');

insert into public.push_delivery_jobs (
    id,
    relationship_id,
    event_id,
    sender_user_id,
    recipient_user_id,
    event_kind
) values (
    '95000000-0000-0000-0000-000000000001',
    '90000000-0000-0000-0000-000000000010',
    '94000000-0000-0000-0000-000000000010',
    '00000000-0000-0000-0000-000000000101',
    '00000000-0000-0000-0000-000000000102',
    'w1_generic'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.claim_w1_push_job(uuid,uuid)',
        'execute'
    ),
    'authenticated clients cannot claim delivery jobs'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.claim_w1_push_job(uuid,uuid)',
        'execute'
    ),
    'trusted sender can claim delivery jobs'
);

select ok(
    not has_table_privilege('service_role', 'public.push_delivery_jobs', 'update'),
    'trusted sender cannot bypass the completion RPC with direct updates'
);

set local role service_role;

select results_eq(
    $$ select job_id::text || '/' || event_id::text || '/' || event_kind || '/'
              || recipient_user_id::text || '/' || attempt_count::text
       from public.claim_w1_push_job(
           '95000000-0000-0000-0000-000000000001',
           '00000000-0000-0000-0000-000000000101'
       ) $$,
    array['95000000-0000-0000-0000-000000000001/94000000-0000-0000-0000-000000000010/w1_generic/00000000-0000-0000-0000-000000000102/1'::text],
    'claim returns only generic routing metadata for the derived recipient'
);

select throws_ok(
    $$ select public.claim_w1_push_job(
        '95000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000101'
    ) $$,
    '55000',
    'push_job_not_claimable',
    'an in-flight job cannot be claimed twice'
);

select lives_ok(
    $$ select public.complete_w1_push_job(
        '95000000-0000-0000-0000-000000000001',
        false,
        'BadDeviceToken'
    ) $$,
    'failed APNs delivery releases the job for explicit retry'
);

select results_eq(
    $$ select attempt_count::text || '/' || coalesce(last_error, '') || '/'
              || (claimed_at is null)::text
       from public.push_delivery_jobs
       where id = '95000000-0000-0000-0000-000000000001' $$,
    array['1/BadDeviceToken/true'::text],
    'failed completion preserves a bounded reason and clears the claim'
);

select results_eq(
    $$ select attempt_count
       from public.claim_w1_push_job(
           '95000000-0000-0000-0000-000000000001',
           '00000000-0000-0000-0000-000000000101'
       ) $$,
    array[2],
    'released job can be claimed again with an incremented attempt'
);

select lives_ok(
    $$ select public.complete_w1_push_job(
        '95000000-0000-0000-0000-000000000001',
        true,
        null
    ) $$,
    'successful APNs delivery marks the claimed job complete'
);

select throws_ok(
    $$ select public.claim_w1_push_job(
        '95000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000101'
    ) $$,
    '55000',
    'push_job_not_claimable',
    'delivered job cannot be claimed again'
);

select throws_ok(
    $$ select public.claim_w1_push_job(
        '95000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000102'
    ) $$,
    '42501',
    'push_job_not_accessible',
    'sender identity mismatch cannot claim the job'
);

select * from finish();
rollback;

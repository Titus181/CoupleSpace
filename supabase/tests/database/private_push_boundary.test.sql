begin;

create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-000000000091', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'push-a@example.test', ''),
    ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'push-b@example.test', ''),
    ('00000000-0000-0000-0000-000000000093', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'push-c@example.test', '');

insert into public.relationships (id)
values
    ('90000000-0000-0000-0000-000000000009'),
    ('90000000-0000-0000-0000-000000000099');

insert into public.relationship_members (relationship_id, user_id)
values
    ('90000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000091'),
    ('90000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000092'),
    ('90000000-0000-0000-0000-000000000099', '00000000-0000-0000-0000-000000000093');

select ok(
    not has_table_privilege('authenticated', 'public.push_devices', 'select'),
    'authenticated users cannot read device tokens directly'
);

select ok(
    not has_table_privilege('authenticated', 'public.push_delivery_jobs', 'select'),
    'authenticated users cannot inspect push delivery jobs directly'
);

select ok(
    has_table_privilege('service_role', 'public.push_devices', 'select'),
    'trusted sender role can resolve recipient device tokens'
);

select ok(
    has_table_privilege('service_role', 'public.push_delivery_jobs', 'select,update'),
    'trusted sender role can claim and complete delivery jobs'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000091', true);

select lives_ok(
    $$ select public.register_push_device(' A1b2C3d4 ', 'SANDBOX') $$,
    'authenticated user can register a normalized APNs token'
);

select lives_ok(
    $$ select public.register_push_device('a1b2c3d4', 'sandbox') $$,
    'registering the same token is idempotent'
);

select throws_ok(
    $$ select public.register_push_device('not-hex', 'sandbox') $$,
    '22023',
    'invalid_device_token',
    'non-hex APNs token is rejected'
);

select throws_ok(
    $$ select public.register_push_device('abc', 'sandbox') $$,
    '22023',
    'invalid_device_token',
    'odd-length APNs token is rejected'
);

select throws_ok(
    $$ select public.register_push_device('a1b2', 'preview') $$,
    '22023',
    'invalid_push_environment',
    'unknown APNs environment is rejected'
);

select lives_ok(
    $$ select public.enqueue_w1_test_push(
        '90000000-0000-0000-0000-000000000009',
        '94000000-0000-0000-0000-000000000001'
    ) $$,
    'member can enqueue a generic W1 push'
);

select lives_ok(
    $$ select public.enqueue_w1_test_push(
        '90000000-0000-0000-0000-000000000009',
        '94000000-0000-0000-0000-000000000001'
    ) $$,
    'retrying the same event is idempotent'
);

reset role;
select results_eq(
    $$ select user_id::text || '/' || token || '/' || environment || '/' || bundle_id
       from public.push_devices $$,
    array['00000000-0000-0000-0000-000000000091/a1b2c3d4/sandbox/com.titus.CoupleSpace'::text],
    'server stores only the normalized token for the authenticated user'
);

select results_eq(
    $$ select count(*)::integer from public.push_delivery_jobs
       where relationship_id = '90000000-0000-0000-0000-000000000009'
         and event_id = '94000000-0000-0000-0000-000000000001' $$,
    array[1],
    'an enqueue retry creates exactly one delivery job'
);

select results_eq(
    $$ select sender_user_id::text || '/' || recipient_user_id::text || '/' || event_kind
       from public.push_delivery_jobs
       where relationship_id = '90000000-0000-0000-0000-000000000009'
         and event_id = '94000000-0000-0000-0000-000000000001' $$,
    array['00000000-0000-0000-0000-000000000091/00000000-0000-0000-0000-000000000092/w1_generic'::text],
    'server derives the other active member as recipient and fixes the generic event kind'
);

select is(
    (
        select count(*)::integer
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'push_delivery_jobs'
          and column_name in ('body', 'content', 'message', 'photo', 'title')
    ),
    0,
    'delivery jobs have no private-content columns'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000093', true);

select throws_ok(
    $$ select public.enqueue_w1_test_push(
        '90000000-0000-0000-0000-000000000009',
        '94000000-0000-0000-0000-000000000002'
    ) $$,
    '42501',
    'relationship_not_accessible',
    'third user cannot enqueue for another relationship'
);

select throws_ok(
    $$ select public.enqueue_w1_test_push(
        '90000000-0000-0000-0000-000000000099',
        '94000000-0000-0000-0000-000000000003'
    ) $$,
    '23514',
    'relationship_requires_two_members',
    'one-member relationship cannot choose a push recipient'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000091', true);
select public.begin_unpairing('90000000-0000-0000-0000-000000000009');

select throws_ok(
    $$ select public.enqueue_w1_test_push(
        '90000000-0000-0000-0000-000000000009',
        '94000000-0000-0000-0000-000000000004'
    ) $$,
    '23514',
    'relationship_not_active',
    'closing relationship cannot enqueue a push'
);

select * from finish();
rollback;

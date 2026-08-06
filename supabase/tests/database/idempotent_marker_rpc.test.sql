begin;

create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-000000000051', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'outbox-a@example.test', ''),
    ('00000000-0000-0000-0000-000000000052', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'outbox-b@example.test', ''),
    ('00000000-0000-0000-0000-000000000053', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'outbox-c@example.test', '');

insert into public.relationships (id)
values ('90000000-0000-0000-0000-000000000001');

insert into public.relationship_members (relationship_id, user_id)
values
    ('90000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000051'),
    ('90000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000052');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000051', true);

select lives_ok(
    $$
        select public.write_shared_marker(
            '90000000-0000-0000-0000-000000000001',
            '91000000-0000-0000-0000-000000000001'
        )
    $$,
    'relationship member can create a marker through the RPC'
);

select lives_ok(
    $$
        select public.write_shared_marker(
            '90000000-0000-0000-0000-000000000001',
            '91000000-0000-0000-0000-000000000001'
        )
    $$,
    'retrying the same marker identity is accepted'
);

reset role;
select results_eq(
    $$
        select count(*)::integer
        from public.shared_items
        where relationship_id = '90000000-0000-0000-0000-000000000001'
          and client_id = '91000000-0000-0000-0000-000000000001'
    $$,
    array[1],
    'an accepted retry does not create a duplicate row'
);

select results_eq(
    $$
        select creator_user_id::text || '/' || item_kind
        from public.shared_items
        where relationship_id = '90000000-0000-0000-0000-000000000001'
          and client_id = '91000000-0000-0000-0000-000000000001'
    $$,
    array['00000000-0000-0000-0000-000000000051/marker'::text],
    'the RPC derives creator identity and marker kind from the session'
);

set local role authenticated;
select lives_ok(
    $$
        select public.write_shared_marker(
            '90000000-0000-0000-0000-000000000001',
            '91000000-0000-0000-0000-000000000004'
        )
    $$,
    'the same member can create a second marker with a different client identity'
);

select lives_ok(
    $$
        select public.write_shared_marker(
            '90000000-0000-0000-0000-000000000001',
            '91000000-0000-0000-0000-000000000004'
        )
    $$,
    'retrying the second marker identity is accepted independently'
);

reset role;
select results_eq(
    $$
        select count(*)::integer
        from public.shared_items
        where relationship_id = '90000000-0000-0000-0000-000000000001'
          and client_id in (
              '91000000-0000-0000-0000-000000000001',
              '91000000-0000-0000-0000-000000000004'
          )
    $$,
    array[2],
    'two independent marker identities produce exactly two rows after retries'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000052', true);

select throws_ok(
    $$
        select public.write_shared_marker(
            '90000000-0000-0000-0000-000000000001',
            '91000000-0000-0000-0000-000000000001'
        )
    $$,
    '23505',
    'shared_item_identity_collision',
    'another participant cannot claim the same client identity'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000053', true);

select throws_ok(
    $$
        select public.write_shared_marker(
            '90000000-0000-0000-0000-000000000001',
            '91000000-0000-0000-0000-000000000002'
        )
    $$,
    '42501',
    'relationship_not_accessible',
    'a third user cannot write a marker'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000051', true);
select public.begin_unpairing('90000000-0000-0000-0000-000000000001');

select throws_ok(
    $$
        select public.write_shared_marker(
            '90000000-0000-0000-0000-000000000001',
            '91000000-0000-0000-0000-000000000003'
        )
    $$,
    '23514',
    'relationship_not_active',
    'closing relationship rejects an outbox retry'
);

select * from finish();
rollback;

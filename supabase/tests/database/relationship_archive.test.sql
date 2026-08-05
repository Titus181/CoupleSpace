begin;

create extension if not exists pgtap with schema extensions;
select plan(16);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'first@example.test', ''),
    ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'second@example.test', ''),
    ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'third@example.test', '');

insert into public.relationships (id)
values ('10000000-0000-0000-0000-000000000001');

insert into public.relationship_members (relationship_id, user_id)
values
    ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001'),
    ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002');

insert into public.relationships (id)
values ('10000000-0000-0000-0000-000000000002');

select throws_ok(
    $$
        insert into public.relationship_members (relationship_id, user_id)
        values (
            '10000000-0000-0000-0000-000000000002',
            '00000000-0000-0000-0000-000000000001'
        )
    $$,
    '23505',
    null,
    'participant cannot have two current relationships'
);

set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-000000000001',
    true
);

select results_eq(
    $$ select count(*)::integer from public.relationships $$,
    array[1],
    'first participant can read the relationship'
);

reset role;
set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-000000000003',
    true
);

select results_eq(
    $$ select count(*)::integer from public.relationships $$,
    array[0],
    'third user cannot read the relationship'
);

select throws_ok(
    $$
        insert into public.shared_items (
            relationship_id,
            client_id,
            creator_user_id,
            item_kind
        ) values (
            '10000000-0000-0000-0000-000000000001',
            '20000000-0000-0000-0000-000000000001',
            '00000000-0000-0000-0000-000000000003',
            'marker'
        )
    $$,
    '42501',
    null,
    'third user cannot add shared content'
);

reset role;
set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-000000000001',
    true
);

select lives_ok(
    $$
        insert into public.shared_items (
            relationship_id,
            client_id,
            creator_user_id,
            item_kind
        ) values (
            '10000000-0000-0000-0000-000000000001',
            '20000000-0000-0000-0000-000000000002',
            '00000000-0000-0000-0000-000000000001',
            'marker'
        )
    $$,
    'member can add shared content while active'
);

select lives_ok(
    $$ select public.begin_unpairing('10000000-0000-0000-0000-000000000001') $$,
    'member can begin unpairing'
);

select throws_ok(
    $$
        insert into public.shared_items (
            relationship_id,
            client_id,
            creator_user_id,
            item_kind
        ) values (
            '10000000-0000-0000-0000-000000000001',
            '20000000-0000-0000-0000-000000000003',
            '00000000-0000-0000-0000-000000000001',
            'message'
        )
    $$,
    '42501',
    null,
    'closing relationship rejects new shared content'
);

select lives_ok(
    $$ select public.seal_personal_archive('10000000-0000-0000-0000-000000000001') $$,
    'first participant can seal a personal archive'
);

reset role;
select results_eq(
    $$ select status from public.relationships where id = '10000000-0000-0000-0000-000000000001' $$,
    array['closing'::text],
    'one archive is not enough to finalize unpairing'
);

set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-000000000003',
    true
);

select results_eq(
    $$ select count(*)::integer from public.personal_archives $$,
    array[0],
    'third user cannot read either personal archive'
);

reset role;
set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-000000000002',
    true
);

select lives_ok(
    $$ select public.seal_personal_archive('10000000-0000-0000-0000-000000000001') $$,
    'second participant can seal a personal archive'
);

reset role;
select results_eq(
    $$ select status from public.relationships where id = '10000000-0000-0000-0000-000000000001' $$,
    array['archived'::text],
    'both archives finalize unpairing'
);

set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-000000000001',
    true
);

select results_eq(
    $$ select count(*)::integer from public.personal_archives $$,
    array[1],
    'first participant sees only their personal archive'
);

select results_eq(
    $$ select count(*)::integer from public.personal_archive_items $$,
    array[1],
    'personal archive contains the server-copied shared item'
);

select lives_ok(
    $$ delete from public.personal_archives $$,
    'first participant can delete their personal archive'
);

reset role;
select results_eq(
    $$
        select count(*)::integer
        from public.personal_archives
        where owner_user_id = '00000000-0000-0000-0000-000000000002'
    $$,
    array[1],
    'deleting one personal archive does not delete the other'
);

select * from finish();
rollback;

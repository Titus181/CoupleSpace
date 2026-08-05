begin;

create extension if not exists pgtap with schema extensions;
select plan(11);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'delete-archive-a@example.test', ''),
    ('00000000-0000-0000-0000-000000000042', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'delete-archive-b@example.test', ''),
    ('00000000-0000-0000-0000-000000000043', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'delete-archive-c@example.test', '');

insert into public.relationships (id)
values ('70000000-0000-0000-0000-000000000001');

insert into public.relationship_members (relationship_id, user_id)
values
    ('70000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000041'),
    ('70000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000042');

insert into public.shared_items (
    relationship_id,
    client_id,
    creator_user_id,
    item_kind
) values
    (
        '70000000-0000-0000-0000-000000000001',
        '80000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000041',
        'photo'
    ),
    (
        '70000000-0000-0000-0000-000000000001',
        '80000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-000000000042',
        'marker'
    );

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000041', true);

select public.begin_unpairing('70000000-0000-0000-0000-000000000001');
select public.seal_personal_archive('70000000-0000-0000-0000-000000000001');

select throws_ok(
    $$ delete from public.personal_archives $$,
    '42501',
    null,
    'authenticated clients cannot bypass the deletion RPC'
);

select throws_ok(
    $$
        select public.delete_personal_archive(
            (select id from public.personal_archives limit 1)
        )
    $$,
    '23514',
    'relationship_not_archived',
    'an archive cannot be deleted before both participants finish unpairing'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000042', true);
select public.seal_personal_archive('70000000-0000-0000-0000-000000000001');

reset role;
select set_config(
    'test.first_archive_id',
    (
        select id::text
        from public.personal_archives
        where owner_user_id = '00000000-0000-0000-0000-000000000041'
    ),
    true
);
select set_config(
    'test.second_archive_id',
    (
        select id::text
        from public.personal_archives
        where owner_user_id = '00000000-0000-0000-0000-000000000042'
    ),
    true
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000043', true);

select throws_ok(
    format(
        'select public.delete_personal_archive(%L::uuid)',
        current_setting('test.first_archive_id')
    ),
    '42501',
    'personal_archive_not_accessible',
    'a third user cannot delete another person archive'
);

select throws_ok(
    $$ select count(*)::integer from public.storage_gc_queue $$,
    '42501',
    null,
    'authenticated clients cannot access the protected GC queue'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000041', true);

select results_eq(
    format(
        'select public.delete_personal_archive(%L::uuid)',
        current_setting('test.first_archive_id')
    ),
    array[0],
    'deleting the first personal archive does not queue shared objects'
);

reset role;
select results_eq(
    $$ select count(*)::integer from public.personal_archives $$,
    array[1],
    'the other participant archive remains'
);

select results_eq(
    $$ select count(*)::integer from public.storage_gc_queue $$,
    array[0],
    'the shared photo remains unqueued while one archive still needs it'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000042', true);

select results_eq(
    format(
        'select public.delete_personal_archive(%L::uuid)',
        current_setting('test.second_archive_id')
    ),
    array[1],
    'deleting the final personal archive queues one shared photo'
);

reset role;
select results_eq(
    $$ select count(*)::integer from public.personal_archives $$,
    array[0],
    'the final personal archive is deleted'
);

select results_eq(
    $$ select bucket_id || '/' || object_path from public.storage_gc_queue $$,
    array[
        'couplespace-w1-photos/70000000-0000-0000-0000-000000000001/80000000-0000-0000-0000-000000000001.jpg'::text
    ],
    'the queue contains only the deterministic archived photo path'
);

select results_eq(
    $$ select count(*)::integer from public.shared_items $$,
    array[2],
    'archive deletion does not silently delete shared metadata'
);

select * from finish();
rollback;

begin;

create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'storage-a@example.test', ''),
    ('00000000-0000-0000-0000-000000000022', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'storage-b@example.test', ''),
    ('00000000-0000-0000-0000-000000000023', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'storage-c@example.test', '');

insert into public.relationships (id)
values ('30000000-0000-0000-0000-000000000001');

insert into public.relationship_members (relationship_id, user_id)
values
    ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000021'),
    ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000022');

select results_eq(
    $$
        select public::integer
        from storage.buckets
        where id = 'couplespace-w1-photos'
    $$,
    array[0],
    'W1 photo bucket is private'
);

select results_eq(
    $$
        select file_size_limit::bigint
        from storage.buckets
        where id = 'couplespace-w1-photos'
    $$,
    array[5242880::bigint],
    'W1 photo bucket limits files to five MiB'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', true);

select lives_ok(
    $$
        insert into storage.objects (bucket_id, name, owner_id)
        values (
            'couplespace-w1-photos',
            '30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001.jpg',
            '00000000-0000-0000-0000-000000000021'
        )
    $$,
    'member can upload to their active relationship folder'
);

select results_eq(
    $$ select count(*)::integer from storage.objects where bucket_id = 'couplespace-w1-photos' $$,
    array[1],
    'uploader can read their stored photo object'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000022', true);

select results_eq(
    $$ select count(*)::integer from storage.objects where bucket_id = 'couplespace-w1-photos' $$,
    array[1],
    'partner can read the relationship photo object'
);

select set_config('storage.allow_delete_query', 'true', true);

select results_eq(
    $$
        with deleted as (
            delete from storage.objects
            where bucket_id = 'couplespace-w1-photos'
            returning 1
        )
        select count(*)::integer from deleted
    $$,
    array[0],
    'partner cannot delete a photo they did not upload'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000023', true);

select results_eq(
    $$ select count(*)::integer from storage.objects where bucket_id = 'couplespace-w1-photos' $$,
    array[0],
    'third user cannot read the relationship photo object'
);

select throws_ok(
    $$
        insert into storage.objects (bucket_id, name, owner_id)
        values (
            'couplespace-w1-photos',
            '30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000002.jpg',
            '00000000-0000-0000-0000-000000000023'
        )
    $$,
    '42501',
    null,
    'third user cannot upload to the relationship folder'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', true);
select public.begin_unpairing('30000000-0000-0000-0000-000000000001');

select throws_ok(
    $$
        insert into storage.objects (bucket_id, name, owner_id)
        values (
            'couplespace-w1-photos',
            '30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000003.jpg',
            '00000000-0000-0000-0000-000000000021'
        )
    $$,
    '42501',
    null,
    'closing relationship rejects new photo uploads'
);

select lives_ok(
    $$
        delete from storage.objects
        where bucket_id = 'couplespace-w1-photos'
    $$,
    'uploader can delete their own stored photo object'
);

select * from finish();
rollback;

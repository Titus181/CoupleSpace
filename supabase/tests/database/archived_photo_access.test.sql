begin;

create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'archive-photo-a@example.test', ''),
    ('00000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'archive-photo-b@example.test', ''),
    ('00000000-0000-0000-0000-000000000033', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'archive-photo-c@example.test', '');

insert into public.relationships (id)
values ('50000000-0000-0000-0000-000000000001');

insert into public.relationship_members (relationship_id, user_id)
values
    ('50000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000031'),
    ('50000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000032');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000031', true);

insert into storage.objects (bucket_id, name, owner_id)
values (
    'couplespace-w1-photos',
    '50000000-0000-0000-0000-000000000001/60000000-0000-0000-0000-000000000001.jpg',
    '00000000-0000-0000-0000-000000000031'
);

reset role;
insert into public.shared_items (
    relationship_id,
    client_id,
    creator_user_id,
    item_kind,
    media_byte_size
)
values (
    '50000000-0000-0000-0000-000000000001',
    '60000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000031',
    'photo',
    1024
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000031', true);
select public.begin_unpairing('50000000-0000-0000-0000-000000000001');
select public.seal_personal_archive('50000000-0000-0000-0000-000000000001');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000032', true);
select public.seal_personal_archive('50000000-0000-0000-0000-000000000001');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000031', true);

select results_eq(
    $$ select count(*)::integer from storage.objects where bucket_id = 'couplespace-w1-photos' $$,
    array[1],
    'first archive owner can read the archived photo'
);

select results_eq(
    $$ select media_byte_size from public.personal_archive_items $$,
    array[1024::bigint],
    'the personal archive preserves the verified photo byte size'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000032', true);

select results_eq(
    $$ select count(*)::integer from storage.objects where bucket_id = 'couplespace-w1-photos' $$,
    array[1],
    'second archive owner can read the archived photo'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000033', true);

select results_eq(
    $$ select count(*)::integer from storage.objects where bucket_id = 'couplespace-w1-photos' $$,
    array[0],
    'third user cannot read the archived photo'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000031', true);

select lives_ok(
    $$
        select public.delete_personal_archive(
            (select id from public.personal_archives limit 1)
        )
    $$,
    'first owner can delete only their personal archive through the RPC'
);

select results_eq(
    $$ select count(*)::integer from storage.objects where bucket_id = 'couplespace-w1-photos' $$,
    array[0],
    'deleting the first archive removes only the first owner access'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000032', true);

select results_eq(
    $$ select count(*)::integer from storage.objects where bucket_id = 'couplespace-w1-photos' $$,
    array[1],
    'second archive owner keeps access after the first archive is deleted'
);

reset role;
select results_eq(
    $$ select count(*)::integer from storage.objects where bucket_id = 'couplespace-w1-photos' $$,
    array[1],
    'the shared object remains while an archive owner still needs it'
);

select * from finish();
rollback;

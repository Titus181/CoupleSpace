begin;

create extension if not exists pgtap with schema extensions;
select plan(25);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'archive-a@example.test', ''),
    ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'archive-b@example.test', ''),
    ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'archive-c@example.test', '');

insert into public.relationships (id)
values ('f0000000-0000-0000-0000-000000000001');

insert into public.relationship_members (relationship_id, user_id)
values
    ('f0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000f1'),
    ('f0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000f2');

insert into public.shared_items (
    id, relationship_id, client_id, creator_user_id, item_kind, text_content
)
values (
    'f1000000-0000-0000-0000-000000000001',
    'f0000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-0000000000f1',
    'message',
    '週末一起吃飯'
);

insert into public.shared_appointments (
    relationship_id,
    client_id,
    creator_user_id,
    title,
    starts_at,
    location,
    note,
    reminder_at,
    source_shared_item_client_id,
    created_at,
    updated_at
)
values (
    'f0000000-0000-0000-0000-000000000001',
    'f3000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-0000000000f1',
    '週末晚餐',
    '2026-08-17 11:30:00+00',
    '中山站',
    '記得訂位',
    '2026-08-17 10:30:00+00',
    'f2000000-0000-0000-0000-000000000001',
    '2026-08-14 01:00:00+00',
    '2026-08-14 02:00:00+00'
);

insert into public.shared_items (
    id,
    relationship_id,
    client_id,
    creator_user_id,
    item_kind,
    text_content,
    media_byte_size,
    appointment_client_id,
    created_at
)
values
    (
        'f1000000-0000-0000-0000-000000000002',
        'f0000000-0000-0000-0000-000000000001',
        'f2000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-0000000000f2',
        'message',
        '我來訂位',
        null,
        'f3000000-0000-0000-0000-000000000001',
        '2026-08-14 01:10:00+00'
    ),
    (
        'f1000000-0000-0000-0000-000000000003',
        'f0000000-0000-0000-0000-000000000001',
        'f2000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-0000000000f1',
        'photo',
        null,
        2048,
        'f3000000-0000-0000-0000-000000000001',
        '2026-08-14 01:20:00+00'
    );

insert into public.shared_appointment_operations (
    relationship_id,
    operation_id,
    appointment_client_id,
    actor_user_id,
    operation_kind,
    title,
    starts_at,
    created_at
)
values (
    'f0000000-0000-0000-0000-000000000001',
    'f4000000-0000-0000-0000-000000000001',
    'f3000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-0000000000f2',
    'update',
    '週末晚餐',
    '2026-08-17 11:30:00+00',
    '2026-08-14 02:00:00+00'
);

insert into public.shared_appointment_events (
    relationship_id,
    operation_id,
    appointment_client_id,
    actor_user_id,
    event_kind,
    previous_starts_at,
    starts_at,
    created_at
)
values (
    'f0000000-0000-0000-0000-000000000001',
    'f4000000-0000-0000-0000-000000000001',
    'f3000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-0000000000f2',
    'rescheduled',
    '2026-08-17 11:00:00+00',
    '2026-08-17 11:30:00+00',
    '2026-08-14 02:00:00+00'
);

select has_table(
    'public',
    'personal_archive_appointments',
    'personal archives have an appointment snapshot table'
);

select has_table(
    'public',
    'personal_archive_appointment_events',
    'personal archives have an immutable appointment event table'
);

select results_eq(
    $$
        select count(*)::integer
        from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.personal_archive_items'::regclass
          and constraint_row.contype = 'f'
          and constraint_row.conname = 'personal_archive_items_appointment_fk'
    $$,
    array[1],
    'archived discussion items retain an enforced appointment link'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', true);

select lives_ok(
    $$ select public.begin_unpairing('f0000000-0000-0000-0000-000000000001') $$,
    'a member can begin unpairing with W11 content present'
);

select lives_ok(
    $$ select public.seal_personal_archive('f0000000-0000-0000-0000-000000000001') $$,
    'the first member can seal the appointment-aware archive'
);

select results_eq(
    $$ select count(*)::integer from public.personal_archive_appointments $$,
    array[1],
    'the owner sees one archived appointment'
);

select results_eq(
    $$
        select title || '/' || location || '/' || note || '/' || status || '/'
            || source_shared_item_client_id::text
        from public.personal_archive_appointments
    $$,
    array['週末晚餐/中山站/記得訂位/scheduled/f2000000-0000-0000-0000-000000000001'::text],
    'the appointment snapshot retains content, state, and source message identity'
);

select results_eq(
    $$
        select client_id::text || '/' || source_creator_user_id::text || '/'
            || item_kind || '/' || appointment_client_id::text
        from public.personal_archive_items
        where appointment_client_id is not null
        order by created_at
    $$,
    array[
        'f2000000-0000-0000-0000-000000000002/00000000-0000-0000-0000-0000000000f2/message/f3000000-0000-0000-0000-000000000001'::text,
        'f2000000-0000-0000-0000-000000000003/00000000-0000-0000-0000-0000000000f1/photo/f3000000-0000-0000-0000-000000000001'::text
    ],
    'archived text and photo discussions retain scope and original creator'
);

select results_eq(
    $$
        select appointment_client_id is null
        from public.personal_archive_items
        where client_id = 'f2000000-0000-0000-0000-000000000001'
    $$,
    array[true],
    'the source conversation message remains outside the appointment discussion'
);

select results_eq(
    $$
        select event_kind || '/' || actor_user_id::text || '/'
            || previous_starts_at::text || '/' || starts_at::text
        from public.personal_archive_appointment_events
    $$,
    array[
        'rescheduled/00000000-0000-0000-0000-0000000000f2/2026-08-17 11:00:00+00/2026-08-17 11:30:00+00'::text
    ],
    'the archive retains the immutable major-change record and actor'
);

select throws_ok(
    $$
        insert into public.personal_archive_appointments (
            archive_id, owner_user_id, client_id, creator_user_id, title, starts_at,
            status, created_at, updated_at
        )
        select id, owner_user_id, gen_random_uuid(), owner_user_id, 'forged', now(),
            'scheduled', now(), now()
        from public.personal_archives
        limit 1
    $$,
    '42501',
    null,
    'authenticated clients cannot forge archived appointments'
);

select throws_ok(
    $$
        insert into public.personal_archive_appointment_events (
            archive_id, owner_user_id, operation_id, appointment_client_id,
            actor_user_id, event_kind, created_at
        )
        select archive_id, owner_user_id, gen_random_uuid(), client_id,
            owner_user_id, 'cancelled', now()
        from public.personal_archive_appointments
        limit 1
    $$,
    '42501',
    null,
    'authenticated clients cannot forge archived appointment events'
);

select lives_ok(
    $$ select public.seal_personal_archive('f0000000-0000-0000-0000-000000000001') $$,
    'retrying the first seal while closing remains safe'
);

select results_eq(
    $$
        select (select count(*) from public.personal_archive_appointments)::text || '/'
            || (select count(*) from public.personal_archive_appointment_events)::text
    $$,
    array['1/1'::text],
    'a seal retry does not duplicate appointment snapshots or events'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f2', true);

select results_eq(
    $$ select count(*)::integer from public.personal_archive_appointments $$,
    array[0],
    'the partner cannot read the first owner archive'
);

select results_eq(
    $$ select count(*)::integer from public.personal_archive_appointment_events $$,
    array[0],
    'the partner cannot read the first owner event archive'
);

select lives_ok(
    $$ select public.seal_personal_archive('f0000000-0000-0000-0000-000000000001') $$,
    'the second member can seal an independent archive'
);

select results_eq(
    $$ select count(*)::integer from public.personal_archive_appointments $$,
    array[1],
    'the second owner sees only their appointment snapshot'
);

reset role;
select results_eq(
    $$ select status from public.relationships where id = 'f0000000-0000-0000-0000-000000000001' $$,
    array['archived'::text],
    'two complete personal archives finalize unpairing'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', true);

select results_eq(
    $$ select count(*)::integer from public.personal_archive_appointments $$,
    array[0],
    'a third user cannot read archived appointments'
);

select results_eq(
    $$ select count(*)::integer from public.personal_archive_appointment_events $$,
    array[0],
    'a third user cannot read archived appointment events'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', true);

select lives_ok(
    $$
        select public.delete_personal_archive(
            (select id from public.personal_archives limit 1)
        )
    $$,
    'an owner can delete their appointment-aware archive'
);

select results_eq(
    $$ select count(*)::integer from public.personal_archive_appointments $$,
    array[0],
    'deleting one archive cascades its appointment snapshot'
);

select results_eq(
    $$ select count(*)::integer from public.personal_archive_appointment_events $$,
    array[0],
    'deleting one archive cascades its event snapshot'
);

reset role;
select results_eq(
    $$
        select count(*)::integer
        from public.personal_archive_appointments appointment
        join public.personal_archives archive on archive.id = appointment.archive_id
        where archive.owner_user_id = '00000000-0000-0000-0000-0000000000f2'
    $$,
    array[1],
    'deleting one owner archive leaves the other owner appointment snapshot intact'
);

select * from finish();
rollback;

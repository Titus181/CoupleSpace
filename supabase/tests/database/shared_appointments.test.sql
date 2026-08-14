begin;

create extension if not exists pgtap with schema extensions;
select plan(25);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'appointment-a@example.test', ''),
    ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'appointment-b@example.test', ''),
    ('00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'appointment-c@example.test', '');

insert into public.relationships (id)
values ('e0000000-0000-0000-0000-000000000001');

insert into public.relationship_members (relationship_id, user_id)
values
    ('e0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000e1'),
    ('e0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000e2');

insert into public.shared_items (
    relationship_id, client_id, creator_user_id, item_kind, text_content, media_byte_size
)
values
    (
        'e0000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-0000000000e1',
        'message',
        '週末一起吃晚餐',
        null
    ),
    (
        'e0000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-0000000000e1',
        'photo',
        null,
        null
    );

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e1', true);

select results_eq(
    $$
        select client_id::text || '/' || creator_user_id::text || '/' || title || '/'
            || status || '/' || source_shared_item_client_id::text
        from public.create_shared_appointment(
            'e0000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000001',
            '  週末晚餐  ',
            '2026-08-16 19:00:00+08',
            '  中山站  ',
            '  記得訂位  ',
            '2026-08-16 18:00:00+08',
            'e1000000-0000-0000-0000-000000000001'
        )
    $$,
    array[
        'e2000000-0000-0000-0000-000000000001/00000000-0000-0000-0000-0000000000e1/週末晚餐/scheduled/e1000000-0000-0000-0000-000000000001'::text
    ],
    'a member can create a normalized appointment from a text message'
);

select results_eq(
    $$
        select location || '/' || note
        from public.shared_appointments
        where relationship_id = 'e0000000-0000-0000-0000-000000000001'
          and client_id = 'e2000000-0000-0000-0000-000000000001'
    $$,
    array['中山站/記得訂位'::text],
    'optional appointment text is normalized before storage'
);

select results_eq(
    $$
        select client_id::text
        from public.create_shared_appointment(
            'e0000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000001',
            '週末晚餐',
            '2026-08-16 19:00:00+08',
            '中山站',
            '記得訂位',
            '2026-08-16 18:00:00+08',
            'e1000000-0000-0000-0000-000000000001'
        )
    $$,
    array['e2000000-0000-0000-0000-000000000001'::text],
    'retrying the same stable appointment identity is accepted'
);

select results_eq(
    $$ select count(*)::integer from public.shared_appointments $$,
    array[1],
    'an idempotent create retry produces no duplicate appointment'
);

select throws_ok(
    $$
        select public.create_shared_appointment(
            'e0000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000001',
            'different title',
            '2026-08-16 19:00:00+08'
        )
    $$,
    '23505',
    'appointment_identity_collision',
    'a stable appointment identity cannot be reused with different content'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e2', true);

select results_eq(
    $$
        select client_id::text || '/' || creator_user_id::text
        from public.create_shared_appointment(
            'e0000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000002',
            '週末晚餐',
            '2026-08-16 19:00:00+08',
            '中山站',
            '記得訂位',
            '2026-08-16 18:00:00+08',
            'e1000000-0000-0000-0000-000000000001'
        )
    $$,
    array['e2000000-0000-0000-0000-000000000001/00000000-0000-0000-0000-0000000000e1'::text],
    'the same source message converges on the existing appointment across both devices'
);

select results_eq(
    $$ select count(*)::integer from public.shared_appointments $$,
    array[1],
    'one source message cannot create duplicate appointment cards'
);

select results_eq(
    $$
        select title || '/' || coalesce(location, '') || '/' || note
        from public.update_shared_appointment(
            'e0000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000001',
            'e3000000-0000-0000-0000-000000000001',
            '週日晚餐',
            '2026-08-17 19:30:00+08',
            '',
            '提早十分鐘',
            null
        )
    $$,
    array['週日晚餐//提早十分鐘'::text],
    'either partner can edit the shared appointment in place'
);

reset role;
update public.shared_appointments
set updated_at = '2026-08-14 00:00:00+00'
where relationship_id = 'e0000000-0000-0000-0000-000000000001'
  and client_id = 'e2000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e2', true);

select results_eq(
    $$
        select updated_at::text
        from public.update_shared_appointment(
            'e0000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000001',
            'e3000000-0000-0000-0000-000000000001',
            '週日晚餐',
            '2026-08-17 19:30:00+08',
            '',
            '提早十分鐘',
            null
        )
    $$,
    array['2026-08-14 00:00:00+00'::text],
    'replaying an identical edit does not refresh the server timestamp'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e1', true);
select results_eq(
    $$
        select title
        from public.update_shared_appointment(
            'e0000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000001',
            'e3000000-0000-0000-0000-000000000006',
            '伴侶較新的編輯',
            '2026-08-17 20:00:00+08'
        )
    $$,
    array['伴侶較新的編輯'::text],
    'a different stable operation can apply a newer edit'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e2', true);
select results_eq(
    $$
        select title
        from public.update_shared_appointment(
            'e0000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000001',
            'e3000000-0000-0000-0000-000000000001',
            '週日晚餐',
            '2026-08-17 19:30:00+08',
            '',
            '提早十分鐘',
            null
        )
    $$,
    array['伴侶較新的編輯'::text],
    'a lost-ack replay returns current state without overwriting a newer edit'
);

reset role;
select results_eq(
    $$
        select count(*)::integer
        from public.shared_appointment_operations
        where relationship_id = 'e0000000-0000-0000-0000-000000000001'
    $$,
    array[2],
    'one durable receipt is stored per accepted update operation'
);

select has_table(
    'public',
    'shared_appointment_operations',
    'appointment operation receipts are durable server state'
);

select ok(
    position(
        'for share' in lower(pg_get_functiondef(
            'public.update_shared_appointment(uuid,uuid,uuid,text,timestamptz,text,text,timestamptz)'::regprocedure
        ))
    ) > 0
    and position(
        'for share' in lower(pg_get_functiondef(
            'public.cancel_shared_appointment(uuid,uuid,uuid)'::regprocedure
        ))
    ) > 0,
    'edit and cancel hold a relationship lock through their write transaction'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e2', true);

select results_eq(
    $$
        select status || '/' || (cancelled_by_user_id is not null)::text
            || '/' || (cancelled_at is not null)::text
        from public.cancel_shared_appointment(
            'e0000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000001',
            'e3000000-0000-0000-0000-000000000002'
        )
    $$,
    array['cancelled/true/true'::text],
    'either partner can cancel while retaining the appointment row'
);

select results_eq(
    $$
        select status
        from public.cancel_shared_appointment(
            'e0000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000001',
            'e3000000-0000-0000-0000-000000000002'
        )
    $$,
    array['cancelled'::text],
    'cancellation retries are idempotent'
);

select throws_ok(
    $$
        select public.update_shared_appointment(
            'e0000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000001',
            'e3000000-0000-0000-0000-000000000003',
            '不能復活',
            '2026-08-18 19:30:00+08'
        )
    $$,
    '23514',
    'appointment_cancelled',
    'a cancelled appointment cannot be silently revived by an edit'
);

select throws_ok(
    $$
        select public.create_shared_appointment(
            'e0000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000003',
            '提醒錯誤',
            '2026-08-16 19:00:00+08',
            null,
            null,
            '2026-08-16 20:00:00+08'
        )
    $$,
    '22023',
    'invalid_appointment_content',
    'a reminder cannot be later than the appointment start'
);

select throws_ok(
    $$
        select public.create_shared_appointment(
            'e0000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000004',
            '未完成照片',
            '2026-08-16 19:00:00+08',
            null,
            null,
            null,
            'e1000000-0000-0000-0000-000000000002'
        )
    $$,
    'P0002',
    'source_message_not_found',
    'an incomplete legacy photo cannot become an appointment source'
);

select throws_ok(
    $$
        insert into public.shared_appointments (
            relationship_id, client_id, creator_user_id, title, starts_at
        ) values (
            'e0000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000005',
            '00000000-0000-0000-0000-0000000000e2',
            'bypass',
            '2026-08-20 12:00:00+08'
        )
    $$,
    '42501',
    null,
    'authenticated clients cannot bypass the appointment RPC'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e3', true);

select results_eq(
    $$
        select count(*)::integer
        from public.shared_appointments
        where relationship_id = 'e0000000-0000-0000-0000-000000000001'
    $$,
    array[0],
    'a third user cannot read private shared appointments'
);

select throws_ok(
    $$
        select public.create_shared_appointment(
            'e0000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000006',
            'intrusion',
            '2026-08-20 12:00:00+08'
        )
    $$,
    '42501',
    'relationship_not_accessible',
    'a third user cannot create an appointment'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e1', true);
select public.create_shared_appointment(
    'e0000000-0000-0000-0000-000000000001',
    'e2000000-0000-0000-0000-000000000007',
    'closing test',
    '2026-08-21 12:00:00+08'
);

reset role;
update public.relationships
set status = 'closing', closing_started_at = now()
where id = 'e0000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e1', true);

select throws_ok(
    $$
        select public.create_shared_appointment(
            'e0000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000008',
            'too late',
            '2026-08-22 12:00:00+08'
        )
    $$,
    '23514',
    'relationship_not_active_pair',
    'a closing relationship cannot create appointments'
);

select throws_ok(
    $$
        select public.update_shared_appointment(
            'e0000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000007',
            'e3000000-0000-0000-0000-000000000004',
            'too late',
            '2026-08-22 12:00:00+08'
        )
    $$,
    '23514',
    'relationship_not_active',
    'a closing relationship cannot edit appointments'
);

select throws_ok(
    $$
        select public.cancel_shared_appointment(
            'e0000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000007',
            'e3000000-0000-0000-0000-000000000005'
        )
    $$,
    '23514',
    'relationship_not_active',
    'a closing relationship cannot cancel appointments'
);

reset role;

select * from finish();
rollback;

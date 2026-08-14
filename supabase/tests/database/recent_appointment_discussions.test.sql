begin;

select plan(10);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-0000000001a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'recent-a@example.test', ''),
    ('00000000-0000-0000-0000-0000000001a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'recent-b@example.test', ''),
    ('00000000-0000-0000-0000-0000000001a3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'recent-c@example.test', '');

insert into public.relationships (id)
values
    ('fa000000-0000-0000-0000-000000000001'),
    ('fa000000-0000-0000-0000-000000000002');

insert into public.relationship_members (relationship_id, user_id)
values
    ('fa000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000001a1'),
    ('fa000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000001a2'),
    ('fa000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000001a3');

insert into public.shared_appointments (
    relationship_id, client_id, creator_user_id, title, starts_at,
    status, cancelled_by_user_id, cancelled_at
)
values
    (
        'fa000000-0000-0000-0000-000000000001',
        'fa100000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-0000000001a1',
        '較早更新',
        '2026-08-20 14:00:00+00',
        'scheduled',
        null,
        null
    ),
    (
        'fa000000-0000-0000-0000-000000000001',
        'fa100000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-0000000001a2',
        '最近更新但已取消',
        '2026-08-21 14:00:00+00',
        'cancelled',
        '00000000-0000-0000-0000-0000000001a2',
        '2026-08-14 09:00:00+00'
    ),
    (
        'fa000000-0000-0000-0000-000000000001',
        'fa100000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-0000000001a1',
        '尚無討論',
        '2026-08-22 14:00:00+00',
        'scheduled',
        null,
        null
    );

insert into public.shared_items (
    relationship_id, client_id, creator_user_id, item_kind, text_content,
    appointment_client_id, created_at
)
values
    (
        'fa000000-0000-0000-0000-000000000001',
        'fa200000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-0000000001a1',
        'message',
        '自己先留言',
        'fa100000-0000-0000-0000-000000000001',
        '2026-08-14 10:00:00+00'
    ),
    (
        'fa000000-0000-0000-0000-000000000001',
        'fa200000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-0000000001a2',
        'message',
        '伴侶回覆',
        'fa100000-0000-0000-0000-000000000001',
        '2026-08-14 11:00:00+00'
    ),
    (
        'fa000000-0000-0000-0000-000000000001',
        'fa200000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-0000000001a2',
        'message',
        '取消後保留的內容',
        'fa100000-0000-0000-0000-000000000002',
        '2026-08-14 12:00:00+00'
    );

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000001a1', true);

select results_eq(
    $$ select appointment_client_id::text || '/' || unread_count::text
       from public.recent_appointment_discussions(
           'fa000000-0000-0000-0000-000000000001'
       ) $$,
    array[
        'fa100000-0000-0000-0000-000000000002/1'::text,
        'fa100000-0000-0000-0000-000000000001/1'::text
    ],
    'recent discussions are ordered by activity and include cancelled appointments'
);

select results_eq(
    $$ select count(*)::integer
       from public.recent_appointment_discussions(
           'fa000000-0000-0000-0000-000000000001'
       )
       where appointment_client_id = 'fa100000-0000-0000-0000-000000000003' $$,
    array[0],
    'appointments without discussion content are omitted'
);

select lives_ok(
    $$ select public.mark_appointment_discussion_read(
        'fa000000-0000-0000-0000-000000000001',
        'fa100000-0000-0000-0000-000000000001',
        'fa200000-0000-0000-0000-000000000002'
    ) $$,
    'a member can advance one appointment discussion cursor'
);

select results_eq(
    $$ select appointment_client_id::text || '/' || unread_count::text
       from public.recent_appointment_discussions(
           'fa000000-0000-0000-0000-000000000001'
       ) $$,
    array[
        'fa100000-0000-0000-0000-000000000002/1'::text,
        'fa100000-0000-0000-0000-000000000001/0'::text
    ],
    'read state only clears unread for its own appointment discussion'
);

reset role;
update public.shared_items
set reaction_updated_at = '2026-08-14 13:00:00+00'
where client_id = 'fa200000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000001a1', true);

select results_eq(
    $$ select appointment_client_id::text || '/' || latest_activity_at::text
       from public.recent_appointment_discussions(
           'fa000000-0000-0000-0000-000000000001'
       )
       limit 1 $$,
    array['fa100000-0000-0000-0000-000000000001/2026-08-14 13:00:00+00'::text],
    'a reaction update moves its appointment discussion to the front'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000001a2', true);

select results_eq(
    $$ select unread_count
       from public.recent_appointment_discussions(
           'fa000000-0000-0000-0000-000000000001'
       )
       where appointment_client_id = 'fa100000-0000-0000-0000-000000000001' $$,
    array[1::bigint],
    'unread counts are computed for the authenticated partner'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000001a3', true);

select throws_ok(
    $$ select * from public.recent_appointment_discussions(
        'fa000000-0000-0000-0000-000000000001'
    ) $$,
    '42501',
    'relationship_not_accessible',
    'a third user cannot inspect recent appointment discussions'
);

select results_eq(
    $$ select has_function_privilege(
        'anon',
        'public.recent_appointment_discussions(uuid)',
        'execute'
    ) $$,
    array[false],
    'anonymous users cannot execute the recent discussion RPC'
);

select results_eq(
    $$ select has_function_privilege(
        'authenticated',
        'public.recent_appointment_discussions(uuid)',
        'execute'
    ) $$,
    array[true],
    'authenticated users can execute the recent discussion RPC'
);

select results_eq(
    $$ select count(*)::integer
       from pg_indexes
       where schemaname = 'public'
         and indexname = 'shared_items_appointment_discussion_activity_idx'
         and indexdef like '%reaction_updated_at%' $$,
    array[1],
    'recent discussion activity has a reaction-aware scoped index'
);

select * from finish();
rollback;

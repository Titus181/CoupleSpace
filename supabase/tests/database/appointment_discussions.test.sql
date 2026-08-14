begin;

select plan(25);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'discussion-a@example.test', ''),
    ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'discussion-b@example.test', ''),
    ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'discussion-c@example.test', '');

insert into public.relationships (id)
values ('f0000000-0000-0000-0000-000000000001');

insert into public.relationship_members (relationship_id, user_id)
values
    ('f0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000f1'),
    ('f0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000f2');

insert into public.shared_appointments (
    relationship_id, client_id, creator_user_id, title, starts_at,
    status, cancelled_by_user_id, cancelled_at
)
values
    (
        'f0000000-0000-0000-0000-000000000001',
        'f1000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-0000000000f1',
        '週末看展',
        '2026-08-16 14:00:00+08',
        'scheduled',
        null,
        null
    ),
    (
        'f0000000-0000-0000-0000-000000000001',
        'f1000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-0000000000f1',
        '另一次約定',
        '2026-08-17 14:00:00+08',
        'scheduled',
        null,
        null
    ),
    (
        'f0000000-0000-0000-0000-000000000001',
        'f1000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-0000000000f1',
        '已取消約定',
        '2026-08-18 14:00:00+08',
        'cancelled',
        '00000000-0000-0000-0000-0000000000f1',
        now()
    );

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', true);

select lives_ok(
    $$ select public.write_appointment_discussion_message(
        'f0000000-0000-0000-0000-000000000001',
        'f1000000-0000-0000-0000-000000000001',
        'f2000000-0000-0000-0000-000000000001',
        ' 第一則討論 '
    ) $$,
    'a member can write the first appointment discussion message'
);

select lives_ok(
    $$ select public.write_appointment_discussion_message(
        'f0000000-0000-0000-0000-000000000001',
        'f1000000-0000-0000-0000-000000000001',
        'f2000000-0000-0000-0000-000000000002',
        '第二則討論'
    ) $$,
    'a member can write a second message in the same appointment discussion'
);

select results_eq(
    $$ select text_content || '/' || appointment_client_id::text
       from public.shared_items
       where client_id = 'f2000000-0000-0000-0000-000000000001' $$,
    array['第一則討論/f1000000-0000-0000-0000-000000000001'::text],
    'discussion text is normalized and scoped to the appointment'
);

select lives_ok(
    $$ select public.write_appointment_discussion_message(
        'f0000000-0000-0000-0000-000000000001',
        'f1000000-0000-0000-0000-000000000001',
        'f2000000-0000-0000-0000-000000000001',
        '第一則討論'
    ) $$,
    'retrying the same stable discussion identity is idempotent'
);

select results_eq(
    $$ select count(*)::integer from public.shared_items
       where appointment_client_id = 'f1000000-0000-0000-0000-000000000001' $$,
    array[2],
    'discussion retries do not duplicate messages'
);

select throws_ok(
    $$ select public.write_shared_message(
        'f0000000-0000-0000-0000-000000000001',
        'f2000000-0000-0000-0000-000000000001',
        '第一則討論'
    ) $$,
    '23505',
    'shared_item_identity_collision',
    'a discussion identity cannot be mistaken for a main-chat retry'
);

select throws_ok(
    $$ select public.write_appointment_discussion_message(
        'f0000000-0000-0000-0000-000000000001',
        'f1000000-0000-0000-0000-000000000002',
        'f2000000-0000-0000-0000-000000000001',
        '第一則討論'
    ) $$,
    '23505',
    'shared_item_identity_collision',
    'a stable discussion identity cannot move to another appointment'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f2', true);

select results_eq(
    $$ select public.appointment_discussion_unread_count(
        'f0000000-0000-0000-0000-000000000001',
        'f1000000-0000-0000-0000-000000000001'
    ) $$,
    array[2::bigint],
    'the partner sees both appointment messages as unread'
);

select results_eq(
    $$ select public.conversation_unread_count(
        'f0000000-0000-0000-0000-000000000001'
    ) $$,
    array[0::bigint],
    'appointment discussion messages do not inflate main-chat unread count'
);

select throws_ok(
    $$ select public.mark_conversation_read(
        'f0000000-0000-0000-0000-000000000001',
        'f2000000-0000-0000-0000-000000000001'
    ) $$,
    '22023',
    'message_not_found',
    'the main-chat cursor cannot target an appointment discussion message'
);

select lives_ok(
    $$ select public.mark_appointment_discussion_read(
        'f0000000-0000-0000-0000-000000000001',
        'f1000000-0000-0000-0000-000000000001',
        'f2000000-0000-0000-0000-000000000001'
    ) $$,
    'the partner can mark through the first visible discussion message'
);

select results_eq(
    $$ select public.appointment_discussion_unread_count(
        'f0000000-0000-0000-0000-000000000001',
        'f1000000-0000-0000-0000-000000000001'
    ) $$,
    array[1::bigint],
    'one later discussion message remains unread'
);

select lives_ok(
    $$ select public.mark_appointment_discussion_read(
        'f0000000-0000-0000-0000-000000000001',
        'f1000000-0000-0000-0000-000000000001',
        'f2000000-0000-0000-0000-000000000002'
    ) $$,
    'the partner can mark through the latest discussion message'
);

select results_eq(
    $$ select public.appointment_discussion_unread_count(
        'f0000000-0000-0000-0000-000000000001',
        'f1000000-0000-0000-0000-000000000001'
    ) $$,
    array[0::bigint],
    'appointment discussion unread returns to zero'
);

select results_eq(
    $$ select scope_id::text from public.conversation_read_states
       where user_id = '00000000-0000-0000-0000-0000000000f2' $$,
    array['f1000000-0000-0000-0000-000000000001'::text],
    'the shared read-state table keeps an appointment-scoped cursor'
);

select lives_ok(
    $$ select public.write_appointment_discussion_message(
        'f0000000-0000-0000-0000-000000000001',
        'f1000000-0000-0000-0000-000000000001',
        'f2000000-0000-0000-0000-000000000003',
        '伴侶回覆'
    ) $$,
    'the partner can reply in the same appointment discussion'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', true);

select results_eq(
    $$ select public.appointment_discussion_unread_count(
        'f0000000-0000-0000-0000-000000000001',
        'f1000000-0000-0000-0000-000000000001'
    ) $$,
    array[1::bigint],
    'the first participant sees the partner reply as unread'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', true);

select throws_ok(
    $$ select public.appointment_discussion_unread_count(
        'f0000000-0000-0000-0000-000000000001',
        'f1000000-0000-0000-0000-000000000001'
    ) $$,
    '42501',
    'relationship_not_accessible',
    'a third user cannot read appointment discussion unread state'
);

select throws_ok(
    $$ select public.write_appointment_discussion_message(
        'f0000000-0000-0000-0000-000000000001',
        'f1000000-0000-0000-0000-000000000001',
        'f2000000-0000-0000-0000-000000000004',
        'intrusion'
    ) $$,
    '42501',
    'relationship_not_accessible',
    'a third user cannot write appointment discussion messages'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', true);

select throws_ok(
    $$ select public.write_appointment_discussion_message(
        'f0000000-0000-0000-0000-000000000001',
        'f1000000-0000-0000-0000-000000000003',
        'f2000000-0000-0000-0000-000000000005',
        'cancelled'
    ) $$,
    '23514',
    'appointment_cancelled',
    'a cancelled appointment remains readable but cannot receive new messages'
);

select throws_ok(
    $$ select public.write_appointment_discussion_message(
        'f0000000-0000-0000-0000-000000000001',
        'f1000000-0000-0000-0000-000000000099',
        'f2000000-0000-0000-0000-000000000006',
        'missing'
    ) $$,
    'P0002',
    'appointment_not_found',
    'a missing appointment cannot receive discussion messages'
);

reset role;

select throws_ok(
    $$ insert into public.shared_items (
        relationship_id, client_id, creator_user_id, item_kind,
        media_byte_size, appointment_client_id
    ) values (
        'f0000000-0000-0000-0000-000000000001',
        'f2000000-0000-0000-0000-000000000007',
        '00000000-0000-0000-0000-0000000000f1',
        'photo',
        null,
        'f1000000-0000-0000-0000-000000000001'
    ) $$,
    '23514',
    null,
    'appointment discussion scope rejects incomplete photo metadata'
);

select results_eq(
    $$ select count(*)::integer
       from pg_indexes
       where schemaname = 'public'
         and indexname = 'shared_items_conversation_order_idx'
         and indexdef like '%appointment_client_id IS NULL%' $$,
    array[1],
    'the main conversation index excludes appointment discussion rows'
);

select results_eq(
    $$ select count(*)::integer
       from pg_indexes
       where schemaname = 'public'
         and indexname = 'shared_items_appointment_discussion_order_idx'
         and indexdef like '%appointment_client_id IS NOT NULL%' $$,
    array[1],
    'appointment discussions have their own scoped ordering index'
);

select results_eq(
    $$ select count(*)::integer
       from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'conversation_read_states' $$,
    array[1],
    'scoped read cursor changes keep the existing realtime hint'
);

select * from finish();
rollback;

begin;

select plan(22);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'discussion-photo-a@example.test', ''),
    ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'discussion-photo-b@example.test', ''),
    ('00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'discussion-photo-c@example.test', '');

insert into public.relationships (id)
values ('e0000000-0000-0000-0000-000000000001');

insert into public.relationship_members (relationship_id, user_id)
values
    ('e0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000e1'),
    ('e0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000e2');

insert into public.shared_appointments (
    relationship_id, client_id, creator_user_id, title, starts_at,
    status, cancelled_by_user_id, cancelled_at
)
values
    (
        'e0000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-0000000000e1',
        '週末看展',
        '2026-08-16 14:00:00+08',
        'scheduled',
        null,
        null
    ),
    (
        'e0000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-0000000000e1',
        '另一次約定',
        '2026-08-17 14:00:00+08',
        'scheduled',
        null,
        null
    ),
    (
        'e0000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-0000000000e1',
        '已取消約定',
        '2026-08-18 14:00:00+08',
        'cancelled',
        '00000000-0000-0000-0000-0000000000e1',
        now()
    );

insert into storage.objects (bucket_id, name, owner_id, metadata)
values (
    'couplespace-w1-photos',
    'e0000000-0000-0000-0000-000000000001/e2000000-0000-0000-0000-000000000001.jpg',
    '00000000-0000-0000-0000-0000000000e1',
    '{"size": 2048}'::jsonb
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e1', true);

select results_eq(
    $$ select accepted::text || '/' || coalesce(reason, 'ok')
       from public.finalize_appointment_discussion_photo_upload(
           'e0000000-0000-0000-0000-000000000001',
           'e1000000-0000-0000-0000-000000000001',
           'e2000000-0000-0000-0000-000000000001',
           2048
       ) $$,
    array['true/ok'::text],
    'an active member can finalize a photo in a scheduled appointment discussion'
);

select results_eq(
    $$ select accepted from public.finalize_appointment_discussion_photo_upload(
           'e0000000-0000-0000-0000-000000000001',
           'e1000000-0000-0000-0000-000000000001',
           'e2000000-0000-0000-0000-000000000001',
           2048
       ) $$,
    array[true],
    'retrying the same scoped photo identity is idempotent'
);

select results_eq(
    $$ select count(*)::integer from public.shared_items
       where client_id = 'e2000000-0000-0000-0000-000000000001' $$,
    array[1],
    'a scoped photo retry creates no duplicate metadata'
);

select results_eq(
    $$ select item_kind || '/' || media_byte_size::text || '/' || appointment_client_id::text
       from public.shared_items
       where client_id = 'e2000000-0000-0000-0000-000000000001' $$,
    array['photo/2048/e1000000-0000-0000-0000-000000000001'::text],
    'photo metadata keeps the verified byte size and appointment scope'
);

select throws_ok(
    $$ select public.finalize_chat_photo_upload(
           'e0000000-0000-0000-0000-000000000001',
           'e2000000-0000-0000-0000-000000000001',
           2048
       ) $$,
    '23505',
    'shared_item_identity_collision',
    'a scoped photo identity cannot be mistaken for a main-chat retry'
);

select throws_ok(
    $$ select public.finalize_appointment_discussion_photo_upload(
           'e0000000-0000-0000-0000-000000000001',
           'e1000000-0000-0000-0000-000000000002',
           'e2000000-0000-0000-0000-000000000001',
           2048
       ) $$,
    '23505',
    'shared_item_identity_collision',
    'a stable photo identity cannot move to another appointment'
);

select lives_ok(
    $$ select public.write_appointment_discussion_message(
           'e0000000-0000-0000-0000-000000000001',
           'e1000000-0000-0000-0000-000000000001',
           'e2000000-0000-0000-0000-000000000002',
           '照片後的文字'
       ) $$,
    'photo and text share one appointment discussion order'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e2', true);

select results_eq(
    $$ select public.appointment_discussion_unread_count(
           'e0000000-0000-0000-0000-000000000001',
           'e1000000-0000-0000-0000-000000000001'
       ) $$,
    array[2::bigint],
    'the partner counts finalized photo and text as unread'
);

select results_eq(
    $$ select public.conversation_unread_count(
           'e0000000-0000-0000-0000-000000000001'
       ) $$,
    array[0::bigint],
    'the scoped photo does not inflate main-chat unread'
);

select throws_ok(
    $$ select public.mark_conversation_read(
           'e0000000-0000-0000-0000-000000000001',
           'e2000000-0000-0000-0000-000000000001'
       ) $$,
    '22023',
    'message_not_found',
    'the main-chat cursor cannot target a scoped photo'
);

select lives_ok(
    $$ select public.mark_appointment_discussion_read(
           'e0000000-0000-0000-0000-000000000001',
           'e1000000-0000-0000-0000-000000000001',
           'e2000000-0000-0000-0000-000000000001'
       ) $$,
    'the partner can advance the scoped cursor through the photo'
);

select results_eq(
    $$ select public.appointment_discussion_unread_count(
           'e0000000-0000-0000-0000-000000000001',
           'e1000000-0000-0000-0000-000000000001'
       ) $$,
    array[1::bigint],
    'the later text remains unread after marking through the photo'
);

select lives_ok(
    $$ select public.set_shared_item_reaction(
           'e0000000-0000-0000-0000-000000000001',
           'e2000000-0000-0000-0000-000000000001',
           'e3000000-0000-0000-0000-000000000001',
           '❤️'
       ) $$,
    'the partner can react to a finalized scoped photo'
);

select results_eq(
    $$ select emoji_value from public.shared_item_reactions
       where message_client_id = 'e2000000-0000-0000-0000-000000000001' $$,
    array['❤️'::text],
    'the scoped photo reaction uses the existing reaction record'
);

select lives_ok(
    $$ select public.mark_appointment_discussion_read(
           'e0000000-0000-0000-0000-000000000001',
           'e1000000-0000-0000-0000-000000000001',
           'e2000000-0000-0000-0000-000000000002'
       ) $$,
    'the partner can advance the scoped cursor through the later text'
);

select results_eq(
    $$ select public.appointment_discussion_unread_count(
           'e0000000-0000-0000-0000-000000000001',
           'e1000000-0000-0000-0000-000000000001'
       ) $$,
    array[0::bigint],
    'no scoped items remain unread after the cursor reaches the text'
);

select throws_ok(
    $$ select public.finalize_appointment_discussion_photo_upload(
           'e0000000-0000-0000-0000-000000000001',
           'e1000000-0000-0000-0000-000000000001',
           'e2000000-0000-0000-0000-000000000001',
           2048
       ) $$,
    '42501',
    'photo_object_not_accessible',
    'the partner cannot finalize the uploader-owned scoped photo object'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e3', true);

select throws_ok(
    $$ select public.finalize_appointment_discussion_photo_upload(
           'e0000000-0000-0000-0000-000000000001',
           'e1000000-0000-0000-0000-000000000001',
           'e2000000-0000-0000-0000-000000000004',
           1
       ) $$,
    '42501',
    'relationship_not_accessible',
    'a third user cannot finalize an appointment discussion photo'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e1', true);

select throws_ok(
    $$ select public.finalize_appointment_discussion_photo_upload(
           'e0000000-0000-0000-0000-000000000001',
           'e1000000-0000-0000-0000-000000000003',
           'e2000000-0000-0000-0000-000000000005',
           1
       ) $$,
    '23514',
    'appointment_cancelled',
    'a cancelled appointment cannot receive a new photo'
);

select throws_ok(
    $$ select public.finalize_appointment_discussion_photo_upload(
           'e0000000-0000-0000-0000-000000000001',
           'e1000000-0000-0000-0000-000000000099',
           'e2000000-0000-0000-0000-000000000006',
           1
       ) $$,
    'P0002',
    'appointment_not_found',
    'a missing appointment cannot receive a new photo'
);

reset role;

select throws_ok(
    $$ insert into public.shared_items (
           relationship_id, client_id, creator_user_id, item_kind,
           media_byte_size, appointment_client_id
       ) values (
           'e0000000-0000-0000-0000-000000000001',
           'e2000000-0000-0000-0000-000000000007',
           '00000000-0000-0000-0000-0000000000e1',
           'photo',
           null,
           'e1000000-0000-0000-0000-000000000001'
       ) $$,
    '23514',
    null,
    'scoped photos cannot exist as incomplete metadata rows'
);

select results_eq(
    $$ select count(*)::integer from pg_indexes
       where schemaname = 'public'
         and indexname = 'shared_items_appointment_discussion_order_idx'
         and indexdef ilike '%item_kind = ''photo''%'
         and indexdef ilike '%media_byte_size IS NOT NULL%' $$,
    array[1],
    'the scoped order index includes finalized photos'
);

select * from finish();
rollback;

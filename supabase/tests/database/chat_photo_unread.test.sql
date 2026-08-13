begin;

create extension if not exists pgtap with schema extensions;
select plan(19);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'chat-photo-a@example.test', ''),
    ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'chat-photo-b@example.test', ''),
    ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'chat-photo-c@example.test', '');

insert into public.relationships (id)
values ('c0000000-0000-0000-0000-000000000001');

insert into public.relationship_members (relationship_id, user_id)
values
    ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000c1'),
    ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000c2');

insert into public.shared_items (
    relationship_id, client_id, creator_user_id, item_kind, media_byte_size
) values (
    'c0000000-0000-0000-0000-000000000001',
    'c1000000-0000-0000-0000-000000000005',
    '00000000-0000-0000-0000-0000000000c1',
    'photo',
    null
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);

insert into storage.objects (bucket_id, name, owner_id, metadata)
values (
    'couplespace-w1-photos',
    'c0000000-0000-0000-0000-000000000001/c1000000-0000-0000-0000-000000000001.jpg',
    '00000000-0000-0000-0000-0000000000c1',
    '{"size": 2048}'::jsonb
);

select results_eq(
    $$
        select accepted::text || '/' || coalesce(reason, 'ok')
        from public.finalize_chat_photo_upload(
            'c0000000-0000-0000-0000-000000000001',
            'c1000000-0000-0000-0000-000000000001',
            2048
        )
    $$,
    array['true/ok'::text],
    'an active member can finalize a chat photo'
);

select results_eq(
    $$
        select accepted
        from public.finalize_chat_photo_upload(
            'c0000000-0000-0000-0000-000000000001',
            'c1000000-0000-0000-0000-000000000001',
            2048
        )
    $$,
    array[true],
    'retrying the same chat photo identity is accepted'
);

reset role;

select results_eq(
    $$
        select count(*)::integer
        from public.shared_items
        where relationship_id = 'c0000000-0000-0000-0000-000000000001'
          and client_id = 'c1000000-0000-0000-0000-000000000001'
    $$,
    array[1],
    'an accepted chat photo retry creates no duplicate metadata'
);

select results_eq(
    $$
        select creator_user_id::text || '/' || item_kind || '/' || media_byte_size::text
        from public.shared_items
        where relationship_id = 'c0000000-0000-0000-0000-000000000001'
          and client_id = 'c1000000-0000-0000-0000-000000000001'
    $$,
    array['00000000-0000-0000-0000-0000000000c1/photo/2048'::text],
    'chat photo metadata derives its creator, kind and verified byte size'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);

select lives_ok(
    $$ select public.write_shared_message(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000002',
        '照片後的文字'
    ) $$,
    'text and photo items can share the same conversation'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c2', true);

select results_eq(
    $$ select public.conversation_unread_count('c0000000-0000-0000-0000-000000000001') $$,
    array[2::bigint],
    'the partner counts finalized photo and text items but not a legacy incomplete photo'
);

select throws_ok(
    $$ select public.mark_conversation_read(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000005'
    ) $$,
    '22023',
    'message_not_found',
    'the read cursor cannot target a legacy incomplete photo'
);

select lives_ok(
    $$ select public.mark_conversation_read(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001'
    ) $$,
    'the partner can advance the read cursor through a photo'
);

select results_eq(
    $$ select public.conversation_unread_count('c0000000-0000-0000-0000-000000000001') $$,
    array[1::bigint],
    'the later text remains unread after marking through the photo'
);

select lives_ok(
    $$ select public.mark_conversation_read(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000002'
    ) $$,
    'the partner can advance the read cursor through the later text'
);

select results_eq(
    $$ select public.conversation_unread_count('c0000000-0000-0000-0000-000000000001') $$,
    array[0::bigint],
    'no conversation items remain unread after the cursor reaches the text'
);

select results_eq(
    $$
        select item_kind
        from public.shared_items
        where relationship_id = 'c0000000-0000-0000-0000-000000000001'
          and (
              item_kind = 'message'
              or (item_kind = 'photo' and media_byte_size is not null)
          )
        order by created_at, client_id
    $$,
    array['photo'::text, 'message'::text],
    'both relationship members read the same mixed conversation order'
);

select throws_ok(
    $$ select public.finalize_chat_photo_upload(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001',
        2048
    ) $$,
    '42501',
    'photo_object_not_accessible',
    'the partner cannot finalize the uploader owned chat photo object'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c3', true);

select results_eq(
    $$
        select count(*)::integer
        from public.shared_items
        where relationship_id = 'c0000000-0000-0000-0000-000000000001'
    $$,
    array[0],
    'a third user cannot read chat text or photo metadata'
);

select throws_ok(
    $$ select public.conversation_unread_count('c0000000-0000-0000-0000-000000000001') $$,
    '42501',
    'relationship_not_accessible',
    'a third user cannot read the mixed conversation unread count'
);

select throws_ok(
    $$ select public.finalize_chat_photo_upload(
        'c0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000003',
        1
    ) $$,
    '42501',
    'relationship_not_accessible',
    'a third user cannot finalize a relationship chat photo'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);

select throws_ok(
    $$
        insert into public.shared_items (
            relationship_id, client_id, creator_user_id, item_kind, media_byte_size
        ) values (
            'c0000000-0000-0000-0000-000000000001',
            'c1000000-0000-0000-0000-000000000004',
            '00000000-0000-0000-0000-0000000000c1',
            'photo',
            1
        )
    $$,
    '42501',
    null,
    'authenticated clients cannot bypass chat photo finalization'
);

reset role;

select results_eq(
    $$
        select count(*)::integer
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'shared_items'
    $$,
    array[1],
    'chat photo changes use the existing Realtime shared items publication'
);

select ok(
    exists (
        select 1
        from pg_index index_metadata
        join pg_class index_relation
          on index_relation.oid = index_metadata.indexrelid
        where index_relation.relname = 'shared_items_conversation_order_idx'
          and pg_get_expr(index_metadata.indpred, index_metadata.indrelid)
              ilike '%media_byte_size IS NOT NULL%'
    ),
    'the conversation order index excludes incomplete photo metadata'
);

select * from finish();
rollback;

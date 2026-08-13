begin;

create extension if not exists pgtap with schema extensions;
select plan(24);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'reaction-a@example.test', ''),
    ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'reaction-b@example.test', ''),
    ('00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'reaction-c@example.test', '');

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
        'A 傳給 B',
        null
    ),
    (
        'e0000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-0000000000e2',
        'message',
        'B 傳給 A',
        null
    ),
    (
        'e0000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-0000000000e1',
        'photo',
        null,
        1024
    ),
    (
        'e0000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000004',
        '00000000-0000-0000-0000-0000000000e1',
        'photo',
        null,
        null
    );

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e2', true);

select throws_ok(
    $$ select public.set_shared_item_reaction(
        'e0000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000004',
        'e2000000-0000-0000-0000-000000000008',
        'heart'
    ) $$,
    'P0002',
    'message_not_found',
    'a legacy incomplete photo is not eligible for a message reaction'
);

select results_eq(
    $$
        select message_client_id::text || '/' || client_id::text || '/'
            || reactor_user_id::text || '/' || emoji_value
        from public.set_shared_item_reaction(
            'e0000000-0000-0000-0000-000000000001',
            'e1000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000001',
            'heart'
        )
    $$,
    array[
        'e1000000-0000-0000-0000-000000000001/e2000000-0000-0000-0000-000000000001/00000000-0000-0000-0000-0000000000e2/heart'::text
    ],
    'the receiving partner can react to a text message'
);

select ok(
    (
        select reaction_updated_at is not null
        from public.shared_items
        where relationship_id = 'e0000000-0000-0000-0000-000000000001'
          and client_id = 'e1000000-0000-0000-0000-000000000001'
    ),
    'setting a reaction touches the parent shared item Realtime hint'
);

select results_eq(
    $$
        select client_id::text || '/' || emoji_value
        from public.set_shared_item_reaction(
            'e0000000-0000-0000-0000-000000000001',
            'e1000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000001',
            'heart'
        )
    $$,
    array['e2000000-0000-0000-0000-000000000001/heart'::text],
    'retrying the same reaction identity and Emoji is accepted'
);

select results_eq(
    $$
        select count(*)::integer
        from public.shared_item_reactions
        where relationship_id = 'e0000000-0000-0000-0000-000000000001'
          and message_client_id = 'e1000000-0000-0000-0000-000000000001'
          and reactor_user_id = '00000000-0000-0000-0000-0000000000e2'
    $$,
    array[1],
    'an idempotent reaction retry creates no duplicate'
);

reset role;
update public.shared_items
set reaction_updated_at = '2000-01-01 00:00:00+00'
where relationship_id = 'e0000000-0000-0000-0000-000000000001'
  and client_id = 'e1000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e2', true);

select results_eq(
    $$
        select client_id::text || '/' || emoji_value
        from public.set_shared_item_reaction(
            'e0000000-0000-0000-0000-000000000001',
            'e1000000-0000-0000-0000-000000000001',
            'e2000000-0000-0000-0000-000000000002',
            'smile'
        )
    $$,
    array['e2000000-0000-0000-0000-000000000002/smile'::text],
    'a new reaction identity replaces the receivers previous Emoji'
);

select ok(
    (
        select reaction_updated_at > '2000-01-01 00:00:00+00'::timestamptz
        from public.shared_items
        where relationship_id = 'e0000000-0000-0000-0000-000000000001'
          and client_id = 'e1000000-0000-0000-0000-000000000001'
    ),
    'replacing a reaction advances the parent shared item Realtime hint'
);

select results_eq(
    $$
        select client_id::text || '/' || emoji_value
        from public.shared_item_reactions
        where relationship_id = 'e0000000-0000-0000-0000-000000000001'
          and message_client_id = 'e1000000-0000-0000-0000-000000000001'
          and reactor_user_id = '00000000-0000-0000-0000-0000000000e2'
    $$,
    array['e2000000-0000-0000-0000-000000000002/smile'::text],
    'replacement persists exactly one current reaction'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e1', true);

select throws_ok(
    $$ select public.set_shared_item_reaction(
        'e0000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000001',
        'e2000000-0000-0000-0000-000000000003',
        'hug'
    ) $$,
    '23514',
    'sender_cannot_react',
    'a sender cannot react to their own text message'
);

select throws_ok(
    $$ select public.set_shared_item_reaction(
        'e0000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000002',
        'e2000000-0000-0000-0000-000000000002',
        'cheer'
    ) $$,
    '23505',
    'message_reaction_identity_collision',
    'a stable reaction identity cannot be reused by another reactor or message'
);

select results_eq(
    $$
        select client_id::text || '/' || emoji_value
        from public.set_shared_item_reaction(
            'e0000000-0000-0000-0000-000000000001',
            'e1000000-0000-0000-0000-000000000002',
            'e2000000-0000-0000-0000-000000000003',
            'cheer'
        )
    $$,
    array['e2000000-0000-0000-0000-000000000003/cheer'::text],
    'the other receiving partner can react in the reverse direction'
);

select throws_ok(
    $$
        insert into public.shared_item_reactions (
            relationship_id, message_client_id, client_id, reactor_user_id, emoji_value
        ) values (
            'e0000000-0000-0000-0000-000000000001',
            'e1000000-0000-0000-0000-000000000002',
            'e2000000-0000-0000-0000-000000000004',
            '00000000-0000-0000-0000-0000000000e1',
            'laugh'
        )
    $$,
    '42501',
    null,
    'authenticated clients cannot bypass the reaction RPC'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e2', true);

select results_eq(
    $$
        select message_client_id::text || '/' || emoji_value
        from public.set_shared_item_reaction(
            'e0000000-0000-0000-0000-000000000001',
            'e1000000-0000-0000-0000-000000000003',
            'e2000000-0000-0000-0000-000000000005',
            'support'
        )
    $$,
    array['e1000000-0000-0000-0000-000000000003/support'::text],
    'the receiving partner can react to a photo message'
);

select throws_ok(
    $$ select public.set_shared_item_reaction(
        'e0000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000003',
        'e2000000-0000-0000-0000-000000000006',
        'fire'
    ) $$,
    '22023',
    'invalid_message_reaction',
    'unsupported message reaction values are rejected'
);

reset role;
update public.shared_items
set reaction_updated_at = '2000-01-01 00:00:00+00'
where relationship_id = 'e0000000-0000-0000-0000-000000000001'
  and client_id = 'e1000000-0000-0000-0000-000000000003';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e2', true);

select lives_ok(
    $$ select public.remove_shared_item_reaction(
        'e0000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000003'
    ) $$,
    'the receiver can remove their photo reaction'
);

select ok(
    (
        select reaction_updated_at > '2000-01-01 00:00:00+00'::timestamptz
        from public.shared_items
        where relationship_id = 'e0000000-0000-0000-0000-000000000001'
          and client_id = 'e1000000-0000-0000-0000-000000000003'
    ),
    'removing a reaction advances the parent shared item Realtime hint'
);

select lives_ok(
    $$ select public.remove_shared_item_reaction(
        'e0000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000003'
    ) $$,
    'removing an already absent reaction is idempotent'
);

select results_eq(
    $$
        select count(*)::integer
        from public.shared_item_reactions
        where relationship_id = 'e0000000-0000-0000-0000-000000000001'
          and message_client_id = 'e1000000-0000-0000-0000-000000000003'
    $$,
    array[0],
    'removed photo reactions do not remain visible'
);

select results_eq(
    $$
        select count(*)::integer
        from public.shared_item_reactions
        where relationship_id = 'e0000000-0000-0000-0000-000000000001'
    $$,
    array[2],
    'current relationship members can read both remaining text reactions'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e3', true);

select results_eq(
    $$
        select count(*)::integer
        from public.shared_item_reactions
        where relationship_id = 'e0000000-0000-0000-0000-000000000001'
    $$,
    array[0],
    'a third user cannot read relationship message reactions'
);

select throws_ok(
    $$ select public.set_shared_item_reaction(
        'e0000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000001',
        'e2000000-0000-0000-0000-000000000007',
        'heart'
    ) $$,
    '42501',
    'relationship_not_accessible',
    'a third user cannot create a relationship message reaction'
);

select throws_ok(
    $$ select public.remove_shared_item_reaction(
        'e0000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000001'
    ) $$,
    '42501',
    'relationship_not_accessible',
    'a third user cannot remove a relationship message reaction'
);

reset role;

select results_eq(
    $$
        select count(*)::integer
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'shared_item_reactions'
    $$,
    array[0],
    'reaction rows are not published because filtered DELETE is not a safe hint'
);

select results_eq(
    $$
        select count(*)::integer
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'shared_items'
    $$,
    array[1],
    'reaction synchronization uses the RLS-filterable shared items publication'
);

select * from finish();
rollback;

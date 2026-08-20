begin;

create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'save-moment-a@example.test', ''),
    ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'save-moment-b@example.test', ''),
    ('00000000-0000-0000-0000-0000000000d3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'save-moment-c@example.test', '');

insert into public.relationships (id)
values ('d0000000-0000-0000-0000-000000000001');

insert into public.relationship_members (relationship_id, user_id)
values
    ('d0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000d1'),
    ('d0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000d2');

insert into storage.objects (bucket_id, name, owner_id, metadata)
values (
    'couplespace-w1-photos',
    'd0000000-0000-0000-0000-000000000001/d1000000-0000-0000-0000-000000000002.jpg',
    '00000000-0000-0000-0000-0000000000d1',
    '{"size": 4096}'::jsonb
);

insert into public.shared_items (
    relationship_id, client_id, creator_user_id, item_kind, text_content, media_byte_size
)
values
    (
        'd0000000-0000-0000-0000-000000000001',
        'd1000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-0000000000d1',
        'message',
        repeat('長', 300),
        null
    ),
    (
        'd0000000-0000-0000-0000-000000000001',
        'd1000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-0000000000d1',
        'photo',
        null,
        4096
    ),
    (
        'd0000000-0000-0000-0000-000000000001',
        'd1000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-0000000000d1',
        'marker',
        null,
        null
    ),
    (
        'd0000000-0000-0000-0000-000000000001',
        'd1000000-0000-0000-0000-000000000004',
        '00000000-0000-0000-0000-0000000000d1',
        'photo',
        null,
        null
    );

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d2', true);

select results_eq(
    $$
        select moment_client_id::text || '/' || creator_user_id::text || '/'
            || source_message_client_id::text || '/' || source_message_creator_user_id::text
            || '/' || kind || '/' || char_length(text_content)::text
        from public.create_moment_from_shared_item(
            'd0000000-0000-0000-0000-000000000001',
            'd1000000-0000-0000-0000-000000000001',
            'd2000000-0000-0000-0000-000000000001'
        )
    $$,
    array[
        'd2000000-0000-0000-0000-000000000001/00000000-0000-0000-0000-0000000000d2/d1000000-0000-0000-0000-000000000001/00000000-0000-0000-0000-0000000000d1/text/300'::text
    ],
    'a partner can save a text message and preserve both user identities'
);

select results_eq(
    $$
        select source_shared_item_client_id::text || '/' || char_length(text_content)::text
        from public.moments
        where relationship_id = 'd0000000-0000-0000-0000-000000000001'
          and client_id = 'd2000000-0000-0000-0000-000000000001'
    $$,
    array['d1000000-0000-0000-0000-000000000001/300'::text],
    'a saved chat text keeps its source reference and full message length'
);

select results_eq(
    $$
        select moment_client_id::text
        from public.create_moment_from_shared_item(
            'd0000000-0000-0000-0000-000000000001',
            'd1000000-0000-0000-0000-000000000001',
            'd2000000-0000-0000-0000-000000000001'
        )
    $$,
    array['d2000000-0000-0000-0000-000000000001'::text],
    'retrying the same saved Moment identity is accepted'
);

select results_eq(
    $$
        select count(*)::integer
        from public.moments
        where relationship_id = 'd0000000-0000-0000-0000-000000000001'
          and source_shared_item_client_id = 'd1000000-0000-0000-0000-000000000001'
    $$,
    array[1],
    'an idempotent save retry creates no duplicate Moment'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', true);

select results_eq(
    $$
        select moment_client_id::text || '/' || creator_user_id::text
        from public.create_moment_from_shared_item(
            'd0000000-0000-0000-0000-000000000001',
            'd1000000-0000-0000-0000-000000000001',
            'd2000000-0000-0000-0000-000000000002'
        )
    $$,
    array['d2000000-0000-0000-0000-000000000001/00000000-0000-0000-0000-0000000000d2'::text],
    'the same source returns the existing shared Moment across both members'
);

select results_eq(
    $$
        select count(*)::integer
        from public.moments
        where relationship_id = 'd0000000-0000-0000-0000-000000000001'
          and source_shared_item_client_id = 'd1000000-0000-0000-0000-000000000001'
    $$,
    array[1],
    'one source message can produce only one relationship Moment'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d2', true);

select results_eq(
    $$
        select moment_client_id::text || '/' || source_message_client_id::text
            || '/' || kind || '/' || media_byte_size::text
        from public.create_moment_from_shared_item(
            'd0000000-0000-0000-0000-000000000001',
            'd1000000-0000-0000-0000-000000000002',
            'd2000000-0000-0000-0000-000000000003'
        )
    $$,
    array[
        'd2000000-0000-0000-0000-000000000003/d1000000-0000-0000-0000-000000000002/photo/4096'::text
    ],
    'a partner can save a finalized photo message as a Moment'
);

select results_eq(
    $$
        select source_shared_item_client_id::text || '/' || media_byte_size::text
        from public.moments
        where relationship_id = 'd0000000-0000-0000-0000-000000000001'
          and client_id = 'd2000000-0000-0000-0000-000000000003'
    $$,
    array['d1000000-0000-0000-0000-000000000002/4096'::text],
    'a saved photo Moment keeps its source reference and verified byte size'
);

select throws_ok(
    $$ select public.create_moment_from_shared_item(
        'd0000000-0000-0000-0000-000000000001',
        'd1000000-0000-0000-0000-000000000002',
        'd2000000-0000-0000-0000-000000000001'
    ) $$,
    '23505',
    'moment_identity_collision',
    'a stable Moment identity cannot be reused for a different source message'
);

select throws_ok(
    $$ select public.create_moment_from_shared_item(
        'd0000000-0000-0000-0000-000000000001',
        'd1000000-0000-0000-0000-000000000003',
        'd2000000-0000-0000-0000-000000000004'
    ) $$,
    'P0002',
    'message_not_found',
    'non-message shared items cannot be saved as Moments'
);

select throws_ok(
    $$ select public.create_moment_from_shared_item(
        'd0000000-0000-0000-0000-000000000001',
        'd1000000-0000-0000-0000-000000000004',
        'd2000000-0000-0000-0000-000000000005'
    ) $$,
    'P0002',
    'message_not_found',
    'a legacy incomplete photo is not an eligible save-as-Moment source'
);

select throws_ok(
    $$
        insert into public.moments (
            relationship_id,
            client_id,
            creator_user_id,
            kind,
            text_content,
            source_shared_item_client_id
        ) values (
            'd0000000-0000-0000-0000-000000000001',
            'd2000000-0000-0000-0000-000000000006',
            '00000000-0000-0000-0000-0000000000d2',
            'text',
            'bypass',
            'd1000000-0000-0000-0000-000000000001'
        )
    $$,
    '42501',
    null,
    'authenticated clients cannot bypass the save as Moment RPC'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', true);

select results_eq(
    $$
        select count(*)::integer
        from public.moments
        where relationship_id = 'd0000000-0000-0000-0000-000000000001'
    $$,
    array[2],
    'both relationship members can read saved text and photo Moments'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d3', true);

select results_eq(
    $$
        select count(*)::integer
        from public.moments
        where relationship_id = 'd0000000-0000-0000-0000-000000000001'
    $$,
    array[0],
    'a third user cannot read Moments saved from private messages'
);

select throws_ok(
    $$ select public.create_moment_from_shared_item(
        'd0000000-0000-0000-0000-000000000001',
        'd1000000-0000-0000-0000-000000000001',
        'd2000000-0000-0000-0000-000000000007'
    ) $$,
    '42501',
    'relationship_not_accessible',
    'a third user cannot save a relationship message as a Moment'
);

reset role;

select results_eq(
    $$
        select count(*)::integer
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'moments'
    $$,
    array[1],
    'saved message Moments use the existing Realtime moments publication'
);

select results_eq(
    $$
        select count(*)::integer
        from pg_indexes
        where schemaname = 'public'
          and indexname = 'moments_one_per_source_shared_item'
    $$,
    array[1],
    'the schema enforces one Moment per source shared item'
);

select ok(
    lower(pg_get_functiondef(
        'public.create_moment_from_shared_item(uuid, uuid, uuid)'::regprocedure
    )) like '%on conflict (relationship_id, source_shared_item_client_id)%where source_shared_item_client_id is not null%do nothing%if not found then%select moment.*%source_shared_item_client_id = source_item.client_id%',
    'the save RPC infers the partial source index and re-reads a concurrent winner'
);

select * from finish();
rollback;

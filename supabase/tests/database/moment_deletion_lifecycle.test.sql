begin;

create extension if not exists pgtap with schema extensions;
select plan(138);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'w14-delete-a@example.test', ''),
    ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'w14-delete-b@example.test', ''),
    ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'w14-delete-c@example.test', ''),
    ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'w14-delete-d@example.test', '');

insert into public.relationships (id)
values
    ('10000000-0000-4000-8000-000000000001'),
    ('20000000-0000-4000-8000-000000000001');

insert into public.relationship_members (relationship_id, user_id)
values
    ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1'),
    ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000b1'),
    ('20000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000c1'),
    ('20000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000d1');

insert into public.shared_items (
    relationship_id,
    client_id,
    creator_user_id,
    item_kind,
    text_content
)
values (
    '10000000-0000-4000-8000-000000000001',
    '64000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-0000000000b1',
    'message',
    'W14::moment-delete::B::message::main-source'
);

insert into public.shared_appointments (
    relationship_id,
    client_id,
    creator_user_id,
    title,
    starts_at
)
values (
    '10000000-0000-4000-8000-000000000001',
    '65000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-0000000000a1',
    'W14 source appointment',
    '2026-09-01 12:00:00+00'
);

insert into public.shared_items (
    relationship_id,
    client_id,
    creator_user_id,
    item_kind,
    text_content,
    appointment_client_id
)
values (
    '10000000-0000-4000-8000-000000000001',
    '64000000-0000-4000-8000-000000000002',
    '00000000-0000-4000-8000-0000000000b1',
    'message',
    'W14::moment-delete::B::message::discussion-source',
    '65000000-0000-4000-8000-000000000001'
);

insert into public.moments (
    relationship_id,
    client_id,
    creator_user_id,
    kind,
    text_content,
    media_byte_size,
    question_key,
    question_prompt,
    source_shared_item_client_id,
    source_appointment_client_id
)
values
    (
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-0000000000a1',
        'text',
        'W14 main saved Moment',
        null,
        null,
        null,
        '64000000-0000-4000-8000-000000000001',
        null
    ),
    (
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000002',
        '00000000-0000-4000-8000-0000000000a1',
        'question',
        null,
        null,
        'understand_today',
        '今天最希望我理解你什麼？',
        null,
        null
    ),
    (
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000003',
        '00000000-0000-4000-8000-0000000000a1',
        'text',
        'W14 appointment discussion Moment',
        null,
        null,
        null,
        '64000000-0000-4000-8000-000000000002',
        '65000000-0000-4000-8000-000000000001'
    ),
    (
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000004',
        '00000000-0000-4000-8000-0000000000a1',
        'photo',
        null,
        9,
        null,
        null,
        null,
        null
    ),
    (
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000005',
        '00000000-0000-4000-8000-0000000000b1',
        'text',
        'W14 partner Moment',
        null,
        null,
        null,
        null,
        null
    ),
    (
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000029',
        '00000000-0000-4000-8000-0000000000a1',
        'text',
        'W14 29-day boundary',
        null,
        null,
        null,
        null,
        null
    ),
    (
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000030',
        '00000000-0000-4000-8000-0000000000a1',
        'text',
        'W14 exact-30-day boundary',
        null,
        null,
        null,
        null,
        null
    ),
    (
        '20000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000006',
        '00000000-0000-4000-8000-0000000000c1',
        'text',
        'W14 unrelated C canary',
        null,
        null,
        null,
        null,
        null
    );

insert into public.moment_responses (
    relationship_id,
    moment_client_id,
    client_id,
    responder_user_id,
    kind,
    emoji_value
)
values
    (
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        '62000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-0000000000b1',
        'emoji',
        'hug'
    ),
    (
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000005',
        '62000000-0000-4000-8000-000000000002',
        '00000000-0000-4000-8000-0000000000a1',
        'emoji',
        'support'
    );

insert into public.moment_question_answers (
    relationship_id,
    moment_client_id,
    client_id,
    answerer_user_id,
    answer_content
)
values
    (
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000002',
        '63000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-0000000000a1',
        'W14 A revealed answer'
    ),
    (
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000002',
        '63000000-0000-4000-8000-000000000002',
        '00000000-0000-4000-8000-0000000000b1',
        'W14 B revealed answer'
    );

insert into storage.objects (bucket_id, name, owner_id, metadata)
values (
    'couplespace-moment-photos',
    '10000000-0000-4000-8000-000000000001/61000000-0000-4000-8000-000000000004.jpg',
    '00000000-0000-4000-8000-0000000000a1',
    '{"size": 9}'::jsonb
);

select has_column(
    'public',
    'moments',
    'deleted_at',
    'Moments have a server-owned deletion timestamp'
);

select has_column(
    'public',
    'moments',
    'lifecycle_revision',
    'Moments have a durable lifecycle convergence revision'
);

select throws_ok(
    $$ insert into public.moments (
           relationship_id,
           client_id,
           creator_user_id,
           kind,
           text_content,
           deleted_at,
           purge_after
       ) values (
           '10000000-0000-4000-8000-000000000001',
           '61000000-0000-4000-8000-000000000099',
           '00000000-0000-4000-8000-0000000000a1',
           'text',
           'W14 malformed deletion fixture',
           statement_timestamp(),
           null
       ) $$,
    '23514',
    null,
    'a deleted Moment cannot omit its purge deadline'
);

select has_column(
    'public',
    'moment_question_answers',
    'removed_at',
    'question answers can retain a neutral removal marker'
);

select ok(
    has_function_privilege(
        'authenticated', expected.signature, 'execute'
    ) = expected.authenticated_execute
    and not has_function_privilege(
        'anon', expected.signature, 'execute'
    )
    and not has_function_privilege(
        'service_role', expected.signature, 'execute'
    )
    and not exists (
        select 1
        from pg_proc routine
        cross join lateral aclexplode(
            coalesce(
                routine.proacl,
                acldefault('f', routine.proowner)
            )
        ) privilege
        where routine.oid = expected.signature::regprocedure
          and privilege.grantee = 0
          and privilege.privilege_type = 'EXECUTE'
    )
    and (
        select routine.prosecdef
        from pg_proc routine
        where routine.oid = expected.signature::regprocedure
    ),
    format(
        '%s has exact %s EXECUTE ACL',
        expected.signature,
        case
            when expected.authenticated_execute then 'authenticated-only'
            else 'owner-only'
        end
    )
)
from (
    values
        ('public._delete_moment_at(uuid,uuid,uuid,timestamptz)', false),
        ('public._restore_moment_at(uuid,uuid,uuid,timestamptz)', false),
        ('public.can_read_moment_interactions(uuid,uuid)', true),
        ('public.can_read_moment_photo_object(text,text)', true),
        ('public.create_moment_from_shared_item(uuid,uuid,uuid)', true),
        ('public.delete_moment(uuid,uuid,uuid)', true),
        ('public.is_active_relationship_member(uuid)', true),
        ('public.is_moment_question_revealed(uuid,uuid)', true),
        ('public.list_hidden_moment_ids(uuid)', true),
        ('public.list_moment_sync_hints(uuid,uuid,integer)', true),
        ('public.list_recently_deleted_moments(uuid)', true),
        ('public.reject_deleted_moment_recreation()', false),
        ('public.remove_moment_answer(uuid,uuid,uuid,uuid)', true),
        ('public.remove_moment_response(uuid,uuid,uuid,uuid)', true),
        ('public.require_live_moment_for_interaction()', false),
        ('public.restore_moment(uuid,uuid,uuid)', true)
) expected(signature, authenticated_execute)
order by expected.signature;

select ok(
    has_table_privilege(role_name, 'public.moment_lifecycle_operations', 'select')
        = expected_select
    and not has_table_privilege(
        role_name,
        'public.moment_lifecycle_operations',
        'insert'
    )
    and not has_table_privilege(
        role_name,
        'public.moment_lifecycle_operations',
        'update'
    )
    and not has_table_privilege(
        role_name,
        'public.moment_lifecycle_operations',
        'delete'
    )
    and not has_table_privilege(
        role_name,
        'public.moment_lifecycle_operations',
        'truncate'
    )
    and not has_table_privilege(
        role_name,
        'public.moment_lifecycle_operations',
        'references'
    )
    and not has_table_privilege(
        role_name,
        'public.moment_lifecycle_operations',
        'trigger'
    ),
    format(
        'the operation ledger grants %s its exact table privileges',
        role_name
    )
)
from (
    values
        ('service_role', true),
        ('anon', false),
        ('authenticated', false)
) expected(role_name, expected_select)
order by expected.role_name;

select ok(
    not exists (
        select 1
        from pg_class target
        cross join lateral aclexplode(
            coalesce(target.relacl, acldefault('r', target.relowner))
        ) privilege
        where target.oid = 'public.moment_lifecycle_operations'::regclass
          and privilege.grantee = 0
    ),
    'the operation ledger grants PUBLIC no table privileges'
);

select results_eq(
    $$ select count(*)::integer
       from pg_policies
       where schemaname = 'realtime'
         and tablename = 'messages'
         and cmd = 'INSERT' $$,
    array[0],
    'the migration creates no client Realtime INSERT policy'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);

select throws_ok(
    $$ select public.delete_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        '71000000-0000-4000-8000-000000000001'
    ) $$,
    '42501',
    'moment_not_owned',
    'the partner cannot delete the creator Moment'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c1', true);

select throws_ok(
    $$ select public.delete_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        '71000000-0000-4000-8000-000000000002'
    ) $$,
    '42501',
    'relationship_not_accessible',
    'a third person with an unrelated active relationship cannot delete the Moment'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);

select lives_ok(
    $$ select public.delete_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        '71000000-0000-4000-8000-000000000003'
    ) $$,
    'the creator can soft-delete their Moment'
);

reset role;

select results_eq(
    $$ select (purge_after - deleted_at)::text
       from public.moments
       where relationship_id = '10000000-0000-4000-8000-000000000001'
         and client_id = '61000000-0000-4000-8000-000000000001' $$,
    array['30 days'::text],
    'delete uses an exact server-time 30-day window'
);

select results_eq(
    $$ select count(*)::integer
       from public.moment_responses
       where moment_client_id = '61000000-0000-4000-8000-000000000001' $$,
    array[1],
    'whole-Moment soft delete preserves the response row'
);

select results_eq(
    $$ select count(*)::integer
       from public.shared_items item
       join public.moments moment
         on moment.relationship_id = item.relationship_id
        and moment.source_shared_item_client_id = item.client_id
       where moment.client_id = '61000000-0000-4000-8000-000000000001' $$,
    array[1],
    'whole-Moment soft delete preserves the W10 source row and reference'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);

select results_eq(
    $$ select count(*)::integer from public.moments
       where client_id = '61000000-0000-4000-8000-000000000001' $$,
    array[0],
    'the creator ordinary Moment collection excludes the deleted row'
);

select results_eq(
    $$ select count(*)::integer from public.moment_responses
       where moment_client_id = '61000000-0000-4000-8000-000000000001' $$,
    array[1],
    'the creator can hydrate retained responses for Recently Deleted'
);

select results_eq(
    $$ select client_id::text
       from public.list_recently_deleted_moments(
           '10000000-0000-4000-8000-000000000001'
       ) $$,
    array['61000000-0000-4000-8000-000000000001'::text],
    'the creator can read their unexpired row through Recently Deleted'
);

select results_eq(
    $$ select moment_client_id::text || '/' || source_message_client_id::text
       from public.list_hidden_moment_ids(
           '10000000-0000-4000-8000-000000000001'
       ) $$,
    array[
        '61000000-0000-4000-8000-000000000001/64000000-0000-4000-8000-000000000001'::text
    ],
    'the creator restart hint maps the hidden Moment to its body-free source ID'
);

select results_eq(
    $$ select moment_client_id::text || '/' || is_deleted::text || '/'
              || source_message_client_id::text || '/' || revision::text
       from public.list_moment_sync_hints(
           '10000000-0000-4000-8000-000000000001'
       ) $$,
    array[
        '61000000-0000-4000-8000-000000000001/true/64000000-0000-4000-8000-000000000001/1'::text
    ],
    'the creator receives a body-free durable delete and source sync hint'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);

select results_eq(
    $$ select count(*)::integer from public.moments
       where client_id = '61000000-0000-4000-8000-000000000001' $$,
    array[0],
    'the partner ordinary Moment collection excludes the deleted row'
);

select results_eq(
    $$ select count(*)::integer from public.moment_responses
       where moment_client_id = '61000000-0000-4000-8000-000000000001' $$,
    array[0],
    'the partner cannot hydrate responses from the creator Recently Deleted Moment'
);

select results_eq(
    $$ select count(*)::integer
       from public.list_recently_deleted_moments(
           '10000000-0000-4000-8000-000000000001'
       ) $$,
    array[0],
    'the partner cannot read the creator Recently Deleted content'
);

select results_eq(
    $$ select moment_client_id::text || '/' || source_message_client_id::text
       from public.list_hidden_moment_ids(
           '10000000-0000-4000-8000-000000000001'
       ) $$,
    array[
        '61000000-0000-4000-8000-000000000001/64000000-0000-4000-8000-000000000001'::text
    ],
    'the partner restart hint can prune the hidden Moment and source entry'
);

select results_eq(
    $$ select moment_client_id::text || '/' || is_deleted::text || '/'
              || source_message_client_id::text || '/' || revision::text
       from public.list_moment_sync_hints(
           '10000000-0000-4000-8000-000000000001'
       ) $$,
    array[
        '61000000-0000-4000-8000-000000000001/true/64000000-0000-4000-8000-000000000001/1'::text
    ],
    'the partner receives the same body-free durable relationship sync hint'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c1', true);

select throws_ok(
    $$ select public.list_recently_deleted_moments(
        '10000000-0000-4000-8000-000000000001'
    ) $$,
    '42501',
    'relationship_not_accessible',
    'a third person cannot call Recently Deleted for the target relationship'
);

select throws_ok(
    $$ select public.list_hidden_moment_ids(
        '10000000-0000-4000-8000-000000000001'
    ) $$,
    '42501',
    'relationship_not_accessible',
    'a third person cannot obtain hidden Moment IDs'
);

select throws_ok(
    $$ select public.list_moment_sync_hints(
        '10000000-0000-4000-8000-000000000001'
    ) $$,
    '42501',
    'relationship_not_accessible',
    'a third person cannot obtain durable Moment sync hints'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);

select lives_ok(
    $$ select public.delete_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        '71000000-0000-4000-8000-000000000003'
    ) $$,
    'retrying the same delete operation is accepted'
);

reset role;

select results_eq(
    $$ select count(*)::integer
       from public.moment_lifecycle_operations
       where relationship_id = '10000000-0000-4000-8000-000000000001'
         and operation_id = '71000000-0000-4000-8000-000000000003' $$,
    array[1],
    'a delete retry records one operation receipt'
);

select results_eq(
    $$ select lifecycle_revision
       from public.moments
       where client_id = '61000000-0000-4000-8000-000000000001' $$,
    array[1::bigint],
    'delete increments revision once and its receipt retry does not increment again'
);

select results_eq(
    $$ select count(*)::integer
       from realtime.messages
       where topic = 'relationship:10000000-0000-4000-8000-000000000001'
         and event = 'moment-lifecycle'
         and payload ->> 'moment_client_id' =
             '61000000-0000-4000-8000-000000000001'
         and payload ->> 'change_kind' = 'deleted' $$,
    array[1],
    'a delete retry emits no duplicate lifecycle Broadcast'
);

select results_eq(
    $$ select ((payload - 'id') = jsonb_build_object(
               'moment_client_id', '61000000-0000-4000-8000-000000000001',
               'change_kind', 'deleted'
           )
           and event = 'moment-lifecycle'
           and private)::text
       from realtime.messages
       where topic = 'relationship:10000000-0000-4000-8000-000000000001'
         and payload ->> 'moment_client_id' =
             '61000000-0000-4000-8000-000000000001'
         and payload ->> 'change_kind' = 'deleted' $$,
    array['true'::text],
    'the application Broadcast is private and body-free apart from transport id'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);

select throws_ok(
    $$ insert into realtime.messages (
        id, payload, event, topic, private, extension
    ) values (
        gen_random_uuid(),
        '{}'::jsonb,
        'moment-lifecycle',
        'relationship:10000000-0000-4000-8000-000000000001',
        true,
        'broadcast'
    ) $$,
    '42501',
    null,
    'authenticated clients cannot directly insert a Broadcast message'
);

select throws_ok(
    $$ select public.create_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        'text',
        target_text_content => 'W14 main saved Moment'
    ) $$,
    '23514',
    'moment_deleted',
    'create_moment cannot recreate a soft-deleted stable identity'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);

select throws_ok(
    $$ select public.create_moment_response(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        '62000000-0000-4000-8000-000000000001',
        'emoji',
        target_emoji_value => 'hug'
    ) $$,
    '23514',
    'moment_deleted',
    'response RPC rejects a deleted parent Moment'
);

select throws_ok(
    $$ select public.restore_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        '71000000-0000-4000-8000-000000000004'
    ) $$,
    '42501',
    'moment_not_owned',
    'the partner cannot restore the creator Moment'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);

select lives_ok(
    $$ select public.restore_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        '71000000-0000-4000-8000-000000000005'
    ) $$,
    'the creator can restore before the server deadline'
);

select results_eq(
    $$ select lifecycle_revision
       from public.moments
       where client_id = '61000000-0000-4000-8000-000000000001' $$,
    array[2::bigint],
    'the actual restore advances the durable lifecycle revision once'
);

select results_eq(
    $$ select count(*)::integer
       from public.moment_responses
       where moment_client_id = '61000000-0000-4000-8000-000000000001' $$,
    array[1],
    'restore reveals the preserved response again'
);

select results_eq(
    $$ select source_shared_item_client_id::text
       from public.moments
       where client_id = '61000000-0000-4000-8000-000000000001' $$,
    array['64000000-0000-4000-8000-000000000001'::text],
    'restore reveals the preserved W10 source reference again'
);

select results_eq(
    $$ select (deleted_at is null)::text
       from public.delete_moment(
           '10000000-0000-4000-8000-000000000001',
           '61000000-0000-4000-8000-000000000001',
           '71000000-0000-4000-8000-000000000003'
       ) $$,
    array['true'::text],
    'delete D then restore R then replay D stays live'
);

select lives_ok(
    $$ select public.delete_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        '71000000-0000-4000-8000-000000000006'
    ) $$,
    'a new delete operation can delete the restored Moment'
);

select results_eq(
    $$ select (deleted_at is not null)::text
       from public.restore_moment(
           '10000000-0000-4000-8000-000000000001',
           '61000000-0000-4000-8000-000000000001',
           '71000000-0000-4000-8000-000000000005'
       ) $$,
    array['true'::text],
    'restore R then delete D2 then replay R stays deleted'
);

select throws_ok(
    $$ select public.restore_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        '71000000-0000-4000-8000-000000000006'
    ) $$,
    '23505',
    'moment_operation_identity_collision',
    'an operation UUID cannot change from delete to restore'
);

select throws_ok(
    $$ select public.delete_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000003',
        '71000000-0000-4000-8000-000000000006'
    ) $$,
    '23505',
    'moment_operation_identity_collision',
    'an operation UUID cannot be reused for a different Moment'
);

select lives_ok(
    $$ select public.restore_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        '71000000-0000-4000-8000-000000000007'
    ) $$,
    'a fresh restore operation restores the Moment after stale replays'
);

select results_eq(
    $$ select lifecycle_revision
       from public.moments
       where client_id = '61000000-0000-4000-8000-000000000001' $$,
    array[4::bigint],
    'stale delete and restore replays do not advance the revision'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);

select throws_ok(
    $$ select public.remove_moment_response(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000005',
        '62000000-0000-4000-8000-000000000002',
        '72000000-0000-4000-8000-000000000001'
    ) $$,
    '42501',
    'moment_response_not_owned',
    'a partner cannot remove another actor response'
);

select lives_ok(
    $$ select public.remove_moment_response(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        '62000000-0000-4000-8000-000000000001',
        '72000000-0000-4000-8000-000000000002'
    ) $$,
    'the responder can remove their own response'
);

select results_eq(
    $$ select count(*)::integer from public.moment_responses
       where client_id = '62000000-0000-4000-8000-000000000001' $$,
    array[0],
    'response removal physically deletes its body and row'
);

select lives_ok(
    $$ select public.remove_moment_response(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        '62000000-0000-4000-8000-000000000001',
        '72000000-0000-4000-8000-000000000002'
    ) $$,
    'retrying the same response removal succeeds after the row is gone'
);

reset role;

select results_eq(
    $$ select count(*)::integer
       from public.moment_lifecycle_operations
       where operation_id = '72000000-0000-4000-8000-000000000002' $$,
    array[1],
    'response removal retry records one receipt'
);

select results_eq(
    $$ select lifecycle_revision
       from public.moments
       where client_id = '61000000-0000-4000-8000-000000000001' $$,
    array[5::bigint],
    'response removal advances revision once and its retry does not advance again'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);

select throws_ok(
    $$ select public.create_moment_response(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        '62000000-0000-4000-8000-000000000001',
        'emoji',
        target_emoji_value => 'heart'
    ) $$,
    '23514',
    'moment_response_removed',
    'a stale create retry cannot resurrect the removed response identity'
);

select lives_ok(
    $$ select public.create_moment_response(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        '62000000-0000-4000-8000-000000000003',
        'emoji',
        target_emoji_value => 'heart'
    ) $$,
    'the partner may submit a new response with a fresh stable identity'
);

select lives_ok(
    $$ select public.remove_moment_response(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        '62000000-0000-4000-8000-000000000001',
        '72000000-0000-4000-8000-000000000002'
    ) $$,
    'replaying the old remove receipt does not mutate the new response'
);

select results_eq(
    $$ select emoji_value from public.moment_responses
       where client_id = '62000000-0000-4000-8000-000000000003' $$,
    array['heart'::text],
    'the fresh response survives stale removal replay'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);

select lives_ok(
    $$ select public.delete_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000001',
        '71000000-0000-4000-8000-000000000014'
    ) $$,
    'a later whole-Moment delete supersedes the earlier response removal result'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);

select results_eq(
    $$ select count(*)::integer
       from public.remove_moment_response(
           '10000000-0000-4000-8000-000000000001',
           '61000000-0000-4000-8000-000000000001',
           '62000000-0000-4000-8000-000000000001',
           '72000000-0000-4000-8000-000000000002'
       ) $$,
    array[0],
    'a durable remove receipt replays as body-free success after parent deletion'
);

reset role;

select results_eq(
    $$ select count(*)::integer from public.moment_responses
       where client_id = '62000000-0000-4000-8000-000000000003' $$,
    array[1],
    'the superseded response replay performs no second mutation'
);

select results_eq(
    $$ select lifecycle_revision
       from public.moments
       where client_id = '61000000-0000-4000-8000-000000000001' $$,
    array[6::bigint],
    'the later delete advances revision while the superseded response replay does not'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);

select throws_ok(
    $$ select public.remove_moment_response(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000005',
        '62000000-0000-4000-8000-000000000002',
        '72000000-0000-4000-8000-000000000002'
    ) $$,
    '23505',
    'moment_operation_identity_collision',
    'response operation UUID reuse by a different actor and target fails'
);

select throws_ok(
    $$ select public.remove_moment_answer(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000002',
        '63000000-0000-4000-8000-000000000002',
        '73000000-0000-4000-8000-000000000001'
    ) $$,
    '42501',
    'moment_answer_not_owned',
    'one partner cannot remove the other answer'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);

select lives_ok(
    $$ select public.remove_moment_answer(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000002',
        '63000000-0000-4000-8000-000000000002',
        '73000000-0000-4000-8000-000000000002'
    ) $$,
    'an answerer can remove their own revealed answer'
);

select results_eq(
    $$ select (answer_content is null and removed_at is not null)::text
       from public.moment_question_answers
       where client_id = '63000000-0000-4000-8000-000000000002' $$,
    array['true'::text],
    'answer removal keeps a neutral marker with no body'
);

select results_eq(
    $$ select public.is_moment_question_revealed(
           '10000000-0000-4000-8000-000000000001',
           '61000000-0000-4000-8000-000000000002'
       )::text $$,
    array['true'::text],
    'removing a revealed answer does not re-lock the joint reveal'
);

select results_eq(
    $$ select coalesce(answer_content, '<removed>')
       from public.moment_question_answers
       where moment_client_id = '61000000-0000-4000-8000-000000000002'
       order by client_id $$,
    array['W14 A revealed answer'::text, '<removed>'::text],
    'the revealed pair exposes the surviving body and neutral marker only'
);

select lives_ok(
    $$ select public.remove_moment_answer(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000002',
        '63000000-0000-4000-8000-000000000002',
        '73000000-0000-4000-8000-000000000002'
    ) $$,
    'retrying the same answer removal is accepted'
);

reset role;

select results_eq(
    $$ select count(*)::integer from public.moment_lifecycle_operations
       where operation_id = '73000000-0000-4000-8000-000000000002' $$,
    array[1],
    'answer removal retry records one receipt'
);

select results_eq(
    $$ select lifecycle_revision
       from public.moments
       where client_id = '61000000-0000-4000-8000-000000000002' $$,
    array[1::bigint],
    'answer removal advances revision once and its retry does not advance again'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);

select throws_ok(
    $$ select public.answer_moment_question(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000002',
        '63000000-0000-4000-8000-000000000002',
        'W14 replacement answer'
    ) $$,
    '23505',
    'question_answer_identity_collision',
    'a removed-answer marker prevents re-answering'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);

select lives_ok(
    $$ select public.delete_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000002',
        '71000000-0000-4000-8000-000000000008'
    ) $$,
    'the creator can delete a jointly revealed question Moment'
);

select results_eq(
    $$ select count(*)::integer from public.moment_question_answers
       where moment_client_id = '61000000-0000-4000-8000-000000000002' $$,
    array[2],
    'the creator can hydrate already revealed answers while the Moment is recently deleted'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);

select results_eq(
    $$ select count(*)::integer from public.moment_question_answers
       where moment_client_id = '61000000-0000-4000-8000-000000000002' $$,
    array[0],
    'the partner cannot read answer children while the Moment is deleted'
);

select throws_ok(
    $$ select public.answer_moment_question(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000002',
        '63000000-0000-4000-8000-000000000002',
        'W14 retry while deleted'
    ) $$,
    '23514',
    'moment_deleted',
    'answer RPC rejects a deleted question Moment'
);

select results_eq(
    $$ select count(*)::integer
       from public.remove_moment_answer(
           '10000000-0000-4000-8000-000000000001',
           '61000000-0000-4000-8000-000000000002',
           '63000000-0000-4000-8000-000000000002',
           '73000000-0000-4000-8000-000000000002'
       ) $$,
    array[0],
    'a durable answer-removal receipt replays without hidden parent content'
);

reset role;

select results_eq(
    $$ select count(*)::integer from public.moment_question_answers
       where moment_client_id = '61000000-0000-4000-8000-000000000002'
         and answer_content is null
         and removed_at is not null $$,
    array[1],
    'whole-Moment delete preserves both answers and the neutral marker internally'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);

select throws_ok(
    $$ select public.create_question_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000002',
        'understand_today',
        '63000000-0000-4000-8000-000000000001',
        'W14 A revealed answer'
    ) $$,
    '23514',
    'moment_deleted',
    'question creation retry cannot recreate a deleted Moment'
);

select lives_ok(
    $$ select public.restore_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000002',
        '71000000-0000-4000-8000-000000000009'
    ) $$,
    'restoring the question reveals its preserved interaction state'
);

select results_eq(
    $$ select lifecycle_revision
       from public.moments
       where client_id = '61000000-0000-4000-8000-000000000002' $$,
    array[3::bigint],
    'answer removal, whole delete, and restore each advanced question revision once'
);

select results_eq(
    $$ select moment_client_id::text || '/' || is_deleted::text || '/'
              || coalesce(source_message_client_id::text, '<none>') || '/'
              || revision::text
       from public.list_moment_sync_hints(
           '10000000-0000-4000-8000-000000000001'
       )
       where moment_client_id = '61000000-0000-4000-8000-000000000002' $$,
    array[
        '61000000-0000-4000-8000-000000000002/false/<none>/3'::text
    ],
    'a restored live Moment remains discoverable through its durable sync hint'
);

select results_eq(
    $$ select public.is_moment_question_revealed(
           '10000000-0000-4000-8000-000000000001',
           '61000000-0000-4000-8000-000000000002'
       )::text $$,
    array['true'::text],
    'the restored question remains revealed without re-answering'
);

select lives_ok(
    $$ select public.delete_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000003',
        '71000000-0000-4000-8000-000000000010'
    ) $$,
    'the W11 discussion-sourced Moment can be soft-deleted'
);

reset role;

select results_eq(
    $$ select item.client_id::text || '/' || appointment.client_id::text || '/'
           || moment.source_shared_item_client_id::text || '/'
           || moment.source_appointment_client_id::text
       from public.moments moment
       join public.shared_items item
         on item.relationship_id = moment.relationship_id
        and item.client_id = moment.source_shared_item_client_id
       join public.shared_appointments appointment
         on appointment.relationship_id = moment.relationship_id
        and appointment.client_id = moment.source_appointment_client_id
       where moment.client_id = '61000000-0000-4000-8000-000000000003' $$,
    array[
        '64000000-0000-4000-8000-000000000002/65000000-0000-4000-8000-000000000001/64000000-0000-4000-8000-000000000002/65000000-0000-4000-8000-000000000001'::text
    ],
    'soft delete preserves the W11 source message, appointment, and both refs'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);

select throws_ok(
    $$ select public.create_moment_from_shared_item(
        '10000000-0000-4000-8000-000000000001',
        '64000000-0000-4000-8000-000000000002',
        '61000000-0000-4000-8000-000000000013'
    ) $$,
    '23514',
    'moment_deleted',
    'a saved source cannot recreate or surface its deleted Moment'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);

select lives_ok(
    $$ select public.restore_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000003',
        '71000000-0000-4000-8000-000000000011'
    ) $$,
    'the W11 discussion-sourced Moment can be restored'
);

select results_eq(
    $$ select moment_client_id::text || '/' || is_deleted::text || '/'
              || source_message_client_id::text || '/' || revision::text
       from public.list_moment_sync_hints(
           '10000000-0000-4000-8000-000000000001'
       )
       where moment_client_id = '61000000-0000-4000-8000-000000000003' $$,
    array[
        '61000000-0000-4000-8000-000000000003/false/64000000-0000-4000-8000-000000000002/2'::text
    ],
    'the durable live hint preserves the restored W11 source mapping'
);

select results_eq(
    $$ select source_shared_item_client_id::text || '/'
           || source_appointment_client_id::text
       from public.moments
       where client_id = '61000000-0000-4000-8000-000000000003' $$,
    array[
        '64000000-0000-4000-8000-000000000002/65000000-0000-4000-8000-000000000001'::text
    ],
    'restore keeps the W11 source refs unchanged'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);

select results_eq(
    $$ select count(*)::integer from storage.objects
       where bucket_id = 'couplespace-moment-photos'
         and name = '10000000-0000-4000-8000-000000000001/61000000-0000-4000-8000-000000000004.jpg' $$,
    array[1],
    'the partner can read a live direct Moment photo'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);

select lives_ok(
    $$ select public.delete_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000004',
        '71000000-0000-4000-8000-000000000012'
    ) $$,
    'the creator can soft-delete a direct photo Moment'
);

select results_eq(
    $$ select count(*)::integer from storage.objects
       where bucket_id = 'couplespace-moment-photos'
         and name = '10000000-0000-4000-8000-000000000001/61000000-0000-4000-8000-000000000004.jpg' $$,
    array[1],
    'the creator retains unexpired Recently Deleted photo access'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);

select results_eq(
    $$ select count(*)::integer from storage.objects
       where bucket_id = 'couplespace-moment-photos'
         and name = '10000000-0000-4000-8000-000000000001/61000000-0000-4000-8000-000000000004.jpg' $$,
    array[0],
    'the partner cannot read a deleted direct Moment photo'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c1', true);

select results_eq(
    $$ select count(*)::integer from storage.objects
       where bucket_id = 'couplespace-moment-photos'
         and name = '10000000-0000-4000-8000-000000000001/61000000-0000-4000-8000-000000000004.jpg' $$,
    array[0],
    'a third person cannot read the deleted direct Moment photo'
);

reset role;

select results_eq(
    $$ select count(*)::integer from public.storage_gc_queue
       where bucket_id = 'couplespace-moment-photos' $$,
    array[0],
    'soft deletion does not enqueue Storage GC in W14-02'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);

select lives_ok(
    $$ select public.restore_moment(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000004',
        '71000000-0000-4000-8000-000000000013'
    ) $$,
    'the creator can restore the direct photo Moment'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);

select results_eq(
    $$ select count(*)::integer from storage.objects
       where bucket_id = 'couplespace-moment-photos'
         and name = '10000000-0000-4000-8000-000000000001/61000000-0000-4000-8000-000000000004.jpg' $$,
    array[1],
    'the partner photo access returns after live restore'
);

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);

select lives_ok(
    $$ select public._delete_moment_at(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000029',
        '74000000-0000-4000-8000-000000000029',
        '2026-01-14 12:00:00+00'
    ) $$,
    'trusted fixture deletes at fixed server T0 for the 29-day boundary'
);

select lives_ok(
    $$ select public._restore_moment_at(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000029',
        '75000000-0000-4000-8000-000000000029',
        '2026-02-12 12:00:00+00'
    ) $$,
    'restore succeeds at fixed server T0 plus 29 days'
);

select results_eq(
    $$ select (deleted_at is null)::text from public.moments
       where client_id = '61000000-0000-4000-8000-000000000029' $$,
    array['true'::text],
    'the 29-day fixture is live after restore'
);

select lives_ok(
    $$ select public._delete_moment_at(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000030',
        '74000000-0000-4000-8000-000000000030',
        '2026-01-14 12:00:00+00'
    ) $$,
    'trusted fixture deletes at fixed server T0 for the exact boundary'
);

select throws_ok(
    $$ select public._restore_moment_at(
        '10000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000030',
        '75000000-0000-4000-8000-000000000030',
        '2026-02-13 12:00:00+00'
    ) $$,
    '23514',
    'moment_restore_window_expired',
    'restore is denied at the exact fixed server 30-day boundary'
);

select results_eq(
    $$ select (deleted_at is not null)::text from public.moments
       where client_id = '61000000-0000-4000-8000-000000000030' $$,
    array['true'::text],
    'the exact-30-day fixture remains deleted'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);

select results_eq(
    $$ select count(*)::integer
       from public.list_recently_deleted_moments(
           '10000000-0000-4000-8000-000000000001'
       )
       where client_id = '61000000-0000-4000-8000-000000000030' $$,
    array[0],
    'expired content is absent from Recently Deleted'
);

select results_eq(
    $$ select count(*)::integer
       from public.list_hidden_moment_ids(
           '10000000-0000-4000-8000-000000000001'
       )
       where moment_client_id = '61000000-0000-4000-8000-000000000030' $$,
    array[1],
    'restart pruning still reports an expired but not-yet-purged hidden ID'
);

select throws_ok(
    $$ update public.moments
       set deleted_at = statement_timestamp(),
           purge_after = statement_timestamp() + interval '30 days'
       where client_id = '61000000-0000-4000-8000-000000000005' $$,
    '42501',
    null,
    'authenticated clients cannot directly update Moment lifecycle columns'
);

select throws_ok(
    $$ delete from public.moment_responses
       where client_id = '62000000-0000-4000-8000-000000000003' $$,
    '42501',
    null,
    'authenticated clients cannot directly delete response rows'
);

select throws_ok(
    $$ update public.moment_question_answers
       set answer_content = null,
           removed_at = statement_timestamp()
       where client_id = '63000000-0000-4000-8000-000000000001' $$,
    '42501',
    null,
    'authenticated clients cannot directly mutate answer removal markers'
);

select throws_ok(
    $$ select count(*) from public.moment_lifecycle_operations $$,
    '42501',
    null,
    'authenticated clients cannot read the service-only receipt ledger'
);

reset role;

insert into public.moments (
    relationship_id,
    client_id,
    creator_user_id,
    kind,
    text_content,
    lifecycle_revision
)
select
    '10000000-0000-4000-8000-000000000001',
    (
        '81000000-0000-4000-8000-'
        || lpad(fixture_number::text, 12, '0')
    )::uuid,
    '00000000-0000-4000-8000-0000000000a1',
    'text',
    'W14 sync pagination fixture ' || fixture_number::text,
    1
from generate_series(1, 1001) fixture(fixture_number);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);

select results_eq(
    $$ with page_one as materialized (
           select *
           from public.list_moment_sync_hints(
               '10000000-0000-4000-8000-000000000001',
               '80000000-0000-4000-8000-000000000000',
               1000
           )
       ), page_two as materialized (
           select *
           from public.list_moment_sync_hints(
               '10000000-0000-4000-8000-000000000001',
               (select max(moment_client_id::text)::uuid from page_one),
               1000
           )
       ), page_three as materialized (
           select *
           from public.list_moment_sync_hints(
               '10000000-0000-4000-8000-000000000001',
               (select max(moment_client_id::text)::uuid from page_two),
               1000
           )
       ), all_pages as (
           select moment_client_id from page_one
           union all
           select moment_client_id from page_two
           union all
           select moment_client_id from page_three
       )
       select (select count(*) from page_one)::text || '/'
              || (select count(*) from page_two)::text || '/'
              || (select count(*) from page_three)::text || '/'
              || count(distinct moment_client_id)::text || '/'
              || min(moment_client_id::text) || '/'
              || max(moment_client_id::text)
       from all_pages $$,
    array[
        '500/500/1/1001/81000000-0000-4000-8000-000000000001/81000000-0000-4000-8000-000000001001'::text
    ],
    'immutable UUID keyset pages all 1001 hints without max_rows truncation or duplicates'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c1', true);

select lives_ok(
    $$ select public.delete_moment(
        '20000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000006',
        '76000000-0000-4000-8000-000000000001'
    ) $$,
    'C can mutate only their own unrelated relationship canary'
);

select lives_ok(
    $$ select public.begin_unpairing(
        '20000000-0000-4000-8000-000000000001'
    ) $$,
    'the unrelated relationship enters closing for the restore boundary'
);

select throws_ok(
    $$ select public.restore_moment(
        '20000000-0000-4000-8000-000000000001',
        '61000000-0000-4000-8000-000000000006',
        '76000000-0000-4000-8000-000000000002'
    ) $$,
    '23514',
    'relationship_not_active',
    'closing prohibits restore even before purge_after'
);

select throws_ok(
    $$ select public.list_hidden_moment_ids(
        '20000000-0000-4000-8000-000000000001'
    ) $$,
    '23514',
    'relationship_not_active',
    'closing prohibits the active restart-pruning RPC'
);

select throws_ok(
    $$ select public.list_moment_sync_hints(
        '20000000-0000-4000-8000-000000000001'
    ) $$,
    '23514',
    'relationship_not_active',
    'closing prohibits the durable Moment sync-hint RPC'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);
select set_config('realtime.topic', 'relationship:10000000-0000-4000-8000-000000000001', true);

select ok(
    (select count(*) from realtime.messages
     where event = 'moment-lifecycle') > 0,
    'active creator A can receive the exact private relationship Broadcast topic'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);
select set_config('realtime.topic', 'relationship:10000000-0000-4000-8000-000000000001', true);

select ok(
    (select count(*) from realtime.messages
     where event = 'moment-lifecycle') > 0,
    'active partner B can receive the exact private relationship Broadcast topic'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c1', true);
select set_config('realtime.topic', 'relationship:10000000-0000-4000-8000-000000000001', true);

select results_eq(
    $$ select count(*)::integer from realtime.messages
       where event = 'moment-lifecycle' $$,
    array[0],
    'C cannot receive the A/B private relationship Broadcast topic'
);

select set_config('realtime.topic', 'relationship:20000000-0000-4000-8000-000000000001', true);

select results_eq(
    $$ select count(*)::integer from realtime.messages
       where event = 'moment-lifecycle' $$,
    array[0],
    'a closing member cannot receive the former active relationship topic'
);

reset role;

select results_eq(
    $$ select text_content from public.moments
       where relationship_id = '20000000-0000-4000-8000-000000000001'
         and client_id = '61000000-0000-4000-8000-000000000006' $$,
    array['W14 unrelated C canary'::text],
    'A/B operations never changed the unrelated C canary body'
);

select results_eq(
    $$ select distinct payload ->> 'change_kind'
       from realtime.messages
       where topic = 'relationship:10000000-0000-4000-8000-000000000001'
         and event = 'moment-lifecycle'
       order by payload ->> 'change_kind' $$,
    array[
        'answer_removed'::text,
        'deleted'::text,
        'response_removed'::text,
        'restored'::text
    ],
    'all four accepted lifecycle changes emit the shared Broadcast event'
);

select results_eq(
    $$ select count(*)::integer
       from realtime.messages
       where topic = 'relationship:10000000-0000-4000-8000-000000000001'
         and event = 'moment-lifecycle'
         and (
             not (payload ?& array['id', 'moment_client_id', 'change_kind'])
             or (select count(*) from jsonb_object_keys(payload)) <> 3
         ) $$,
    array[0],
    'every lifecycle Broadcast contains only two app fields plus transport id'
);

select * from finish();
rollback;

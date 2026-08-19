begin;

create extension if not exists pgtap with schema extensions;
select plan(41);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password) values
 ('00000000-0000-0000-0000-000000000801','00000000-0000-0000-0000-000000000000','authenticated','authenticated','appointment-boundary-a@example.test',''),
 ('00000000-0000-0000-0000-000000000802','00000000-0000-0000-0000-000000000000','authenticated','authenticated','appointment-boundary-b@example.test',''),
 ('00000000-0000-0000-0000-000000000803','00000000-0000-0000-0000-000000000000','authenticated','authenticated','appointment-boundary-outsider@example.test','');

insert into public.relationships (id) values
 ('80000000-0000-0000-0000-000000000001'),
 ('80000000-0000-0000-0000-000000000002');

insert into public.relationship_members (relationship_id, user_id) values
 ('80000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000801'),
 ('80000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000802'),
 ('80000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000803');

insert into public.shared_appointments (
    relationship_id, client_id, creator_user_id, title, starts_at
) values (
    '80000000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000801',
    'initial appointment',
    '2031-01-01 10:00:00+00'
);

update public.shared_appointments
set created_at = '2030-01-01 00:00:00+00',
    updated_at = '2030-01-01 00:00:00+00'
where relationship_id = '80000000-0000-0000-0000-000000000001'
  and client_id = '81000000-0000-0000-0000-000000000001';

update public.relationship_interaction_events
set id = '82000000-0000-0000-0000-000000000001',
    created_at = '2030-02-01 00:00:00+00'
where relationship_id = '80000000-0000-0000-0000-000000000001'
  and source_identity = '81000000-0000-0000-0000-000000000001';

insert into public.shared_appointment_operations (
    relationship_id, operation_id, appointment_client_id, actor_user_id,
    operation_kind, title, starts_at, location, note, reminder_at
) values (
    '80000000-0000-0000-0000-000000000001',
    '83000000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000801',
    'update', 'visible revision', '2031-01-02 10:00:00+00',
    'visible location', 'visible note', '2031-01-02 09:00:00+00'
);

update public.shared_appointments
set title = 'visible revision',
    starts_at = '2031-01-02 10:00:00+00',
    location = 'visible location',
    note = 'visible note',
    reminder_at = '2031-01-02 09:00:00+00',
    updated_at = '2030-01-01 00:00:01+00'
where relationship_id = '80000000-0000-0000-0000-000000000001'
  and client_id = '81000000-0000-0000-0000-000000000001';

update public.shared_appointment_operations
set applied_at = '2030-01-01 00:00:01+00'
where relationship_id = '80000000-0000-0000-0000-000000000001'
  and operation_id = '83000000-0000-0000-0000-000000000001';

update public.relationship_interaction_events
set id = '82000000-0000-0000-0000-000000000002',
    created_at = '2030-02-01 00:00:01+00'
where relationship_id = '80000000-0000-0000-0000-000000000001'
  and source_identity = '83000000-0000-0000-0000-000000000001';

select is(
    (select interaction_boundary_source_identity
     from public.shared_appointments
     where relationship_id = '80000000-0000-0000-0000-000000000001'
       and client_id = '81000000-0000-0000-0000-000000000001'),
    '83000000-0000-0000-0000-000000000001'::uuid,
    'an effective update publishes its verified operation source with the appointment snapshot'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000802',true);

select is(
    (select interaction_boundary_source_identity
     from public.shared_appointments
     where relationship_id = '80000000-0000-0000-0000-000000000001'
       and client_id = '81000000-0000-0000-0000-000000000001'),
    '83000000-0000-0000-0000-000000000001'::uuid,
    'a current member can read the server-issued boundary with the appointment snapshot'
);

select is(
    coalesce((
        select unread_count::integer
        from public.relationship_unread_counts('80000000-0000-0000-0000-000000000001')
        where scope_id = '81000000-0000-0000-0000-000000000001'
    ), 0),
    2,
    'appointment creation and update begin unread in the appointment scope'
);

select lives_ok(
    $$ select public.mark_appointment_interactions_read_through_source(
        '80000000-0000-0000-0000-000000000001',
        '81000000-0000-0000-0000-000000000001',
        '81000000-0000-0000-0000-000000000001'
    ) $$,
    'the verified creation snapshot is a valid lifecycle boundary'
);

select is(
    coalesce((
        select unread_count::integer
        from public.relationship_unread_counts('80000000-0000-0000-0000-000000000001')
        where scope_id = '81000000-0000-0000-0000-000000000001'
    ), 0),
    1,
    'reading the creation snapshot leaves the later update unread'
);

select is(
    (select last_read_event_id
     from public.relationship_interaction_read_states
     where relationship_id = '80000000-0000-0000-0000-000000000001'
       and scope_id = '81000000-0000-0000-0000-000000000001'
       and user_id = '00000000-0000-0000-0000-000000000802'),
    '82000000-0000-0000-0000-000000000001'::uuid,
    'the creation snapshot maps to the server-owned creation event'
);

select lives_ok(
    $$ select public.mark_appointment_interactions_read_through_source(
        '80000000-0000-0000-0000-000000000001',
        '81000000-0000-0000-0000-000000000001',
        '83000000-0000-0000-0000-000000000001'
    ) $$,
    'the rendered update snapshot advances through its lifecycle event'
);

select is(
    coalesce((
        select unread_count::integer
        from public.relationship_unread_counts('80000000-0000-0000-0000-000000000001')
        where scope_id = '81000000-0000-0000-0000-000000000001'
    ), 0),
    0,
    'opening appointment detail clears scope-only lifecycle unread'
);

select is(
    (select last_read_event_id
     from public.relationship_interaction_read_states
     where relationship_id = '80000000-0000-0000-0000-000000000001'
       and scope_id = '81000000-0000-0000-0000-000000000001'
       and user_id = '00000000-0000-0000-0000-000000000802'),
    '82000000-0000-0000-0000-000000000002'::uuid,
    'the update snapshot maps to the matching applied operation event'
);

reset role;

insert into public.shared_items (
    relationship_id, client_id, creator_user_id, item_kind,
    text_content, appointment_client_id
) values (
    '80000000-0000-0000-0000-000000000001',
    '84000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000801',
    'message', 'new discussion message',
    '81000000-0000-0000-0000-000000000001'
);

update public.relationship_interaction_events event
set id = '82000000-0000-0000-0000-000000000003',
    created_at = '2030-02-01 00:00:01+00'
from public.shared_items item
where item.relationship_id = event.relationship_id
  and item.id = event.source_identity
  and item.client_id = '84000000-0000-0000-0000-000000000001';

insert into public.shared_items (
    relationship_id, client_id, creator_user_id, item_kind,
    media_byte_size, appointment_client_id
) values (
    '80000000-0000-0000-0000-000000000001',
    '84000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000801',
    'photo', 1,
    '81000000-0000-0000-0000-000000000001'
);

update public.relationship_interaction_events event
set id = '82000000-0000-0000-0000-000000000004',
    created_at = '2030-02-01 00:00:02+00'
from public.shared_items item
where item.relationship_id = event.relationship_id
  and item.id = event.source_identity
  and item.client_id = '84000000-0000-0000-0000-000000000002';

insert into public.shared_appointment_operations (
    relationship_id, operation_id, appointment_client_id, actor_user_id,
    operation_kind
) values (
    '80000000-0000-0000-0000-000000000001',
    '83000000-0000-0000-0000-000000000002',
    '81000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000801',
    'cancel'
);

update public.shared_appointments
set status = 'cancelled',
    cancelled_by_user_id = '00000000-0000-0000-0000-000000000801',
    cancelled_at = '2030-01-01 00:00:02+00',
    updated_at = '2030-01-01 00:00:02+00'
where relationship_id = '80000000-0000-0000-0000-000000000001'
  and client_id = '81000000-0000-0000-0000-000000000001';

update public.shared_appointment_operations
set applied_at = '2030-01-01 00:00:02+00'
where relationship_id = '80000000-0000-0000-0000-000000000001'
  and operation_id = '83000000-0000-0000-0000-000000000002';

update public.relationship_interaction_events
set id = '82000000-0000-0000-0000-000000000005',
    created_at = '2030-02-01 00:00:02+00'
where relationship_id = '80000000-0000-0000-0000-000000000001'
  and source_identity = '83000000-0000-0000-0000-000000000002';

select is(
    (select interaction_boundary_source_identity
     from public.shared_appointments
     where relationship_id = '80000000-0000-0000-0000-000000000001'
       and client_id = '81000000-0000-0000-0000-000000000001'),
    '83000000-0000-0000-0000-000000000002'::uuid,
    'cancellation publishes its verified operation source with the appointment snapshot'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000802',true);

select lives_ok(
    $$ select public.mark_appointment_interactions_read_through_source(
        '80000000-0000-0000-0000-000000000001',
        '81000000-0000-0000-0000-000000000001',
        '83000000-0000-0000-0000-000000000001'
    ) $$,
    'a delayed appointment-detail read retries only through its old snapshot'
);

select is(
    coalesce((
        select unread_count::integer
        from public.relationship_unread_counts('80000000-0000-0000-0000-000000000001')
        where scope_id = '81000000-0000-0000-0000-000000000001'
    ), 0),
    3,
    'message, completed photo, and cancellation after the snapshot remain unread'
);

select is(
    (select last_read_event_id
     from public.relationship_interaction_read_states
     where relationship_id = '80000000-0000-0000-0000-000000000001'
       and scope_id = '81000000-0000-0000-0000-000000000001'
       and user_id = '00000000-0000-0000-0000-000000000802'),
    '82000000-0000-0000-0000-000000000002'::uuid,
    'the delayed snapshot cannot jump to the latest appointment-scope event'
);

select lives_ok(
    $$ select public.mark_relationship_interactions_read_through_message(
        '80000000-0000-0000-0000-000000000001',
        '81000000-0000-0000-0000-000000000001',
        '84000000-0000-0000-0000-000000000002'
    ) $$,
    'appointment discussion photos use the existing verified item boundary'
);

select is(
    coalesce((
        select unread_count::integer
        from public.relationship_unread_counts('80000000-0000-0000-0000-000000000001')
        where scope_id = '81000000-0000-0000-0000-000000000001'
    ), 0),
    1,
    'a cancellation after the visible photo remains unread'
);

select is(
    (select last_read_event_id
     from public.relationship_interaction_read_states
     where relationship_id = '80000000-0000-0000-0000-000000000001'
       and scope_id = '81000000-0000-0000-0000-000000000001'
       and user_id = '00000000-0000-0000-0000-000000000802'),
    '82000000-0000-0000-0000-000000000004'::uuid,
    'same-timestamp ordering stops at the visible photo event UUID'
);

select lives_ok(
    $$ select public.mark_appointment_interactions_read_through_source(
        '80000000-0000-0000-0000-000000000001',
        '81000000-0000-0000-0000-000000000001',
        '83000000-0000-0000-0000-000000000002'
    ) $$,
    'the visible cancelled snapshot maps to its applied cancellation event'
);

select is(
    coalesce((
        select unread_count::integer
        from public.relationship_unread_counts('80000000-0000-0000-0000-000000000001')
        where scope_id = '81000000-0000-0000-0000-000000000001'
    ), 0),
    0,
    'reading through cancellation clears the final appointment-scope event'
);

select is(
    (select last_read_event_id
     from public.relationship_interaction_read_states
     where relationship_id = '80000000-0000-0000-0000-000000000001'
       and scope_id = '81000000-0000-0000-0000-000000000001'
       and user_id = '00000000-0000-0000-0000-000000000802'),
    '82000000-0000-0000-0000-000000000005'::uuid,
    'the cancellation boundary uses the matching server operation source'
);

select lives_ok(
    $$ select public.mark_appointment_interactions_read_through_source(
        '80000000-0000-0000-0000-000000000001',
        '81000000-0000-0000-0000-000000000001',
        '83000000-0000-0000-0000-000000000001'
    ) $$,
    'an older verified lifecycle boundary remains safely retryable'
);

select is(
    (select last_read_event_id
     from public.relationship_interaction_read_states
     where relationship_id = '80000000-0000-0000-0000-000000000001'
       and scope_id = '81000000-0000-0000-0000-000000000001'
       and user_id = '00000000-0000-0000-0000-000000000802'),
    '82000000-0000-0000-0000-000000000005'::uuid,
    'the appointment cursor is forward-only'
);

reset role;

insert into public.shared_appointment_operations (
    relationship_id, operation_id, appointment_client_id, actor_user_id,
    operation_kind, title, starts_at, location, note, reminder_at
) values (
    '80000000-0000-0000-0000-000000000001',
    '83000000-0000-0000-0000-000000000003',
    '81000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000801',
    'update', 'visible revision', '2031-01-02 10:00:00+00',
    'visible location', 'visible note', '2031-01-02 09:00:00+00'
);

-- A no-op write changes updated_at but produces no ledger event/applied_at.
update public.shared_appointments
set title = 'visible revision',
    starts_at = '2031-01-02 10:00:00+00',
    location = 'visible location',
    note = 'visible note',
    reminder_at = '2031-01-02 09:00:00+00',
    updated_at = '2030-01-01 00:00:03+00'
where relationship_id = '80000000-0000-0000-0000-000000000001'
  and client_id = '81000000-0000-0000-0000-000000000001';

select is(
    (select interaction_boundary_source_identity
     from public.shared_appointments
     where relationship_id = '80000000-0000-0000-0000-000000000001'
       and client_id = '81000000-0000-0000-0000-000000000001'),
    '83000000-0000-0000-0000-000000000002'::uuid,
    'a no-op write preserves the prior verified lifecycle boundary'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000802',true);

select lives_ok(
    $$ select public.mark_appointment_interactions_read_through_source(
        '80000000-0000-0000-0000-000000000001',
        '81000000-0000-0000-0000-000000000001',
        '83000000-0000-0000-0000-000000000002'
    ) $$,
    'a locked current no-op snapshot falls back only to its prior verified lifecycle event'
);

select is(
    (select last_read_event_id
     from public.relationship_interaction_read_states
     where relationship_id = '80000000-0000-0000-0000-000000000001'
       and scope_id = '81000000-0000-0000-0000-000000000001'
       and user_id = '00000000-0000-0000-0000-000000000802'),
    '82000000-0000-0000-0000-000000000005'::uuid,
    'the no-op snapshot cannot fabricate a newer cursor'
);

reset role;

insert into public.shared_appointments (
    relationship_id, client_id, creator_user_id, title, starts_at
) values (
    '80000000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000801',
    'other appointment',
    '2031-02-01 10:00:00+00'
);

update public.shared_appointments
set created_at = '2030-01-01 00:00:04+00',
    updated_at = '2030-01-01 00:00:04+00'
where relationship_id = '80000000-0000-0000-0000-000000000001'
  and client_id = '81000000-0000-0000-0000-000000000002';

insert into public.shared_appointments (
    relationship_id, client_id, creator_user_id, title, starts_at
) values (
    '80000000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000801',
    'pre-ledger appointment',
    '2031-03-01 10:00:00+00'
);

update public.shared_appointments
set created_at = '2030-01-01 00:00:05+00',
    updated_at = '2030-01-01 00:00:05+00'
where relationship_id = '80000000-0000-0000-0000-000000000001'
  and client_id = '81000000-0000-0000-0000-000000000003';

delete from public.relationship_interaction_events
where relationship_id = '80000000-0000-0000-0000-000000000001'
  and source_identity = '81000000-0000-0000-0000-000000000003';

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000802',true);

select lives_ok(
    $$ select public.mark_appointment_interactions_read_through_source(
        '80000000-0000-0000-0000-000000000001',
        '81000000-0000-0000-0000-000000000003',
        '81000000-0000-0000-0000-000000000003'
    ) $$,
    'a verified pre-ledger snapshot with no event is a safe no-op'
);

select is(
    (select count(*)::integer
     from public.relationship_interaction_read_states
     where relationship_id = '80000000-0000-0000-0000-000000000001'
       and scope_id = '81000000-0000-0000-0000-000000000003'
       and user_id = '00000000-0000-0000-0000-000000000802'),
    0,
    'a pre-ledger snapshot does not fabricate a read cursor'
);

select throws_ok(
    $$ select public.mark_appointment_interactions_read_through_source(
        '80000000-0000-0000-0000-000000000001',
        '81000000-0000-0000-0000-000000000001',
        '89999999-0000-0000-0000-000000000099'
    ) $$,
    '22023', 'interaction_source_not_found',
    'an arbitrary source identity cannot select an appointment event'
);

select throws_ok(
    $$ select public.mark_appointment_interactions_read_through_source(
        '80000000-0000-0000-0000-000000000001',
        '81000000-0000-0000-0000-000000000001',
        '81000000-0000-0000-0000-000000000002'
    ) $$,
    '22023', 'interaction_source_not_found',
    'a snapshot boundary from another appointment cannot cross scopes'
);

select throws_ok(
    $$ select public.mark_appointment_interactions_read_through_source(
        '80000000-0000-0000-0000-000000000001',
        '81000000-0000-0000-0000-000000000099',
        '81000000-0000-0000-0000-000000000003'
    ) $$,
    '22023', 'interaction_scope_not_found',
    'a missing appointment scope cannot advance a cursor'
);

select throws_ok(
    $$ select public.mark_appointment_interactions_read_through_source(
        '80000000-0000-0000-0000-000000000001',
        '80000000-0000-0000-0000-000000000001',
        '81000000-0000-0000-0000-000000000001'
    ) $$,
    '22023', 'interaction_scope_not_found',
    'an appointment scope cannot collide with the relationship scope'
);

select throws_ok(
    $$ select public.mark_appointment_interactions_read_through_source(
        '80000000-0000-0000-0000-000000000002',
        '81000000-0000-0000-0000-000000000001',
        '83000000-0000-0000-0000-000000000002'
    ) $$,
    '42501', 'relationship_not_accessible',
    'a member cannot use an appointment from a different relationship'
);

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000803',true);
select throws_ok(
    $$ select public.mark_appointment_interactions_read_through_source(
        '80000000-0000-0000-0000-000000000001',
        '81000000-0000-0000-0000-000000000001',
        '83000000-0000-0000-0000-000000000002'
    ) $$,
    '42501', 'relationship_not_accessible',
    'an outsider cannot advance an appointment interaction cursor'
);

select is(
    (select count(*)::integer
     from public.shared_appointments
     where relationship_id = '80000000-0000-0000-0000-000000000001'),
    0,
    'appointment RLS does not expose boundary identities to an outsider'
);

select ok(
    has_function_privilege(
        'authenticated',
        'public.mark_appointment_interactions_read_through_source(uuid,uuid,uuid)',
        'execute'
    ),
    'authenticated members may invoke the verified appointment boundary RPC'
);

select ok(
    not has_function_privilege(
        'anon',
        'public.mark_appointment_interactions_read_through_source(uuid,uuid,uuid)',
        'execute'
    ),
    'anonymous clients cannot invoke the appointment boundary RPC'
);

select ok(
    not exists (
        select 1
        from pg_catalog.pg_proc function
        cross join lateral pg_catalog.aclexplode(
            coalesce(function.proacl, pg_catalog.acldefault('f', function.proowner))
        ) privilege
        where function.oid =
            'public.mark_appointment_interactions_read_through_source(uuid,uuid,uuid)'::regprocedure
          and privilege.grantee = 0
          and privilege.privilege_type = 'EXECUTE'
    ),
    'PUBLIC has no execute privilege on the appointment boundary RPC'
);

select ok(
    not has_table_privilege(
        'authenticated', 'public.relationship_interaction_read_states', 'update'
    ),
    'authenticated clients cannot forge appointment read cursors directly'
);

select ok(
    not has_table_privilege(
        'authenticated', 'public.shared_appointment_operations', 'select'
    ),
    'the operation identity used for verification remains server-only'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.set_shared_appointment_interaction_boundary()',
        'execute'
    ),
    'authenticated clients cannot invoke the boundary trigger helper'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.record_relationship_interaction_event(uuid,uuid,uuid,uuid,text)',
        'execute'
    ),
    'authenticated clients cannot invoke the internal interaction writer'
);

select ok(
    not has_function_privilege(
        'anon',
        'public.record_relationship_interaction_event(uuid,uuid,uuid,uuid,text)',
        'execute'
    ),
    'anonymous clients cannot invoke the internal interaction writer'
);

select * from finish();
rollback;

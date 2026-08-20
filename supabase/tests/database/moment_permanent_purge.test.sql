begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (id, instance_id, aud, role, email, encrypted_password)
values
    ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'w14-purge-a@example.test', ''),
    ('00000000-0000-4000-8000-0000000000f2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'w14-purge-b@example.test', ''),
    ('00000000-0000-4000-8000-0000000000f3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'w14-purge-c@example.test', ''),
    ('00000000-0000-4000-8000-0000000000f4', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'w14-purge-d@example.test', '');

insert into public.relationships (id)
values
    ('30000000-0000-4000-8000-000000000001'),
    ('40000000-0000-4000-8000-000000000001');

insert into public.relationship_members (relationship_id, user_id)
values
    ('30000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000f1'),
    ('30000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000f2'),
    ('40000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000f3'),
    ('40000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000f4');

insert into storage.objects (bucket_id, name, owner_id, metadata)
values
    (
        'couplespace-w1-photos',
        '30000000-0000-4000-8000-000000000001/32000000-0000-4000-8000-000000000001.jpg',
        '00000000-0000-4000-8000-0000000000f2',
        '{"size": 1100}'::jsonb
    ),
    (
        'couplespace-moment-photos',
        '30000000-0000-4000-8000-000000000001/31000000-0000-4000-8000-000000000002.jpg',
        '00000000-0000-4000-8000-0000000000f1',
        '{"size": 1200}'::jsonb
    ),
    (
        'couplespace-moment-photos',
        '30000000-0000-4000-8000-000000000001/31000000-0000-4000-8000-000000000003.jpg',
        '00000000-0000-4000-8000-0000000000f1',
        '{"size": 1300}'::jsonb
    );

insert into public.shared_appointments (
    relationship_id,
    client_id,
    creator_user_id,
    title,
    starts_at
)
values (
    '30000000-0000-4000-8000-000000000001',
    '32500000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-0000000000f2',
    'W14 permanent-purge retained appointment',
    '2026-03-01 12:00:00+00'
);

insert into public.shared_items (
    relationship_id,
    client_id,
    creator_user_id,
    item_kind,
    text_content,
    media_byte_size,
    appointment_client_id
)
values
    (
        '30000000-0000-4000-8000-000000000001',
        '32000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-0000000000f2',
        'photo',
        null,
        1100,
        null
    ),
    (
        '30000000-0000-4000-8000-000000000001',
        '32000000-0000-4000-8000-000000000002',
        '00000000-0000-4000-8000-0000000000f2',
        'message',
        'W14 retained source message',
        null,
        null
    ),
    (
        '30000000-0000-4000-8000-000000000001',
        '32000000-0000-4000-8000-000000000003',
        '00000000-0000-4000-8000-0000000000f2',
        'message',
        'W14 retained appointment discussion message',
        null,
        '32500000-0000-4000-8000-000000000001'
    );

insert into public.moments (
    relationship_id,
    client_id,
    creator_user_id,
    kind,
    text_content,
    media_byte_size,
    source_shared_item_client_id,
    source_appointment_client_id
)
values
    (
        '30000000-0000-4000-8000-000000000001',
        '31000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-0000000000f1',
        'text',
        'W14 direct text body that must disappear',
        null,
        null,
        null
    ),
    (
        '30000000-0000-4000-8000-000000000001',
        '31000000-0000-4000-8000-000000000002',
        '00000000-0000-4000-8000-0000000000f1',
        'photo',
        null,
        1200,
        null,
        null
    ),
    (
        '30000000-0000-4000-8000-000000000001',
        '31000000-0000-4000-8000-000000000003',
        '00000000-0000-4000-8000-0000000000f1',
        'photo',
        null,
        1300,
        null,
        null
    ),
    (
        '30000000-0000-4000-8000-000000000001',
        '31000000-0000-4000-8000-000000000004',
        '00000000-0000-4000-8000-0000000000f1',
        'text',
        'W14 copied message body that must disappear',
        null,
        '32000000-0000-4000-8000-000000000002',
        null
    ),
    (
        '30000000-0000-4000-8000-000000000001',
        '31000000-0000-4000-8000-000000000005',
        '00000000-0000-4000-8000-0000000000f1',
        'text',
        'W14 copied discussion body that must disappear',
        null,
        '32000000-0000-4000-8000-000000000003',
        '32500000-0000-4000-8000-000000000001'
    ),
    (
        '30000000-0000-4000-8000-000000000001',
        '31000000-0000-4000-8000-000000000006',
        '00000000-0000-4000-8000-0000000000f1',
        'photo',
        null,
        1100,
        '32000000-0000-4000-8000-000000000001',
        null
    ),
    (
        '40000000-0000-4000-8000-000000000001',
        '41000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-0000000000f3',
        'text',
        'W14 closing-state body that must disappear immediately',
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
values (
    '30000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000001',
    '31500000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-0000000000f2',
    'emoji',
    'hug'
);

-- Simulate a distinct product/archive reference to the retained direct photo.
-- The GC queue may appear only after this final reference is released.
insert into public.storage_media_references (
    object_ref,
    reference_kind,
    reference_scope_id,
    reference_id,
    relationship_id
)
select
    media.object_ref,
    'personal_archive_item',
    '39000000-0000-4000-8000-000000000001',
    '39000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000001'
from public.storage_media_objects media
where media.bucket_id = 'couplespace-moment-photos'
  and media.object_path =
      '30000000-0000-4000-8000-000000000001/31000000-0000-4000-8000-000000000003.jpg';

select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-4000-8000-0000000000f1',
    true
);

select lives_ok(
    $test$
    do $setup$
    begin
        perform * from public._delete_moment_at(
            '30000000-0000-4000-8000-000000000001',
            '31000000-0000-4000-8000-000000000001',
            '33000000-0000-4000-8000-000000000001',
            '2026-01-01 00:00:00+00'
        );
        perform * from public._delete_moment_at(
            '30000000-0000-4000-8000-000000000001',
            '31000000-0000-4000-8000-000000000002',
            '33000000-0000-4000-8000-000000000002',
            '2026-01-01 00:00:00+00'
        );
        perform * from public._delete_moment_at(
            '30000000-0000-4000-8000-000000000001',
            '31000000-0000-4000-8000-000000000003',
            '33000000-0000-4000-8000-000000000003',
            '2026-01-01 00:00:00+00'
        );
        perform * from public._delete_moment_at(
            '30000000-0000-4000-8000-000000000001',
            '31000000-0000-4000-8000-000000000004',
            '33000000-0000-4000-8000-000000000004',
            '2026-01-01 00:00:00+00'
        );
        perform * from public._delete_moment_at(
            '30000000-0000-4000-8000-000000000001',
            '31000000-0000-4000-8000-000000000005',
            '33000000-0000-4000-8000-000000000005',
            '2026-01-01 00:00:00+00'
        );
        perform * from public._delete_moment_at(
            '30000000-0000-4000-8000-000000000001',
            '31000000-0000-4000-8000-000000000006',
            '33000000-0000-4000-8000-000000000006',
            '2026-01-01 00:00:00+00'
        );
    end
    $setup$
    $test$,
    'six fixture Moments can be soft-deleted at one deterministic server time'
);

select results_eq(
    $$ select count(*)::integer
       from public.moments
       where relationship_id = '30000000-0000-4000-8000-000000000001'
         and purge_after - deleted_at = interval '30 days' $$,
    array[6],
    'every soft delete has the exact server-authoritative 30-day deadline'
);

select results_eq(
    $$ select purged_count::text || '/' || queued_count::text
       from public._purge_expired_moments_at(
           '2026-01-30 23:59:59.999999+00',
           100,
           '30000000-0000-4000-8000-000000000001',
           false
       ) $$,
    array['0/0'::text],
    'one microsecond before 30 days cannot purge or enqueue anything'
);

select results_eq(
    $$ select count(*)::integer
       from public.moments
       where relationship_id = '30000000-0000-4000-8000-000000000001' $$,
    array[6],
    'the pre-boundary purge attempt leaves all Moment rows intact'
);

select results_eq(
    $$ select count(*)::integer from public.moment_purge_markers $$,
    array[0],
    'the pre-boundary purge attempt creates no permanent marker'
);

select results_eq(
    $$ select purged_count::text || '/' || queued_count::text
       from public._purge_expired_moments_at(
           '2026-01-31 00:00:00+00',
           100,
           '30000000-0000-4000-8000-000000000001',
           false
       ) $$,
    array['6/1'::text],
    'the exact 30-day boundary purges six Moments and queues only the unreferenced direct photo'
);

select results_eq(
    $$ select count(*)::integer
       from public.moments
       where relationship_id = '30000000-0000-4000-8000-000000000001' $$,
    array[0],
    'permanent purge physically removes all expired Moment bodies'
);

select results_eq(
    $$ select count(*)::integer
       from public.moment_responses
       where moment_client_id = '31000000-0000-4000-8000-000000000001' $$,
    array[0],
    'permanent purge removes dependent Moment interactions'
);

select results_eq(
    $$ select count(*)::integer
       from public.shared_items
       where relationship_id = '30000000-0000-4000-8000-000000000001'
         and client_id in (
             '32000000-0000-4000-8000-000000000001',
             '32000000-0000-4000-8000-000000000002',
             '32000000-0000-4000-8000-000000000003'
         ) $$,
    array[3],
    'source-backed purge retains the original photo, message, and discussion rows'
);

select results_eq(
    $$ select count(*)::integer
       from public.shared_appointments
       where relationship_id = '30000000-0000-4000-8000-000000000001'
         and client_id = '32500000-0000-4000-8000-000000000001' $$,
    array[1],
    'source-backed purge retains the original appointment'
);

select results_eq(
    $$ select count(*)::integer
       from storage.objects
       where bucket_id = 'couplespace-w1-photos'
         and name = '30000000-0000-4000-8000-000000000001/32000000-0000-4000-8000-000000000001.jpg' $$,
    array[1],
    'source-backed purge retains the source photo object'
);

select results_eq(
    $$ select count(*)::integer
       from public.storage_media_references reference
       join public.storage_media_objects media
         on media.object_ref = reference.object_ref
       where media.bucket_id = 'couplespace-w1-photos'
         and media.object_path =
             '30000000-0000-4000-8000-000000000001/32000000-0000-4000-8000-000000000001.jpg'
         and reference.reference_kind = 'shared_item' $$,
    array[1],
    'the source photo keeps its product reference after its Moment reference is removed'
);

set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-4000-8000-0000000000f2',
    true
);

select set_config('storage.allow_delete_query', 'true', true);

select results_eq(
    $$ with deleted as (
           delete from storage.objects
           where bucket_id = 'couplespace-w1-photos'
             and name =
                 '30000000-0000-4000-8000-000000000001/32000000-0000-4000-8000-000000000001.jpg'
           returning id
       )
       select count(*)::integer from deleted $$,
    array[0],
    'an active uploader cannot delete registered W1 media with live product references'
);

select set_config('storage.allow_delete_query', 'false', true);

reset role;

select results_eq(
    $$ select count(*)::integer
       from storage.objects
       where bucket_id = 'couplespace-w1-photos'
         and name =
             '30000000-0000-4000-8000-000000000001/32000000-0000-4000-8000-000000000001.jpg' $$,
    array[1],
    'the referenced W1 source photo remains stored after the blocked uploader delete'
);

select results_eq(
    $$ select count(*)::integer
       from public.storage_gc_queue queue
       join public.storage_media_objects media
         on media.object_ref = queue.object_ref
       where media.bucket_id = 'couplespace-w1-photos' $$,
    array[0],
    'source-backed media is never enqueued by Moment purge'
);

select results_eq(
    $$ select count(*)::integer
       from public.storage_gc_queue
       where object_path =
           '30000000-0000-4000-8000-000000000001/31000000-0000-4000-8000-000000000002.jpg' $$,
    array[1],
    'an unreferenced direct Moment photo is enqueued once'
);

select results_eq(
    $$ select count(*)::integer
       from public.storage_gc_queue
       where object_path =
           '30000000-0000-4000-8000-000000000001/31000000-0000-4000-8000-000000000003.jpg' $$,
    array[0],
    'a direct Moment photo with another reference is not enqueued'
);

select results_eq(
    $$ select count(*)::integer
       from storage.objects
       where bucket_id = 'couplespace-moment-photos'
         and name in (
             '30000000-0000-4000-8000-000000000001/31000000-0000-4000-8000-000000000002.jpg',
             '30000000-0000-4000-8000-000000000001/31000000-0000-4000-8000-000000000003.jpg'
         ) $$,
    array[2],
    'purge never deletes Storage objects inline before the GC worker owns them'
);

delete from public.storage_media_references reference
using public.storage_media_objects media
where reference.object_ref = media.object_ref
  and media.bucket_id = 'couplespace-moment-photos'
  and media.object_path =
      '30000000-0000-4000-8000-000000000001/31000000-0000-4000-8000-000000000003.jpg'
  and reference.reference_kind = 'personal_archive_item'
  and reference.reference_scope_id = '39000000-0000-4000-8000-000000000001';

select results_eq(
    $$ select count(*)::integer
       from public.storage_gc_queue
       where object_path =
           '30000000-0000-4000-8000-000000000001/31000000-0000-4000-8000-000000000003.jpg' $$,
    array[1],
    'releasing the final reference enqueues the retained direct photo'
);

select results_eq(
    $$ select purged_count::text || '/' || queued_count::text
       from public._purge_expired_moments_at(
           '2026-02-01 00:00:00+00',
           100,
           '30000000-0000-4000-8000-000000000001',
           false
       ) $$,
    array['0/0'::text],
    'retrying permanent purge is a no-op'
);

select results_eq(
    $$ select count(*)::integer from public.moment_purge_markers
       where relationship_id = '30000000-0000-4000-8000-000000000001' $$,
    array[6],
    'purge retry does not duplicate durable markers'
);

select results_eq(
    $$ select count(*)::integer from public.storage_gc_queue $$,
    array[2],
    'purge retry does not duplicate GC jobs'
);

set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-4000-8000-0000000000f1',
    true
);

select throws_ok(
    $$ select public.restore_moment(
        '30000000-0000-4000-8000-000000000001',
        '31000000-0000-4000-8000-000000000001',
        '33500000-0000-4000-8000-000000000001'
    ) $$,
    'P0002',
    'moment_not_found',
    'a permanently purged Moment cannot be restored'
);

select throws_ok(
    $$ select public.create_moment(
        '30000000-0000-4000-8000-000000000001',
        '31000000-0000-4000-8000-000000000001',
        'text',
        target_text_content => 'attempted resurrection'
    ) $$,
    '23514',
    'moment_permanently_deleted',
    'a stable purged Moment identity cannot be recreated'
);

select throws_ok(
    $$ select public.create_moment_from_shared_item(
        '30000000-0000-4000-8000-000000000001',
        '32000000-0000-4000-8000-000000000001',
        '31000000-0000-4000-8000-000000000099'
    ) $$,
    '23514',
    'moment_permanently_deleted',
    'a source-backed purge cannot be resurrected under a new Moment identity'
);

select results_eq(
    $$ select moment_client_id::text || '/' || source_message_client_id::text
       from public.list_hidden_moment_ids(
           '30000000-0000-4000-8000-000000000001'
       )
       where moment_client_id = '31000000-0000-4000-8000-000000000006' $$,
    array[
        '31000000-0000-4000-8000-000000000006/32000000-0000-4000-8000-000000000001'::text
    ],
    'the durable hidden-ID seam survives physical Moment deletion'
);

select results_eq(
    $$ select moment_client_id::text || '/' || is_deleted::text || '/'
              || source_message_client_id::text || '/' || revision::text
       from public.list_moment_sync_hints(
           '30000000-0000-4000-8000-000000000001'
       )
       where moment_client_id = '31000000-0000-4000-8000-000000000006' $$,
    array[
        '31000000-0000-4000-8000-000000000006/true/32000000-0000-4000-8000-000000000001/2'::text
    ],
    'the body-free deletion and source hint survives permanent purge'
);

reset role;

create temporary table w14_initial_claims on commit drop as
select *
from public._claim_storage_gc_jobs_at(
    100,
    '2026-02-01 00:00:00+00'
);

select results_eq(
    $$ select count(*)::integer from w14_initial_claims $$,
    array[2],
    'the worker claims both eligible final-reference jobs once'
);

select results_eq(
    $$ select count(*)::integer
       from public._claim_storage_gc_jobs_at(
           100,
           '2026-02-01 00:00:00+00'
       ) $$,
    array[0],
    'retrying claim while leases are live returns no duplicate work'
);

select lives_ok(
    $$ select public._fail_storage_gc_job_at(
        (
            select job_id from w14_initial_claims
            where object_path =
                '30000000-0000-4000-8000-000000000001/31000000-0000-4000-8000-000000000002.jpg'
        ),
        (
            select claim_token from w14_initial_claims
            where object_path =
                '30000000-0000-4000-8000-000000000001/31000000-0000-4000-8000-000000000002.jpg'
        ),
        'storage_delete_failed',
        '2026-02-01 00:00:00+00'
    ) $$,
    'a claimed worker failure is recorded for retry'
);

select results_eq(
    $$ select attempt_count::text || '/' || status || '/'
              || last_error_code || '/' || next_attempt_at::text
       from public.storage_gc_queue
       where object_path =
           '30000000-0000-4000-8000-000000000001/31000000-0000-4000-8000-000000000002.jpg' $$,
    array['1/pending/storage_delete_failed/2026-02-01 00:00:02+00'::text],
    'failure increments the attempt once and applies deterministic exponential backoff'
);

select throws_ok(
    $$ select public._fail_storage_gc_job_at(
        (
            select job_id from w14_initial_claims
            where object_path =
                '30000000-0000-4000-8000-000000000001/31000000-0000-4000-8000-000000000002.jpg'
        ),
        '39000000-0000-4000-8000-000000000099',
        'storage_delete_failed',
        '2026-02-01 00:00:01+00'
    ) $$,
    '42501',
    'gc_claim_not_owned',
    'a stale or foreign claim token cannot record failure'
);

select results_eq(
    $$ select count(*)::integer
       from public._claim_storage_gc_jobs_at(
           100,
           '2026-02-01 00:00:01+00'
       ) $$,
    array[0],
    'the failed job cannot be reclaimed before backoff expires'
);

create temporary table w14_retry_claim on commit drop as
select *
from public._claim_storage_gc_jobs_at(
    100,
    '2026-02-01 00:00:02+00'
);

select results_eq(
    $$ select count(*)::integer from w14_retry_claim $$,
    array[1],
    'the failed job becomes claimable exactly at its retry boundary'
);

select results_eq(
    $$ select (retry.claim_token <> initial.claim_token)::text
       from w14_retry_claim retry
       join w14_initial_claims initial using (job_id) $$,
    array['true'::text],
    'a retry receives a new fencing token'
);

select set_config('storage.allow_delete_query', 'true', true);

delete from storage.objects
where bucket_id = 'couplespace-moment-photos'
  and name =
      '30000000-0000-4000-8000-000000000001/31000000-0000-4000-8000-000000000002.jpg';

select set_config('storage.allow_delete_query', 'false', true);

select lives_ok(
    $$ select public._complete_storage_gc_job_at(
        (select job_id from w14_retry_claim),
        (select claim_token from w14_retry_claim),
        '2026-02-01 00:00:03+00'
    ) $$,
    'the retried worker can complete after Storage deletion succeeds'
);

select results_eq(
    $$ select status || '/' || attempt_count::text || '/'
              || completed_at::text
       from public.storage_gc_queue
       where job_id = (select job_id from w14_retry_claim) $$,
    array['completed/1/2026-02-01 00:00:03+00'::text],
    'completed GC retains an auditable terminal job receipt'
);

select lives_ok(
    $$ select public._complete_storage_gc_job_at(
        (select job_id from w14_retry_claim),
        (select claim_token from w14_retry_claim),
        '2026-02-01 00:00:04+00'
    ) $$,
    'repeating completion with the same fencing token is idempotent'
);

select results_eq(
    $$ select count(*)::integer
       from public.deletion_tombstone_journal event
       join public.storage_gc_queue queue
         on queue.gc_operation_id = event.operation_id
       where queue.job_id = (select job_id from w14_retry_claim)
         and event.action = 'object_gc' $$,
    array[1],
    'completion retry creates no duplicate object-GC tombstone'
);

select throws_ok(
    $$ select public._complete_storage_gc_job_at(
        (select job_id from w14_retry_claim),
        (
            select claim_token from w14_initial_claims
            where job_id = (select job_id from w14_retry_claim)
        ),
        '2026-02-01 00:00:05+00'
    ) $$,
    '42501',
    'gc_claim_not_owned',
    'the pre-retry fencing token cannot complete a terminal job'
);

select results_eq(
    $$ select count(*)::integer
       from public.lifecycle_audit_events audit
       join public.storage_gc_queue queue
         on queue.gc_operation_id = audit.operation_id
       where queue.job_id = (select job_id from w14_retry_claim)
         and audit.event_type = 'object_gc'
         and audit.result = 'failed'
         and audit.reason_code = 'storage_delete_failed' $$,
    array[1],
    'the injected worker failure is auditable with an allowlisted reason code'
);

create temporary table w14_recovered_claim on commit drop as
select *
from public._claim_storage_gc_jobs_at(
    100,
    '2026-02-01 00:05:00+00'
);

select results_eq(
    $$ select count(*)::integer from w14_recovered_claim $$,
    array[1],
    'an expired worker lease is recovered for a fenced retry'
);

select results_eq(
    $$ select queue.attempt_count::text || '/'
              || (recovered.claim_token <> initial.claim_token)::text
       from w14_recovered_claim recovered
       join w14_initial_claims initial using (job_id)
       join public.storage_gc_queue queue using (job_id) $$,
    array['1/true'::text],
    'lease recovery increments the attempt and issues a new token'
);

select results_eq(
    $$ select count(*)::integer
       from public.lifecycle_audit_events audit
       join public.storage_gc_queue queue
         on queue.gc_operation_id = audit.operation_id
       where queue.job_id = (select job_id from w14_recovered_claim)
         and audit.event_type = 'object_gc'
         and audit.result = 'failed'
         and audit.reason_code = 'internal_error' $$,
    array[1],
    'a lost worker lease leaves one body-free failure audit event'
);

-- Fault-inject a reference that appears after claim but before completion.
-- Production inserts are fenced while processing; disabling only that guard
-- models the race so completion itself must still fail closed and persist its
-- blocked evidence without an object-GC tombstone.
alter table public.storage_media_references
disable trigger guard_storage_media_reference_insert;

insert into public.storage_media_references (
    object_ref,
    reference_kind,
    reference_scope_id,
    reference_id,
    relationship_id
)
select
    queue.object_ref,
    'personal_archive_item',
    '39500000-0000-4000-8000-000000000001',
    '39500000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000001'
from public.storage_gc_queue queue
where queue.job_id = (select job_id from w14_recovered_claim);

alter table public.storage_media_references
enable trigger guard_storage_media_reference_insert;

select results_eq(
    $$ select public._complete_storage_gc_job_at(
        (select job_id from w14_recovered_claim),
        (select claim_token from w14_recovered_claim),
        '2026-02-01 00:05:01+00'
    ) $$,
    array[false],
    'completion returns false when a reference appears after claim'
);

select results_eq(
    $$ select status || '/' || last_error_code || '/'
              || attempt_count::text || '/'
              || (claim_token is null)::text || '/'
              || (claimed_at is null)::text || '/'
              || (lease_expires_at is null)::text || '/'
              || (completed_at is null)::text
       from public.storage_gc_queue
       where job_id = (select job_id from w14_recovered_claim) $$,
    array[
        'blocked/reference_integrity_failed/1/true/true/true/true'::text
    ],
    'reference-integrity failure persists a fenced blocked queue receipt'
);

select results_eq(
    $$ select count(*)::integer
       from public.lifecycle_audit_events audit
       join public.storage_gc_queue queue
         on queue.gc_operation_id = audit.operation_id
       where queue.job_id = (select job_id from w14_recovered_claim)
         and audit.event_type = 'object_gc'
         and audit.result = 'blocked'
         and audit.reason_code = 'reference_integrity_failed'
         and audit.affected_count = 0 $$,
    array[1],
    'completion-time reference failure persists one blocked audit event'
);

select results_eq(
    $$ select count(*)::integer
       from public.deletion_tombstone_journal event
       join public.storage_gc_queue queue
         on queue.gc_operation_id = event.operation_id
       where queue.job_id = (select job_id from w14_recovered_claim)
         and event.action = 'object_gc' $$,
    array[0],
    'blocked completion writes no object-GC tombstone'
);

-- A closing relationship must purge Recently Deleted immediately, even though
-- its ordinary 30-day deadline remains in the future.
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-4000-8000-0000000000f3',
    true
);

select lives_ok(
    $$ select public._delete_moment_at(
        '40000000-0000-4000-8000-000000000001',
        '41000000-0000-4000-8000-000000000001',
        '43000000-0000-4000-8000-000000000001',
        statement_timestamp()
    ) $$,
    'the closing fixture starts as an ordinary fresh soft delete'
);

create temporary table w14_closing_deadline on commit drop as
select purge_after
from public.moments
where relationship_id = '40000000-0000-4000-8000-000000000001'
  and client_id = '41000000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-4000-8000-0000000000f3',
    true
);

select lives_ok(
    $$ select public.begin_unpairing(
        '40000000-0000-4000-8000-000000000001'
    ) $$,
    'entering closing synchronously forces permanent purge'
);

reset role;

select results_eq(
    $$ select count(*)::integer from public.moments
       where relationship_id = '40000000-0000-4000-8000-000000000001'
         and client_id = '41000000-0000-4000-8000-000000000001' $$,
    array[0],
    'closing leaves no restorable Moment body'
);

select results_eq(
    $$ select (marker.purged_at < deadline.purge_after)::text
       from public.moment_purge_markers marker
       cross join w14_closing_deadline deadline
       where marker.relationship_id = '40000000-0000-4000-8000-000000000001'
         and marker.moment_client_id = '41000000-0000-4000-8000-000000000001' $$,
    array['true'::text],
    'closing purges before the otherwise applicable 30-day deadline'
);

select results_eq(
    $$ select status from public.relationships
       where id = '40000000-0000-4000-8000-000000000001' $$,
    array['closing'::text],
    'the forced purge is part of the server closing transition'
);

select results_eq(
    $$ select column_name::text collate "default"
       from information_schema.columns
       where table_schema = 'public'
         and table_name = 'deletion_tombstone_journal'
       order by ordinal_position $$,
    array[
        'event_id'::text,
        'sequence'::text,
        'operation_id'::text,
        'occurred_at'::text,
        'actor_kind'::text,
        'actor_ref'::text,
        'scope_type'::text,
        'scope_ref'::text,
        'entity_type'::text,
        'entity_ref'::text,
        'action'::text,
        'contract_version'::text,
        'event_hash'::text
    ],
    'the deletion journal has only the body-free W14 tombstone contract'
);

select results_eq(
    $$ select column_name::text collate "default"
       from information_schema.columns
       where table_schema = 'public'
         and table_name = 'lifecycle_audit_events'
       order by ordinal_position $$,
    array[
        'audit_event_id'::text,
        'operation_id'::text,
        'occurred_at'::text,
        'event_type'::text,
        'actor_kind'::text,
        'actor_ref'::text,
        'scope_type'::text,
        'scope_ref'::text,
        'entity_type'::text,
        'entity_ref'::text,
        'result'::text,
        'reason_code'::text,
        'affected_count'::text,
        'contract_version'::text
    ],
    'the audit stream has only the approved generic metadata contract'
);

select hasnt_column(
    'public',
    'moment_purge_markers',
    'text_content',
    'durable purge markers contain no Moment text body'
);

select hasnt_column(
    'public',
    'moment_purge_markers',
    'media_bytes',
    'durable purge markers contain no media body'
);

select results_eq(
    $$ with chained as (
           select
               event.*,
               lag(event.event_hash, 1, repeat('0', 64)) over (
                   order by event.sequence
               ) as previous_hash
           from public.deletion_tombstone_journal event
       )
       select count(*)::integer
       from chained event
       where event.event_hash <> encode(
           extensions.digest(
               convert_to(
                   event.previous_hash || E'\n'
                   || public._w14_tombstone_canonical_json(
                       event.event_id,
                       event.sequence,
                       event.operation_id,
                       event.occurred_at,
                       event.actor_kind,
                       event.actor_ref,
                       event.scope_type,
                       event.scope_ref,
                       event.entity_type,
                       event.entity_ref,
                       event.action,
                       event.contract_version
                   ),
                   'UTF8'
               ),
               'sha256'
           ),
           'hex'
       ) $$,
    array[0],
    'every tombstone verifies against the prior hash and canonical W14 payload'
);

select results_eq(
    $$ with sequenced as (
           select
               sequence,
               row_number() over (order by sequence) as expected_sequence
           from public.deletion_tombstone_journal
       )
       select count(*)::integer
       from sequenced
       where sequence <> expected_sequence $$,
    array[0],
    'the append-only tombstone sequence is contiguous from one'
);

select results_eq(
    $$ select count(*)::integer
       from public.deletion_tombstone_journal
       where actor_kind <> 'system'
          or actor_ref is not null $$,
    array[0],
    'deferred purge and GC tombstones contain no raw Auth actor UUID'
);

select results_eq(
    $$ select last_sequence::text || '/' || last_event_hash
       from public.deletion_journal_head
       where singleton $$,
    $$ select max(sequence)::text || '/'
              || (array_agg(event_hash order by sequence desc))[1]
       from public.deletion_tombstone_journal $$,
    'the locked journal head matches the durable hash-chain tail'
);

select throws_ok(
    $$ update public.deletion_tombstone_journal
       set action = action
       where sequence = (
           select min(sequence) from public.deletion_tombstone_journal
       ) $$,
    '55000',
    'deletion_tombstone_append_only',
    'tombstones cannot be updated even by a privileged replay process'
);

-- A/B/C can consume body-free sync RPCs, but none can read the protected
-- journal/marker/GC tables or invoke service-authoritative purge.
set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-4000-8000-0000000000f1',
    true
);

select throws_ok(
    $$ select count(*) from public.deletion_tombstone_journal $$,
    '42501',
    null,
    'member A cannot read deletion tombstones directly'
);

select throws_ok(
    $$ select count(*) from public.moment_purge_markers $$,
    '42501',
    null,
    'member A cannot read permanent markers directly'
);

select throws_ok(
    $$ select * from public.purge_expired_moments(100) $$,
    '42501',
    null,
    'member A cannot invoke server-authoritative permanent purge'
);

select throws_ok(
    $$ insert into storage.objects (bucket_id, name, owner_id, metadata)
       values (
           'couplespace-moment-photos',
           '30000000-0000-4000-8000-000000000001/31000000-0000-4000-8000-000000000002.jpg',
           '00000000-0000-4000-8000-0000000000f1',
           '{"size": 1200}'::jsonb
       ) $$,
    '42501',
    null,
    'the original uploader cannot re-upload a permanently purged photo path'
);

reset role;
set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-4000-8000-0000000000f2',
    true
);

select throws_ok(
    $$ select count(*) from public.deletion_tombstone_journal $$,
    '42501',
    null,
    'member B cannot read deletion tombstones directly'
);

reset role;
set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '00000000-0000-4000-8000-0000000000f3',
    true
);

select throws_ok(
    $$ select count(*) from public.deletion_tombstone_journal $$,
    '42501',
    null,
    'unrelated member C cannot read deletion tombstones directly'
);

reset role;

select ok(
    not has_table_privilege(
        'authenticated',
        'public.lifecycle_audit_events',
        'SELECT'
    ),
    'authenticated clients have no direct audit-table grant'
);

select ok(
    not has_table_privilege(
        'authenticated',
        'public.storage_gc_queue',
        'SELECT'
    ),
    'authenticated clients have no direct GC queue grant'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.purge_expired_moments(integer)',
        'EXECUTE'
    ),
    'only the service worker role receives the purge RPC seam'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.claim_storage_gc_jobs(integer)',
        'EXECUTE'
    ),
    'the service worker role receives the lease-based claim RPC seam'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.fail_storage_gc_job(uuid,uuid,text)',
        'EXECUTE'
    ),
    'the service worker role receives the retry/failure RPC seam'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.complete_storage_gc_job(uuid,uuid)',
        'EXECUTE'
    ),
    'the service worker role receives the fenced completion RPC seam'
);

select ok(
    has_function_privilege(
        'service_role',
        'public.replay_moment_purge_tombstone(uuid)',
        'EXECUTE'
    ),
    'the privileged restore pipeline receives the tombstone replay seam'
);

select ok(
    not has_function_privilege(
        'authenticated',
        'public.replay_moment_purge_tombstone(uuid)',
        'EXECUTE'
    ),
    'clients cannot invoke tombstone replay'
);

-- Simulate an old backup restoring a purged row without the new marker. The
-- privileged replay seam must recreate the body-free marker and delete the body
-- before ordinary client reads are enabled. The formal restore drill is G15/G17.
delete from public.moment_purge_markers
where relationship_id = '30000000-0000-4000-8000-000000000001'
  and moment_client_id = '31000000-0000-4000-8000-000000000001';

alter table public.moments disable trigger reject_deleted_moment_recreation;

insert into public.moments (
    relationship_id,
    client_id,
    creator_user_id,
    kind,
    text_content
)
values (
    '30000000-0000-4000-8000-000000000001',
    '31000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-0000000000f1',
    'text',
    'simulated stale backup body'
);

alter table public.moments enable trigger reject_deleted_moment_recreation;

select results_eq(
    $$ select count(*)::integer from public.moments
       where relationship_id = '30000000-0000-4000-8000-000000000001'
         and client_id = '31000000-0000-4000-8000-000000000001' $$,
    array[1],
    'the fixture models a stale backup that restored one purged body'
);

select lives_ok(
    $$ select public.replay_moment_purge_tombstone(
        (
            select event_id
            from public.deletion_tombstone_journal
            where scope_ref = '30000000-0000-4000-8000-000000000001'
              and entity_ref = '31000000-0000-4000-8000-000000000001'
              and action = 'content_delete'
        )
    ) $$,
    'the privileged restore seam replays the permanent-deletion tombstone'
);

select results_eq(
    $$ select count(*)::integer from public.moments
       where relationship_id = '30000000-0000-4000-8000-000000000001'
         and client_id = '31000000-0000-4000-8000-000000000001' $$,
    array[0],
    'tombstone replay removes the stale restored body before visibility'
);

select results_eq(
    $$ select count(*)::integer from public.moment_purge_markers
       where relationship_id = '30000000-0000-4000-8000-000000000001'
         and moment_client_id = '31000000-0000-4000-8000-000000000001' $$,
    array[1],
    'tombstone replay restores the durable anti-resurrection marker'
);

select * from finish();
rollback;

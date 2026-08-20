-- W14-03 permanent Moment purge, deletion tombstones, and reference-safe Storage GC.

create table public.lifecycle_audit_events (
    audit_event_id uuid primary key default gen_random_uuid(),
    operation_id uuid not null,
    occurred_at timestamptz not null default statement_timestamp(),
    event_type text not null check (event_type in (
        'unpair', 'archive_seal', 'archive_delete', 'account_delete',
        'content_delete', 'object_gc', 'scope_cleanup', 'export_generation'
    )),
    actor_kind text not null check (actor_kind in ('user', 'system')),
    actor_ref uuid,
    scope_type text not null check (
        scope_type in ('account', 'relationship', 'archive', 'content', 'object')
    ),
    scope_ref uuid not null,
    entity_type text not null check (entity_type in (
        'account', 'relationship', 'relationship_content', 'archive', 'profile',
        'partner_alias', 'current_status', 'moment', 'moment_response',
        'moment_answer', 'message', 'message_reaction', 'appointment',
        'appointment_event', 'source_link', 'analytics_event', 'media_object',
        'invitation', 'device_registration', 'delivery_job', 'read_state',
        'operation', 'gc_queue'
    )),
    entity_ref uuid not null,
    result text not null check (
        result in ('accepted', 'blocked', 'succeeded', 'failed')
    ),
    reason_code text check (reason_code in (
        'outbox_not_empty', 'relationship_not_active',
        'relationship_not_accessible', 'personal_archive_not_accessible',
        'resource_not_found', 'export_not_ready',
        'reference_integrity_failed', 'checksum_mismatch',
        'journal_not_durable', 'auth_delete_failed',
        'storage_delete_failed', 'operation_conflict', 'invalid_request',
        'internal_error'
    )),
    affected_count integer check (affected_count is null or affected_count >= 0),
    contract_version text not null default 'w14-v1'
        check (contract_version = 'w14-v1'),
    constraint lifecycle_audit_actor_matches_kind check (
        (actor_kind = 'user' and actor_ref is not null)
        or (actor_kind = 'system' and actor_ref is null)
    )
);

create table public.deletion_tombstone_journal (
    event_id uuid primary key,
    sequence bigint not null unique check (sequence > 0),
    operation_id uuid not null,
    occurred_at timestamptz not null,
    actor_kind text not null check (actor_kind in ('user', 'system')),
    actor_ref uuid,
    scope_type text not null check (
        scope_type in ('account', 'relationship', 'archive', 'content', 'object')
    ),
    scope_ref uuid not null,
    entity_type text not null check (entity_type in (
        'account', 'relationship', 'relationship_content', 'archive', 'profile',
        'partner_alias', 'current_status', 'moment', 'moment_response',
        'moment_answer', 'message', 'message_reaction', 'appointment',
        'appointment_event', 'source_link', 'analytics_event', 'media_object',
        'invitation', 'device_registration', 'delivery_job', 'read_state',
        'operation', 'gc_queue'
    )),
    entity_ref uuid not null,
    action text not null check (
        action in ('content_delete', 'unpair', 'archive_delete',
                   'account_delete', 'object_gc')
    ),
    contract_version text not null check (contract_version = 'w14-v1'),
    event_hash text not null check (event_hash ~ '^[0-9a-f]{64}$'),
    constraint deletion_tombstone_actor_matches_kind check (
        (actor_kind = 'user' and actor_ref is not null)
        or (actor_kind = 'system' and actor_ref is null)
    )
);

create table public.deletion_journal_head (
    singleton boolean primary key default true check (singleton),
    last_sequence bigint not null check (last_sequence >= 0),
    last_event_hash text not null check (last_event_hash ~ '^[0-9a-f]{64}$')
);

insert into public.deletion_journal_head (
    singleton,
    last_sequence,
    last_event_hash
) values (
    true,
    0,
    repeat('0', 64)
);

alter table public.lifecycle_audit_events enable row level security;
alter table public.deletion_tombstone_journal enable row level security;
alter table public.deletion_journal_head enable row level security;

create function public._w14_tombstone_canonical_json(
    target_event_id uuid,
    target_sequence bigint,
    target_operation_id uuid,
    target_occurred_at timestamptz,
    target_actor_kind text,
    target_actor_ref uuid,
    target_scope_type text,
    target_scope_ref uuid,
    target_entity_type text,
    target_entity_ref uuid,
    target_action text,
    target_contract_version text
)
returns text
language sql
immutable
set search_path = ''
as $$
    select '{'
        || '"action":' || to_json(target_action)::text
        || ',"actor_kind":' || to_json(target_actor_kind)::text
        || ',"actor_ref":' || coalesce(to_json(target_actor_ref::text)::text, 'null')
        || ',"contract_version":' || to_json(target_contract_version)::text
        || ',"entity_ref":' || to_json(target_entity_ref::text)::text
        || ',"entity_type":' || to_json(target_entity_type)::text
        || ',"event_id":' || to_json(target_event_id::text)::text
        || ',"occurred_at":' || to_json(
            to_char(
                target_occurred_at at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            )
        )::text
        || ',"operation_id":' || to_json(target_operation_id::text)::text
        || ',"scope_ref":' || to_json(target_scope_ref::text)::text
        || ',"scope_type":' || to_json(target_scope_type)::text
        || ',"sequence":' || target_sequence::text
        || '}';
$$;

create function public._append_deletion_tombstone(
    target_operation_id uuid,
    target_occurred_at timestamptz,
    target_actor_kind text,
    target_actor_ref uuid,
    target_scope_type text,
    target_scope_ref uuid,
    target_entity_type text,
    target_entity_ref uuid,
    target_action text
)
returns public.deletion_tombstone_journal
language plpgsql
security definer
set search_path = ''
as $$
declare
    journal_head public.deletion_journal_head%rowtype;
    created_event public.deletion_tombstone_journal%rowtype;
    created_event_id uuid := gen_random_uuid();
    next_sequence bigint;
    canonical_event text;
    next_hash text;
begin
    if target_operation_id is null
       or target_occurred_at is null
       or target_scope_ref is null
       or target_entity_ref is null then
        raise exception 'invalid_tombstone_event' using errcode = '22023';
    end if;

    select journal.*
    into journal_head
    from public.deletion_journal_head journal
    where journal.singleton
    for update;

    next_sequence := journal_head.last_sequence + 1;
    canonical_event := public._w14_tombstone_canonical_json(
        created_event_id,
        next_sequence,
        target_operation_id,
        target_occurred_at,
        target_actor_kind,
        target_actor_ref,
        target_scope_type,
        target_scope_ref,
        target_entity_type,
        target_entity_ref,
        target_action,
        'w14-v1'
    );
    next_hash := encode(
        extensions.digest(
            convert_to(
                journal_head.last_event_hash || E'\n' || canonical_event,
                'UTF8'
            ),
            'sha256'
        ),
        'hex'
    );

    insert into public.deletion_tombstone_journal (
        event_id,
        sequence,
        operation_id,
        occurred_at,
        actor_kind,
        actor_ref,
        scope_type,
        scope_ref,
        entity_type,
        entity_ref,
        action,
        contract_version,
        event_hash
    ) values (
        created_event_id,
        next_sequence,
        target_operation_id,
        target_occurred_at,
        target_actor_kind,
        target_actor_ref,
        target_scope_type,
        target_scope_ref,
        target_entity_type,
        target_entity_ref,
        target_action,
        'w14-v1',
        next_hash
    )
    returning * into created_event;

    update public.deletion_journal_head
    set last_sequence = next_sequence,
        last_event_hash = next_hash
    where singleton;

    return created_event;
end;
$$;

create function public._write_lifecycle_audit(
    target_operation_id uuid,
    target_occurred_at timestamptz,
    target_event_type text,
    target_actor_kind text,
    target_actor_ref uuid,
    target_scope_type text,
    target_scope_ref uuid,
    target_entity_type text,
    target_entity_ref uuid,
    target_result text,
    target_reason_code text,
    target_affected_count integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    created_audit_event_id uuid;
begin
    insert into public.lifecycle_audit_events (
        operation_id,
        occurred_at,
        event_type,
        actor_kind,
        actor_ref,
        scope_type,
        scope_ref,
        entity_type,
        entity_ref,
        result,
        reason_code,
        affected_count
    ) values (
        target_operation_id,
        target_occurred_at,
        target_event_type,
        target_actor_kind,
        target_actor_ref,
        target_scope_type,
        target_scope_ref,
        target_entity_type,
        target_entity_ref,
        target_result,
        target_reason_code,
        target_affected_count
    )
    returning audit_event_id into created_audit_event_id;

    return created_audit_event_id;
end;
$$;

create function public._reject_tombstone_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    raise exception 'deletion_tombstone_append_only' using errcode = '55000';
end;
$$;

create trigger deletion_tombstone_append_only
before update or delete on public.deletion_tombstone_journal
for each row execute function public._reject_tombstone_mutation();

create table public.storage_media_objects (
    object_ref uuid primary key,
    bucket_id text not null check (
        bucket_id in ('couplespace-w1-photos', 'couplespace-moment-photos')
    ),
    object_path text not null,
    registered_at timestamptz not null default statement_timestamp(),
    unique (bucket_id, object_path)
);

create table public.storage_media_references (
    object_ref uuid not null references public.storage_media_objects(object_ref),
    reference_kind text not null check (
        reference_kind in ('moment', 'shared_item', 'personal_archive_item')
    ),
    reference_scope_id uuid not null,
    reference_id uuid not null,
    relationship_id uuid not null,
    created_at timestamptz not null default statement_timestamp(),
    primary key (
        object_ref,
        reference_kind,
        reference_scope_id,
        reference_id
    )
);

create index storage_media_references_object_idx
on public.storage_media_references (object_ref);

alter table public.storage_media_objects enable row level security;
alter table public.storage_media_references enable row level security;

alter table public.storage_gc_queue
    add column job_id uuid not null default gen_random_uuid(),
    add column gc_operation_id uuid not null default gen_random_uuid(),
    add column object_ref uuid,
    add column status text not null default 'pending',
    add column claim_token uuid,
    add column claimed_at timestamptz,
    add column lease_expires_at timestamptz,
    add column next_attempt_at timestamptz not null default statement_timestamp(),
    add column last_error_code text,
    add column completed_at timestamptz,
    add constraint storage_gc_queue_job_id_key unique (job_id),
    add constraint storage_gc_queue_status_check check (
        status in ('pending', 'processing', 'blocked', 'completed')
    ),
    add constraint storage_gc_queue_error_code_check check (
        last_error_code is null
        or last_error_code in ('storage_delete_failed', 'reference_integrity_failed')
    ),
    add constraint storage_gc_queue_state_check check (
        (status = 'pending'
            and claim_token is null
            and claimed_at is null
            and lease_expires_at is null
            and completed_at is null)
        or (status = 'processing'
            and claim_token is not null
            and claimed_at is not null
            and lease_expires_at is not null
            and completed_at is null)
        or (status = 'blocked'
            and claim_token is null
            and claimed_at is null
            and lease_expires_at is null
            and completed_at is null)
        or (status = 'completed'
            and claim_token is not null
            and claimed_at is not null
            and lease_expires_at is not null
            and completed_at is not null)
    );

insert into public.storage_media_objects (object_ref, bucket_id, object_path)
select
    coalesce(object.id, gen_random_uuid()),
    queue.bucket_id,
    coalesce(object.name, queue.object_path)
from public.storage_gc_queue queue
left join storage.objects object
  on object.bucket_id = queue.bucket_id
 and lower(object.name) = lower(queue.object_path)
on conflict (bucket_id, object_path) do nothing;

update public.storage_gc_queue queue
set object_ref = media.object_ref,
    object_path = media.object_path
from public.storage_media_objects media
where media.bucket_id = queue.bucket_id
  and lower(media.object_path) = lower(queue.object_path);

alter table public.storage_gc_queue
    alter column object_ref set not null,
    add constraint storage_gc_queue_object_ref_fkey
        foreign key (object_ref)
        references public.storage_media_objects(object_ref),
    drop column last_error;

create index storage_gc_queue_pending_claim_idx
on public.storage_gc_queue (next_attempt_at, enqueued_at, job_id)
where status = 'pending';

create index moments_pending_permanent_purge_idx
on public.moments (purge_after, relationship_id, client_id)
where deleted_at is not null;

create function public._register_storage_media_object(
    target_bucket_id text,
    target_object_path text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    stored_object_id uuid;
    stored_object_path text;
    registered_object_ref uuid;
begin
    select object.id, object.name
    into stored_object_id, stored_object_path
    from storage.objects object
    where object.bucket_id = target_bucket_id
      and lower(object.name) = lower(target_object_path)
    order by (object.name = target_object_path) desc, object.id
    limit 1
    for share;

    if stored_object_id is null then
        return null;
    end if;

    insert into public.storage_media_objects (
        object_ref,
        bucket_id,
        object_path
    ) values (
        stored_object_id,
        target_bucket_id,
        stored_object_path
    )
    on conflict do nothing;

    select media.object_ref
    into registered_object_ref
    from public.storage_media_objects media
    where media.bucket_id = target_bucket_id
      and media.object_path = stored_object_path;

    if registered_object_ref is distinct from stored_object_id then
        raise exception 'storage_object_identity_collision' using errcode = '23505';
    end if;

    return registered_object_ref;
end;
$$;

create function public._hydrate_storage_gc_queue_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    resolved_object_ref uuid;
    resolved_object_path text;
begin
    if new.object_ref is null then
        select media.object_ref, media.object_path
        into resolved_object_ref, resolved_object_path
        from public.storage_media_objects media
        where media.bucket_id = new.bucket_id
          and lower(media.object_path) = lower(new.object_path)
        order by (media.object_path = new.object_path) desc, media.object_ref
        limit 1;

        if resolved_object_ref is null then
            resolved_object_ref := public._register_storage_media_object(
                new.bucket_id,
                new.object_path
            );

            if resolved_object_ref is not null then
                select media.object_path
                into resolved_object_path
                from public.storage_media_objects media
                where media.object_ref = resolved_object_ref;
            end if;
        end if;

        if resolved_object_ref is null then
            resolved_object_ref := gen_random_uuid();
            insert into public.storage_media_objects (
                object_ref,
                bucket_id,
                object_path
            ) values (
                resolved_object_ref,
                new.bucket_id,
                new.object_path
            );
            resolved_object_path := new.object_path;
        end if;

        new.object_ref := resolved_object_ref;
        new.object_path := resolved_object_path;
    end if;

    return new;
end;
$$;

create trigger hydrate_storage_gc_queue_identity
before insert on public.storage_gc_queue
for each row execute function public._hydrate_storage_gc_queue_identity();

create function public._guard_storage_media_reference_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_gc_status text;
begin
    select queue.status
    into current_gc_status
    from public.storage_gc_queue queue
    where queue.object_ref = new.object_ref
    for update;

    perform 1
    from public.storage_media_objects media
    where media.object_ref = new.object_ref
    for update;

    -- A queue row can be inserted after the first lookup when this object had
    -- never been queued.  The media-row lock serializes that race; re-read the
    -- queue before allowing the new durable reference.
    select queue.status
    into current_gc_status
    from public.storage_gc_queue queue
    where queue.object_ref = new.object_ref
    for update;

    if current_gc_status in ('processing', 'completed') then
        raise exception 'media_object_gc_unavailable' using errcode = '23514';
    end if;

    if current_gc_status in ('pending', 'blocked') then
        update public.storage_gc_queue
        set status = 'blocked',
            claim_token = null,
            claimed_at = null,
            lease_expires_at = null,
            last_error_code = 'reference_integrity_failed'
        where object_ref = new.object_ref
          and status in ('pending', 'blocked');
    end if;

    return new;
end;
$$;

create trigger guard_storage_media_reference_insert
before insert on public.storage_media_references
for each row execute function public._guard_storage_media_reference_insert();

create function public._register_moment_media_reference()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_bucket_id text;
    target_object_path text;
    resolved_object_ref uuid;
begin
    if tg_op = 'DELETE' then
        delete from public.storage_media_references reference
        where reference.reference_kind = 'moment'
          and reference.reference_scope_id = old.id;
        return old;
    end if;

    delete from public.storage_media_references reference
    where reference.reference_kind = 'moment'
      and reference.reference_scope_id = new.id;

    if new.kind <> 'photo' then
        return new;
    end if;

    if new.source_shared_item_client_id is null then
        target_bucket_id := 'couplespace-moment-photos';
        target_object_path := lower(
            new.relationship_id::text || '/' || new.client_id::text || '.jpg'
        );
    else
        target_bucket_id := 'couplespace-w1-photos';
        target_object_path := lower(
            new.relationship_id::text || '/'
            || new.source_shared_item_client_id::text || '.jpg'
        );
    end if;

    resolved_object_ref := public._register_storage_media_object(
        target_bucket_id,
        target_object_path
    );

    if resolved_object_ref is null then
        raise exception 'moment_photo_not_available' using errcode = '23514';
    end if;

    insert into public.storage_media_references (
        object_ref,
        reference_kind,
        reference_scope_id,
        reference_id,
        relationship_id
    ) values (
        resolved_object_ref,
        'moment',
        new.id,
        new.client_id,
        new.relationship_id
    )
    on conflict do nothing;

    return new;
end;
$$;

create trigger register_moment_media_reference
after insert or update of kind, source_shared_item_client_id, media_byte_size
on public.moments
for each row execute function public._register_moment_media_reference();

create trigger remove_moment_media_reference
after delete on public.moments
for each row execute function public._register_moment_media_reference();

create function public._register_shared_item_media_reference()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_object_path text;
    resolved_object_ref uuid;
    relationship_status text;
begin
    if tg_op = 'DELETE' then
        delete from public.storage_media_references reference
        where reference.reference_kind = 'shared_item'
          and reference.reference_scope_id = old.id;
        return old;
    end if;

    delete from public.storage_media_references reference
    where reference.reference_kind = 'shared_item'
      and reference.reference_scope_id = new.id;

    if new.item_kind <> 'photo' or new.media_byte_size is null then
        return new;
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = new.relationship_id;

    if relationship_status = 'archived' then
        return new;
    end if;

    target_object_path := lower(
        new.relationship_id::text || '/' || new.client_id::text || '.jpg'
    );
    resolved_object_ref := public._register_storage_media_object(
        'couplespace-w1-photos',
        target_object_path
    );

    if resolved_object_ref is not null then
        insert into public.storage_media_references (
            object_ref,
            reference_kind,
            reference_scope_id,
            reference_id,
            relationship_id
        ) values (
            resolved_object_ref,
            'shared_item',
            new.id,
            new.client_id,
            new.relationship_id
        )
        on conflict do nothing;
    end if;

    return new;
end;
$$;

create trigger register_shared_item_media_reference
after insert or update of item_kind, media_byte_size
on public.shared_items
for each row execute function public._register_shared_item_media_reference();

create trigger remove_shared_item_media_reference
after delete on public.shared_items
for each row execute function public._register_shared_item_media_reference();

create function public._register_personal_archive_media_reference()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_relationship_id uuid;
    target_object_path text;
    resolved_object_ref uuid;
begin
    if tg_op = 'DELETE' then
        delete from public.storage_media_references reference
        where reference.reference_kind = 'personal_archive_item'
          and reference.reference_scope_id = old.archive_id
          and reference.reference_id = old.source_item_id;
        return old;
    end if;

    delete from public.storage_media_references reference
    where reference.reference_kind = 'personal_archive_item'
      and reference.reference_scope_id = new.archive_id
      and reference.reference_id = new.source_item_id;

    if new.item_kind <> 'photo' or new.media_byte_size is null then
        return new;
    end if;

    select archive.relationship_id
    into target_relationship_id
    from public.personal_archives archive
    where archive.id = new.archive_id;

    if target_relationship_id is null then
        return new;
    end if;

    target_object_path := lower(
        target_relationship_id::text || '/' || new.client_id::text || '.jpg'
    );
    resolved_object_ref := public._register_storage_media_object(
        'couplespace-w1-photos',
        target_object_path
    );

    if resolved_object_ref is not null then
        insert into public.storage_media_references (
            object_ref,
            reference_kind,
            reference_scope_id,
            reference_id,
            relationship_id
        ) values (
            resolved_object_ref,
            'personal_archive_item',
            new.archive_id,
            new.source_item_id,
            target_relationship_id
        )
        on conflict do nothing;
    end if;

    return new;
end;
$$;

create trigger register_personal_archive_media_reference
after insert or update of item_kind, media_byte_size
on public.personal_archive_items
for each row execute function public._register_personal_archive_media_reference();

create trigger remove_personal_archive_media_reference
after delete on public.personal_archive_items
for each row execute function public._register_personal_archive_media_reference();

create function public._drop_archived_live_media_references()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.status = 'archived' and old.status is distinct from 'archived' then
        delete from public.storage_media_references reference
        where reference.relationship_id = new.id
          and reference.reference_kind = 'shared_item';
    end if;
    return new;
end;
$$;

create trigger drop_archived_live_media_references
after update of status on public.relationships
for each row execute function public._drop_archived_live_media_references();

-- Backfill the existing product/reference graph. Runtime triggers maintain it afterward.
insert into public.storage_media_objects (object_ref, bucket_id, object_path)
select object.id, object.bucket_id, object.name
from storage.objects object
where object.bucket_id in ('couplespace-w1-photos', 'couplespace-moment-photos')
on conflict do nothing;

insert into public.storage_media_references (
    object_ref,
    reference_kind,
    reference_scope_id,
    reference_id,
    relationship_id
)
select
    media.object_ref,
    'moment',
    moment.id,
    moment.client_id,
    moment.relationship_id
from public.moments moment
join public.storage_media_objects media
  on media.bucket_id = case
      when moment.source_shared_item_client_id is null
          then 'couplespace-moment-photos'
      else 'couplespace-w1-photos'
  end
 and lower(media.object_path) = lower(
      moment.relationship_id::text || '/'
      || coalesce(moment.source_shared_item_client_id, moment.client_id)::text
      || '.jpg'
 )
where moment.kind = 'photo'
on conflict do nothing;

insert into public.storage_media_references (
    object_ref,
    reference_kind,
    reference_scope_id,
    reference_id,
    relationship_id
)
select
    media.object_ref,
    'shared_item',
    item.id,
    item.client_id,
    item.relationship_id
from public.shared_items item
join public.relationships relationship
  on relationship.id = item.relationship_id
join public.storage_media_objects media
  on media.bucket_id = 'couplespace-w1-photos'
 and lower(media.object_path) = lower(
      item.relationship_id::text || '/' || item.client_id::text || '.jpg'
 )
where item.item_kind = 'photo'
  and item.media_byte_size is not null
  and relationship.status <> 'archived'
on conflict do nothing;

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
    item.archive_id,
    item.source_item_id,
    archive.relationship_id
from public.personal_archive_items item
join public.personal_archives archive
  on archive.id = item.archive_id
join public.storage_media_objects media
  on media.bucket_id = 'couplespace-w1-photos'
 and lower(media.object_path) = lower(
      archive.relationship_id::text || '/' || item.client_id::text || '.jpg'
 )
where item.item_kind = 'photo'
  and item.media_byte_size is not null
on conflict do nothing;

create table public.moment_purge_markers (
    relationship_id uuid not null,
    moment_client_id uuid not null,
    source_message_client_id uuid,
    lifecycle_revision bigint not null check (lifecycle_revision > 0),
    deletion_operation_id uuid not null,
    content_tombstone_event_id uuid not null unique,
    purged_at timestamptz not null,
    media_object_ref uuid,
    gc_operation_id uuid,
    primary key (relationship_id, moment_client_id),
    constraint moment_purge_marker_gc_identity check (
        (media_object_ref is null and gc_operation_id is null)
        or (media_object_ref is not null and gc_operation_id is not null)
    )
);

create index moment_purge_markers_media_idx
on public.moment_purge_markers (media_object_ref)
where media_object_ref is not null;

alter table public.moment_purge_markers enable row level security;

-- These body-free rows are concurrency fences, not product data.  ON CONFLICT
-- observes the winning tuple even when a create started before a concurrent
-- purge committed, closing the unique-key wait/resurrection race.
create table public.moment_identity_guards (
    relationship_id uuid not null,
    moment_client_id uuid not null,
    is_permanently_deleted boolean not null default false,
    primary key (relationship_id, moment_client_id)
);

create table public.moment_source_identity_guards (
    relationship_id uuid not null,
    source_message_client_id uuid not null,
    is_permanently_deleted boolean not null default false,
    primary key (relationship_id, source_message_client_id)
);

alter table public.moment_identity_guards enable row level security;
alter table public.moment_source_identity_guards enable row level security;

insert into public.moment_identity_guards (
    relationship_id,
    moment_client_id,
    is_permanently_deleted
)
select moment.relationship_id, moment.client_id, false
from public.moments moment
on conflict do nothing;

insert into public.moment_source_identity_guards (
    relationship_id,
    source_message_client_id,
    is_permanently_deleted
)
select moment.relationship_id, moment.source_shared_item_client_id, false
from public.moments moment
where moment.source_shared_item_client_id is not null
on conflict do nothing;

create function public._enqueue_storage_gc_if_unreferenced(
    target_object_ref uuid,
    target_gc_operation_id uuid,
    target_server_time timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    stored_media public.storage_media_objects%rowtype;
    changed_count integer := 0;
begin
    -- Keep the lock order aligned with claim/reference insertion: queue first,
    -- then the opaque media identity.  This avoids a queue/media deadlock when
    -- the final reference disappears while another transaction adds one.
    perform 1
    from public.storage_gc_queue queue
    where queue.object_ref = target_object_ref
    for update;

    select media.*
    into stored_media
    from public.storage_media_objects media
    where media.object_ref = target_object_ref
    for update;

    if stored_media.object_ref is null
       or exists (
           select 1
           from public.storage_media_references reference
           where reference.object_ref = target_object_ref
       ) then
        return false;
    end if;

    insert into public.storage_gc_queue (
        bucket_id,
        object_path,
        object_ref,
        gc_operation_id,
        status,
        next_attempt_at,
        last_error_code
    ) values (
        stored_media.bucket_id,
        stored_media.object_path,
        stored_media.object_ref,
        target_gc_operation_id,
        'pending',
        target_server_time,
        null
    )
    on conflict (bucket_id, object_path) do update
    set status = case
            when public.storage_gc_queue.status = 'blocked' then 'pending'
            else public.storage_gc_queue.status
        end,
        next_attempt_at = case
            when public.storage_gc_queue.status = 'blocked'
                then excluded.next_attempt_at
            else public.storage_gc_queue.next_attempt_at
        end,
        last_error_code = case
            when public.storage_gc_queue.status = 'blocked' then null
            else public.storage_gc_queue.last_error_code
        end
    where public.storage_gc_queue.object_ref = excluded.object_ref
      and public.storage_gc_queue.status in ('pending', 'blocked');

    get diagnostics changed_count = row_count;
    return changed_count > 0;
end;
$$;

create function public._enqueue_released_moment_media()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_gc_operation_id uuid;
    target_not_before timestamptz;
begin
    if exists (
        select 1
        from public.storage_media_references reference
        where reference.object_ref = old.object_ref
    ) then
        return old;
    end if;

    select marker.gc_operation_id, marker.purged_at
    into target_gc_operation_id, target_not_before
    from public.moment_purge_markers marker
    where marker.media_object_ref = old.object_ref
      and marker.gc_operation_id is not null
    order by marker.purged_at, marker.moment_client_id
    limit 1;

    if target_gc_operation_id is not null then
        perform public._enqueue_storage_gc_if_unreferenced(
            old.object_ref,
            target_gc_operation_id,
            least(statement_timestamp(), target_not_before)
        );
    end if;

    return old;
end;
$$;

create trigger enqueue_released_moment_media
after delete on public.storage_media_references
for each row execute function public._enqueue_released_moment_media();

create or replace function public.reject_deleted_moment_recreation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    existing_deleted_at timestamptz;
    identity_is_permanently_deleted boolean;
    source_is_permanently_deleted boolean;
begin
    insert into public.moment_identity_guards (
        relationship_id,
        moment_client_id,
        is_permanently_deleted
    ) values (
        new.relationship_id,
        new.client_id,
        false
    )
    on conflict (relationship_id, moment_client_id) do update
    set is_permanently_deleted =
        public.moment_identity_guards.is_permanently_deleted
    returning is_permanently_deleted
    into identity_is_permanently_deleted;

    if identity_is_permanently_deleted then
        raise exception 'moment_permanently_deleted' using errcode = '23514';
    end if;

    if new.source_shared_item_client_id is not null then
        insert into public.moment_source_identity_guards (
            relationship_id,
            source_message_client_id,
            is_permanently_deleted
        ) values (
            new.relationship_id,
            new.source_shared_item_client_id,
            false
        )
        on conflict (relationship_id, source_message_client_id) do update
        set is_permanently_deleted =
            public.moment_source_identity_guards.is_permanently_deleted
        returning is_permanently_deleted
        into source_is_permanently_deleted;

        if source_is_permanently_deleted then
            raise exception 'moment_permanently_deleted' using errcode = '23514';
        end if;
    end if;

    if exists (
        select 1
        from public.moment_purge_markers marker
        where marker.relationship_id = new.relationship_id
          and (
              marker.moment_client_id = new.client_id
              or (
                  new.source_shared_item_client_id is not null
                  and marker.source_message_client_id
                      = new.source_shared_item_client_id
              )
          )
    ) then
        raise exception 'moment_permanently_deleted' using errcode = '23514';
    end if;

    select moment.deleted_at
    into existing_deleted_at
    from public.moments moment
    where moment.relationship_id = new.relationship_id
      and moment.client_id = new.client_id;

    if found and existing_deleted_at is not null then
        raise exception 'moment_deleted' using errcode = '23514';
    end if;

    return new;
end;
$$;

create or replace function public.list_hidden_moment_ids(target_relationship_id uuid)
returns table (
    moment_client_id uuid,
    source_message_client_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id;

    if relationship_status <> 'active' then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    return query
    select hidden.moment_client_id, hidden.source_message_client_id
    from (
        select moment.client_id as moment_client_id,
               moment.source_shared_item_client_id as source_message_client_id
        from public.moments moment
        where moment.relationship_id = target_relationship_id
          and moment.deleted_at is not null
        union all
        select marker.moment_client_id,
               marker.source_message_client_id
        from public.moment_purge_markers marker
        where marker.relationship_id = target_relationship_id
    ) hidden
    order by hidden.moment_client_id;
end;
$$;

create or replace function public.list_moment_sync_hints(
    target_relationship_id uuid,
    after_moment_client_id uuid default null,
    target_limit integer default 500
)
returns table (
    moment_client_id uuid,
    is_deleted boolean,
    source_message_client_id uuid,
    revision bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id;

    if relationship_status <> 'active' then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    return query
    select hint.moment_client_id,
           hint.is_deleted,
           hint.source_message_client_id,
           hint.revision
    from (
        select moment.client_id as moment_client_id,
               moment.deleted_at is not null as is_deleted,
               moment.source_shared_item_client_id as source_message_client_id,
               moment.lifecycle_revision as revision
        from public.moments moment
        where moment.relationship_id = target_relationship_id
          and moment.lifecycle_revision > 0
        union all
        select marker.moment_client_id,
               true,
               marker.source_message_client_id,
               marker.lifecycle_revision
        from public.moment_purge_markers marker
        where marker.relationship_id = target_relationship_id
    ) hint
    where after_moment_client_id is null
       or hint.moment_client_id > after_moment_client_id
    order by hint.moment_client_id
    limit least(greatest(coalesce(target_limit, 500), 1), 500);
end;
$$;

create function public._moment_photo_path_is_purged(
    target_relationship_id_text text,
    target_filename text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select case
        when not exists (
            select 1
            from public.relationship_members member
            join public.relationships relationship
              on relationship.id = member.relationship_id
            where member.relationship_id::text = lower(target_relationship_id_text)
              and member.user_id = (select auth.uid())
              and member.membership_status = 'active'
              and relationship.status = 'active'
        ) then true
        else exists (
            select 1
            from public.moment_purge_markers marker
            where marker.relationship_id::text = lower(target_relationship_id_text)
              and lower(marker.moment_client_id::text || '.jpg')
                  = lower(target_filename)
        )
    end;
$$;

drop policy if exists "Relationship members can upload Moment photos while active"
on storage.objects;
create policy "Relationship members can upload new Moment photos while active"
on storage.objects for insert
to authenticated
with check (
    bucket_id = 'couplespace-moment-photos'
    and owner_id = (select auth.uid())::text
    and array_length(storage.foldername(name), 1) = 1
    and storage.filename(name) = lower(storage.filename(name))
    and storage.filename(name) ~
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.]jpg$'
    and not public._moment_photo_path_is_purged(
        (storage.foldername(name))[1],
        storage.filename(name)
    )
    and exists (
        select 1
        from public.relationship_members member
        join public.relationships relationship
          on relationship.id = member.relationship_id
        where member.relationship_id::text = (storage.foldername(name))[1]
          and member.user_id = (select auth.uid())
          and member.membership_status = 'active'
          and relationship.status = 'active'
    )
);

drop policy if exists "Uploaders can delete unfinalized Moment photos"
on storage.objects;
create policy "Uploaders can delete only unfinalized Moment photos"
on storage.objects for delete
to authenticated
using (
    bucket_id = 'couplespace-moment-photos'
    and owner_id = (select auth.uid())::text
    and not exists (
        select 1
        from public.storage_media_objects media
        where media.object_ref = storage.objects.id
    )
    and not public._moment_photo_path_is_purged(
        (storage.foldername(name))[1],
        storage.filename(name)
    )
    and not exists (
        select 1
        from public.moments moment
        where moment.relationship_id::text = (storage.foldername(name))[1]
          and lower(moment.client_id::text || '.jpg') = lower(storage.filename(name))
    )
);

create function public._purge_expired_moments_at(
    target_server_time timestamptz,
    target_limit integer default 100,
    target_relationship_id uuid default null,
    target_force_relationship boolean default false
)
returns table (
    purged_count integer,
    queued_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    stored_moment public.moments%rowtype;
    target_delete_operation_id uuid;
    target_content_tombstone public.deletion_tombstone_journal%rowtype;
    target_media_object_ref uuid;
    target_gc_operation_id uuid;
    target_queue_preexisted boolean;
    total_purged integer := 0;
    total_queued integer := 0;
begin
    if target_server_time is null
       or target_limit is null
       or target_limit not between 1 and 500
       or target_force_relationship is null
       or (target_force_relationship and target_relationship_id is null) then
        raise exception 'invalid_purge_request' using errcode = '22023';
    end if;

    for stored_moment in
        select moment.*
        from public.moments moment
        where moment.deleted_at is not null
          and (
              (
                  target_force_relationship
                  and moment.relationship_id = target_relationship_id
              )
              or (
                  not target_force_relationship
                  and moment.purge_after <= target_server_time
                  and (
                      target_relationship_id is null
                      or moment.relationship_id = target_relationship_id
                  )
              )
          )
        order by moment.purge_after, moment.relationship_id, moment.client_id
        for update skip locked
        limit target_limit
    loop
        select operation.operation_id
        into target_delete_operation_id
        from public.moment_lifecycle_operations operation
        where operation.relationship_id = stored_moment.relationship_id
          and operation.moment_client_id = stored_moment.client_id
          and operation.operation_kind = 'delete'
        order by operation.created_at desc, operation.operation_id desc
        limit 1;

        target_delete_operation_id := coalesce(
            target_delete_operation_id,
            gen_random_uuid()
        );
        target_media_object_ref := null;
        target_gc_operation_id := null;
        target_queue_preexisted := false;

        insert into public.moment_identity_guards (
            relationship_id,
            moment_client_id,
            is_permanently_deleted
        ) values (
            stored_moment.relationship_id,
            stored_moment.client_id,
            true
        )
        on conflict (relationship_id, moment_client_id) do update
        set is_permanently_deleted = true;

        if stored_moment.source_shared_item_client_id is not null then
            insert into public.moment_source_identity_guards (
                relationship_id,
                source_message_client_id,
                is_permanently_deleted
            ) values (
                stored_moment.relationship_id,
                stored_moment.source_shared_item_client_id,
                true
            )
            on conflict (relationship_id, source_message_client_id) do update
            set is_permanently_deleted = true;
        end if;

        if stored_moment.kind = 'photo'
           and stored_moment.source_shared_item_client_id is null then
            select reference.object_ref
            into target_media_object_ref
            from public.storage_media_references reference
            where reference.reference_kind = 'moment'
              and reference.reference_scope_id = stored_moment.id
            order by reference.object_ref
            limit 1;

            if target_media_object_ref is null then
                target_media_object_ref := public._register_storage_media_object(
                    'couplespace-moment-photos',
                    lower(
                        stored_moment.relationship_id::text || '/'
                        || stored_moment.client_id::text || '.jpg'
                    )
                );
            end if;

            if target_media_object_ref is not null then
                target_gc_operation_id := gen_random_uuid();
                select exists (
                    select 1
                    from public.storage_gc_queue queue
                    where queue.object_ref = target_media_object_ref
                ) into target_queue_preexisted;
            end if;
        end if;

        target_content_tombstone := public._append_deletion_tombstone(
            target_delete_operation_id,
            target_server_time,
            'system',
            null,
            'content',
            stored_moment.relationship_id,
            'moment',
            stored_moment.client_id,
            'content_delete'
        );

        perform public._write_lifecycle_audit(
            target_delete_operation_id,
            target_server_time,
            'content_delete',
            'system',
            null,
            'content',
            stored_moment.relationship_id,
            'moment',
            stored_moment.client_id,
            'succeeded',
            null,
            null
        );

        insert into public.moment_purge_markers (
            relationship_id,
            moment_client_id,
            source_message_client_id,
            lifecycle_revision,
            deletion_operation_id,
            content_tombstone_event_id,
            purged_at,
            media_object_ref,
            gc_operation_id
        ) values (
            stored_moment.relationship_id,
            stored_moment.client_id,
            stored_moment.source_shared_item_client_id,
            stored_moment.lifecycle_revision + 1,
            target_delete_operation_id,
            target_content_tombstone.event_id,
            target_server_time,
            target_media_object_ref,
            target_gc_operation_id
        )
        on conflict (relationship_id, moment_client_id) do nothing;

        delete from public.moments moment
        where moment.id = stored_moment.id;

        -- A direct photo can have no registered Moment reference when an older
        -- client finalized the row before its Storage upload.  Recheck after
        -- the row is gone so that this path still reaches the same last-ref
        -- queue without relying solely on the reference-delete trigger.
        if target_media_object_ref is not null then
            perform public._enqueue_storage_gc_if_unreferenced(
                target_media_object_ref,
                target_gc_operation_id,
                target_server_time
            );
        end if;

        if target_media_object_ref is not null
           and not target_queue_preexisted
           and exists (
               select 1
               from public.storage_gc_queue queue
               where queue.object_ref = target_media_object_ref
           ) then
            total_queued := total_queued + 1;
        end if;

        perform realtime.send(
            jsonb_build_object(
                'moment_client_id', stored_moment.client_id,
                'change_kind', 'deleted'
            ),
            'moment-lifecycle',
            'relationship:' || stored_moment.relationship_id::text,
            true
        );

        total_purged := total_purged + 1;
    end loop;

    return query select total_purged, total_queued;
end;
$$;

create function public.purge_expired_moments(target_limit integer default 100)
returns table (
    purged_count integer,
    queued_count integer
)
language sql
volatile
security definer
set search_path = ''
as $$
    select *
    from public._purge_expired_moments_at(
        statement_timestamp(),
        target_limit,
        null,
        false
    );
$$;

create or replace function public.begin_unpairing(target_relationship_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    batch_purged_count integer;
begin
    if not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    if (
        select count(*)
        from public.relationship_members member
        where member.relationship_id = target_relationship_id
          and member.membership_status = 'active'
    ) <> 2 then
        raise exception 'relationship_requires_two_members' using errcode = '23514';
    end if;

    update public.relationships
    set status = 'closing',
        closing_started_at = coalesce(closing_started_at, statement_timestamp())
    where id = target_relationship_id
      and status in ('active', 'closing');

    if not found then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    loop
        select result.purged_count
        into batch_purged_count
        from public._purge_expired_moments_at(
            statement_timestamp(),
            500,
            target_relationship_id,
            true
        ) result;

        exit when batch_purged_count < 500;
    end loop;
end;
$$;

create function public.replay_moment_purge_tombstone(target_event_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    stored_event public.deletion_tombstone_journal%rowtype;
    restored_moment public.moments%rowtype;
    restored_media_object_ref uuid;
    restored_gc_operation_id uuid;
begin
    select event.*
    into stored_event
    from public.deletion_tombstone_journal event
    where event.event_id = target_event_id
      and event.action = 'content_delete'
      and event.entity_type = 'moment';

    if stored_event.event_id is null then
        raise exception 'resource_not_found' using errcode = 'P0002';
    end if;

    select moment.*
    into restored_moment
    from public.moments moment
    where moment.relationship_id = stored_event.scope_ref
      and moment.client_id = stored_event.entity_ref
    for update;

    if restored_moment.id is not null
       and restored_moment.kind = 'photo'
       and restored_moment.source_shared_item_client_id is null then
        restored_media_object_ref := public._register_storage_media_object(
            'couplespace-moment-photos',
            lower(
                restored_moment.relationship_id::text || '/'
                || restored_moment.client_id::text || '.jpg'
            )
        );
        if restored_media_object_ref is not null then
            restored_gc_operation_id := gen_random_uuid();
        end if;
    end if;

    insert into public.moment_identity_guards (
        relationship_id,
        moment_client_id,
        is_permanently_deleted
    ) values (
        stored_event.scope_ref,
        stored_event.entity_ref,
        true
    )
    on conflict (relationship_id, moment_client_id) do update
    set is_permanently_deleted = true;

    if restored_moment.source_shared_item_client_id is not null then
        insert into public.moment_source_identity_guards (
            relationship_id,
            source_message_client_id,
            is_permanently_deleted
        ) values (
            restored_moment.relationship_id,
            restored_moment.source_shared_item_client_id,
            true
        )
        on conflict (relationship_id, source_message_client_id) do update
        set is_permanently_deleted = true;
    end if;

    insert into public.moment_purge_markers (
        relationship_id,
        moment_client_id,
        source_message_client_id,
        lifecycle_revision,
        deletion_operation_id,
        content_tombstone_event_id,
        purged_at,
        media_object_ref,
        gc_operation_id
    ) values (
        stored_event.scope_ref,
        stored_event.entity_ref,
        restored_moment.source_shared_item_client_id,
        greatest(coalesce(restored_moment.lifecycle_revision, 0) + 1, stored_event.sequence),
        stored_event.operation_id,
        stored_event.event_id,
        stored_event.occurred_at,
        restored_media_object_ref,
        restored_gc_operation_id
    )
    on conflict (relationship_id, moment_client_id) do nothing;

    if restored_moment.id is not null then
        delete from public.moments moment
        where moment.id = restored_moment.id;
    end if;

    return true;
end;
$$;

create function public._registered_owned_storage_media_object(target_object_ref uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select case
        when not exists (
            select 1
            from storage.objects object
            where object.id = target_object_ref
              and object.owner_id = (select auth.uid())::text
        ) then true
        else exists (
            select 1
            from public.storage_media_objects media
            where media.object_ref = target_object_ref
        )
    end;
$$;

drop policy "Uploaders can delete active or archived W1 photos"
on storage.objects;
create policy "Uploaders can delete active or archived W1 photos"
on storage.objects for delete
to authenticated
using (
    bucket_id = 'couplespace-w1-photos'
    and owner_id = (select auth.uid())::text
    and not public._registered_owned_storage_media_object(storage.objects.id)
    and array_length(storage.foldername(name), 1) = 1
    and (
        exists (
            select 1
            from public.relationship_members member
            where member.relationship_id::text = (storage.foldername(name))[1]
              and member.user_id = (select auth.uid())
              and member.membership_status = 'active'
        )
        or (
            exists (
                select 1
                from public.personal_archives archive
                where archive.relationship_id::text = (storage.foldername(name))[1]
                  and archive.owner_user_id = (select auth.uid())
            )
            and public.is_w1_photo_orphan(name)
        )
    )
);

drop policy "Uploaders can delete only unfinalized Moment photos"
on storage.objects;
create policy "Uploaders can delete only unfinalized Moment photos"
on storage.objects for delete
to authenticated
using (
    bucket_id = 'couplespace-moment-photos'
    and owner_id = (select auth.uid())::text
    and not public._registered_owned_storage_media_object(storage.objects.id)
    and not public._moment_photo_path_is_purged(
        (storage.foldername(name))[1],
        storage.filename(name)
    )
    and not exists (
        select 1
        from public.moments moment
        where moment.relationship_id::text = (storage.foldername(name))[1]
          and lower(moment.client_id::text || '.jpg') = lower(storage.filename(name))
    )
);

create function public._claim_storage_gc_jobs_at(
    target_limit integer,
    target_server_time timestamptz
)
returns table (
    job_id uuid,
    claim_token uuid,
    bucket_id text,
    object_path text,
    attempt_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    stored_job public.storage_gc_queue%rowtype;
    recovered_job public.storage_gc_queue%rowtype;
    current_storage_object_id uuid;
    created_claim_token uuid;
begin
    if target_server_time is null
       or target_limit is null
       or target_limit not between 1 and 100 then
        raise exception 'invalid_gc_claim_request' using errcode = '22023';
    end if;

    for recovered_job in
        update public.storage_gc_queue queue
        set status = 'pending',
            claim_token = null,
            claimed_at = null,
            lease_expires_at = null,
            attempt_count = queue.attempt_count + 1,
            next_attempt_at = target_server_time,
            last_error_code = null
        where queue.status = 'processing'
          and queue.lease_expires_at <= target_server_time
        returning queue.*
    loop
        perform public._write_lifecycle_audit(
            recovered_job.gc_operation_id,
            target_server_time,
            'object_gc',
            'system',
            null,
            'object',
            recovered_job.object_ref,
            'media_object',
            recovered_job.object_ref,
            'failed',
            'internal_error',
            0
        );
    end loop;

    update public.storage_gc_queue queue
    set status = 'pending',
        next_attempt_at = target_server_time,
        last_error_code = null
    where queue.status = 'blocked'
      and not exists (
          select 1
          from public.storage_media_references reference
          where reference.object_ref = queue.object_ref
      )
      and not exists (
          select 1
          from storage.objects object
          where object.bucket_id = queue.bucket_id
            and object.name = queue.object_path
            and object.id <> queue.object_ref
      );

    for stored_job in
        select queue.*
        from public.storage_gc_queue queue
        where queue.status = 'pending'
          and queue.next_attempt_at <= target_server_time
        order by queue.enqueued_at, queue.job_id
        for update skip locked
        limit target_limit
    loop
        perform 1
        from public.storage_media_objects media
        where media.object_ref = stored_job.object_ref
        for update;

        if exists (
            select 1
            from public.storage_media_references reference
            where reference.object_ref = stored_job.object_ref
        ) then
            update public.storage_gc_queue queue
            set status = 'blocked',
                last_error_code = 'reference_integrity_failed'
            where queue.job_id = stored_job.job_id;

            perform public._write_lifecycle_audit(
                stored_job.gc_operation_id,
                target_server_time,
                'object_gc',
                'system',
                null,
                'object',
                stored_job.object_ref,
                'media_object',
                stored_job.object_ref,
                'blocked',
                'reference_integrity_failed',
                0
            );
            continue;
        end if;

        select object.id
        into current_storage_object_id
        from storage.objects object
        where object.bucket_id = stored_job.bucket_id
          and object.name = stored_job.object_path;

        if current_storage_object_id is not null
           and current_storage_object_id <> stored_job.object_ref then
            update public.storage_gc_queue queue
            set status = 'blocked',
                last_error_code = 'reference_integrity_failed'
            where queue.job_id = stored_job.job_id;

            perform public._write_lifecycle_audit(
                stored_job.gc_operation_id,
                target_server_time,
                'object_gc',
                'system',
                null,
                'object',
                stored_job.object_ref,
                'media_object',
                stored_job.object_ref,
                'blocked',
                'reference_integrity_failed',
                0
            );
            continue;
        end if;

        created_claim_token := gen_random_uuid();
        update public.storage_gc_queue queue
        set status = 'processing',
            claim_token = created_claim_token,
            claimed_at = target_server_time,
            lease_expires_at = target_server_time + interval '5 minutes',
            last_error_code = null
        where queue.job_id = stored_job.job_id;

        job_id := stored_job.job_id;
        claim_token := created_claim_token;
        bucket_id := stored_job.bucket_id;
        object_path := stored_job.object_path;
        attempt_count := stored_job.attempt_count;
        return next;
    end loop;
end;
$$;

create function public.claim_storage_gc_jobs(target_limit integer default 20)
returns table (
    job_id uuid,
    claim_token uuid,
    bucket_id text,
    object_path text,
    attempt_count integer
)
language sql
volatile
security definer
set search_path = ''
as $$
    select *
    from public._claim_storage_gc_jobs_at(
        target_limit,
        statement_timestamp()
    );
$$;

create function public._fail_storage_gc_job_at(
    target_job_id uuid,
    target_claim_token uuid,
    target_reason_code text,
    target_server_time timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    stored_job public.storage_gc_queue%rowtype;
    next_attempt_count integer;
    backoff_seconds integer;
begin
    if target_reason_code is distinct from 'storage_delete_failed' then
        raise exception 'invalid_gc_failure_reason' using errcode = '22023';
    end if;

    select queue.*
    into stored_job
    from public.storage_gc_queue queue
    where queue.job_id = target_job_id
    for update;

    if stored_job.job_id is null
       or stored_job.status <> 'processing'
       or stored_job.claim_token is distinct from target_claim_token then
        raise exception 'gc_claim_not_owned' using errcode = '42501';
    end if;

    next_attempt_count := stored_job.attempt_count + 1;
    backoff_seconds := least(
        300,
        power(2::numeric, least(next_attempt_count, 8))::integer
    );

    update public.storage_gc_queue queue
    set status = 'pending',
        claim_token = null,
        claimed_at = null,
        lease_expires_at = null,
        attempt_count = next_attempt_count,
        next_attempt_at = target_server_time
            + make_interval(secs => backoff_seconds),
        last_error_code = target_reason_code
    where queue.job_id = target_job_id;

    perform public._write_lifecycle_audit(
        stored_job.gc_operation_id,
        target_server_time,
        'object_gc',
        'system',
        null,
        'object',
        stored_job.object_ref,
        'media_object',
        stored_job.object_ref,
        'failed',
        'storage_delete_failed',
        0
    );

    return true;
end;
$$;

create function public.fail_storage_gc_job(
    target_job_id uuid,
    target_claim_token uuid,
    target_reason_code text
)
returns boolean
language sql
volatile
security definer
set search_path = ''
as $$
    select public._fail_storage_gc_job_at(
        target_job_id,
        target_claim_token,
        target_reason_code,
        statement_timestamp()
    );
$$;

create function public._complete_storage_gc_job_at(
    target_job_id uuid,
    target_claim_token uuid,
    target_server_time timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    stored_job public.storage_gc_queue%rowtype;
begin
    select queue.*
    into stored_job
    from public.storage_gc_queue queue
    where queue.job_id = target_job_id
    for update;

    if stored_job.job_id is null then
        raise exception 'resource_not_found' using errcode = 'P0002';
    end if;

    if stored_job.status = 'completed'
       and stored_job.claim_token = target_claim_token then
        return true;
    end if;

    if stored_job.status <> 'processing'
       or stored_job.claim_token is distinct from target_claim_token then
        raise exception 'gc_claim_not_owned' using errcode = '42501';
    end if;

    if exists (
        select 1
        from public.storage_media_references reference
        where reference.object_ref = stored_job.object_ref
    ) then
        update public.storage_gc_queue queue
        set status = 'blocked',
            claim_token = null,
            claimed_at = null,
            lease_expires_at = null,
            last_error_code = 'reference_integrity_failed'
        where queue.job_id = stored_job.job_id;

        perform public._write_lifecycle_audit(
            stored_job.gc_operation_id,
            target_server_time,
            'object_gc',
            'system',
            null,
            'object',
            stored_job.object_ref,
            'media_object',
            stored_job.object_ref,
            'blocked',
            'reference_integrity_failed',
            0
        );
        return false;
    end if;

    perform public._append_deletion_tombstone(
        stored_job.gc_operation_id,
        target_server_time,
        'system',
        null,
        'object',
        stored_job.object_ref,
        'media_object',
        stored_job.object_ref,
        'object_gc'
    );

    perform public._write_lifecycle_audit(
        stored_job.gc_operation_id,
        target_server_time,
        'object_gc',
        'system',
        null,
        'object',
        stored_job.object_ref,
        'media_object',
        stored_job.object_ref,
        'succeeded',
        null,
        1
    );

    update public.storage_gc_queue queue
    set status = 'completed',
        completed_at = target_server_time,
        last_error_code = null
    where queue.job_id = stored_job.job_id;

    return true;
end;
$$;

create function public.complete_storage_gc_job(
    target_job_id uuid,
    target_claim_token uuid
)
returns boolean
language sql
volatile
security definer
set search_path = ''
as $$
    select public._complete_storage_gc_job_at(
        target_job_id,
        target_claim_token,
        statement_timestamp()
    );
$$;

-- The journal, audit trail, media graph, and queue are server internals.  The
-- service role also uses only the narrow RPC surface so a leaked user JWT (or
-- an accidental direct table query in the worker) cannot obtain ambient GC
-- authority.
revoke all on table public.lifecycle_audit_events
from anon, authenticated, service_role;
revoke all on table public.deletion_tombstone_journal
from anon, authenticated, service_role;
revoke all on table public.deletion_journal_head
from anon, authenticated, service_role;
revoke all on table public.storage_media_objects
from anon, authenticated, service_role;
revoke all on table public.storage_media_references
from anon, authenticated, service_role;
revoke all on table public.moment_purge_markers
from anon, authenticated, service_role;
revoke all on table public.moment_identity_guards
from anon, authenticated, service_role;
revoke all on table public.moment_source_identity_guards
from anon, authenticated, service_role;
revoke all on table public.storage_gc_queue
from anon, authenticated, service_role;

revoke all on function public._w14_tombstone_canonical_json(
    uuid, bigint, uuid, timestamptz, text, uuid, text, uuid, text, uuid, text, text
) from public, anon, authenticated, service_role;
revoke all on function public._append_deletion_tombstone(
    uuid, timestamptz, text, uuid, text, uuid, text, uuid, text
) from public, anon, authenticated, service_role;
revoke all on function public._write_lifecycle_audit(
    uuid, timestamptz, text, text, uuid, text, uuid, text, uuid, text, text, integer
) from public, anon, authenticated, service_role;
revoke all on function public._reject_tombstone_mutation()
from public, anon, authenticated, service_role;
revoke all on function public._register_storage_media_object(text, text)
from public, anon, authenticated, service_role;
revoke all on function public._hydrate_storage_gc_queue_identity()
from public, anon, authenticated, service_role;
revoke all on function public._guard_storage_media_reference_insert()
from public, anon, authenticated, service_role;
revoke all on function public._register_moment_media_reference()
from public, anon, authenticated, service_role;
revoke all on function public._register_shared_item_media_reference()
from public, anon, authenticated, service_role;
revoke all on function public._register_personal_archive_media_reference()
from public, anon, authenticated, service_role;
revoke all on function public._drop_archived_live_media_references()
from public, anon, authenticated, service_role;
revoke all on function public._enqueue_storage_gc_if_unreferenced(
    uuid, uuid, timestamptz
) from public, anon, authenticated, service_role;
revoke all on function public._enqueue_released_moment_media()
from public, anon, authenticated, service_role;
revoke all on function public.reject_deleted_moment_recreation()
from public, anon, authenticated, service_role;
revoke all on function public._purge_expired_moments_at(
    timestamptz, integer, uuid, boolean
) from public, anon, authenticated, service_role;
revoke all on function public._claim_storage_gc_jobs_at(integer, timestamptz)
from public, anon, authenticated, service_role;
revoke all on function public._fail_storage_gc_job_at(
    uuid, uuid, text, timestamptz
) from public, anon, authenticated, service_role;
revoke all on function public._complete_storage_gc_job_at(
    uuid, uuid, timestamptz
) from public, anon, authenticated, service_role;

revoke all on function public._moment_photo_path_is_purged(text, text)
from public, anon, authenticated, service_role;
revoke all on function public._registered_owned_storage_media_object(uuid)
from public, anon, authenticated, service_role;
grant execute on function public._moment_photo_path_is_purged(text, text)
to authenticated;
grant execute on function public._registered_owned_storage_media_object(uuid)
to authenticated;

revoke all on function public.list_hidden_moment_ids(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.list_moment_sync_hints(uuid, uuid, integer)
from public, anon, authenticated, service_role;
revoke all on function public.begin_unpairing(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.list_hidden_moment_ids(uuid)
to authenticated;
grant execute on function public.list_moment_sync_hints(uuid, uuid, integer)
to authenticated;
grant execute on function public.begin_unpairing(uuid)
to authenticated;

revoke all on function public.purge_expired_moments(integer)
from public, anon, authenticated, service_role;
revoke all on function public.claim_storage_gc_jobs(integer)
from public, anon, authenticated, service_role;
revoke all on function public.fail_storage_gc_job(uuid, uuid, text)
from public, anon, authenticated, service_role;
revoke all on function public.complete_storage_gc_job(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.replay_moment_purge_tombstone(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.purge_expired_moments(integer)
to service_role;
grant execute on function public.claim_storage_gc_jobs(integer)
to service_role;
grant execute on function public.fail_storage_gc_job(uuid, uuid, text)
to service_role;
grant execute on function public.complete_storage_gc_job(uuid, uuid)
to service_role;
grant execute on function public.replay_moment_purge_tombstone(uuid)
to service_role;

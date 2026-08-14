alter table public.shared_items
    drop constraint shared_items_appointment_discussion_kind,
    add constraint shared_items_appointment_discussion_kind check (
        appointment_client_id is null
        or item_kind = 'message'
        or (item_kind = 'photo' and media_byte_size is not null)
    );

drop index public.shared_items_appointment_discussion_order_idx;

create index shared_items_appointment_discussion_order_idx
on public.shared_items (relationship_id, appointment_client_id, created_at, client_id)
where appointment_client_id is not null
  and (
      item_kind = 'message'
      or (item_kind = 'photo' and media_byte_size is not null)
  );

create function public.finalize_scoped_photo_upload(
    target_relationship_id uuid,
    target_appointment_client_id uuid,
    target_client_id uuid,
    target_byte_size bigint
)
returns table (
    accepted boolean,
    reason text,
    accepted_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
    appointment_status text;
    target_path text := lower(target_relationship_id::text)
        || '/'
        || lower(target_client_id::text)
        || '.jpg';
    stored_owner_id text;
    stored_byte_size bigint;
    existing_creator_id uuid;
    existing_kind text;
    existing_byte_size bigint;
    existing_created_at timestamptz;
    existing_appointment_client_id uuid;
    monthly_photo_count integer;
    relationship_total_bytes bigint;
    month_start timestamptz := (
        date_trunc('month', now() at time zone 'UTC') at time zone 'UTC'
    );
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    if target_byte_size is null
       or target_byte_size not between 1 and 5242880 then
        raise exception 'invalid_photo_byte_size' using errcode = '22023';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id
    for update;

    if relationship_status <> 'active' then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    if target_appointment_client_id is not null then
        select appointment.status
        into appointment_status
        from public.shared_appointments appointment
        where appointment.relationship_id = target_relationship_id
          and appointment.client_id = target_appointment_client_id
        for share;

        if appointment_status is null then
            raise exception 'appointment_not_found' using errcode = 'P0002';
        end if;
        if appointment_status <> 'scheduled' then
            raise exception 'appointment_cancelled' using errcode = '23514';
        end if;
    end if;

    select
        object.owner_id,
        case
            when object.metadata ->> 'size' ~ '^[0-9]+$'
                then (object.metadata ->> 'size')::bigint
            else null
        end
    into stored_owner_id, stored_byte_size
    from storage.objects object
    where object.bucket_id = 'couplespace-w1-photos'
      and lower(object.name) = target_path;

    if not found
       or stored_owner_id <> participant_id::text then
        raise exception 'photo_object_not_accessible' using errcode = '42501';
    end if;

    if stored_byte_size is null
       or stored_byte_size <> target_byte_size then
        raise exception 'photo_byte_size_mismatch' using errcode = '22023';
    end if;

    select
        item.creator_user_id,
        item.item_kind,
        item.media_byte_size,
        item.created_at,
        item.appointment_client_id
    into
        existing_creator_id,
        existing_kind,
        existing_byte_size,
        existing_created_at,
        existing_appointment_client_id
    from public.shared_items item
    where item.relationship_id = target_relationship_id
      and item.client_id = target_client_id;

    if found then
        if existing_creator_id <> participant_id
           or existing_kind <> 'photo'
           or (existing_byte_size is not null and existing_byte_size <> target_byte_size)
           or existing_appointment_client_id is distinct from target_appointment_client_id then
            raise exception 'shared_item_identity_collision' using errcode = '23505';
        end if;

        if existing_byte_size is null then
            update public.shared_items
            set media_byte_size = target_byte_size
            where relationship_id = target_relationship_id
              and client_id = target_client_id;
        end if;

        return query select true, null::text, existing_created_at;
        return;
    end if;

    select count(*)::integer
    into monthly_photo_count
    from public.shared_items item
    where item.relationship_id = target_relationship_id
      and item.item_kind = 'photo'
      and item.created_at >= month_start;

    if monthly_photo_count >= 30 then
        return query select false, 'monthly_photo_limit'::text, null::timestamptz;
        return;
    end if;

    select coalesce(sum(item.media_byte_size), 0)::bigint
    into relationship_total_bytes
    from public.shared_items item
    where item.relationship_id = target_relationship_id
      and item.item_kind = 'photo';

    if relationship_total_bytes + target_byte_size > 1000000000 then
        return query select false, 'total_storage_limit'::text, null::timestamptz;
        return;
    end if;

    insert into public.shared_items (
        relationship_id,
        client_id,
        creator_user_id,
        item_kind,
        media_byte_size,
        appointment_client_id
    ) values (
        target_relationship_id,
        target_client_id,
        participant_id,
        'photo',
        target_byte_size,
        target_appointment_client_id
    )
    returning created_at into existing_created_at;

    return query select true, null::text, existing_created_at;
end;
$$;

create or replace function public.finalize_w1_photo_upload(
    target_relationship_id uuid,
    target_client_id uuid,
    target_byte_size bigint
)
returns table (
    accepted boolean,
    reason text,
    accepted_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
    select result.accepted, result.reason, result.accepted_at
    from public.finalize_scoped_photo_upload(
        target_relationship_id,
        null,
        target_client_id,
        target_byte_size
    ) result;
$$;

create function public.finalize_appointment_discussion_photo_upload(
    target_relationship_id uuid,
    target_appointment_client_id uuid,
    target_client_id uuid,
    target_byte_size bigint
)
returns table (
    accepted boolean,
    reason text,
    accepted_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
    select result.accepted, result.reason, result.accepted_at
    from public.finalize_scoped_photo_upload(
        target_relationship_id,
        target_appointment_client_id,
        target_client_id,
        target_byte_size
    ) result;
$$;

create or replace function public.appointment_discussion_unread_count(
    target_relationship_id uuid,
    target_appointment_client_id uuid
)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    unread_count bigint;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    if not exists (
        select 1
        from public.shared_appointments appointment
        where appointment.relationship_id = target_relationship_id
          and appointment.client_id = target_appointment_client_id
    ) then
        raise exception 'appointment_not_found' using errcode = 'P0002';
    end if;

    select count(*)
    into unread_count
    from public.shared_items message
    left join public.conversation_read_states read_state
      on read_state.relationship_id = target_relationship_id
     and read_state.user_id = participant_id
     and read_state.scope_id = target_appointment_client_id
    where message.relationship_id = target_relationship_id
      and message.appointment_client_id = target_appointment_client_id
      and (
          message.item_kind = 'message'
          or (message.item_kind = 'photo' and message.media_byte_size is not null)
      )
      and message.creator_user_id <> participant_id
      and (
          read_state.user_id is null
          or (message.created_at, message.client_id)
             > (read_state.last_read_created_at, read_state.last_read_client_id)
      );

    return unread_count;
end;
$$;

create or replace function public.mark_appointment_discussion_read(
    target_relationship_id uuid,
    target_appointment_client_id uuid,
    target_message_client_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    read_created_at timestamptz;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    select message.created_at
    into read_created_at
    from public.shared_items message
    where message.relationship_id = target_relationship_id
      and message.appointment_client_id = target_appointment_client_id
      and message.client_id = target_message_client_id
      and (
          message.item_kind = 'message'
          or (message.item_kind = 'photo' and message.media_byte_size is not null)
      );

    if read_created_at is null then
        raise exception 'message_not_found' using errcode = '22023';
    end if;

    insert into public.conversation_read_states (
        relationship_id,
        user_id,
        scope_id,
        last_read_created_at,
        last_read_client_id
    ) values (
        target_relationship_id,
        participant_id,
        target_appointment_client_id,
        read_created_at,
        target_message_client_id
    )
    on conflict (relationship_id, user_id, scope_id) do update
    set last_read_created_at = excluded.last_read_created_at,
        last_read_client_id = excluded.last_read_client_id,
        updated_at = now()
    where (excluded.last_read_created_at, excluded.last_read_client_id)
          > (conversation_read_states.last_read_created_at,
             conversation_read_states.last_read_client_id);
end;
$$;

revoke all on function public.finalize_scoped_photo_upload(
    uuid, uuid, uuid, bigint
) from public;
revoke all on function public.finalize_appointment_discussion_photo_upload(
    uuid, uuid, uuid, bigint
) from public;

grant execute on function public.finalize_appointment_discussion_photo_upload(
    uuid, uuid, uuid, bigint
) to authenticated;

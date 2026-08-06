create table public.push_devices (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    token text not null,
    environment text not null check (environment in ('sandbox', 'production')),
    bundle_id text not null check (bundle_id = 'com.titus.CoupleSpace'),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (environment, bundle_id, token)
);

create table public.push_delivery_jobs (
    id uuid primary key default gen_random_uuid(),
    relationship_id uuid not null references public.relationships(id) on delete cascade,
    event_id uuid not null,
    sender_user_id uuid not null references auth.users(id) on delete cascade,
    recipient_user_id uuid not null references auth.users(id) on delete cascade,
    event_kind text not null check (event_kind = 'w1_generic'),
    created_at timestamptz not null default now(),
    attempt_count integer not null default 0 check (attempt_count >= 0),
    claimed_at timestamptz,
    delivered_at timestamptz,
    last_error text,
    check (sender_user_id <> recipient_user_id),
    unique (relationship_id, event_id, recipient_user_id)
);

alter table public.push_devices enable row level security;
alter table public.push_delivery_jobs enable row level security;

create function public.register_push_device(
    target_token text,
    target_environment text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    normalized_token text := lower(btrim(target_token, E' \t\n\r'));
    normalized_environment text := lower(btrim(target_environment, E' \t\n\r'));
    registered_device_id uuid;
begin
    if participant_id is null then
        raise exception 'authentication_required' using errcode = '42501';
    end if;

    if normalized_token is null
       or char_length(normalized_token) = 0
       or mod(char_length(normalized_token), 2) <> 0
       or normalized_token !~ '^[0-9a-f]+$' then
        raise exception 'invalid_device_token' using errcode = '22023';
    end if;

    if normalized_environment not in ('sandbox', 'production') then
        raise exception 'invalid_push_environment' using errcode = '22023';
    end if;

    insert into public.push_devices (
        user_id,
        token,
        environment,
        bundle_id
    ) values (
        participant_id,
        normalized_token,
        normalized_environment,
        'com.titus.CoupleSpace'
    )
    on conflict (environment, bundle_id, token) do update
    set user_id = excluded.user_id,
        updated_at = now()
    returning id into registered_device_id;

    return registered_device_id;
end;
$$;

create function public.unregister_push_device(
    target_token text,
    target_environment text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
begin
    if participant_id is null then
        raise exception 'authentication_required' using errcode = '42501';
    end if;

    delete from public.push_devices device
    where device.user_id = participant_id
      and device.token = lower(btrim(target_token, E' \t\n\r'))
      and device.environment = lower(btrim(target_environment, E' \t\n\r'))
      and device.bundle_id = 'com.titus.CoupleSpace';

    return found;
end;
$$;

create function public.enqueue_w1_test_push(
    target_relationship_id uuid,
    target_event_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    relationship_status text;
    active_member_count integer;
    derived_recipient_id uuid;
    queued_job_id uuid;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id
    for share;

    if relationship_status <> 'active' then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    select count(*)
    into active_member_count
    from public.relationship_members member
    where member.relationship_id = target_relationship_id
      and member.membership_status = 'active';

    if active_member_count <> 2 then
        raise exception 'relationship_requires_two_members' using errcode = '23514';
    end if;

    select member.user_id
    into derived_recipient_id
    from public.relationship_members member
    where member.relationship_id = target_relationship_id
      and member.membership_status = 'active'
      and member.user_id <> participant_id;

    if derived_recipient_id is null then
        raise exception 'push_recipient_not_available' using errcode = '23514';
    end if;

    insert into public.push_delivery_jobs (
        relationship_id,
        event_id,
        sender_user_id,
        recipient_user_id,
        event_kind
    ) values (
        target_relationship_id,
        target_event_id,
        participant_id,
        derived_recipient_id,
        'w1_generic'
    )
    on conflict (relationship_id, event_id, recipient_user_id) do nothing
    returning id into queued_job_id;

    if queued_job_id is null then
        select job.id
        into queued_job_id
        from public.push_delivery_jobs job
        where job.relationship_id = target_relationship_id
          and job.event_id = target_event_id
          and job.sender_user_id = participant_id
          and job.recipient_user_id = derived_recipient_id;

        if queued_job_id is null then
            raise exception 'push_event_identity_collision' using errcode = '23505';
        end if;
    end if;

    return queued_job_id;
end;
$$;

revoke all on public.push_devices from anon, authenticated;
revoke all on public.push_delivery_jobs from anon, authenticated;
revoke all on function public.register_push_device(text, text) from public;
revoke all on function public.unregister_push_device(text, text) from public;
revoke all on function public.enqueue_w1_test_push(uuid, uuid) from public;

grant execute on function public.register_push_device(text, text) to authenticated;
grant execute on function public.unregister_push_device(text, text) to authenticated;
grant execute on function public.enqueue_w1_test_push(uuid, uuid) to authenticated;

grant select on public.push_devices to service_role;
grant select, update on public.push_delivery_jobs to service_role;

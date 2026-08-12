create table public.conversation_read_states (
    relationship_id uuid not null,
    user_id uuid not null,
    last_read_created_at timestamptz not null,
    last_read_client_id uuid not null,
    updated_at timestamptz not null default now(),
    primary key (relationship_id, user_id),
    foreign key (relationship_id, user_id)
        references public.relationship_members(relationship_id, user_id)
        on delete cascade
);

alter table public.conversation_read_states enable row level security;

create policy "Users can read only their own conversation cursor"
on public.conversation_read_states for select
to authenticated
using (user_id = (select auth.uid()));

create index shared_items_message_order_idx
on public.shared_items (relationship_id, created_at, client_id)
where item_kind = 'message';

create function public.conversation_unread_count(target_relationship_id uuid)
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

    select count(*)
    into unread_count
    from public.shared_items message
    left join public.conversation_read_states read_state
      on read_state.relationship_id = target_relationship_id
     and read_state.user_id = participant_id
    where message.relationship_id = target_relationship_id
      and message.item_kind = 'message'
      and message.creator_user_id <> participant_id
      and (
          read_state.user_id is null
          or (message.created_at, message.client_id)
             > (read_state.last_read_created_at, read_state.last_read_client_id)
      );

    return unread_count;
end;
$$;

create function public.mark_conversation_read(
    target_relationship_id uuid,
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
      and message.client_id = target_message_client_id
      and message.item_kind = 'message';

    if read_created_at is null then
        raise exception 'message_not_found' using errcode = '22023';
    end if;

    insert into public.conversation_read_states (
        relationship_id,
        user_id,
        last_read_created_at,
        last_read_client_id
    ) values (
        target_relationship_id,
        participant_id,
        read_created_at,
        target_message_client_id
    )
    on conflict (relationship_id, user_id) do update
    set last_read_created_at = excluded.last_read_created_at,
        last_read_client_id = excluded.last_read_client_id,
        updated_at = now()
    where (excluded.last_read_created_at, excluded.last_read_client_id)
          > (conversation_read_states.last_read_created_at,
             conversation_read_states.last_read_client_id);
end;
$$;

revoke all on public.conversation_read_states from anon, authenticated;
revoke all on function public.conversation_unread_count(uuid) from public;
revoke all on function public.mark_conversation_read(uuid, uuid) from public;

grant select on public.conversation_read_states to authenticated;
grant execute on function public.conversation_unread_count(uuid) to authenticated;
grant execute on function public.mark_conversation_read(uuid, uuid) to authenticated;

do $$
begin
    if exists (
        select 1
        from pg_publication
        where pubname = 'supabase_realtime'
    ) and not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'conversation_read_states'
    ) then
        alter publication supabase_realtime add table public.conversation_read_states;
    end if;
end;
$$;

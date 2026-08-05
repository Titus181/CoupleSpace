create table public.relationships (
    id uuid primary key default gen_random_uuid(),
    status text not null default 'active'
        check (status in ('active', 'closing', 'archived')),
    created_at timestamptz not null default now(),
    closing_started_at timestamptz,
    archived_at timestamptz
);

create table public.relationship_members (
    relationship_id uuid not null references public.relationships(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    membership_status text not null default 'active'
        check (membership_status in ('active', 'archived')),
    primary key (relationship_id, user_id)
);

create unique index one_current_relationship_per_user
    on public.relationship_members(user_id)
    where membership_status = 'active';

create table public.shared_items (
    id uuid primary key default gen_random_uuid(),
    relationship_id uuid not null references public.relationships(id) on delete cascade,
    client_id uuid not null,
    creator_user_id uuid not null references auth.users(id),
    item_kind text not null check (item_kind in ('marker', 'message', 'photo')),
    created_at timestamptz not null default now(),
    unique (relationship_id, client_id)
);

create table public.personal_archives (
    id uuid primary key default gen_random_uuid(),
    relationship_id uuid not null references public.relationships(id),
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    sealed_at timestamptz not null default now(),
    unique (relationship_id, owner_user_id)
);

create table public.personal_archive_items (
    archive_id uuid not null references public.personal_archives(id) on delete cascade,
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    source_item_id uuid not null,
    client_id uuid not null,
    item_kind text not null,
    created_at timestamptz not null,
    primary key (archive_id, source_item_id)
);

alter table public.relationships enable row level security;
alter table public.relationship_members enable row level security;
alter table public.shared_items enable row level security;
alter table public.personal_archives enable row level security;
alter table public.personal_archive_items enable row level security;

create function public.is_current_relationship_member(target_relationship_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.relationship_members member
        where member.relationship_id = target_relationship_id
          and member.user_id = (select auth.uid())
          and member.membership_status = 'active'
    );
$$;

create policy "Current members can read relationship"
on public.relationships for select
to authenticated
using (public.is_current_relationship_member(id));

create policy "Current members can read memberships"
on public.relationship_members for select
to authenticated
using (public.is_current_relationship_member(relationship_id));

create policy "Current members can read shared items"
on public.shared_items for select
to authenticated
using (public.is_current_relationship_member(relationship_id));

create policy "Current members can add shared items while active"
on public.shared_items for insert
to authenticated
with check (
    creator_user_id = (select auth.uid())
    and public.is_current_relationship_member(relationship_id)
    and exists (
        select 1
        from public.relationships relationship
        where relationship.id = relationship_id
          and relationship.status = 'active'
    )
);

create policy "Owners can read personal archives"
on public.personal_archives for select
to authenticated
using (owner_user_id = (select auth.uid()));

create policy "Owners can delete personal archives"
on public.personal_archives for delete
to authenticated
using (owner_user_id = (select auth.uid()));

create policy "Owners can read personal archive items"
on public.personal_archive_items for select
to authenticated
using (owner_user_id = (select auth.uid()));

create function public.begin_unpairing(target_relationship_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
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
        closing_started_at = coalesce(closing_started_at, now())
    where id = target_relationship_id
      and status in ('active', 'closing');

    if not found then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;
end;
$$;

create function public.seal_personal_archive(target_relationship_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    created_archive_id uuid;
    relationship_status text;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    select relationship.status
    into relationship_status
    from public.relationships relationship
    where relationship.id = target_relationship_id
    for update;

    if relationship_status <> 'closing' then
        raise exception 'relationship_not_closing' using errcode = '23514';
    end if;

    insert into public.personal_archives (relationship_id, owner_user_id)
    values (target_relationship_id, participant_id)
    on conflict (relationship_id, owner_user_id) do nothing
    returning id into created_archive_id;

    if created_archive_id is null then
        select archive.id
        into created_archive_id
        from public.personal_archives archive
        where archive.relationship_id = target_relationship_id
          and archive.owner_user_id = participant_id;
    end if;

    insert into public.personal_archive_items (
        archive_id,
        owner_user_id,
        source_item_id,
        client_id,
        item_kind,
        created_at
    )
    select
        created_archive_id,
        participant_id,
        item.id,
        item.client_id,
        item.item_kind,
        item.created_at
    from public.shared_items item
    where item.relationship_id = target_relationship_id
    on conflict (archive_id, source_item_id) do nothing;

    if (
        select count(*)
        from public.personal_archives archive
        where archive.relationship_id = target_relationship_id
    ) = 2 then
        update public.relationships
        set status = 'archived',
            archived_at = now()
        where id = target_relationship_id;

        update public.relationship_members
        set membership_status = 'archived'
        where relationship_id = target_relationship_id;
    end if;

    return created_archive_id;
end;
$$;

revoke all on public.relationships from anon, authenticated;
revoke all on public.relationship_members from anon, authenticated;
revoke all on public.shared_items from anon, authenticated;
revoke all on public.personal_archives from anon, authenticated;
revoke all on public.personal_archive_items from anon, authenticated;
revoke all on function public.is_current_relationship_member(uuid) from public;
revoke all on function public.begin_unpairing(uuid) from public;
revoke all on function public.seal_personal_archive(uuid) from public;

grant select on public.relationships to authenticated;
grant select on public.relationship_members to authenticated;
grant select, insert on public.shared_items to authenticated;
grant select, delete on public.personal_archives to authenticated;
grant select on public.personal_archive_items to authenticated;
grant execute on function public.is_current_relationship_member(uuid) to authenticated;
grant execute on function public.begin_unpairing(uuid) to authenticated;
grant execute on function public.seal_personal_archive(uuid) to authenticated;

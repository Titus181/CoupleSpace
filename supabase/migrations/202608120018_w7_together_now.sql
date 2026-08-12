create table public.user_profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    display_name text not null,
    updated_at timestamptz not null default now(),
    constraint user_profiles_display_name_length
        check (char_length(display_name) between 1 and 20),
    constraint user_profiles_display_name_trimmed
        check (display_name = btrim(display_name, E' \t\n\r'))
);

create table public.relationship_partner_aliases (
    relationship_id uuid not null references public.relationships(id) on delete cascade,
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    partner_user_id uuid not null references auth.users(id) on delete cascade,
    private_name text not null,
    updated_at timestamptz not null default now(),
    primary key (relationship_id, owner_user_id),
    foreign key (relationship_id, owner_user_id)
        references public.relationship_members(relationship_id, user_id) on delete cascade,
    foreign key (relationship_id, partner_user_id)
        references public.relationship_members(relationship_id, user_id) on delete cascade,
    constraint relationship_partner_aliases_distinct_users
        check (owner_user_id <> partner_user_id),
    constraint relationship_partner_aliases_name_length
        check (char_length(private_name) between 1 and 20),
    constraint relationship_partner_aliases_name_trimmed
        check (private_name = btrim(private_name, E' \t\n\r'))
);

create table public.current_relationship_statuses (
    relationship_id uuid not null references public.relationships(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    status_kind text not null check (status_kind in (
        'busy',
        'available_to_talk',
        'quiet',
        'tired',
        'need_company',
        'need_hug',
        'thinking_of_you',
        'custom'
    )),
    custom_text text,
    expiration_kind text not null check (expiration_kind in (
        'one_hour',
        'four_hours',
        'tonight',
        'manual'
    )),
    expires_at timestamptz,
    updated_at timestamptz not null default now(),
    primary key (relationship_id, user_id),
    foreign key (relationship_id, user_id)
        references public.relationship_members(relationship_id, user_id) on delete cascade,
    constraint current_relationship_statuses_content check (
        (status_kind = 'custom'
            and custom_text is not null
            and char_length(custom_text) between 1 and 40
            and custom_text = btrim(custom_text, E' \t\n\r'))
        or (status_kind <> 'custom' and custom_text is null)
    ),
    constraint current_relationship_statuses_expiration check (
        (expiration_kind = 'manual' and expires_at is null)
        or (expiration_kind <> 'manual' and expires_at is not null)
    )
);

alter table public.user_profiles enable row level security;
alter table public.relationship_partner_aliases enable row level security;
alter table public.current_relationship_statuses enable row level security;

create policy "Users and active partners can read display names"
on public.user_profiles for select
to authenticated
using (
    user_id = (select auth.uid())
    or exists (
        select 1
        from public.relationship_members viewer
        join public.relationship_members profile_owner
          on profile_owner.relationship_id = viewer.relationship_id
        join public.relationships relationship
          on relationship.id = viewer.relationship_id
        where viewer.user_id = (select auth.uid())
          and viewer.membership_status = 'active'
          and profile_owner.user_id = user_profiles.user_id
          and profile_owner.membership_status = 'active'
          and relationship.status = 'active'
    )
);

create policy "Alias owners can read private partner names"
on public.relationship_partner_aliases for select
to authenticated
using (
    owner_user_id = (select auth.uid())
    and public.is_current_relationship_member(relationship_id)
    and exists (
        select 1
        from public.relationships relationship
        where relationship.id = relationship_id
          and relationship.status = 'active'
    )
);

create policy "Active partners can read unexpired current statuses"
on public.current_relationship_statuses for select
to authenticated
using (
    public.is_current_relationship_member(relationship_id)
    and (expires_at is null or expires_at > now())
    and exists (
        select 1
        from public.relationships relationship
        where relationship.id = relationship_id
          and relationship.status = 'active'
    )
);

revoke all on public.user_profiles from anon, authenticated;
revoke all on public.relationship_partner_aliases from anon, authenticated;
revoke all on public.current_relationship_statuses from anon, authenticated;
grant select on public.user_profiles to authenticated;
grant select on public.relationship_partner_aliases to authenticated;
grant select on public.current_relationship_statuses to authenticated;

create function public.update_relationship_names(
    target_relationship_id uuid,
    target_display_name text default null,
    target_partner_name text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    partner_id uuid;
    normalized_display_name text := nullif(btrim(target_display_name, E' \t\n\r'), '');
    normalized_partner_name text := nullif(btrim(target_partner_name, E' \t\n\r'), '');
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    select member.user_id
    into partner_id
    from public.relationship_members member
    join public.relationships relationship
      on relationship.id = member.relationship_id
    where member.relationship_id = target_relationship_id
      and member.user_id <> participant_id
      and member.membership_status = 'active'
      and relationship.status = 'active';

    if partner_id is null then
        raise exception 'relationship_not_paired' using errcode = '23514';
    end if;

    if normalized_display_name is not null
       and char_length(normalized_display_name) > 20 then
        raise exception 'invalid_display_name' using errcode = '22023';
    end if;

    if normalized_partner_name is not null
       and char_length(normalized_partner_name) > 20 then
        raise exception 'invalid_partner_name' using errcode = '22023';
    end if;

    if normalized_display_name is null then
        delete from public.user_profiles profile
        where profile.user_id = participant_id;
    else
        insert into public.user_profiles (user_id, display_name)
        values (participant_id, normalized_display_name)
        on conflict (user_id) do update
        set display_name = excluded.display_name,
            updated_at = now();
    end if;

    if normalized_partner_name is null then
        delete from public.relationship_partner_aliases alias
        where alias.relationship_id = target_relationship_id
          and alias.owner_user_id = participant_id;
    else
        insert into public.relationship_partner_aliases (
            relationship_id,
            owner_user_id,
            partner_user_id,
            private_name
        ) values (
            target_relationship_id,
            participant_id,
            partner_id,
            normalized_partner_name
        )
        on conflict (relationship_id, owner_user_id) do update
        set partner_user_id = excluded.partner_user_id,
            private_name = excluded.private_name,
            updated_at = now();
    end if;
end;
$$;

create function public.set_current_relationship_status(
    target_relationship_id uuid,
    target_status_kind text,
    target_custom_text text default null,
    target_expiration_kind text default 'one_hour',
    target_tonight_expires_at timestamptz default null,
    target_moment_client_id uuid default null
)
returns table (
    user_id uuid,
    status_kind text,
    custom_text text,
    expiration_kind text,
    expires_at timestamptz,
    updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    normalized_custom_text text := nullif(btrim(target_custom_text, E' \t\n\r'), '');
    calculated_expires_at timestamptz;
    moment_text text;
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    if not exists (
        select 1
        from public.relationships relationship
        where relationship.id = target_relationship_id
          and relationship.status = 'active'
          and 2 = (
              select count(*)
              from public.relationship_members member
              where member.relationship_id = target_relationship_id
                and member.membership_status = 'active'
          )
    ) then
        raise exception 'relationship_not_paired' using errcode = '23514';
    end if;

    if target_status_kind = 'custom' then
        if normalized_custom_text is null
           or char_length(normalized_custom_text) > 40 then
            raise exception 'invalid_current_status' using errcode = '22023';
        end if;
        moment_text := normalized_custom_text;
    elsif target_status_kind = 'busy' then
        moment_text := '忙一下，晚點聊';
    elsif target_status_kind = 'available_to_talk' then
        moment_text := '現在可以聊聊';
    elsif target_status_kind = 'quiet' then
        moment_text := '想安靜一下';
    elsif target_status_kind = 'tired' then
        moment_text := '有點累';
    elsif target_status_kind = 'need_company' then
        moment_text := '想被陪陪';
    elsif target_status_kind = 'need_hug' then
        moment_text := '想要抱抱';
    elsif target_status_kind = 'thinking_of_you' then
        moment_text := '想到你';
    else
        raise exception 'invalid_current_status' using errcode = '22023';
    end if;

    if target_status_kind <> 'custom' and target_custom_text is not null then
        raise exception 'invalid_current_status' using errcode = '22023';
    end if;

    if target_expiration_kind = 'one_hour' then
        if target_tonight_expires_at is not null then
            raise exception 'invalid_status_expiration' using errcode = '22023';
        end if;
        calculated_expires_at := now() + interval '1 hour';
    elsif target_expiration_kind = 'four_hours' then
        if target_tonight_expires_at is not null then
            raise exception 'invalid_status_expiration' using errcode = '22023';
        end if;
        calculated_expires_at := now() + interval '4 hours';
    elsif target_expiration_kind = 'tonight' then
        if target_tonight_expires_at is null
           or target_tonight_expires_at <= now()
           or target_tonight_expires_at > now() + interval '25 hours' then
            raise exception 'invalid_status_expiration' using errcode = '22023';
        end if;
        calculated_expires_at := target_tonight_expires_at;
    elsif target_expiration_kind = 'manual' then
        if target_tonight_expires_at is not null then
            raise exception 'invalid_status_expiration' using errcode = '22023';
        end if;
        calculated_expires_at := null;
    else
        raise exception 'invalid_status_expiration' using errcode = '22023';
    end if;

    insert into public.current_relationship_statuses (
        relationship_id,
        user_id,
        status_kind,
        custom_text,
        expiration_kind,
        expires_at
    ) values (
        target_relationship_id,
        participant_id,
        target_status_kind,
        case when target_status_kind = 'custom' then normalized_custom_text else null end,
        target_expiration_kind,
        calculated_expires_at
    )
    on conflict on constraint current_relationship_statuses_pkey do update
    set status_kind = excluded.status_kind,
        custom_text = excluded.custom_text,
        expiration_kind = excluded.expiration_kind,
        expires_at = excluded.expires_at,
        updated_at = now();

    if target_moment_client_id is not null then
        insert into public.moments (
            relationship_id,
            client_id,
            creator_user_id,
            kind,
            text_content
        ) values (
            target_relationship_id,
            target_moment_client_id,
            participant_id,
            'text',
            moment_text
        )
        on conflict on constraint moments_relationship_id_client_id_key do nothing;

        if not exists (
            select 1
            from public.moments moment
            where moment.relationship_id = target_relationship_id
              and moment.client_id = target_moment_client_id
              and moment.creator_user_id = participant_id
              and moment.kind = 'text'
              and moment.text_content = moment_text
        ) then
            raise exception 'moment_identity_collision' using errcode = '23505';
        end if;
    end if;

    return query
    select
        current_status.user_id,
        current_status.status_kind,
        current_status.custom_text,
        current_status.expiration_kind,
        current_status.expires_at,
        current_status.updated_at
    from public.current_relationship_statuses current_status
    where current_status.relationship_id = target_relationship_id
      and current_status.user_id = participant_id;
end;
$$;

create function public.clear_current_relationship_status(target_relationship_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    delete from public.current_relationship_statuses current_status
    where current_status.relationship_id = target_relationship_id
      and current_status.user_id = participant_id;
end;
$$;

revoke all on function public.update_relationship_names(uuid, text, text) from public;
revoke all on function public.set_current_relationship_status(uuid, text, text, text, timestamptz, uuid) from public;
revoke all on function public.clear_current_relationship_status(uuid) from public;
grant execute on function public.update_relationship_names(uuid, text, text) to authenticated;
grant execute on function public.set_current_relationship_status(uuid, text, text, text, timestamptz, uuid) to authenticated;
grant execute on function public.clear_current_relationship_status(uuid) to authenticated;

do $$
begin
    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'user_profiles'
    ) then
        alter publication supabase_realtime add table public.user_profiles;
    end if;

    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'relationship_partner_aliases'
    ) then
        alter publication supabase_realtime add table public.relationship_partner_aliases;
    end if;

    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'current_relationship_statuses'
    ) then
        alter publication supabase_realtime add table public.current_relationship_statuses;
    end if;
end;
$$;

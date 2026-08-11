create table public.moments (
    id uuid primary key default gen_random_uuid(),
    relationship_id uuid not null references public.relationships(id) on delete cascade,
    client_id uuid not null,
    creator_user_id uuid not null references auth.users(id),
    kind text not null check (kind in ('mood', 'text', 'photo')),
    mood_value text check (mood_value in ('calm', 'happy', 'tired', 'thinking_of_you', 'need_hug')),
    text_content text,
    media_byte_size bigint,
    created_at timestamptz not null default now(),
    unique (relationship_id, client_id),
    constraint moments_content_matches_kind check (
        (kind = 'mood'
            and mood_value is not null
            and text_content is null
            and media_byte_size is null)
        or (kind = 'text'
            and mood_value is null
            and text_content is not null
            and char_length(text_content) between 1 and 280
            and media_byte_size is null)
        or (kind = 'photo'
            and mood_value is null
            and text_content is null
            and media_byte_size > 0)
    )
);

alter table public.moments enable row level security;

create policy "Current members can read moments"
on public.moments for select
to authenticated
using (public.is_current_relationship_member(relationship_id));

revoke all on public.moments from anon, authenticated;
grant select on public.moments to authenticated;

insert into storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
values (
    'couplespace-moment-photos',
    'couplespace-moment-photos',
    false,
    5242880,
    array['image/jpeg']
)
on conflict (id) do nothing;

create policy "Relationship members can read Moment photos"
on storage.objects for select
to authenticated
using (
    bucket_id = 'couplespace-moment-photos'
    and array_length(storage.foldername(name), 1) = 1
    and exists (
        select 1
        from public.relationship_members member
        where member.relationship_id::text = (storage.foldername(name))[1]
          and member.user_id = (select auth.uid())
          and member.membership_status = 'active'
    )
);

create policy "Relationship members can upload Moment photos while active"
on storage.objects for insert
to authenticated
with check (
    bucket_id = 'couplespace-moment-photos'
    and owner_id = (select auth.uid())::text
    and array_length(storage.foldername(name), 1) = 1
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

create policy "Uploaders can delete unfinalized Moment photos"
on storage.objects for delete
to authenticated
using (
    bucket_id = 'couplespace-moment-photos'
    and owner_id = (select auth.uid())::text
    and not exists (
        select 1
        from public.moments moment
        where moment.relationship_id::text = (storage.foldername(name))[1]
          and lower(moment.client_id::text || '.jpg') = lower(storage.filename(name))
    )
);

create function public.create_moment(
    target_relationship_id uuid,
    target_client_id uuid,
    target_kind text,
    target_mood_value text default null,
    target_text_content text default null,
    target_media_byte_size bigint default null
)
returns table (
    client_id uuid,
    creator_user_id uuid,
    kind text,
    mood_value text,
    text_content text,
    media_byte_size bigint,
    created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    normalized_text text := btrim(target_text_content, E' \t\n\r');
    relationship_status text;
    expected_path text := lower(target_relationship_id::text || '/' || target_client_id::text || '.jpg');
    stored_owner_id text;
    stored_byte_size bigint;
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

    if target_kind = 'mood' then
        if target_mood_value is null
           or target_mood_value not in ('calm', 'happy', 'tired', 'thinking_of_you', 'need_hug')
           or target_text_content is not null
           or target_media_byte_size is not null then
            raise exception 'invalid_moment_content' using errcode = '22023';
        end if;
    elsif target_kind = 'text' then
        if normalized_text is null
           or char_length(normalized_text) not between 1 and 280
           or target_mood_value is not null
           or target_media_byte_size is not null then
            raise exception 'invalid_moment_content' using errcode = '22023';
        end if;
    elsif target_kind = 'photo' then
        if target_mood_value is not null
           or target_text_content is not null
           or target_media_byte_size is null
           or target_media_byte_size <= 0 then
            raise exception 'invalid_moment_content' using errcode = '22023';
        end if;

        select object.owner_id, (object.metadata ->> 'size')::bigint
        into stored_owner_id, stored_byte_size
        from storage.objects object
        where object.bucket_id = 'couplespace-moment-photos'
          and lower(object.name) = expected_path;

        if stored_owner_id is null
           or stored_owner_id <> participant_id::text
           or stored_byte_size is distinct from target_media_byte_size then
            raise exception 'moment_photo_not_available' using errcode = '23514';
        end if;
    else
        raise exception 'invalid_moment_kind' using errcode = '22023';
    end if;

    insert into public.moments (
        relationship_id,
        client_id,
        creator_user_id,
        kind,
        mood_value,
        text_content,
        media_byte_size
    ) values (
        target_relationship_id,
        target_client_id,
        participant_id,
        target_kind,
        target_mood_value,
        case when target_kind = 'text' then normalized_text else null end,
        target_media_byte_size
    )
    on conflict on constraint moments_relationship_id_client_id_key do nothing;

    if not exists (
        select 1
        from public.moments moment
        where moment.relationship_id = target_relationship_id
          and moment.client_id = target_client_id
          and moment.creator_user_id = participant_id
          and moment.kind = target_kind
          and moment.mood_value is not distinct from target_mood_value
          and moment.text_content is not distinct from (
              case when target_kind = 'text' then normalized_text else null end
          )
          and moment.media_byte_size is not distinct from target_media_byte_size
    ) then
        raise exception 'moment_identity_collision' using errcode = '23505';
    end if;

    return query
    select
        moment.client_id,
        moment.creator_user_id,
        moment.kind,
        moment.mood_value,
        moment.text_content,
        moment.media_byte_size,
        moment.created_at
    from public.moments moment
    where moment.relationship_id = target_relationship_id
      and moment.client_id = target_client_id;
end;
$$;

revoke all on function public.create_moment(uuid, uuid, text, text, text, bigint) from public;
grant execute on function public.create_moment(uuid, uuid, text, text, text, bigint) to authenticated;

do $$
begin
    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'moments'
    ) then
        alter publication supabase_realtime add table public.moments;
    end if;
end;
$$;

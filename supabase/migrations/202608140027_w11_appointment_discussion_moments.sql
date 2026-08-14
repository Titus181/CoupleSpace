alter table public.moments
    add column source_appointment_client_id uuid,
    add constraint moments_source_appointment_fk
        foreign key (relationship_id, source_appointment_client_id)
        references public.shared_appointments(relationship_id, client_id),
    add constraint moments_source_appointment_requires_message check (
        source_appointment_client_id is null
        or source_shared_item_client_id is not null
    );

update public.moments moment
set source_appointment_client_id = item.appointment_client_id
from public.shared_items item
where item.relationship_id = moment.relationship_id
  and item.client_id = moment.source_shared_item_client_id
  and item.appointment_client_id is not null;

create or replace function public.create_moment_from_shared_item(
    target_relationship_id uuid,
    target_message_client_id uuid,
    target_moment_client_id uuid
)
returns table (
    moment_client_id uuid,
    creator_user_id uuid,
    source_message_client_id uuid,
    source_message_creator_user_id uuid,
    kind text,
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
    relationship_status text;
    active_member_count integer;
    source_item public.shared_items%rowtype;
    stored_moment public.moments%rowtype;
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

    select count(*)
    into active_member_count
    from public.relationship_members member
    where member.relationship_id = target_relationship_id
      and member.membership_status = 'active';

    if relationship_status <> 'active' or active_member_count <> 2 then
        raise exception 'relationship_not_active_pair' using errcode = '23514';
    end if;

    select item.*
    into source_item
    from public.shared_items item
    where item.relationship_id = target_relationship_id
      and item.client_id = target_message_client_id
      and (
          item.item_kind = 'message'
          or (item.item_kind = 'photo' and item.media_byte_size is not null)
      )
    for share;

    if source_item.id is null then
        raise exception 'message_not_found' using errcode = 'P0002';
    end if;

    select moment.*
    into stored_moment
    from public.moments moment
    where moment.relationship_id = target_relationship_id
      and moment.client_id = target_moment_client_id;

    if found then
        if stored_moment.creator_user_id <> participant_id
           or stored_moment.source_shared_item_client_id is distinct from source_item.client_id
           or stored_moment.source_appointment_client_id
                is distinct from source_item.appointment_client_id
           or stored_moment.kind <> (case
               when source_item.item_kind = 'message' then 'text'
               else 'photo'
           end)
           or stored_moment.text_content is distinct from source_item.text_content
           or stored_moment.media_byte_size is distinct from source_item.media_byte_size then
            raise exception 'moment_identity_collision' using errcode = '23505';
        end if;
    else
        select moment.*
        into stored_moment
        from public.moments moment
        where moment.relationship_id = target_relationship_id
          and moment.source_shared_item_client_id = source_item.client_id;

        if not found then
            insert into public.moments (
                relationship_id,
                client_id,
                creator_user_id,
                kind,
                text_content,
                media_byte_size,
                source_shared_item_client_id,
                source_appointment_client_id
            ) values (
                target_relationship_id,
                target_moment_client_id,
                participant_id,
                case when source_item.item_kind = 'message' then 'text' else 'photo' end,
                source_item.text_content,
                source_item.media_byte_size,
                source_item.client_id,
                source_item.appointment_client_id
            )
            on conflict (relationship_id, source_shared_item_client_id)
                where source_shared_item_client_id is not null
                do nothing
            returning * into stored_moment;

            if not found then
                select moment.*
                into stored_moment
                from public.moments moment
                where moment.relationship_id = target_relationship_id
                  and moment.source_shared_item_client_id = source_item.client_id;
            end if;
        end if;
    end if;

    return query
    select
        stored_moment.client_id,
        stored_moment.creator_user_id,
        source_item.client_id,
        source_item.creator_user_id,
        stored_moment.kind,
        stored_moment.text_content,
        stored_moment.media_byte_size,
        stored_moment.created_at;
end;
$$;

-- W11 reliable appointment operation retries.
-- Replaying an already-applied edit returns the stored row without changing updated_at.

create or replace function public.update_shared_appointment(
    target_relationship_id uuid,
    target_appointment_client_id uuid,
    target_title text,
    target_starts_at timestamptz,
    target_location text default null,
    target_note text default null,
    target_reminder_at timestamptz default null
)
returns setof public.shared_appointments
language plpgsql
security definer
set search_path = ''
as $$
declare
    participant_id uuid := auth.uid();
    normalized_title text := btrim(target_title, E' \t\n\r');
    normalized_location text := nullif(btrim(target_location, E' \t\n\r'), '');
    normalized_note text := nullif(btrim(target_note, E' \t\n\r'), '');
begin
    if participant_id is null
       or not public.is_current_relationship_member(target_relationship_id) then
        raise exception 'relationship_not_accessible' using errcode = '42501';
    end if;

    if not exists (
        select 1 from public.relationships relationship
        where relationship.id = target_relationship_id
          and relationship.status = 'active'
    ) then
        raise exception 'relationship_not_active' using errcode = '23514';
    end if;

    if normalized_title is null
       or char_length(normalized_title) not between 1 and 200
       or target_starts_at is null
       or (normalized_location is not null and char_length(normalized_location) > 200)
       or (normalized_note is not null and char_length(normalized_note) > 1000)
       or (target_reminder_at is not null and target_reminder_at > target_starts_at) then
        raise exception 'invalid_appointment_content' using errcode = '22023';
    end if;

    return query
    select appointment.*
    from public.shared_appointments appointment
    where appointment.relationship_id = target_relationship_id
      and appointment.client_id = target_appointment_client_id
      and appointment.status = 'scheduled'
      and appointment.title = normalized_title
      and appointment.starts_at = target_starts_at
      and appointment.location is not distinct from normalized_location
      and appointment.note is not distinct from normalized_note
      and appointment.reminder_at is not distinct from target_reminder_at;

    if found then
        return;
    end if;

    return query
    update public.shared_appointments appointment
    set title = normalized_title,
        starts_at = target_starts_at,
        location = normalized_location,
        note = normalized_note,
        reminder_at = target_reminder_at,
        updated_at = now()
    where appointment.relationship_id = target_relationship_id
      and appointment.client_id = target_appointment_client_id
      and appointment.status = 'scheduled'
    returning appointment.*;

    if not found then
        if exists (
            select 1 from public.shared_appointments appointment
            where appointment.relationship_id = target_relationship_id
              and appointment.client_id = target_appointment_client_id
              and appointment.status = 'cancelled'
        ) then
            raise exception 'appointment_cancelled' using errcode = '23514';
        end if;
        raise exception 'appointment_not_found' using errcode = 'P0002';
    end if;
end;
$$;

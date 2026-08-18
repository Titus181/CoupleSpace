alter table public.push_devices
    add column content_preview_enabled boolean not null default false;

create or replace function public.register_push_device(
    target_token text,
    target_environment text,
    target_content_preview_enabled boolean default false
) returns uuid language plpgsql security definer set search_path = '' as $$
declare participant_id uuid := auth.uid(); normalized_token text := lower(btrim(target_token, E' \t\n\r')); normalized_environment text := lower(btrim(target_environment, E' \t\n\r')); registered_device_id uuid; begin
    if participant_id is null then raise exception 'authentication_required' using errcode = '42501'; end if;
    if normalized_token is null or char_length(normalized_token) = 0 or mod(char_length(normalized_token), 2) <> 0 or normalized_token !~ '^[0-9a-f]+$' then raise exception 'invalid_device_token' using errcode = '22023'; end if;
    if normalized_environment not in ('sandbox', 'production') then raise exception 'invalid_push_environment' using errcode = '22023'; end if;
    insert into public.push_devices (user_id, token, environment, bundle_id, content_preview_enabled)
    values (participant_id, normalized_token, normalized_environment, 'com.titus.CoupleSpace', target_content_preview_enabled)
    on conflict (environment, bundle_id, token) do update set user_id = excluded.user_id, content_preview_enabled = excluded.content_preview_enabled, updated_at = now()
    returning id into registered_device_id;
    return registered_device_id;
end;
$$;
revoke all on function public.register_push_device(text, text, boolean) from public;
grant execute on function public.register_push_device(text, text, boolean) to authenticated;

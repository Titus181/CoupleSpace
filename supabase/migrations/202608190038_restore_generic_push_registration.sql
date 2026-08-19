-- Notification content preview is intentionally deferred until after W13.
-- Keep the legacy column for migration compatibility, but remove the RPC
-- overload and reset stored preferences so current runtime is generic-only.
drop function if exists public.register_push_device(text, text, boolean);

update public.push_devices
set content_preview_enabled = false,
    updated_at = now()
where content_preview_enabled;

comment on column public.push_devices.content_preview_enabled is
    'Legacy compatibility field; unused while push payloads are generic-only.';

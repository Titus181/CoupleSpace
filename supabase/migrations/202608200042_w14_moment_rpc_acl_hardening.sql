-- W14-02 forward-only hardening for every callable created or replaced by 041.

-- Client and policy entry points are authenticated-only. Revoke first so this
-- migration also repairs any direct grants retained by CREATE OR REPLACE.
revoke all on function public.delete_moment(uuid, uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.restore_moment(uuid, uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.remove_moment_response(uuid, uuid, uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.remove_moment_answer(uuid, uuid, uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.list_recently_deleted_moments(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.list_hidden_moment_ids(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.list_moment_sync_hints(uuid, uuid, integer)
from public, anon, authenticated, service_role;
revoke all on function public.is_active_relationship_member(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.can_read_moment_interactions(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.is_moment_question_revealed(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.can_read_moment_photo_object(text, text)
from public, anon, authenticated, service_role;
revoke all on function public.create_moment_from_shared_item(uuid, uuid, uuid)
from public, anon, authenticated, service_role;

grant execute on function public.delete_moment(uuid, uuid, uuid)
to authenticated;
grant execute on function public.restore_moment(uuid, uuid, uuid)
to authenticated;
grant execute on function public.remove_moment_response(uuid, uuid, uuid, uuid)
to authenticated;
grant execute on function public.remove_moment_answer(uuid, uuid, uuid, uuid)
to authenticated;
grant execute on function public.list_recently_deleted_moments(uuid)
to authenticated;
grant execute on function public.list_hidden_moment_ids(uuid)
to authenticated;
grant execute on function public.list_moment_sync_hints(uuid, uuid, integer)
to authenticated;
grant execute on function public.is_active_relationship_member(uuid)
to authenticated;
grant execute on function public.can_read_moment_interactions(uuid, uuid)
to authenticated;
grant execute on function public.is_moment_question_revealed(uuid, uuid)
to authenticated;
grant execute on function public.can_read_moment_photo_object(text, text)
to authenticated;
grant execute on function public.create_moment_from_shared_item(uuid, uuid, uuid)
to authenticated;

-- Deterministic-time and trigger helpers have no direct client or service-role
-- caller. PostgreSQL invokes trigger functions as the owning table operation.
revoke all on function public._delete_moment_at(
    uuid, uuid, uuid, timestamptz
) from public, anon, authenticated, service_role;
revoke all on function public._restore_moment_at(
    uuid, uuid, uuid, timestamptz
) from public, anon, authenticated, service_role;
revoke all on function public.reject_deleted_moment_recreation()
from public, anon, authenticated, service_role;
revoke all on function public.require_live_moment_for_interaction()
from public, anon, authenticated, service_role;

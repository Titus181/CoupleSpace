-- W14-02 forward-only operation-ledger ACL hardening.

revoke all privileges on table public.moment_lifecycle_operations
from public, anon, authenticated, service_role;

grant select on table public.moment_lifecycle_operations
to service_role;

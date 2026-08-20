import { createClient } from "jsr:@supabase/supabase-js@2";
import { createStorageGCGateway } from "./gateway.ts";
import { createStorageGCHandler, StorageGCGateway } from "./worker.ts";

const projectURL = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
let gateway: StorageGCGateway | undefined;

if (projectURL && serviceRoleKey) {
  const service = createClient(projectURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  gateway = createStorageGCGateway({
    async rpc(functionName, arguments_) {
      const { data, error } = await service.rpc(functionName, arguments_);
      return { data, error };
    },
    async remove(bucketID, objectPaths) {
      const { error } = await service.storage.from(bucketID).remove(
        objectPaths,
      );
      return { error };
    },
  });
}

Deno.serve(createStorageGCHandler({ serviceRoleKey, gateway }));

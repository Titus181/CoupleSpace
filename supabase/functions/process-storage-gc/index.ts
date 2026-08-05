import { createClient } from "jsr:@supabase/supabase-js@2";

type QueueRow = {
  bucket_id: string;
  object_path: string;
  attempt_count: number;
};

const jsonHeaders = { "Content-Type": "application/json" };

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: jsonHeaders,
    });
  }

  const projectURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = request.headers.get("Authorization");
  const accessToken = authorization?.replace(/^Bearer\s+/i, "");

  if (!projectURL || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: "server_not_configured" }), {
      status: 500,
      headers: jsonHeaders,
    });
  }

  if (!accessToken) {
    return new Response(JSON.stringify({ error: "missing_authorization" }), {
      status: 401,
      headers: jsonHeaders,
    });
  }

  const service = createClient(projectURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await service.auth.getUser(accessToken);

  if (authError || !authData.user) {
    return new Response(JSON.stringify({ error: "invalid_authorization" }), {
      status: 401,
      headers: jsonHeaders,
    });
  }

  const { data, error: queueError } = await service
    .from("storage_gc_queue")
    .select("bucket_id,object_path,attempt_count")
    .order("enqueued_at", { ascending: true })
    .limit(20);

  if (queueError) {
    return new Response(JSON.stringify({ error: "queue_read_failed" }), {
      status: 500,
      headers: jsonHeaders,
    });
  }

  const rows = (data ?? []) as QueueRow[];
  const rowsByBucket = new Map<string, QueueRow[]>();
  for (const row of rows) {
    rowsByBucket.set(row.bucket_id, [
      ...(rowsByBucket.get(row.bucket_id) ?? []),
      row,
    ]);
  }
  let deletedCount = 0;
  let failedCount = 0;

  for (const [bucketID, bucketRows] of rowsByBucket) {
    const paths = bucketRows.map((row) => row.object_path);
    const { error: removeError } = await service.storage.from(bucketID).remove(paths);

    if (removeError) {
      failedCount += paths.length;
      await Promise.all(bucketRows.map((row) =>
        service
          .from("storage_gc_queue")
          .update({
            attempt_count: row.attempt_count + 1,
            last_error: removeError.message,
          })
          .eq("bucket_id", row.bucket_id)
          .eq("object_path", row.object_path)
      ));
      continue;
    }

    const { error: dequeueError } = await service
      .from("storage_gc_queue")
      .delete()
      .eq("bucket_id", bucketID)
      .in("object_path", paths);

    if (dequeueError) {
      failedCount += paths.length;
      continue;
    }

    deletedCount += paths.length;
  }

  return new Response(JSON.stringify({ deletedCount, failedCount }), {
    status: failedCount === 0 ? 200 : 503,
    headers: jsonHeaders,
  });
});

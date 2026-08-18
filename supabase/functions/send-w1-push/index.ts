import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  APNsConfiguration,
  APNsEnvironment,
  createProviderToken,
  NotificationPreview,
  sendGenericPush,
} from "./apns.ts";

type ClaimedJob = {
  job_id: string;
  source_item_id: string;
  event_kind: string;
  recipient_user_id: string;
  claim_token: string;
  attempt_count: number;
  badge_count: number;
};

type DeviceRow = {
  token: string;
  content_preview_enabled: boolean;
};

const jsonHeaders = { "Content-Type": "application/json" };
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function diagnostic(event: string, details: Record<string, string | number | boolean> = {}) {
  console.log(JSON.stringify({ event, ...details }));
}

function response(error: string, status: number): Response {
  return new Response(JSON.stringify({ error }), {
    status,
    headers: jsonHeaders,
  });
}

Deno.serve(async (request) => {
  diagnostic("push_request_started", { method: request.method });
  if (request.method !== "POST") return response("method_not_allowed", 405);

  const projectURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const keyID = Deno.env.get("APNS_KEY_ID");
  const teamID = Deno.env.get("APNS_TEAM_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY");
  const environment = Deno.env.get("APNS_ENVIRONMENT") as
    | APNsEnvironment
    | undefined;
  const authorization = request.headers.get("Authorization");
  const accessToken = authorization?.replace(/^Bearer\s+/i, "");

  if (
    !projectURL || !serviceRoleKey || !keyID || !teamID || !privateKey ||
    !environment || !["sandbox", "production"].includes(environment)
  ) {
    return response("server_not_configured", 500);
  }
  if (!accessToken) return response("missing_authorization", 401);

  let jobID: string;
  try {
    diagnostic("push_request_body_started");
    const body = await request.json() as { job_id?: unknown };
    if (typeof body.job_id !== "string" || !uuidPattern.test(body.job_id)) {
      diagnostic("push_request_body_invalid");
      return response("invalid_job_id", 400);
    }
    jobID = body.job_id;
    diagnostic("push_request_body_loaded");
  } catch {
    diagnostic("push_request_body_invalid");
    return response("invalid_request", 400);
  }

  const service = createClient(projectURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  diagnostic("push_authorization_started");
  const { data: authData, error: authError } = await service.auth.getUser(accessToken);
  if (authError || !authData.user) {
    diagnostic("push_authorization_invalid");
    return response("invalid_authorization", 401);
  }
  diagnostic("push_authorization_verified");

  const { data: claimedRows, error: claimError } = await service.rpc(
    "claim_push_delivery_job",
    {
      target_job_id: jobID,
      target_sender_user_id: authData.user.id,
    },
  );
  if (claimError) {
    diagnostic("push_claim_failed");
    return response("push_job_not_claimable", 409);
  }

  const job = (claimedRows as ClaimedJob[] | null)?.[0];
  if (!job) {
    diagnostic("push_not_claimable");
    return response("push_job_not_claimable", 409);
  }
  diagnostic("push_claimed", {
    event_kind: job.event_kind,
    has_source_reference: Boolean(job.source_item_id),
  });

  const complete = async (succeeded: boolean, error: string | null) => {
    await service.rpc("complete_push_delivery_job", {
      target_job_id: job.job_id,
      target_claim_token: job.claim_token,
      target_succeeded: succeeded,
      target_error: error,
    });
  };

  const { data: deviceRows, error: deviceError } = await service
    .from("push_devices")
    .select("token,content_preview_enabled")
    .eq("user_id", job.recipient_user_id)
    .eq("environment", environment)
    .eq("bundle_id", "com.titus.CoupleSpace")
    .order("updated_at", { ascending: false });
  if (deviceError) {
    diagnostic("push_device_lookup_failed", { event_kind: job.event_kind });
    await complete(false, "device_lookup_failed");
    return response("device_lookup_failed", 500);
  }

  const devices = (deviceRows ?? []) as DeviceRow[];
  diagnostic("push_devices_loaded", {
    event_kind: job.event_kind,
    device_count: devices.length,
  });
  if (devices.length === 0) {
    await complete(false, "recipient_has_no_device");
    return response("recipient_has_no_device", 409);
  }

  let providerToken: string;
  try {
    const configuration: APNsConfiguration = {
      keyID,
      teamID,
      privateKey,
      environment,
    };
    providerToken = await createProviderToken(configuration);
  } catch {
    diagnostic("push_apns_key_invalid", { event_kind: job.event_kind });
    await complete(false, "apns_key_invalid");
    return response("apns_key_invalid", 500);
  }

  const preview = async (device: DeviceRow): Promise<NotificationPreview | undefined> => {
    if (!device.content_preview_enabled || !job.source_item_id) return undefined;
    const { data } = await service.from("shared_items")
      .select("item_kind,text_content,creator_user_id")
      .eq("id", job.source_item_id).limit(1).maybeSingle();
    if (!data) return undefined;
    if (data.item_kind === "photo") return { title: "CoupleSpace 有新動態", body: "傳送了一張照片" };
    if (typeof data.text_content !== "string") return undefined;
    const { data: profile } = await service.from("user_profiles")
      .select("display_name").eq("user_id", data.creator_user_id).maybeSingle();
    return { title: profile?.display_name ?? "CoupleSpace 有新訊息", body: data.text_content.slice(0, 140) };
  };
  const deliveries = await Promise.all(devices.map(async (device) =>
    sendGenericPush(
      device.token,
      job.source_item_id,
      job.event_kind,
      job.badge_count,
      await preview(device),
      providerToken,
      environment,
    ).catch(() => ({ ok: false, status: 0, reason: "apns_network_failed" }))
  ));
  const succeeded = deliveries.some((delivery) => delivery.ok);
  diagnostic("push_apns_finished", {
    event_kind: job.event_kind,
    succeeded,
    successful_deliveries: deliveries.filter((delivery) => delivery.ok).length,
    failed_deliveries: deliveries.filter((delivery) => !delivery.ok).length,
  });
  const failureReason = deliveries
    .filter((delivery) => !delivery.ok)
    .map((delivery) => delivery.reason ?? `apns_${delivery.status}`)
    .join(",")
    .slice(0, 500) || null;

  await complete(succeeded, succeeded ? null : failureReason);
  if (!succeeded) return response("apns_delivery_failed", 503);

  return new Response(JSON.stringify({ delivered: true }), {
    status: 200,
    headers: jsonHeaders,
  });
});

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  APNsConfiguration,
  APNsEnvironment,
  createProviderToken,
  sendGenericPush,
} from "./apns.ts";

type ClaimedJob = {
  job_id: string;
  event_id: string;
  event_kind: string;
  recipient_user_id: string;
  attempt_count: number;
};

type DeviceRow = {
  token: string;
};

const jsonHeaders = { "Content-Type": "application/json" };
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function response(error: string, status: number): Response {
  return new Response(JSON.stringify({ error }), { status, headers: jsonHeaders });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return response("method_not_allowed", 405);

  const projectURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const keyID = Deno.env.get("APNS_KEY_ID");
  const teamID = Deno.env.get("APNS_TEAM_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY");
  const environment = Deno.env.get("APNS_ENVIRONMENT") as APNsEnvironment | undefined;
  const authorization = request.headers.get("Authorization");
  const accessToken = authorization?.replace(/^Bearer\s+/i, "");

  if (!projectURL || !serviceRoleKey || !keyID || !teamID || !privateKey
    || !environment || !["sandbox", "production"].includes(environment)) {
    return response("server_not_configured", 500);
  }
  if (!accessToken) return response("missing_authorization", 401);

  let jobID: string;
  try {
    const body = await request.json() as { job_id?: unknown };
    if (typeof body.job_id !== "string" || !uuidPattern.test(body.job_id)) {
      return response("invalid_job_id", 400);
    }
    jobID = body.job_id;
  } catch {
    return response("invalid_request", 400);
  }

  const service = createClient(projectURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await service.auth.getUser(accessToken);
  if (authError || !authData.user) return response("invalid_authorization", 401);

  const { data: claimedRows, error: claimError } = await service.rpc(
    "claim_w1_push_job",
    {
      target_job_id: jobID,
      target_sender_user_id: authData.user.id,
    },
  );
  if (claimError) return response("push_job_not_claimable", 409);

  const job = (claimedRows as ClaimedJob[] | null)?.[0];
  if (!job) return response("push_job_not_claimable", 409);

  const complete = async (succeeded: boolean, error: string | null) => {
    await service.rpc("complete_w1_push_job", {
      target_job_id: job.job_id,
      target_succeeded: succeeded,
      target_error: error,
    });
  };

  const { data: deviceRows, error: deviceError } = await service
    .from("push_devices")
    .select("token")
    .eq("user_id", job.recipient_user_id)
    .eq("environment", environment)
    .eq("bundle_id", "com.titus.CoupleSpace")
    .order("updated_at", { ascending: false });
  if (deviceError) {
    await complete(false, "device_lookup_failed");
    return response("device_lookup_failed", 500);
  }

  const devices = (deviceRows ?? []) as DeviceRow[];
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
    await complete(false, "apns_key_invalid");
    return response("apns_key_invalid", 500);
  }

  const deliveries = await Promise.all(devices.map((device) =>
    sendGenericPush(
      device.token,
      job.event_id,
      job.event_kind,
      providerToken,
      environment,
    ).catch(() => ({ ok: false, status: 0, reason: "apns_network_failed" }))
  ));
  const succeeded = deliveries.some((delivery) => delivery.ok);
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

export type APNsEnvironment = "sandbox" | "production";

export type APNsConfiguration = {
  keyID: string;
  teamID: string;
  privateKey: string;
  environment: APNsEnvironment;
};

export type APNsDelivery = {
  ok: boolean;
  status: number;
  reason: string | null;
};

type Fetcher = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Promise<Response>;

const topic = "com.titus.CoupleSpace";

function base64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/g, "");
}

function encodeJSON(value: unknown): string {
  return base64URL(new TextEncoder().encode(JSON.stringify(value)));
}

function privateKeyBytes(pem: string): Uint8Array {
  const body = pem
    .replaceAll("\\n", "\n")
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  if (!body) throw new Error("invalid_apns_private_key");

  try {
    return Uint8Array.from(atob(body), (character) => character.charCodeAt(0));
  } catch {
    throw new Error("invalid_apns_private_key");
  }
}

export type NotificationPreview = { title: string; body: string };

export function genericPayload(eventID: string, eventKind: string, badgeCount = 0, preview?: NotificationPreview) {
  if (
    ![
      "chat_message_created",
      "appointment_discussion_message_created",
      "appointment_created",
      "appointment_updated",
      "appointment_cancelled",
    ].includes(eventKind)
  ) {
    throw new Error("unsupported_event_kind");
  }

  return {
    aps: {
      alert: {
        title: preview?.title ?? "CoupleSpace 有新動態",
        body: preview?.body ?? "打開 App 查看",
      },
      sound: "default",
      badge: Math.max(0, badgeCount),
      "content-available": 1,
    },
    event_kind: eventKind,
  };
}

export async function createProviderToken(
  configuration: APNsConfiguration,
  now = new Date(),
): Promise<string> {
  const sourceBytes = privateKeyBytes(configuration.privateKey);
  const keyData = new ArrayBuffer(sourceBytes.byteLength);
  new Uint8Array(keyData).set(sourceBytes);
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const header = encodeJSON({ alg: "ES256", kid: configuration.keyID });
  const claims = encodeJSON({
    iss: configuration.teamID,
    iat: Math.floor(now.getTime() / 1000),
  });
  const signingInput = `${header}.${claims}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64URL(new Uint8Array(signature))}`;
}

export async function sendGenericPush(
  deviceToken: string,
  eventID: string,
  eventKind: string,
  badgeCount: number,
  preview: NotificationPreview | undefined,
  providerToken: string,
  environment: APNsEnvironment,
  fetcher: Fetcher = fetch,
): Promise<APNsDelivery> {
  if (!/^[0-9a-f]+$/.test(deviceToken) || deviceToken.length % 2 !== 0) {
    throw new Error("invalid_device_token");
  }

  const host = environment === "sandbox"
    ? "api.sandbox.push.apple.com"
    : "api.push.apple.com";
  const response = await fetcher(`https://${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${providerToken}`,
      "apns-id": eventID,
      "apns-priority": "10",
      "apns-push-type": "alert",
      "apns-topic": topic,
      "content-type": "application/json",
    },
    body: JSON.stringify(genericPayload(eventID, eventKind, badgeCount, preview)),
  });

  let reason: string | null = null;
  if (!response.ok) {
    try {
      const body = await response.json() as { reason?: unknown };
      if (typeof body.reason === "string") reason = body.reason.slice(0, 100);
    } catch {
      reason = "apns_request_failed";
    }
  }

  return { ok: response.ok, status: response.status, reason };
}

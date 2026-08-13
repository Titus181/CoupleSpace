import {
  assert,
  assertEquals,
  assertThrows,
} from "jsr:@std/assert@1";
import {
  createProviderToken,
  genericPayload,
  sendGenericPush,
} from "./apns.ts";

function decodeBase64URLJSON(value: string): unknown {
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
  return JSON.parse(atob(padded));
}

Deno.test("generic payload contains routing metadata but no private content", () => {
  const eventID = "94000000-0000-0000-0000-000000000010";
  const payload = genericPayload(eventID, "w1_generic");
  const encoded = JSON.stringify(payload);

  assertEquals(payload.aps.alert.title, "CoupleSpace 有新動態");
  assertEquals(payload.aps.alert.body, "打開 App 查看");
  assertEquals(payload.event_id, eventID);
  assert(!encoded.includes("relationship"));
  assert(!encoded.includes("sender"));
  assert(!encoded.includes("message"));
  assert(!encoded.includes("photo"));
});

Deno.test("unsupported event kind is rejected", () => {
  assertThrows(
    () => genericPayload("event", "message_created"),
    Error,
    "unsupported_event_kind",
  );
});

Deno.test("provider token is an ES256 JWT with key and team identifiers", async () => {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const bytes = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  const key = `-----BEGIN PRIVATE KEY-----\n${btoa(binary)}\n-----END PRIVATE KEY-----`;

  const token = await createProviderToken({
    keyID: "KEY123",
    teamID: "TEAM123",
    privateKey: key,
    environment: "sandbox",
  }, new Date("2026-08-06T00:00:00Z"));
  const [header, claims, signature] = token.split(".");

  assertEquals(decodeBase64URLJSON(header), {
    alg: "ES256",
    kid: "KEY123",
  });
  assertEquals(decodeBase64URLJSON(claims), {
    iss: "TEAM123",
    iat: 1785974400,
  });
  assert(signature.length > 0);
});

Deno.test("sandbox request uses generic APNs headers and body", async () => {
  let requestURL = "";
  let requestInit: RequestInit | undefined;
  const result = await sendGenericPush(
    "a1b2c3d4",
    "94000000-0000-0000-0000-000000000010",
    "w1_generic",
    "provider.jwt",
    "sandbox",
    async (input, init) => {
      requestURL = input.toString();
      requestInit = init;
      return new Response(null, { status: 200 });
    },
  );

  assert(result.ok);
  assertEquals(requestURL, "https://api.sandbox.push.apple.com/3/device/a1b2c3d4");
  const headers = requestInit?.headers as Record<string, string>;
  assertEquals(headers["apns-topic"], "com.titus.CoupleSpace");
  assertEquals(headers["apns-push-type"], "alert");
  assertEquals(headers["authorization"], "bearer provider.jwt");
  assertEquals(
    JSON.parse(requestInit?.body as string),
    genericPayload("94000000-0000-0000-0000-000000000010", "w1_generic"),
  );
});

Deno.test("APNs rejection returns only its bounded reason", async () => {
  const result = await sendGenericPush(
    "a1b2c3d4",
    "94000000-0000-0000-0000-000000000010",
    "w1_generic",
    "provider.jwt",
    "production",
    async () => new Response(JSON.stringify({ reason: "BadDeviceToken" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    }),
  );

  assertEquals(result, { ok: false, status: 400, reason: "BadDeviceToken" });
});

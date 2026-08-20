import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { createStorageGCGateway, StorageGCTransport } from "./gateway.ts";
import {
  ClaimedStorageGCJob,
  createStorageGCHandler,
  StorageGCGateway,
} from "./worker.ts";

const serviceRoleKey = "service-role-secret";
const jobOne: ClaimedStorageGCJob = {
  job_id: "job-private-one",
  claim_token: "claim-private-one",
  bucket_id: "private-bucket-one",
  object_path: "private/path/one.jpg",
  attempt_count: 1,
};
const jobTwo: ClaimedStorageGCJob = {
  job_id: "job-private-two",
  claim_token: "claim-private-two",
  bucket_id: "private-bucket-two",
  object_path: "private/path/two.jpg",
  attempt_count: 2,
};
const jobThree: ClaimedStorageGCJob = {
  job_id: "job-private-three",
  claim_token: "claim-private-three",
  bucket_id: "private-bucket-three",
  object_path: "private/path/three.jpg",
  attempt_count: 3,
};

type FakeOptions = {
  jobs?: ClaimedStorageGCJob[];
  deleteFailures?: Set<string>;
  completionFailures?: Set<string>;
  failRPC?: boolean;
};

function fakeGateway(options: FakeOptions = {}) {
  const calls: string[] = [];
  const failedJobs: Array<[string, string, string]> = [];
  const completedJobs: Array<[string, string]> = [];
  const deletedObjects: Array<[string, string[]]> = [];
  const gateway: StorageGCGateway = {
    purgeExpiredMoments(targetLimit) {
      calls.push(`purge:${targetLimit}`);
      return Promise.resolve({ purged_count: 2, queued_count: 1 });
    },
    claimStorageGCJobs(targetLimit) {
      calls.push(`claim:${targetLimit}`);
      return Promise.resolve(options.jobs ?? []);
    },
    deleteStorageObject(bucketID, objectPath) {
      calls.push("delete");
      deletedObjects.push([bucketID, [objectPath]]);
      if (options.deleteFailures?.has(objectPath)) {
        return Promise.reject(new Error(`provider leaked ${objectPath}`));
      }
      return Promise.resolve();
    },
    failStorageGCJob(jobID, claimToken, reasonCode) {
      calls.push("fail");
      failedJobs.push([jobID, claimToken, reasonCode]);
      if (options.failRPC) {
        return Promise.reject(new Error("raw database failure"));
      }
      return Promise.resolve();
    },
    completeStorageGCJob(jobID, claimToken) {
      calls.push("complete");
      completedJobs.push([jobID, claimToken]);
      if (options.completionFailures?.has(jobID)) {
        return Promise.reject(new Error(`raw completion failure ${jobID}`));
      }
      return Promise.resolve();
    },
  };

  return { gateway, calls, failedJobs, completedJobs, deletedObjects };
}

function request(method = "POST", token = serviceRoleKey): Request {
  return new Request("https://example.invalid/process-storage-gc", {
    method,
    headers: { Authorization: `Bearer ${token}` },
  });
}

async function body(response: Response): Promise<Record<string, unknown>> {
  return await response.json();
}

Deno.test("storage GC accepts POST with only the service role bearer token", async () => {
  const fake = fakeGateway();
  const handler = createStorageGCHandler({
    serviceRoleKey,
    gateway: fake.gateway,
    diagnostic: () => {},
  });

  const methodResponse = await handler(request("GET"));
  assertEquals(methodResponse.status, 405);
  assertEquals(await body(methodResponse), { error: "method_not_allowed" });

  const missingResponse = await handler(
    new Request("https://example.invalid", {
      method: "POST",
    }),
  );
  assertEquals(missingResponse.status, 401);
  assertEquals(await body(missingResponse), { error: "missing_authorization" });

  const endUserResponse = await handler(request("POST", "end-user-jwt"));
  assertEquals(endUserResponse.status, 401);
  assertEquals(await body(endUserResponse), { error: "invalid_authorization" });
  assertEquals(fake.calls, []);

  const serviceResponse = await handler(request());
  assertEquals(serviceResponse.status, 200);
  assertEquals(fake.calls, ["purge:100", "claim:20"]);
});

Deno.test("empty GC run purges before claiming and returns counts only", async () => {
  const fake = fakeGateway();
  const logs: unknown[] = [];
  const handler = createStorageGCHandler({
    serviceRoleKey,
    gateway: fake.gateway,
    diagnostic: (event, details) => logs.push({ event, ...details }),
  });

  const response = await handler(request());

  assertEquals(response.status, 200);
  assertEquals(await body(response), {
    purged_count: 2,
    queued_count: 1,
    claimed_count: 0,
    completed_count: 0,
    failed_count: 0,
  });
  assertEquals(fake.calls, ["purge:100", "claim:20"]);
  assertEquals(logs, [{
    event: "storage_gc_request_finished",
    result_code: "succeeded",
    purged_count: 2,
    queued_count: 1,
    claimed_count: 0,
    completed_count: 0,
    failed_count: 0,
  }]);
});

Deno.test("Supabase gateway uses fixed RPC arguments and one-object removes", async () => {
  const rpcCalls: Array<[string, Record<string, unknown>]> = [];
  const removeCalls: Array<[string, string[]]> = [];
  let removeError: unknown = null;
  let mutationResult: unknown = true;
  const transport: StorageGCTransport = {
    rpc(functionName, arguments_) {
      rpcCalls.push([functionName, arguments_]);
      if (functionName === "purge_expired_moments") {
        return Promise.resolve({
          data: [{ purged_count: 4, queued_count: 2 }],
          error: null,
        });
      }
      if (functionName === "claim_storage_gc_jobs") {
        return Promise.resolve({ data: [jobOne], error: null });
      }
      return Promise.resolve({ data: mutationResult, error: null });
    },
    remove(bucketID, objectPaths) {
      removeCalls.push([bucketID, objectPaths]);
      return Promise.resolve({ error: removeError });
    },
  };
  const gateway = createStorageGCGateway(transport);

  assertEquals(await gateway.purgeExpiredMoments(100), {
    purged_count: 4,
    queued_count: 2,
  });
  assertEquals(await gateway.claimStorageGCJobs(20), [jobOne]);
  await gateway.deleteStorageObject(jobOne.bucket_id, jobOne.object_path);
  await gateway.failStorageGCJob(
    jobOne.job_id,
    jobOne.claim_token,
    "storage_delete_failed",
  );
  await gateway.completeStorageGCJob(jobOne.job_id, jobOne.claim_token);

  assertEquals(rpcCalls, [
    ["purge_expired_moments", { target_limit: 100 }],
    ["claim_storage_gc_jobs", { target_limit: 20 }],
    ["fail_storage_gc_job", {
      target_job_id: jobOne.job_id,
      target_claim_token: jobOne.claim_token,
      target_reason_code: "storage_delete_failed",
    }],
    ["complete_storage_gc_job", {
      target_job_id: jobOne.job_id,
      target_claim_token: jobOne.claim_token,
    }],
  ]);
  assertEquals(removeCalls, [[
    jobOne.bucket_id,
    [jobOne.object_path],
  ]]);

  removeError = new Error(`raw provider error for ${jobOne.object_path}`);
  await assertRejects(
    () => gateway.deleteStorageObject(jobOne.bucket_id, jobOne.object_path),
    Error,
    "storage_delete_failed",
  );

  mutationResult = false;
  await assertRejects(
    () =>
      gateway.failStorageGCJob(
        jobOne.job_id,
        jobOne.claim_token,
        "storage_delete_failed",
      ),
    Error,
    "storage_gc_fail_rpc_failed",
  );
  await assertRejects(
    () => gateway.completeStorageGCJob(jobOne.job_id, jobOne.claim_token),
    Error,
    "storage_gc_complete_rpc_failed",
  );
});

Deno.test("storage deletion failure is recorded with a stable code and can retry", async () => {
  let shouldFail = true;
  const failedJobs: Array<[string, string, string]> = [];
  const completedJobs: Array<[string, string]> = [];
  const gateway: StorageGCGateway = {
    purgeExpiredMoments() {
      return Promise.resolve({ purged_count: 0, queued_count: 0 });
    },
    claimStorageGCJobs() {
      return Promise.resolve([jobOne]);
    },
    deleteStorageObject() {
      if (shouldFail) {
        return Promise.reject(
          new Error("raw provider secret and private path"),
        );
      }
      return Promise.resolve();
    },
    failStorageGCJob(jobID, claimToken, reasonCode) {
      failedJobs.push([jobID, claimToken, reasonCode]);
      shouldFail = false;
      return Promise.resolve();
    },
    completeStorageGCJob(jobID, claimToken) {
      completedJobs.push([jobID, claimToken]);
      return Promise.resolve();
    },
  };
  const handler = createStorageGCHandler({
    serviceRoleKey,
    gateway,
    diagnostic: () => {},
  });

  const firstResponse = await handler(request());
  assertEquals(firstResponse.status, 503);
  assertEquals(await body(firstResponse), {
    error: "storage_gc_incomplete",
    purged_count: 0,
    queued_count: 0,
    claimed_count: 1,
    completed_count: 0,
    failed_count: 1,
  });
  assertEquals(failedJobs, [[
    jobOne.job_id,
    jobOne.claim_token,
    "storage_delete_failed",
  ]]);
  assertEquals(completedJobs, []);

  const retryResponse = await handler(request());
  assertEquals(retryResponse.status, 200);
  assertEquals(completedJobs, [[jobOne.job_id, jobOne.claim_token]]);
});

Deno.test("mixed GC outcomes are isolated and delete one object per call", async () => {
  const fake = fakeGateway({
    jobs: [jobOne, jobTwo, jobThree],
    deleteFailures: new Set([jobTwo.object_path]),
  });
  const handler = createStorageGCHandler({
    serviceRoleKey,
    gateway: fake.gateway,
    diagnostic: () => {},
  });

  const response = await handler(request());

  assertEquals(response.status, 503);
  assertEquals(await body(response), {
    error: "storage_gc_incomplete",
    purged_count: 2,
    queued_count: 1,
    claimed_count: 3,
    completed_count: 2,
    failed_count: 1,
  });
  assertEquals(fake.deletedObjects, [
    [jobOne.bucket_id, [jobOne.object_path]],
    [jobTwo.bucket_id, [jobTwo.object_path]],
    [jobThree.bucket_id, [jobThree.object_path]],
  ]);
  assertEquals(fake.failedJobs, [[
    jobTwo.job_id,
    jobTwo.claim_token,
    "storage_delete_failed",
  ]]);
  assertEquals(fake.completedJobs, [
    [jobOne.job_id, jobOne.claim_token],
    [jobThree.job_id, jobThree.claim_token],
  ]);
});

Deno.test("completion failure leaves the lease intact and returns failure", async () => {
  const fake = fakeGateway({
    jobs: [jobOne],
    completionFailures: new Set([jobOne.job_id]),
  });
  const handler = createStorageGCHandler({
    serviceRoleKey,
    gateway: fake.gateway,
    diagnostic: () => {},
  });

  const response = await handler(request());

  assertEquals(response.status, 503);
  assertEquals(await body(response), {
    error: "storage_gc_incomplete",
    purged_count: 2,
    queued_count: 1,
    claimed_count: 1,
    completed_count: 0,
    failed_count: 1,
  });
  assertEquals(fake.failedJobs, []);
  assertEquals(fake.completedJobs, [[jobOne.job_id, jobOne.claim_token]]);
});

Deno.test("responses and diagnostics never expose IDs paths content or provider errors", async () => {
  const fake = fakeGateway({
    jobs: [jobOne],
    deleteFailures: new Set([jobOne.object_path]),
    failRPC: true,
  });
  const logs: unknown[] = [];
  const handler = createStorageGCHandler({
    serviceRoleKey,
    gateway: fake.gateway,
    diagnostic: (event, details) => logs.push({ event, ...details }),
  });

  const response = await handler(request());
  const output = JSON.stringify({ response: await body(response), logs });

  for (
    const privateValue of [
      jobOne.job_id,
      jobOne.claim_token,
      jobOne.bucket_id,
      jobOne.object_path,
      "provider leaked",
      "raw database failure",
      "private content",
    ]
  ) {
    assertEquals(output.includes(privateValue), false);
  }
  assertEquals(logs, [{
    event: "storage_gc_request_finished",
    result_code: "incomplete",
    purged_count: 2,
    queued_count: 1,
    claimed_count: 1,
    completed_count: 0,
    failed_count: 1,
  }]);
});

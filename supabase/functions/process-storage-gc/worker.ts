export type ClaimedStorageGCJob = {
  job_id: string;
  claim_token: string;
  bucket_id: string;
  object_path: string;
  attempt_count: number;
};

export type MomentPurgeResult = {
  purged_count: number;
  queued_count: number;
};

export interface StorageGCGateway {
  purgeExpiredMoments(targetLimit: number): Promise<MomentPurgeResult>;
  claimStorageGCJobs(targetLimit: number): Promise<ClaimedStorageGCJob[]>;
  deleteStorageObject(bucketID: string, objectPath: string): Promise<void>;
  failStorageGCJob(
    jobID: string,
    claimToken: string,
    reasonCode: "storage_delete_failed",
  ): Promise<void>;
  completeStorageGCJob(jobID: string, claimToken: string): Promise<void>;
}

type DiagnosticDetails = Record<string, string | number | boolean>;
type Diagnostic = (event: string, details?: DiagnosticDetails) => void;

type HandlerDependencies = {
  serviceRoleKey?: string;
  gateway?: StorageGCGateway;
  diagnostic?: Diagnostic;
};

const jsonHeaders = { "Content-Type": "application/json" };
const encoder = new TextEncoder();

function json(body: Record<string, string | number>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  });
}

export async function constantTimeEqual(
  candidate: string,
  expected: string,
): Promise<boolean> {
  const [candidateHash, expectedHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(candidate)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const candidateBytes = new Uint8Array(candidateHash);
  const expectedBytes = new Uint8Array(expectedHash);
  let difference = candidate.length ^ expected.length;

  for (let index = 0; index < candidateBytes.length; index += 1) {
    difference |= candidateBytes[index] ^ expectedBytes[index];
  }

  return difference === 0;
}

export function createStorageGCHandler(
  dependencies: HandlerDependencies,
): (request: Request) => Promise<Response> {
  const diagnostic = dependencies.diagnostic ??
    ((event, details = {}) =>
      console.log(JSON.stringify({ event, ...details })));

  return async (request) => {
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }

    const serviceRoleKey = dependencies.serviceRoleKey;
    const gateway = dependencies.gateway;
    if (!serviceRoleKey || !gateway) {
      diagnostic("storage_gc_request_failed", {
        result_code: "server_not_configured",
      });
      return json({ error: "server_not_configured" }, 500);
    }

    const authorization = request.headers.get("Authorization");
    if (!authorization) {
      return json({ error: "missing_authorization" }, 401);
    }

    const bearerMatch = authorization.match(/^Bearer ([^\s]+)$/i);
    if (
      !bearerMatch ||
      !(await constantTimeEqual(bearerMatch[1], serviceRoleKey))
    ) {
      return json({ error: "invalid_authorization" }, 401);
    }

    let purgeResult: MomentPurgeResult;
    try {
      purgeResult = await gateway.purgeExpiredMoments(100);
    } catch {
      diagnostic("storage_gc_request_failed", {
        result_code: "moment_purge_failed",
      });
      return json({ error: "moment_purge_failed" }, 503);
    }

    let jobs: ClaimedStorageGCJob[];
    try {
      jobs = await gateway.claimStorageGCJobs(20);
    } catch {
      diagnostic("storage_gc_request_failed", {
        result_code: "storage_gc_claim_failed",
        purged_count: purgeResult.purged_count,
        queued_count: purgeResult.queued_count,
      });
      return json({
        error: "storage_gc_claim_failed",
        purged_count: purgeResult.purged_count,
        queued_count: purgeResult.queued_count,
      }, 503);
    }

    let completedCount = 0;
    let failedCount = 0;

    for (const job of jobs) {
      try {
        await gateway.deleteStorageObject(job.bucket_id, job.object_path);
      } catch {
        failedCount += 1;
        try {
          await gateway.failStorageGCJob(
            job.job_id,
            job.claim_token,
            "storage_delete_failed",
          );
        } catch {
          // The existing lease remains the authority when failure recording fails.
        }
        continue;
      }

      try {
        await gateway.completeStorageGCJob(job.job_id, job.claim_token);
        completedCount += 1;
      } catch {
        // The DB keeps the authoritative processing or blocked state.  Do not
        // issue a second mutation after Storage has already succeeded.
        failedCount += 1;
      }
    }

    const counts = {
      purged_count: purgeResult.purged_count,
      queued_count: purgeResult.queued_count,
      claimed_count: jobs.length,
      completed_count: completedCount,
      failed_count: failedCount,
    };
    const resultCode = failedCount === 0 ? "succeeded" : "incomplete";
    diagnostic("storage_gc_request_finished", {
      result_code: resultCode,
      ...counts,
    });

    if (failedCount > 0) {
      return json({ error: "storage_gc_incomplete", ...counts }, 503);
    }

    return json(counts, 200);
  };
}

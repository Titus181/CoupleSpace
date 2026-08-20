import {
  ClaimedStorageGCJob,
  MomentPurgeResult,
  StorageGCGateway,
} from "./worker.ts";

type RPCResult = {
  data: unknown;
  error: unknown;
};

type StorageResult = {
  error: unknown;
};

export type StorageGCTransport = {
  rpc(
    functionName: string,
    arguments_: Record<string, unknown>,
  ): Promise<RPCResult>;
  remove(bucketID: string, objectPaths: string[]): Promise<StorageResult>;
};

function stableError(code: string): Error {
  return new Error(code);
}

function isNonnegativeInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0;
}

function parsePurgeResult(data: unknown): MomentPurgeResult {
  const row = Array.isArray(data) ? data[0] : data;
  if (
    typeof row !== "object" || row === null ||
    !isNonnegativeInteger(Reflect.get(row, "purged_count")) ||
    !isNonnegativeInteger(Reflect.get(row, "queued_count"))
  ) {
    throw stableError("invalid_purge_result");
  }

  return {
    purged_count: Reflect.get(row, "purged_count") as number,
    queued_count: Reflect.get(row, "queued_count") as number,
  };
}

function parseClaimedJobs(data: unknown): ClaimedStorageGCJob[] {
  if (!Array.isArray(data)) throw stableError("invalid_claim_result");

  return data.map((row) => {
    if (
      typeof row !== "object" || row === null ||
      typeof Reflect.get(row, "job_id") !== "string" ||
      typeof Reflect.get(row, "claim_token") !== "string" ||
      typeof Reflect.get(row, "bucket_id") !== "string" ||
      typeof Reflect.get(row, "object_path") !== "string" ||
      !isNonnegativeInteger(Reflect.get(row, "attempt_count"))
    ) {
      throw stableError("invalid_claim_result");
    }

    return {
      job_id: Reflect.get(row, "job_id") as string,
      claim_token: Reflect.get(row, "claim_token") as string,
      bucket_id: Reflect.get(row, "bucket_id") as string,
      object_path: Reflect.get(row, "object_path") as string,
      attempt_count: Reflect.get(row, "attempt_count") as number,
    };
  });
}

export function createStorageGCGateway(
  transport: StorageGCTransport,
): StorageGCGateway {
  return {
    async purgeExpiredMoments(targetLimit) {
      const { data, error } = await transport.rpc("purge_expired_moments", {
        target_limit: targetLimit,
      });
      if (error) throw stableError("moment_purge_failed");
      return parsePurgeResult(data);
    },

    async claimStorageGCJobs(targetLimit) {
      const { data, error } = await transport.rpc("claim_storage_gc_jobs", {
        target_limit: targetLimit,
      });
      if (error) throw stableError("storage_gc_claim_failed");
      return parseClaimedJobs(data);
    },

    async deleteStorageObject(bucketID, objectPath) {
      const { error } = await transport.remove(bucketID, [objectPath]);
      if (error) throw stableError("storage_delete_failed");
    },

    async failStorageGCJob(jobID, claimToken, reasonCode) {
      const { data, error } = await transport.rpc("fail_storage_gc_job", {
        target_job_id: jobID,
        target_claim_token: claimToken,
        target_reason_code: reasonCode,
      });
      if (error || data !== true) {
        throw stableError("storage_gc_fail_rpc_failed");
      }
    },

    async completeStorageGCJob(jobID, claimToken) {
      const { data, error } = await transport.rpc("complete_storage_gc_job", {
        target_job_id: jobID,
        target_claim_token: claimToken,
      });
      if (error || data !== true) {
        throw stableError("storage_gc_complete_rpc_failed");
      }
    },
  };
}

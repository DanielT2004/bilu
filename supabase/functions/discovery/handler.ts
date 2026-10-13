import {
  PaidAPIAccessError,
  paidAPIAccessErrorResponse,
  requireAuthenticatedUser,
} from "../_shared/paid_api_guard.ts";
import {
  commitDiscovery,
  getPurchaseWallet,
  readDiscovery,
  releaseDiscovery,
  reserveDiscovery,
} from "../_shared/purchase_wallet.ts";
import { fulfillDiscovery } from "../_shared/discovery_fulfillment.ts";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Expose-Headers": "retry-after",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};
const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const json = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), { status, headers });

async function limitedText(req: Request): Promise<string | null> {
  const reader = req.body?.getReader();
  if (!reader) return "";
  const chunks: Uint8Array[] = [];
  let length = 0;
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(() => {
        void reader.cancel().catch(() => {});
        reject(
          new PaidAPIAccessError(
            408,
            "REQUEST_TIMEOUT",
            "The request timed out.",
          ),
        );
      }, 5_000);
    });
    while (true) {
      const { done, value } = await Promise.race([reader.read(), timeout]);
      if (done) break;
      length += value.byteLength;
      if (length > 24_576) {
        void reader.cancel().catch(() => {});
        return null;
      }
      chunks.push(value);
    }
  } finally {
    if (timer !== undefined) clearTimeout(timer);
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

export const discoveryDependencies = {
  authenticate: requireAuthenticatedUser,
  wallet: getPurchaseWallet,
  reserve: reserveDiscovery,
  read: readDiscovery,
  commit: commitDiscovery,
  release: releaseDiscovery,
  fulfill: fulfillDiscovery,
};

export async function handleDiscovery(
  req: Request,
  dependencies = discoveryDependencies,
): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return json({ code: "METHOD_NOT_ALLOWED" }, 405);
  let reservation:
    | { userId: string; id: string; kind: "explore" | "tiktok" }
    | null = null;
  // Once commit starts its HTTP response can be lost after the database commits.
  // Never infer that failure means rollback or release someone else's paid result.
  let isCommitting = false;
  try {
    const user = await dependencies.authenticate(req);
    if (Number(req.headers.get("Content-Length") ?? 0) > 24_576) {
      return json({ code: "REQUEST_TOO_LARGE" }, 413);
    }
    const text = await limitedText(req);
    if (text === null) {
      return json({ code: "REQUEST_TOO_LARGE" }, 413);
    }
    let body: Record<string, unknown>;
    try {
      const parsed = JSON.parse(text);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        throw new Error();
      }
      body = parsed;
    } catch {
      return json({ code: "INVALID_REQUEST" }, 400);
    }
    const id = body.discoveryId;
    const kind = body.kind;
    if (
      typeof id !== "string" || !uuid.test(id) ||
      (kind !== "explore" && kind !== "tiktok") ||
      (body.action !== undefined && body.action !== "start" &&
        body.action !== "status")
    ) {
      return json({ code: "INVALID_REQUEST" }, 400);
    }
    if (body.action === "status") {
      const current = await dependencies.read(user.id, id, kind);
      if (current.status === "missing") {
        return json({ code: "DISCOVERY_NOT_FOUND" }, 404);
      }
      return json(current, current.status === "reserved" ? 202 : 200);
    }
    const input = body.input;
    if (!input || typeof input !== "object" || Array.isArray(input)) {
      return json({ code: "INVALID_REQUEST" }, 400);
    }
    const values = input as Record<string, unknown>;
    if (kind === "explore") {
      if (
        typeof values.prompt !== "string" || !values.prompt.trim() ||
        values.prompt.length > 12_000 ||
        (values.location !== undefined &&
          (typeof values.location !== "string" ||
            values.location.length > 300)) ||
        (values.occasion !== undefined &&
          (typeof values.occasion !== "string" || values.occasion.length > 200))
      ) {
        return json({ code: "INVALID_REQUEST" }, 400);
      }
      for (const key of ["latitude", "longitude", "radiusMiles"]) {
        if (
          values[key] !== undefined &&
          (typeof values[key] !== "number" || !Number.isFinite(values[key]))
        ) {
          return json({ code: "INVALID_REQUEST" }, 400);
        }
      }
      if (
        typeof values.latitude === "number" && Math.abs(values.latitude) > 90 ||
        typeof values.longitude === "number" &&
          Math.abs(values.longitude) > 180 ||
        typeof values.radiusMiles === "number" &&
          (values.radiusMiles <= 0 || values.radiusMiles > 100)
      ) {
        return json({ code: "INVALID_REQUEST" }, 400);
      }
    } else if (
      typeof values.query !== "string" || values.query.trim().length < 3 ||
      values.query.length > 300 ||
      (values.sortType !== undefined &&
        ![0, 1, 2].includes(values.sortType as number))
    ) {
      return json({ code: "INVALID_REQUEST" }, 400);
    }

    const wallet = await dependencies.wallet(user);
    if (!wallet.commerceEnabled) {
      return json({
        code: "COMMERCE_UNAVAILABLE",
        error: "Discovery passes are not available yet.",
      }, 503);
    }
    const access = await dependencies.reserve(user.id, id, kind);
    if (!access.acquired) {
      return json(access, access.status === "reserved" ? 202 : 200);
    }
    reservation = { userId: user.id, id, kind };
    const outcome = await dependencies.fulfill(kind, values, { user });
    if (!outcome.usable) {
      const released = await dependencies.release(user.id, id, kind);
      reservation = null;
      return json({ ...released, result: outcome.result });
    }
    isCommitting = true;
    const completed = await dependencies.commit(
      user.id,
      id,
      kind,
      outcome.result,
    );
    return json(completed, completed.status === "reserved" ? 202 : 200);
  } catch (error) {
    if (reservation && !isCommitting) {
      try {
        await dependencies.release(
          reservation.userId,
          reservation.id,
          reservation.kind,
        );
      } catch {
        // The durable reservation remains recoverable; never claim a refund succeeded.
        return json({
          code: "DISCOVERY_PENDING",
          error: "Your discovery is still being reconciled.",
        }, 202);
      }
    }
    if (isCommitting) {
      return json({
        code: "DISCOVERY_PENDING",
        error: "Your result is being synchronized.",
      }, 202);
    }
    const accessResponse = paidAPIAccessErrorResponse(error, headers);
    if (accessResponse) return accessResponse;
    console.error(JSON.stringify({ event: "discovery_failed" }));
    return json({
      code: "DISCOVERY_UNAVAILABLE",
      error: "Discovery is temporarily unavailable.",
    }, 503);
  }
}

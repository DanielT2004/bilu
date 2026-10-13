import { paidAPIAccessErrorResponse } from "../_shared/paid_api_guard.ts";

const MAXIMUM_BODY_BYTES = 24_000;
const eventNames = new Set([
  "started",
  "completed",
  "failed",
  "cancelled",
  "resultsArrived",
  "adRequested",
  "adImpression",
  "adFailed",
  "adRevenue",
  "adClicked",
  "backgrounded",
]);
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const allowedEventKeys = new Set([
  "id",
  "discoveryID",
  "event",
  "capturedAt",
  "durationMilliseconds",
  "adVisible",
  "code",
  "revenue",
  "currency",
  "precision",
]);
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

export interface DiscoveryEvent {
  id: string;
  discoveryID: string;
  event: string;
  capturedAt: string;
  durationMilliseconds?: number;
  adVisible: boolean;
  code?: number;
  revenue?: string;
  currency?: string;
  precision?: number;
}

export interface DiscoveryTelemetryEnvelope {
  version: 1;
  appVersion: string;
  build: string;
  events: DiscoveryEvent[];
}

export interface DiscoveryTelemetryDependencies {
  authenticate: (request: Request) => Promise<{ id: string }>;
  ingest: (
    userID: string,
    envelope: DiscoveryTelemetryEnvelope,
  ) => Promise<boolean>;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function boundedInteger(
  value: unknown,
  minimum: number,
  maximum: number,
): boolean {
  return typeof value === "number" && Number.isInteger(value) &&
    value >= minimum && value <= maximum;
}

export function parseEnvelope(
  value: unknown,
): DiscoveryTelemetryEnvelope | null {
  if (
    !isRecord(value) || value.version !== 1 ||
    Object.keys(value).some((key) =>
      !["version", "appVersion", "build", "events"].includes(key)
    ) ||
    typeof value.appVersion !== "string" ||
    !/^[\w.()+-]{1,64}$/.test(value.appVersion) ||
    typeof value.build !== "string" || !/^[\w.()+-]{1,64}$/.test(value.build) ||
    !Array.isArray(value.events) || value.events.length < 1 ||
    value.events.length > 20
  ) return null;

  for (const event of value.events) {
    if (
      !isRecord(event) || Object.keys(event).some((key) =>
        !allowedEventKeys.has(key)
      ) ||
      typeof event.id !== "string" || !uuidPattern.test(event.id) ||
      typeof event.discoveryID !== "string" ||
      !uuidPattern.test(event.discoveryID) ||
      typeof event.event !== "string" || !eventNames.has(event.event) ||
      typeof event.adVisible !== "boolean" ||
      typeof event.capturedAt !== "string" || event.capturedAt.length > 30 ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$/.test(
        event.capturedAt,
      ) ||
      !Number.isFinite(Date.parse(event.capturedAt))
    ) return null;
    if (
      event.durationMilliseconds !== undefined &&
      !boundedInteger(event.durationMilliseconds, 0, 3_600_000)
    ) return null;
    if (
      event.code !== undefined && !boundedInteger(event.code, -100_000, 100_000)
    ) return null;
    if (event.event === "adRevenue") {
      if (
        typeof event.revenue !== "string" || event.revenue.length > 40 ||
        !/^\d+(\.\d+)?$/.test(event.revenue) ||
        Number(event.revenue) > 10_000 ||
        typeof event.currency !== "string" ||
        !/^[A-Z]{3}$/.test(event.currency) ||
        !boundedInteger(event.precision, 0, 3)
      ) return null;
    } else if (
      event.revenue !== undefined || event.currency !== undefined ||
      event.precision !== undefined
    ) return null;
  }
  return value as unknown as DiscoveryTelemetryEnvelope;
}

export async function handleDiscoveryTelemetry(
  request: Request,
  dependencies: DiscoveryTelemetryDependencies,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed" });
  }
  try {
    const user = await dependencies.authenticate(request);
    if (
      Number(request.headers.get("content-length") ?? 0) > MAXIMUM_BODY_BYTES
    ) {
      return jsonResponse(413, { error: "Telemetry payload is too large" });
    }
    const raw = await request.text();
    if (new TextEncoder().encode(raw).byteLength > MAXIMUM_BODY_BYTES) {
      return jsonResponse(413, { error: "Telemetry payload is too large" });
    }
    let body: unknown;
    try {
      body = JSON.parse(raw);
    } catch {
      return jsonResponse(400, { error: "Invalid JSON body" });
    }
    const envelope = parseEnvelope(body);
    if (!envelope) {
      return jsonResponse(400, {
        error: "Invalid discovery telemetry envelope",
      });
    }
    const accepted = await dependencies.ingest(user.id, envelope);
    return accepted
      ? jsonResponse(202, { accepted: true })
      : jsonResponse(429, { error: "Telemetry daily limit reached" });
  } catch (error) {
    return paidAPIAccessErrorResponse(error, corsHeaders) ??
      jsonResponse(503, { error: "Discovery telemetry unavailable" });
  }
}

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

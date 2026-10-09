import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  paidAPIAccessErrorResponse,
  requireAuthenticatedUser,
} from "../_shared/paid_api_guard.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  "";
const MAXIMUM_BODY_BYTES = 512_000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface TelemetryRequest {
  id: string;
  kind: "diagnostic" | "metric";
  payload: string;
  appVersion?: string;
  build?: string;
  osVersion?: string;
  capturedAt?: string;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed" });
  }

  try {
    const user = await requireAuthenticatedUser(req);
    const declaredLength = Number(req.headers.get("content-length") ?? 0);
    if (declaredLength > MAXIMUM_BODY_BYTES) {
      return jsonResponse(413, { error: "Telemetry payload is too large" });
    }

    const rawBody = await req.text();
    if (new TextEncoder().encode(rawBody).byteLength > MAXIMUM_BODY_BYTES) {
      return jsonResponse(413, { error: "Telemetry payload is too large" });
    }

    let body: TelemetryRequest;
    try {
      body = JSON.parse(rawBody) as TelemetryRequest;
    } catch {
      return jsonResponse(400, { error: "Invalid JSON body" });
    }
    if (!body.id || !["diagnostic", "metric"].includes(body.kind)) {
      return jsonResponse(400, { error: "Invalid telemetry envelope" });
    }

    let payload: unknown;
    try {
      payload = JSON.parse(body.payload);
    } catch {
      return jsonResponse(400, { error: "MetricKit payload must be JSON" });
    }

    const response = await fetch(
      `${SUPABASE_URL}/rest/v1/rpc/ingest_app_diagnostic`,
      {
        method: "POST",
        headers: {
          "apikey": SUPABASE_SERVICE_ROLE_KEY,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          p_event_id: body.id,
          p_user_id: user.id,
          p_kind: body.kind,
          p_payload: payload,
          p_app_version: body.appVersion ?? "unknown",
          p_build: body.build ?? "unknown",
          p_os_version: body.osVersion ?? "unknown",
          p_captured_at: body.capturedAt ?? new Date().toISOString(),
        }),
        signal: AbortSignal.timeout(5_000),
      },
    );

    if (!response.ok) {
      console.error(JSON.stringify({
        event: "telemetry_ingest_failed",
        status: response.status,
      }));
      return jsonResponse(503, { error: "Telemetry storage unavailable" });
    }

    const accepted = await response.json() as boolean;
    if (!accepted) {
      return jsonResponse(429, { error: "Telemetry daily limit reached" });
    }
    return jsonResponse(202, { accepted: true });
  } catch (error) {
    return paidAPIAccessErrorResponse(error, corsHeaders) ??
      jsonResponse(500, { error: "Telemetry ingestion failed" });
  }
});

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

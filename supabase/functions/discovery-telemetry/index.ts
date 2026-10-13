import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { requireAuthenticatedUser } from "../_shared/paid_api_guard.ts";
import { handleDiscoveryTelemetry } from "./handler.ts";

const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

serve((request: Request) =>
  handleDiscoveryTelemetry(request, {
    authenticate: requireAuthenticatedUser,
    ingest: async (userID, envelope) => {
      const response = await fetch(
        `${supabaseURL}/rest/v1/rpc/ingest_discovery_diagnostics`,
        {
          method: "POST",
          headers: {
            "apikey": serviceKey,
            "Authorization": `Bearer ${serviceKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            p_user_id: userID,
            p_app_version: envelope.appVersion,
            p_build: envelope.build,
            p_events: envelope.events,
          }),
          signal: AbortSignal.timeout(5_000),
        },
      );
      if (!response.ok) {
        console.error(
          JSON.stringify({
            event: "discovery_telemetry_ingest_failed",
            status: response.status,
          }),
        );
        throw new Error("Telemetry storage unavailable");
      }
      return await response.json() === true;
    },
  })
);

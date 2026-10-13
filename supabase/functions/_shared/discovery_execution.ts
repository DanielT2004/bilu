import {
  type AuthenticatedUser,
  PaidAPIAccessError,
} from "./paid_api_guard.ts";

/** Only an in-process orchestrator can supply this context. Never decode it from HTTP. */
export interface DiscoveryExecution {
  user: AuthenticatedUser;
}

export function requireMeteredDiscovery(execution?: DiscoveryExecution): void {
  if (Deno.env.get("BILU_COMMERCE_ENABLED") === "true" && !execution) {
    throw new PaidAPIAccessError(
      426,
      "DISCOVERY_UPDATE_REQUIRED",
      "Please update Bilu to continue discovering places.",
    );
  }
}

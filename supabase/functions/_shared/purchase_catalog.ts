export const PURCHASE_PRODUCTS = {
  discoveryPass: "com.simonsoloman.bilu.discovery_pass",
  proMonthly: "com.simonsoloman.bilu.pro.monthly",
  proAnnual: "com.simonsoloman.bilu.pro.annual",
} as const;

export type DiscoveryKind = "explore" | "tiktok";

// The App Store supplies localized prices. These are server-owned allowances,
// never quantities or prices accepted from a client purchase request.
export const DISCOVERY_ALLOWANCES = {
  free: { explore: 2, tiktok: 1 },
  pro: { explore: 6, tiktok: 1 },
  discoveryPass: { explore: 4, tiktok: 1 },
} as const;

export function commerceEnvironmentEnabled(): boolean {
  return Deno.env.get("BILU_COMMERCE_ENABLED") === "true";
}

export function proEnvironmentEnabled(): boolean {
  return commerceEnvironmentEnabled() &&
    Deno.env.get("BILU_PRO_ENABLED") === "true";
}

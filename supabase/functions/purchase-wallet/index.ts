import {
  paidAPIAccessErrorResponse,
  requireAuthenticatedUser,
} from "../_shared/paid_api_guard.ts";
import { getPurchaseWallet } from "../_shared/purchase_wallet.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
};

export async function handlePurchaseWallet(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return Response.json({
      error: "Method not allowed",
      code: "METHOD_NOT_ALLOWED",
    }, {
      status: 405,
      headers: { ...corsHeaders, Allow: "POST, OPTIONS" },
    });
  }
  try {
    const user = await requireAuthenticatedUser(req);
    // The body intentionally cannot choose another account or mutate balances.
    return Response.json(await getPurchaseWallet(user), {
      headers: corsHeaders,
    });
  } catch (error) {
    return paidAPIAccessErrorResponse(error, corsHeaders) ?? Response.json({
      error: "Discovery access is temporarily unavailable",
      code: "WALLET_UNAVAILABLE",
    }, { status: 503, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handlePurchaseWallet);

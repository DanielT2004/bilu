import { purchaseVerifyHandler } from "../_shared/apple_store_handlers.ts";
import { appleStoreDependencies } from "../_shared/apple_store_runtime.ts";

Deno.serve(purchaseVerifyHandler(appleStoreDependencies));

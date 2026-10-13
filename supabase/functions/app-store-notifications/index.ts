import { appStoreNotificationHandler } from "../_shared/apple_store_handlers.ts";
import { appleStoreDependencies } from "../_shared/apple_store_runtime.ts";

// Gateway JWT verification is disabled only for this endpoint. The handler
// authenticates Apple's complete V2 JWS chain before trusting any notification.
Deno.serve(appStoreNotificationHandler(appleStoreDependencies));

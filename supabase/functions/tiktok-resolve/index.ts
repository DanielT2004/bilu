import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { handleTikTokResolve } from "./handler.ts";

serve((req: Request) => handleTikTokResolve(req));

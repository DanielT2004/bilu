import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { handleEnrichment } from "./handler.ts";

serve((req: Request) => handleEnrichment(req));

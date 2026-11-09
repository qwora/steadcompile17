// Entry point. Logic lives in handler.ts (testable) and lib.ts (pure).
import { handle } from "./handler.ts";

Deno.serve((req) => handle(req));

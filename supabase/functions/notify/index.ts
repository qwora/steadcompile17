// Entry point. Deploy with --no-verify-jwt: the caller is the database trigger, authenticated by NOTIFY_SECRET.
import { handle } from "./handler.ts";

Deno.serve((req) => handle(req));

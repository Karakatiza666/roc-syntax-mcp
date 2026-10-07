respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |_request, _context| Ok(Server.respond(Response.from_status(200)))

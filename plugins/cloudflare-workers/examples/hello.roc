app [event!] { pf: platform "https://github.com/Karakatiza666/roc-cloudflare-workers/releases/download/0.0.1/GcDNxAwPR5tSzqU8T2Kdj35CK3sQMRQDB8ywwfZKdrm.tar.zst" }

## The example Worker (PLAN.md 11b). It has no `cbor` and no `http` entry: the platform brings both.
## The platform line is a path so that the repo can test it. In your project, write the release URL (README.md).
##
## | Route | Shows |
## | --- | --- |
## | `/` | a text answer |
## | `/d1` | a D1 read into a record (a BLOB column is a `List(U8)`) |
## | `/cbor` | `Cbor.encode` and `Cbor.parse` |
## | `/fetch?url=U` | `Http.get!` and the status of the answer |
import pf.Worker
import pf.Request
import pf.Response
import pf.D1
import pf.Sql
import pf.Cbor
import pf.Http

db = D1.binding("DB")

## One row of the D1 query of `/d1`. D1 gives a BLOB as an array of numbers: the field is a `List(U8)`.
Person : { id : I64, name : Str, avatar : List(U8) }

fetch! : Request => Try(Response, _)
fetch! = |req| {
	res = match req.segments() {
		[] => Response.from_text(200, "hello from Roc")
		["d1"] => d1!()
		["cbor"] => cbor()
		["fetch"] => fetch_url!(req.query("url") ?? "")
		_ => Response.from_text(404, "no route")
	}
	Ok(res)
}

d1! : () => Response
d1! = || {
	rows : Try(List(Person), _)
	rows = db.all!("SELECT 1 AS id, 'ann' AS name, x'010203' AS avatar", Sql.none)
	match rows {
		Ok(people) => Response.from_text(200, "Ok ${Str.inspect(people)}")
		Err(e) => Response.from_text(500, "Err ${Str.inspect(e)}")
	}
}

cbor : () -> Response
cbor = || {
	raw = Cbor.encode({ id: 7.I64, avatar: Cbor.bytes([1, 2, 3]) })
	back : Try({ id : I64, avatar : Cbor.Bytes }, _)
	back = Cbor.parse(raw)
	Response.from_text(200, "${raw.len().to_str()} bytes, ${Str.inspect(back)}")
}

fetch_url! : Str => Response
fetch_url! = |url| match Http.get!(url) {
	Ok(r) => Response.from_text(200, "status ${r.status().to_str()}")
	Err(e) => Response.from_text(502, "Err ${Str.inspect(e)}")
}

## `bindings`: the manifest lists the D1 binding, so the shim checks `env.DB` at load, and `roc-cloudflare-workers sync`
## checks `wrangler.toml`.
worker = Worker.new({ fetch!: fetch!, bindings: [db.declare()] })

event! = |e| worker.event!(e)

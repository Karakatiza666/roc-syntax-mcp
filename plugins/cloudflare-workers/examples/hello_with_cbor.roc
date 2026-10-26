app [event!] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.2.1/9jD8bxEKhNu6CzBKej1nA1hzymTedJsfhiGgiMPGA1mu.tar.zst",
	pf: platform "https://github.com/Karakatiza666/roc-cloudflare-workers/releases/download/0.0.1/GcDNxAwPR5tSzqU8T2Kdj35CK3sQMRQDB8ywwfZKdrm.tar.zst",
}

## An app that also adds the roc-cbor URL of the platform header (PLAN.md 11a test). It builds and runs the same as hello.
## The types are the same: a `pf.Cbor.Bytes` goes where a package `Bytes` is wanted, and bytes written by one are read by the other.
import pf.Worker
import pf.Request
import pf.Response
import pf.Cbor
import cbor.Cbor as CborPkg

takes_pkg : CborPkg.Bytes -> List(U8)
takes_pkg = |b| b.to_list()

takes_pf : Cbor.Bytes -> List(U8)
takes_pf = |b| b.to_list()

fetch! : Request => Try(Response, [])
fetch! = |_req| {
	a : Cbor.Bytes
	a = Cbor.bytes([1, 2])
	b : CborPkg.Bytes
	b = CborPkg.Bytes.([3, 4])
	raw = CborPkg.encode({ x: a, y: b })
	back : Try({ x : CborPkg.Bytes, y : Cbor.Bytes }, _)
	back = Cbor.parse(raw)
	both : Try({ x : Cbor.Bytes, y : CborPkg.Bytes }, _)
	both = CborPkg.parse(Cbor.encode({ x: b, y: a }))
	Ok(Response.from_text(200, "${Str.inspect(takes_pkg(a))} ${Str.inspect(takes_pf(b))} ${Str.inspect(back)} ${Str.inspect(both)}"))
}

worker = Worker.new({ fetch!: fetch! })

event! = |e| worker.event!(e)

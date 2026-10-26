## Every snippet that the overview page shows, in one app, so that the page
## cannot drift from code that compiles.
app [event!] { pf: platform "https://github.com/Karakatiza666/roc-cloudflare-workers/releases/download/0.0.1/GcDNxAwPR5tSzqU8T2Kdj35CK3sQMRQDB8ywwfZKdrm.tar.zst" }

import pf.Worker
import pf.Request
import pf.Response
import pf.D1
import pf.Sql
import pf.Object
import pf.Rpc
import pf.Queue
import pf.Log

db = D1.binding("DB")

Item : { id : I64, name : Str }

Ask : { name : Str }

fetch! : Request => Try(Response, _)
fetch! = |req| match (req.method(), req.segments()) {
	(GET, []) => Ok(Response.from_text(200, "hello from Roc"))
	(POST, ["ask"]) => {
		ask : Ask
		ask = req.json!()?
		text = req.header("X-Note") ?? ""
		Ok(Response.from_text(202, ask.name).after(|| note!(text)))
	}
	(GET, ["items", id_text]) => {
		id = I64.from_str(id_text) ? |_| BadId
		item : Item
		item = db.first!("SELECT id, name FROM items WHERE id = ?", id)?
		Ok(Response.from_json(200, item))
	}
	(POST, ["count"]) => {
		n = counters.named("main").call!(increment, 1)?
		Ok(Response.from_text(200, n.to_str()))
	}
	(POST, ["jobs"]) => {
		jobs.send!({ pkg: "a/b" })?
		Ok(Response.from_status(202))
	}
	_ => Ok(Response.from_status(404))
}

note! : Str => Try({}, _)
note! = |text| {
	Log.info!(
		"note",
		{
			text
		},
	)
	Ok({})
}

purge! : Worker.Scheduled => Try({}, _)
purge! = |s| {
	_ = db.run!("DELETE FROM items WHERE expires_ms < ?", [s.time_ms()])?
	Ok({})
}

Counter := []

counter_iface : Rpc.Iface(Counter)
counter_iface = Rpc.iface("Counter")

increment : Rpc(Counter, U64, U64, [Infra(Rpc.Infra)])
increment = counter_iface.method("increment")

total : Object.Cell(U64)
total = Object.cell("total")

counter : Object.Class(Counter)
counter = Object.class(
	"Counter",
	{
		alarm!: |self, _info| {
			self.set_alarm_in!(60_000)?
			Ok({})
		},
		rpc: [
			increment.on(
				|self, by| {
					n = total.get_or!(self, 0)? + by
					total.set!(self, n)?
					Ok(n)
				},
			),
		],
	},
)

counters = Object.namespace("COUNTERS", { class: counter })

jobs : Queue(Job)
jobs = Queue.json("JOBS")

Job : { pkg : Str }

queue! : Queue.Batch => Try({}, _)
queue! = |batch| {
	_ = jobs.each!(batch, |_msg, job| note!(job.pkg))
	Ok({})
}

worker = Worker.new({ fetch!: fetch!, scheduled!: purge!, bindings: [db.declare()] })

## Every field of `Worker.new` at once, to check that they fit together.
worker_full = Worker.new({
	fetch!: fetch!,
	scheduled!: purge!,
	queue!: queue!,
	objects: [counter.erase()],
	bindings: [db.declare(), counters.declare(), jobs.declare()],
	crons: [Worker.cron("*/5 * * * *", purge!)],
})

event! = |e| worker.event!(e)

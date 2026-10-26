## Queues: a typed producer and consumer, ack and retry, delays, many queues.
##
## One constant is the producer and the consumer (MC6): `jobs : Queue(Job)`, `jobs = Queue.json("JOBS")`, where "JOBS" is
## the producer binding of the Wrangler config. The consumer gets its batches in the `queue!` field of `Worker.new`.
## `Queue.json` cannot send an integer above 2^53 (`QueueErr` at the send): use `Queue.v8`. `Queue.v8` also keeps a `Cbor.Bytes`
## field as bytes. Every platform error is inside `Infra(QueueErr(..))`.
##
##   wrangler.toml [[queues.producers]]  binding = "JOBS", queue = "crawl-jobs"
##                 [[queues.consumers]]  queue = "crawl-jobs", max_batch_size = 10, max_retries = 5
##                 Set `max_batch_size` small: a batch crosses into wasm memory whole.
app [event!] { pf: platform "https://github.com/Karakatiza666/roc-cloudflare-workers/releases/download/0.0.1/GcDNxAwPR5tSzqU8T2Kdj35CK3sQMRQDB8ywwfZKdrm.tar.zst" }

import pf.Worker
import pf.Request
import pf.Response
import pf.Queue
import pf.Http

Job : { url : Str }

jobs : Queue(Job)
jobs = Queue.json("JOBS")

Mail : { to : Str, subject : Str }

mails : Queue(Mail)
mails = Queue.json("MAILS")

fetch! : Request => Try(Response, _)
fetch! = |req| {
	job : Job
	job = req.json!()?
	# `delay_ms` goes to Workers in whole seconds, rounded up, 24 h at most (more is `QueueErr`).
	# A message is 128 KB or less. A batch send is 100 messages and 256 KB or less.
	jobs.send_with!(job, { delay_ms: 2_000 })?
	mails.send_batch!([{ to: "a@example.com", subject: "queued" }, { to: "b@example.com", subject: "queued" }])?
	Ok(Response.from_status(202))
}

## `each!` reads each message as the type of the queue and calls the handler with the message and the value. `Ok` acks
## the message. `Err(e)` retries it and logs `Str.inspect(e)`. So the usual retry is an `Err`, not a `retry!` call.
## A body that is not a `Job` is logged and retried, and after `max_retries` it goes to the dead letter queue, if the
## queue has one. `Queue.Batch` and `Queue.Message` are opaque: write `msg.attempts()`, `batch.queue()`. `attempts()`
## starts at 1. `each!` gives the counts `{ acked, retried }`.
crawl! : Queue.Batch => Try({}, _)
crawl! = |batch| {
	health = Http.get!("https://example.com/health")?
	if health.status() != 200 {
		# The upstream is down: retry the whole batch with one delay, before `each!` touches a message.
		batch.retry_all_with!({ delay_ms: 300_000 })
	} else {
		_counts = jobs.each!(
			batch,
			|msg, job| {
				res = Http.get!(job.url)?
				if res.status() >= 500 and msg.attempts() < 5 {
					Err(Upstream(res.status()))
				} else {
					Ok({})
				}
			},
		)
	}
	Ok({})
}

## The low-level form, for a consumer that decides alone: loop over `batch.messages()`, then `ack!` or `retry_with!` each
## one. They have no `Try`: a throw is dropped. The body of a message is the raw CBOR, so `each!` is the typed way to
## read it. A message with no ack and no retry follows the default of the queue.
drain_mails! : Queue.Batch => Try({}, _)
drain_mails! = |batch| {
	for msg in batch.messages() {
		if msg.attempts() > 3 {
			msg.ack!()
		} else {
			msg.retry_with!({ delay_ms: 60_000 })
		}
	}
	Ok({})
}

## One `queue!` for all queues. `batch.queue()` is the name of the queue in the Wrangler config, not the binding name.
## `Err` of `queue!` retries the whole batch, except the messages that already have an explicit ack or retry.
queue! : Queue.Batch => Try({}, _)
queue! = |batch| match batch.queue() {
	"crawl-jobs" => crawl!(batch)
	"mails" => drain_mails!(batch)
	other => Err(UnknownQueue(other))
}

worker = Worker.new({ fetch!: fetch!, queue!: queue!, bindings: [jobs.declare(), mails.declare()] })

event! = |e| worker.event!(e)

## A basic-cli session over a WebSocket or HTTP: typed queries, writes, errors, transactions and record users, each checked against Roc.
# How an app on the basic-cli platform connects to a running SurrealDB, runs
# queries and writes, and reads each result as a Roc type. Start here to
# connect from basic-cli.
#
# The app opens a WebSocket session on `/rpc`, or with `-- --http` a
# session over HTTP (`POST /rpc`), runs queries and writes with
# `Session.run!`, and reads each result as the Roc type of the query. Only
# the transport of the session (`transport`) knows which one it is.
#
# It also checks itself. The result that Roc computes from the same
# functions over the rows in the database stands next to each typed result:
# a line starts with `ok` when the two agree, and with `FAIL` when they do
# not. The exit code is 1 when one line fails. `tests/check.py` runs the app
# for that exit code.
#
# The tables are the tables of `monitoring.roc`, and `check.py` makes them:
# run `python3 tests/check.py` first, then `roc examples/client.roc`. The
# writes use rows of their own (kennel `q`, carers `kim` and `lea`, a reading of
# 2026-03-10), and delete them again. The tables `payment` and
# `placement`, each with a tag union field, and `bin`, which `placement`
# links to, are the app's own: it defines them, and removes them at the end. With `-- --record DIR`, the app saves
# the reply to each request as `DIR/<name>.cbor` (`check.py --record`).
app [main!] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.4.0/EnfRKFT7uPHmd3zT5PcwAiBWUtGmBXapJqFK5166U33J.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	cli_ws: "https://github.com/Karakatiza666/roc-basic-cli-websocket/releases/download/0.0.3/9c6XLWHRSREuaoELdH1a835Yopw92Jxy2b5e151X6mZj.tar.zst",
	surreal: "https://github.com/Karakatiza666/roc-reify-surrealdb/releases/download/0.0.1/7MmdAaAt5bThg6ih3nR9ewVgw4CtNGvuK5HNQhEgZoSV.tar.zst",
}

import pf.Http
import pf.Path
import pf.Stdout
import cli_ws.WsClient
import surreal.Surreal
import http.Request

# ------------------------------------------------- the tables of monitoring.roc

Site : { id : Str, name : Str, location : Surreal.Point, area : Surreal.Polygon }

Kennel : { id : Str, label : Str, site : Surreal.Link(Site) }

Vital : { id : Surreal.TimeKey(Surreal.Id(Kennel)), pulse : I64, temp_c : Dec, fevered : Bool }

Carer : { id : Str, name : Str }

CaresFor : { id : Str, from : Surreal.Link(Carer), to : Surreal.Link(Kennel), lead : Bool }

CareRead : { id : Str, from : Surreal.Linked(Carer), to : Surreal.Link(Kennel), lead : Bool }

KennelRead : { id : Str, label : Str, site : Surreal.Linked(Site), cares_for : Surreal.In(CareRead) }

sites : Surreal.Table(Site)
sites = Surreal.table("site")

kennels : Surreal.Table(Kennel)
kennels = Surreal.table("kennel")

kennel_reads : Surreal.Table(KennelRead)
kennel_reads = Surreal.table("kennel")

vitals : Surreal.Table(Vital)
vitals = Surreal.table("vital")

carers : Surreal.Table(Carer)
carers = Surreal.table("carer")

cares_for : Surreal.Table(CaresFor)
cares_for = Surreal.relation("cares_for", carers, kennels)

kennel_a : Surreal.Id(Kennel)
kennel_a = kennels.id("a")

fever : Dec, I64 -> Bool
fever = |temp_c, pulse| temp_c > 39.0 or pulse > 120

fever_fn : Surreal.DbFn((Dec, I64 -> Bool))
fever_fn = Surreal.db_fn("fever", fever)

# ------------------------------------------- the rows that check.py leaves

moment : Str -> Surreal.Datetime
moment = |text| match Surreal.datetime(text) {
	Ok(d) => d
	Err(_) => crash "a valid datetime"
}

## A reading as the database stores it, with the computed field run in Roc.
reading : Str, Str, I64, Dec -> Vital
reading = |kennel, at, pulse, temp_c| { id: Surreal.time_key(kennels.id(kennel), moment(at)), pulse, temp_c, fevered: fever(temp_c, pulse) }

day_start : Surreal.Datetime
day_start = moment("2026-03-01T00:00:00Z")

day_end : Surreal.Datetime
day_end = moment("2026-03-02T00:00:00Z")

## The readings of `monitoring.roc` that the retention write keeps. The
## live blocks and `watch.roc` delete what they write.
kept_vitals : List(Vital)
kept_vitals = [
	reading("a", "2026-03-01T00:00:00Z", 82, 38.4),
	reading("a", "2026-03-01T08:00:00Z", 80, 38.5),
	reading("a", "2026-03-01T14:30:00Z", 90, 39.5),
	reading("a", "2026-03-02T00:00:00Z", 85, 38.6),
	reading("a", "2026-03-02T09:15:00Z", 125, 38.0),
	reading("b", "2026-03-01T10:00:00Z", 120, 39.0),
	reading("b", "2026-03-01T23:59:59.5Z", 130, 38.0),
	reading("b", "2026-03-02T11:00:00Z", 121, 39.1),
]

ida : Carer
ida = { id: "ida", name: "Ida" }

## The kennels, their sites, and the carers: the block `unattended`
## deletes the carer `jon`.
seed_kennels : List({ kennel : Kennel, site : Str, carers : List(Carer), leads : I64 })
seed_kennels = [
	{ kennel: { id: "a", label: "North", site: sites.link("oslo") }, site: "Oslo", carers: [ida], leads: 1 },
	{ kennel: { id: "b", label: "South", site: sites.link("bergen") }, site: "Bergen", carers: [], leads: 0 },
]

here : Surreal.Point
here = Surreal.point(10.75, 59.91)

## A rectangle from its south-west corner to its north-east corner, its ring closed.
rectangle : Surreal.Point, Surreal.Point -> Surreal.Polygon
rectangle = |sw, ne| {
	se = Surreal.point(ne.lon(), sw.lat())
	nw = Surreal.point(sw.lon(), ne.lat())
	Surreal.Polygon.({ exterior: [sw, se, ne, nw, sw], holes: [] })
}

oslo : Site
oslo = { id: "oslo", name: "Oslo", location: Surreal.point(10.75, 59.91), area: rectangle(Surreal.point(10.6, 59.85), Surreal.point(10.9, 60.0)) }

# ------------------------------------------------------------- the queries

VitalLine : { kennel : Surreal.Id(Kennel), at : Surreal.Datetime, pulse : I64, temp_c : Dec }

vital_line : Vital -> VitalLine
vital_line = |v| { kennel: v.id.series(), at: v.id.time(), pulse: v.pulse, temp_c: v.temp_c }

DayKey : { kennel : Surreal.Id(Kennel), day : Surreal.Datetime }

day_of : Vital -> DayKey
day_of = |v| { kennel: v.id.series(), day: Surreal.Time.floor(v.id.time(), Surreal.Time.days(1)) }

Daily : { kennel : Surreal.Id(Kennel), day : Surreal.Datetime, readings : I64, fevers : I64 }

day_line : DayKey, List(Vital) -> Daily
day_line = |k, rows| { kennel: k.kennel, day: k.day, readings: rows.len().to_i64_wrap(), fevers: rows.keep_if(|v| fever_fn.call2(v.temp_c, v.pulse)).len().to_i64_wrap() }

## One result row for each kennel and day, in Roc.
rollup : List(Vital) -> List(Daily)
rollup = |rows| {
	keys = rows.map(day_of).fold([], |seen, k| if (seen.contains(k)) seen else seen.append(k))
	keys.map(|k| day_line(k, rows.keep_if(|v| day_of(v) == k)))
}

fevers : Try(Surreal.Prepared(List(VitalLine)), Surreal.Error)
fevers = Surreal.from(vitals).filter(|v| fever_fn.call2(v.temp_c, v.pulse)).select(vital_line).prepare({})

## The whole rows, with the key as the array `[kennel, time]`.
kennel_a_rows : Try(Surreal.Prepared(List(Vital)), Surreal.Error)
kennel_a_rows = Surreal.from(vitals).between(kennel_a, day_start, day_end).select(|r| r).prepare({})

daily : Try(Surreal.Prepared(List(Daily)), Surreal.Error)
daily = Surreal.from(vitals).group_by(day_of).aggregate(day_line).prepare({})

## A `LET` and a query: the result of the `LET` is not read.
busy_days : Try(Surreal.Prepared(List(Daily)), Surreal.Error)
busy_days = Surreal.from(vitals).group_by(day_of).aggregate(day_line).query().filter_by(|p, d| d.readings >= p.least).select(|r| r).prepare({ least: 2 })

fastest_pulses : Try(Surreal.Prepared(List(I64)), Surreal.Error)
fastest_pulses = Surreal.from(vitals).select_value(|v| v.pulse).order_by(|n| n, Desc).limit(3).filter(|n| n < 130).prepare({})

sites_covering : Try(Surreal.Prepared(List(Str)), Surreal.Error)
sites_covering = Surreal.from(sites).filter_by(|p, s| Surreal.Geo.inside(p.here.to_geometry(), s.area.to_geometry())).select_value(|s| s.id).prepare({ here: here })

## The whole row of a site by its key: a point and a polygon (tags 88
## and 90).
oslo_site : Try(Surreal.Prepared(Try(Site, [NotFound])), Surreal.Error)
oslo_site = sites.at(sites.id("oslo")).select(|r| r).prepare_one({})

## The same row as one value: `SELECT VALUE { id: record::id(id), .. }`,
## so that `id` is the key, as `Site` has it.
oslo_value : Try(Surreal.Prepared(Try(Site, [NotFound])), Surreal.Error)
oslo_value = sites.at(sites.id("oslo")).select_value(|r| r).prepare_one({})

## A key with no row.
no_site : Try(Surreal.Prepared(Try(Site, [NotFound])), Surreal.Error)
no_site = sites.at(sites.id("nowhere")).select(|r| r).prepare_one({})

KennelCarers : { label : Str, site : Str, carers : List(Surreal.Linked(Carer)), leads : I64 }

## The read row: a linked site, and the edges that end at the kennel, each
## with its linked carer as a whole row.
kennel_carers : Try(Surreal.Prepared(List(KennelCarers)), Surreal.Error)
kennel_carers = Surreal.from(kennel_reads).select(|k| { label: k.label, site: k.site.name, carers: k.cares_for.list().map(|e| e.from), leads: k.cares_for.list().keep_if(|e| e.lead).len().to_i64_wrap() }).prepare({})

# --------------------------------------------------------------- the writes

quay : Kennel
quay = { id: "q", label: "Quay", site: sites.link("oslo") }

quay_wing : Kennel
quay_wing = { ..quay, label: "Quay wing" }

ida_quay : CaresFor
ida_quay = { id: "ida_q", from: carers.link("ida"), to: kennels.link("q"), lead: Bool.True }

new_carers : List(Carer)
new_carers = [{ id: "kim", name: "Kim" }, { id: "lea", name: "Lea" }]

## A new name for `kim`: an upsert replaces the row.
kim_b : Carer
kim_b = { id: "kim", name: "Kim B" }

## The carers that the delete finds: `kim` after the upsert, and `lea`.
kept_carers : List(Carer)
kept_carers = [kim_b, { id: "lea", name: "Lea" }]

## A reading written with `fevered` false: the database computes it.
noon : Vital
noon = { ..reading("a", "2026-03-10T12:00:00Z", 85, 39.4), fevered: Bool.False }

KennelLine : { label : Str, carers : I64 }

## A new label for a kennel, then the kennel read back: two `LET`s, an
## update and a query, in one request.
relabel : Try(Surreal.Prepared((Try(List(Kennel), Surreal.Error), Try(List(KennelLine), Surreal.Error))), Surreal.Error)
relabel = match (relabel_write, relabel_read) {
	(Ok(write), Ok(read)) => write.then(read)
	(Err(e), _) | (_, Err(e)) => Err(e)
}

relabel_write : Try(Surreal.Prepared(List(Kennel)), Surreal.Error)
relabel_write = kennels.update_by(|p, k| k.id == p.key, |p, k| { ..k, label: p.label }).prepare({ key: "q", label: "Quay wing" })

relabel_read : Try(Surreal.Prepared(List(KennelLine)), Surreal.Error)
relabel_read = Surreal.from(kennel_reads).filter_by(|p, k| k.id == p.key).select(|k| { label: k.label, carers: k.cares_for.list().len().to_i64_wrap() }).prepare({ key: "q" })

remove_carers : Try(Surreal.Prepared(List(Carer)), Surreal.Error)
remove_carers = carers.delete(|c| c.id == "kim" or c.id == "lea").prepare({})

remove_quay : Try(Surreal.Prepared(List(Kennel)), Surreal.Error)
remove_quay = kennels.delete_at(kennels.id("q")).prepare({})

# ------------------------------------------------- a table with a tag union

## Each form of an arm: no payload, a record, one value, two values.
Pay : [Cash, Card({ last4 : Str }), Check(I64), Wire(Str, I64)]

Payment : { id : Str, pay : Pay }

payments : Surreal.Table(Payment)
payments = Surreal.table("payment")

payment_schema : Try(Str, Surreal.Error)
payment_schema = Surreal.schema([payments.define().done()])

paid : List(Payment)
paid = [
	{ id: "cash", pay: Cash },
	{ id: "card", pay: Card({ last4: "4242" }) },
	{ id: "check", pay: Check(7) },
	{ id: "wire", pay: Wire("eu", 9) },
]

PaymentLine : { id : Str, amount : I64 }

## The amount of a payment: a `match` that reads a payload of each form.
payment_line : Payment -> PaymentLine
payment_line = |p| {
	id: p.id,
	amount: match p.pay {
		Cash => 0
		Card(_) => 1
		Check(n) => n
		Wire(_, n) => n
	},
}

insert_payments : Try(Surreal.Prepared(List(Payment)), Surreal.Error)
insert_payments = payments.insert(paid)

payment_rows : Try(Surreal.Prepared(List(Payment)), Surreal.Error)
payment_rows = Surreal.from(payments).select(|r| r).prepare({})

payment_lines : Try(Surreal.Prepared(List(PaymentLine)), Surreal.Error)
payment_lines = Surreal.from(payments).select(payment_line).prepare({})

# --------------------------------- a table with a union of nominal payloads

## A nominal of the app over a record: its payload is spread, as a record is.
Shelf := { aisle : Str, bin : I64 }.{
	is_eq : _
	encoder_for : _
	parser_for : _
}

Bin : { id : Str, label : Str }

## One payload of each kind: a geometry, which writes an object but is not a
## record, so it is `value`; a link; a datetime; a nominal record; and two
## values.
Place : [Away, At(Surreal.Point), Kept(Surreal.Link(Bin)), Since(Surreal.Datetime), Shelved(Shelf), Stacked(Str, I64)]

## The fields next to `place` give the payloads of the writes that read the
## row.
Placement : { id : Str, bin : Surreal.Link(Bin), at : Surreal.Datetime, aisle : Str, slot : I64, place : Place }

bins : Surreal.Table(Bin)
bins = Surreal.table("bin")

placements : Surreal.Table(Placement)
placements = Surreal.table("placement")

place_schema : Try(Str, Surreal.Error)
place_schema = Surreal.schema(place_defs)

## A bin's label is unique: a second bin with it is the server's `Unique`
## error, which names the field because the session knows the schema.
place_defs : List(Surreal.Defined)
place_defs = [bins.define().unique(|b| b.label).done(), placements.define().done()]

stock : List(Bin)
stock = [{ id: "b1", label: "Top" }]

## Another bin with the label of `b1`.
twin_bin : Bin
twin_bin = { id: "b2", label: "Top" }

## Bins with labels of their own.
side_bin : Bin
side_bin = { id: "b3", label: "Side" }

low_bin : Bin
low_bin = { id: "b4", label: "Low" }

bin_rows : Try(Surreal.Prepared(List(Bin)), Surreal.Error)
bin_rows = Surreal.from(bins).select(|r| r).prepare({})

## Two prepared statements in one request, each on its own (`then`).
batch : Try(Surreal.Prepared(a), Surreal.Error), Try(Surreal.Prepared(b), Surreal.Error) -> Try(Surreal.Prepared((Try(a, Surreal.Error), Try(b, Surreal.Error))), Surreal.Error)
batch = |first, second| first?.then(second?)

## Two prepared statements in one transaction.
atomic : Try(Surreal.Prepared(a), Surreal.Error), Try(Surreal.Prepared(b), Surreal.Error) -> Try(Surreal.Prepared((a, b)), Surreal.Error)
atomic = |first, second| Ok(first?.begin().then(second?)?.commit())

## Three prepared statements in one transaction: each `then` nests the pair.
atomic3 : Try(Surreal.Prepared(a), Surreal.Error), Try(Surreal.Prepared(b), Surreal.Error), Try(Surreal.Prepared(c), Surreal.Error) -> Try(Surreal.Prepared(((a, b), c)), Surreal.Error)
atomic3 = |first, second, third| Ok(first?.begin().then(second?)?.then(third?)?.commit())

## A create, then an insert whose second row has the label of `b1`, in
## one transaction: the unique index fails the insert, the second part,
## and the create is rolled back.
twin_in_transaction : Try(Surreal.Prepared((List(Bin), List(Bin))), Surreal.Error)
twin_in_transaction = atomic(bins.create(side_bin), bins.insert([low_bin, twin_bin]))

## The same create of a twin, then the bins, on their own: the create
## fails, and the read has its rows.
twin_then_rows : Try(Surreal.Prepared((Try(List(Bin), Surreal.Error), Try(List(Bin), Surreal.Error))), Surreal.Error)
twin_then_rows = batch(bins.create(twin_bin), bin_rows)

## A create, an insert and the bins after them, in one transaction.
stock_up : Try(Surreal.Prepared(((List(Bin), List(Bin)), List(Bin))), Surreal.Error)
stock_up = atomic3(bins.create(side_bin), bins.insert([low_bin]), bin_rows)

## A row at bin `b1`, aisle `d`, slot 2, since the start of the day.
placement : Str, Place -> Placement
placement = |id, place| { id, bin: bins.link("b1"), at: day_start, aisle: "d", slot: 2, place }

placed : List(Placement)
placed = [
	placement("away", Away),
	placement("at", At(here)),
	placement("kept", Kept(bins.link("b1"))),
	placement("since", Since(day_end)),
	placement("shelved", Shelved(Shelf.({ aisle: "b", bin: 4 }))),
	placement("stacked", Stacked("e", 5)),
]

place_rows : Try(Surreal.Prepared(List(Placement)), Surreal.Error)
place_rows = Surreal.from(placements).select(|r| r).prepare({})

## A union value written in the clause.
place_literal : Try(Surreal.Prepared(List(Placement)), Surreal.Error)
place_literal = placements.update_at(placements.id("away"), |p| { ..p, place: At(Surreal.point(5, 6)) }).prepare({})

## A union value bound as a parameter.
place_bound : Place -> Try(Surreal.Prepared(List(Placement)), Surreal.Error)
place_bound = |to| placements.update_at_by(placements.id("away"), |b, p| { ..p, place: b.to }).prepare({ to: to })

## A union value whose payload reads fields of the row: one patch for each
## kind of payload. SurrealDB computes it, and Roc computes it from the row.
since_at : Placement -> Placement
since_at = |p| { ..p, place: Since(p.at) }

kept_bin : Placement -> Placement
kept_bin = |p| { ..p, place: Kept(p.bin) }

shelved_slot : Placement -> Placement
shelved_slot = |p| { ..p, place: Shelved(Shelf.({ aisle: p.aisle, bin: p.slot })) }

stacked_slot : Placement -> Placement
stacked_slot = |p| { ..p, place: Stacked(p.aisle, p.slot) }

place_from_row : Code(Placement -> Placement) -> Try(Surreal.Prepared(List(Placement)), Surreal.Error)
place_from_row = |patch| placements.update_at(placements.id("away"), patch).prepare({})

# ------------------------------------------- tables whose keys the server makes

## A shift, written without its `id`: the server makes the key, a ULID
## (`default_by` on `id`).
Shift : { id : Str, label : Str }

## A task of a shift, with a UUID key that the server makes, as text. Its
## link holds the key that the server gave the shift.
Task : { id : Str, title : Str, shift : Surreal.Link(Shift) }

TaskRead : { id : Str, title : Str, shift : Surreal.Linked(Shift) }

## A handover from one shift to another: an edge with SurrealDB's own
## random key, as `id` has no default.
Handover : { id : Str, from : Surreal.Link(Shift), to : Surreal.Link(Shift), notes : Str }

shifts : Surreal.Table(Shift)
shifts = Surreal.table("shift")

tasks : Surreal.Table(Task)
tasks = Surreal.table("task")

task_reads : Surreal.Table(TaskRead)
task_reads = Surreal.table("task")

handovers : Surreal.Table(Handover)
handovers = Surreal.relation("handover", shifts, shifts)

shift_schema : Try(Str, Surreal.Error)
shift_schema = Surreal.schema(
	[
		shifts.define().default_by(|s| s.id, |_| Surreal.Rand.ulid()).done(),
		tasks.define().default_by(|t| t.id, |_| Surreal.Rand.uuid()).on_delete(shifts, Cascade).done(),
		handovers.define().done(),
		task_reads.define_read(),
	],
)

## A task, as written: no `id`.
NewTask : { title : Str, shift : Surreal.Link(Shift) }

TaskLine : { title : Str, shift : Str }

task_lines : Try(Surreal.Prepared(List(TaskLine)), Surreal.Error)
task_lines = Surreal.from(task_reads).select(|t| { title: t.title, shift: t.shift.label }).prepare({})

HandoverLine : { label : Str, to : List(Str) }

handover_lines : Try(Surreal.Prepared(List(HandoverLine)), Surreal.Error)
handover_lines = Surreal.from(shifts).outgoing(handovers).select(|(s, out)| { label: s.label, to: out.map(|h| h.to.get().label) }).prepare({})

## Whether the bytes of a key are `count` of `allowed`, with a `-` at each
## place of `dashes`.
key_shape : Str, U64, List(U64), (U8 -> Bool) -> Bool
key_shape = |key, count, dashes, allowed| {
	bytes = key.to_utf8()
	bytes.len() == count and bytes.map_with_index(|b, i| if (dashes.contains(i)) b == 45 else allowed(b)).all(|ok| ok)
}

is_digit : U8 -> Bool
is_digit = |b| b >= 48 and b <= 57

## A ULID: 26 characters of Crockford's base 32, upper case.
is_ulid : Str -> Bool
is_ulid = |key| key_shape(key, 26, [], |b| is_digit(b) or (b >= 65 and b <= 90 and b != 73 and b != 76 and b != 79 and b != 85))

## A UUID as text: 36 characters, lower-case hex with four dashes.
is_uuid : Str -> Bool
is_uuid = |key| key_shape(key, 36, [8, 13, 18, 23], |b| is_digit(b) or (b >= 97 and b <= 102))

## SurrealDB's random key: 20 lower-case letters and digits.
is_random : Str -> Bool
is_random = |key| key_shape(key, 20, [], |b| is_digit(b) or (b >= 97 and b <= 122))

# ------------------------------------------------------------- the verdicts

## Two lists of texts hold the same texts, each as many times.
same_texts : List(Str), List(Str) -> Bool
same_texts = |got, want| got.len() == want.len() and want.all(|w| got.count_if(|g| g == w) == want.count_if(|x| x == w))

## What a result is, next to what Roc computes: whether the two agree,
## and the text of the line. When they do not agree, the text has both.
Verdict : { agrees : Bool, text : Str }

## The verdict on a result that is not an error: `same` compares it, and
## `brief` is the text of a result that agrees.
judge : Try(a, Surreal.Error), a, (a, a -> Bool), (a -> Str) -> Verdict
judge = |got, want, same, brief| match got {
	Ok(value) if same(value, want) => { agrees: Bool.True, text: brief(value) }
	Ok(value) => { agrees: Bool.False, text: "${Str.inspect(value)}, Roc computes ${Str.inspect(want)}" }
	Err(e) => { agrees: Bool.False, text: Str.inspect(e) }
}

row_count : List(a) -> Str
row_count = |rows| if (rows.len() == 1) "1 row" else "${rows.len().to_str()} rows"

## The rows agree as a multiset, compared as text.
same_rows : List(a) -> (Try(List(a), Surreal.Error) -> Verdict)
same_rows = |want| |got| judge(got, want, |x, y| same_texts(x.map(Str.inspect), y.map(Str.inspect)), row_count)

## The row of one key, or `NotFound`, agrees.
same_one : Try(a, [NotFound]) -> (Try(Try(a, [NotFound]), Surreal.Error) -> Verdict)
same_one = |want| |got| judge(got, want, |x, y| Str.inspect(x) == Str.inspect(y), |found| if (found.is_ok()) "the row" else "no row")

## The rows agree in this order.
ordered_rows : List(a) -> (Try(List(a), Surreal.Error) -> Verdict)
ordered_rows = |want| |got| judge(got, want, |x, y| Str.inspect(x) == Str.inspect(y), Str.inspect)

## Two verdicts as one: it agrees when both agree.
joined : Verdict, Verdict -> Verdict
joined = |a, b| { agrees: a.agrees and b.agrees, text: "${a.text}, then ${b.text}" }

## Each result of a pair agrees with its verdict.
pair_of : (Try(a, Surreal.Error) -> Verdict), (Try(b, Surreal.Error) -> Verdict) -> (Try((a, b), Surreal.Error) -> Verdict)
pair_of = |first, second| |got| match got {
	Ok((a, b)) => joined(first(Ok(a)), second(Ok(b)))
	Err(e) => { agrees: Bool.False, text: Str.inspect(e) }
}

## Each result of a batch (`Prepared.then`), with its own error, agrees
## with its verdict.
each_of : (Try(a, Surreal.Error) -> Verdict), (Try(b, Surreal.Error) -> Verdict) -> (Try((Try(a, Surreal.Error), Try(b, Surreal.Error)), Surreal.Error) -> Verdict)
each_of = |first, second| |got| match got {
	Ok((a, b)) => joined(first(a), second(b))
	Err(e) => { agrees: Bool.False, text: Str.inspect(e) }
}

## The rows that a write made agree with `want` in its order, and each
## has a key of the table that `shape` accepts, which `kind` names, and
## another key than the others.
made_rows : Str, List(new), (Str -> Bool), Str -> (Try(List(Surreal.Created(row, new)), Surreal.Error) -> Verdict)
made_rows = |table, want, shape, kind| |got| match got {
	Ok(rows) => {
		keys = rows.map(|r| r.id.key())
		fine = Str.inspect(rows.map(|r| r.fields)) == Str.inspect(want) and rows.all(|r| r.id.table() == table and shape(r.id.key())) and keys.all(|k| keys.count_if(|o| o == k) == 1)
		if fine {
			{ agrees: Bool.True, text: "${row_count(rows)}, ${kind} keys" }
		} else {
			{ agrees: Bool.False, text: "${Str.inspect(rows.map(|r| (r.id.key(), r.fields)))}, Roc expects ${Str.inspect(want)} with ${kind} keys of `${table}`" }
		}
	}
	Err(e) => { agrees: Bool.False, text: Str.inspect(e) }
}

## The text of a reading: its record id and its fields.
facts : Vital -> Str
facts = |v| "${vitals.ref(v).map_ok(|r| r.to_str()) ?? "?"} pulse ${v.pulse.to_str()} temp_c ${v.temp_c.to_str()} fevered ${Str.inspect(v.fevered)}"

## The readings agree as a multiset of their texts. A `TimeKey` has no `==`.
same_readings : List(Vital) -> (Try(List(Vital), Surreal.Error) -> Verdict)
same_readings = |want| |got| judge(got, want, |x, y| same_texts(x.map(facts), y.map(facts)), |rows| Str.join_with(rows.map(facts), "; "))

## The server refuses the statement with the error that `expected`
## accepts, which `what` describes.
refused : (Surreal.ServerError -> Bool), Str -> (Try(a, Surreal.Error) -> Verdict)
refused = |expected, what| |got| match got {
	Err(Server(e)) if expected(e) => { agrees: Bool.True, text: "Server(${Str.inspect(e)})" }
	other => { agrees: Bool.False, text: "${Str.inspect(other)}, Roc expects ${what}" }
}

## The transaction failed at the part `at`, with the error that
## `expected` accepts.
aborted : U64, (Surreal.ServerError -> Bool), Str -> (Try(a, Surreal.Error) -> Verdict)
aborted = |at, expected, what| |got| match got {
	Err(Aborted(a)) if a.at == at and expected(a.error) => { agrees: Bool.True, text: "Aborted(${Str.inspect(a)})" }
	other => { agrees: Bool.False, text: "${Str.inspect(other)}, Roc expects `Aborted` at ${at.to_str()} with ${what}" }
}

## The record `kennel:q` exists.
quay_exists : Surreal.ServerError -> Bool
quay_exists = |e| match e {
	Exists({ what: "Record", name: "kennel:q", .. }) => Bool.True
	_ => Bool.False
}

## The unique index on `bin.label` holds the label.
label_taken : Surreal.ServerError -> Bool
label_taken = |e| match e {
	Unique({ table: "bin", fields: ["label"], value: "'Top'", .. }) => Bool.True
	_ => Bool.False
}

# ------------------------------------------------------------- the platform

## The transport of the session: a WebSocket through
## roc-basic-cli-websocket (`WsClient`, with `receive_within!`, so
## `Session.next_within!` can wait with a deadline), or HTTP through the platform's
## `Http.send!`. `Session.open!` takes either, and each query and write
## after it is the same on both.
transport : [WebSocket, Http] -> Surreal.Transport
transport = |over| match over {
	WebSocket => Surreal.Transport.websocket_timed(WsClient.connect, WsClient.ops, "ws://127.0.0.1:8000")
	Http => Surreal.Transport.http(http_client, "http://127.0.0.1:8000")
}

## The HTTP function of the session: each post is one `Http.send!`.
http_client : Surreal.HttpClient
http_client = {
	post!: |post| {
		request = post.headers.fold(
			Request.from_method(POST).with_uri(post.uri).with_body(post.body).with_timeout(TimeoutMilliseconds(10_000)),
			|r, h| r.add_header(h.name, h.value),
		)
		response = Http.send!(request, {}).map_err(Str.inspect)?
		Ok({ status: response.status(), body: response.body() })
	},
}

login : Surreal.Login
login = Root({ ns: "roc", db: "roc_surreal", user: "root", pass: "root" })

# ------------------------------------------------------------------ the run

## The session, the count of the lines that fail, and the folder that the
## replies go to when the app records.
Run : { session : Surreal.Session, failures : U64, record : [Keep(Str), Drop] }

## Sends one prepared statement and reads its result. When the app
## records, it sends the request with `query!` and saves the reply before
## it reads it; else it runs it with `run!`. A statement that fails is an
## error in the result, and the session goes on; a `Transport` or
## `WebSocket` error ends
## the run.
send! : Run, Str, Surreal.Prepared(out) => Try({ session : Surreal.Session, result : Try(out, Surreal.Error) }, Str)
send! = |run, name, prepared| match run.record {
	Keep(folder) => {
		done = Surreal.Unchecked.query!(run.session, prepared.request()).map_err(Str.inspect)?
		Path.unix("${folder}/${name}.cbor").write_bytes!(done.reply).map_err(Str.inspect)?
		Ok({ session: done.session, result: Surreal.Unchecked.result(done.session, prepared, done.reply) })
	}
	Drop => going(run.session.run!(prepared))
}

## A result, unless the connection failed.
going : { session : Surreal.Session, result : Try(out, Surreal.Error) } -> Try({ session : Surreal.Session, result : Try(out, Surreal.Error) }, Str)
going = |done| match done.result {
	Err(Transport(why)) => Err(why)
	Err(WebSocket(why)) => Err(Str.inspect(why))
	_ => Ok(done)
}

## Runs one prepared statement, and prints its result with the verdict.
check! : Run, Str, Try(Surreal.Prepared(out), Surreal.Error), (Try(out, Surreal.Error) -> Verdict) => Try(Run, Str)
check! = |run, name, prepared, verdict| kept!(run, name, prepared, verdict).map_ok(|done| done.run)

## [check!] that also gives the result to the steps after it.
kept! : Run, Str, Try(Surreal.Prepared(out), Surreal.Error), (Try(out, Surreal.Error) -> Verdict) => Try({ run : Run, result : Try(out, Surreal.Error) }, Str)
kept! = |run, name, prepared, verdict| {
	sent = match prepared {
		Ok(one) => send!(run, name, one)?
		Err(e) => { session: run.session, result: Err(e) }
	}
	Ok({ run: tell!(run, sent.session, name, verdict(sent.result))?, result: sent.result })
}

## The tables whose keys the server makes. Each write gives the rows it
## made with their keys, and the steps after it link to them, read them
## by key, and delete one by key.
server_keys! : Run => Try(Run, Str)
server_keys! = |run| {
	var $run = script!(run, "define_shifts", shift_schema)?
	early = kept!($run, "create_shift", shifts.create_new({ label: "Early" }), made_rows("shift", [{ label: "Early" }], is_ulid, "ULID"))?
	$run = early.run
	later = kept!($run, "insert_shifts", shifts.insert_new([{ label: "Late" }, { label: "Night" }]), made_rows("shift", [{ label: "Late" }, { label: "Night" }], is_ulid, "ULID"))?
	$run = later.run
	match (early.result, later.result) {
		(Ok([first]), Ok([second, _])) => {
			feed : NewTask
			feed = { title: "Feed", shift: shifts.link(first.id.key()) }
			walk : NewTask
			walk = { title: "Walk", shift: shifts.link(second.id.key()) }
			handover = { from: shifts.link(first.id.key()), to: shifts.link(second.id.key()), notes: "keys" }
			$run = check!($run, "insert_tasks", tasks.insert_new([feed, walk]), made_rows("task", [feed, walk], is_uuid, "UUID"))?
			$run = check!($run, "relate_handover", handovers.create_new(handover), made_rows("handover", [handover], is_random, "random"))?
			$run = check!($run, "shift_at_key", shifts.at(first.id).select(|r| r).prepare_one({}), same_one(Ok({ id: first.id.key(), label: "Early" })))?
			$run = check!($run, "task_lines", task_lines, same_rows([{ title: "Feed", shift: "Early" }, { title: "Walk", shift: "Late" }]))?
			$run = check!($run, "handover_lines", handover_lines, same_rows([{ label: "Early", to: ["Late"] }, { label: "Late", to: [] }, { label: "Night", to: [] }]))?
			# The delete of the shift cascades to its task, and SurrealDB
			# deletes the edge at it.
			$run = check!($run, "delete_shift", shifts.delete_at(first.id).prepare({}), same_rows([{ id: first.id.key(), label: "Early" }]))?
			$run = check!($run, "task_lines_after", task_lines, same_rows([{ title: "Walk", shift: "Late" }]))?
		}
		_ => {}
	}
	script!($run, "remove_shifts", Ok("REMOVE TABLE handover; REMOVE TABLE task; REMOVE TABLE shift;"))
}

## Prints a verdict, and counts it when it fails. The run goes on with
## `session`.
tell! : Run, Surreal.Session, Str, Verdict => Try(Run, Str)
tell! = |run, session, name, judged|
	if judged.agrees {
		say!("ok   ${name}: ${judged.text}")?
		Ok({ ..run, session })
	} else {
		say!("FAIL ${name}: ${judged.text}")?
		Ok({ ..run, session, failures: run.failures + 1 })
	}

## Two requests sent before either reply is read, and their replies read
## the last first. Over a WebSocket both are in flight together; over
## HTTP, `send!` waits for each reply and keeps it in the inbox.
pipelined! : Run, Try(Surreal.Prepared(a), Surreal.Error), (Try(a, Surreal.Error) -> Verdict), Try(Surreal.Prepared(b), Surreal.Error), (Try(b, Surreal.Error) -> Verdict) => Try(Run, Str)
pipelined! = |run, first, first_verdict, second, second_verdict| match (first, second) {
	(Ok(one), Ok(two)) => {
		sent_one = run.session.send!(one).map_err(Str.inspect)?
		sent_two = sent_one.session.send!(two).map_err(Str.inspect)?
		got_two = going(sent_two.session.await!(sent_two.ticket, two))?
		got_one = going(got_two.session.await!(sent_one.ticket, one))?
		judged_one = first_verdict(got_one.result)
		judged_two = second_verdict(got_two.result)
		tell!(run, got_one.session, "pipelined", { agrees: judged_one.agrees and judged_two.agrees, text: "${judged_two.text}, then ${judged_one.text}" })
	}
	(Err(e), _) | (_, Err(e)) => tell!(run, run.session, "pipelined", { agrees: Bool.False, text: Str.inspect(e) })
}

## A watch of the carers.
carer_watch : Try(Surreal.Watch(Carer), Surreal.Error)
carer_watch = Surreal.from(carers).select(|r| r).live({}, [])

## A watch on a session over HTTP is an `Unsupported` error, and the
## session goes on. A WebSocket session pushes, and the line is left out.
watch_over_http! : Run => Try(Run, Str)
watch_over_http! = |run|
	if run.session.pushes() {
		Ok(run)
	} else {
		judged = match carer_watch {
			Ok(watch) =>
				match run.session.live!(watch) {
					Err(Unsupported(why)) => { agrees: Bool.True, text: "Unsupported(${why})" }
					Ok(_) => { agrees: Bool.False, text: "a watch started on a session over HTTP" }
					Err(e) => { agrees: Bool.False, text: "${Str.inspect(e)}, Roc expects an `Unsupported` error" }
				}
			Err(e) => { agrees: Bool.False, text: Str.inspect(e) }
		}
		tell!(run, run.session, "watch_over_http", judged)
	}

## A watch that nothing writes to: `next_within!` gives `TimedOut` after
## 300 ms, and the watch goes on (it is killed after). A session over HTTP
## has no watch (`watch_over_http!`), and the line is left out.
watch_idle! : Run => Try(Run, Str)
watch_idle! = |run|
	if run.session.pushes() {
		match carer_watch {
			Ok(watch) => {
				started = run.session.live!(watch).map_err(Str.inspect)?
				waited = started.session.next_within!(started.live, 300).map_err(Str.inspect)?
				killed = waited.session.kill!(waited.live.lives()).map_err(Str.inspect)?
				judged = match waited.next {
					TimedOut => { agrees: Bool.True, text: "TimedOut after 300 ms, no change" }
					Got(changes) => { agrees: Bool.False, text: "${changes.len().to_str()} change(s) of a watch nothing writes to" }
					Ended => { agrees: Bool.False, text: "the watch ended" }
					Unread(e) => { agrees: Bool.False, text: Str.inspect(e) }
				}
				tell!(run, killed, "watch_idle", judged)
			}
			Err(e) => tell!(run, run.session, "watch_idle", { agrees: Bool.False, text: Str.inspect(e) })
		}
	} else {
		Ok(run)
	}

## Runs a script of statements with no rows, such as a schema. The line
## is `ok` when each statement is OK.
script! : Run, Str, Try(Str, Surreal.Error) => Try(Run, Str)
script! = |run, name, text| {
	done = match text {
		Ok(script) => Surreal.Unchecked.query!(run.session, script).map_err(Str.inspect)?
		Err(e) => return Err("${name}: ${Str.inspect(e)}")
	}
	statuses : Try({ result : List({ status : Str, result : Try(Str, [Missing]) }) }, Surreal.Error)
	statuses = Surreal.Unchecked.decode(done.reply)
	match statuses {
		Ok(reply) if reply.result.all(|s| s.status == "OK") => {
			say!("ok   ${name}: ${if (reply.result.len() == 1) "1 statement" else "${reply.result.len().to_str()} statements"}")?
			Ok({ ..run, session: done.session })
		}
		other => {
			say!("FAIL ${name}: ${Str.inspect(other)}")?
			Ok({ ..run, session: done.session, failures: run.failures + 1 })
		}
	}
}

## The queries and the writes in turn on one session.
run! : [Keep(Str), Drop], [WebSocket, Http] => Try(U64, Str)
run! = |record, over| {
	match record {
		Keep(folder) => Path.unix(folder).create_all!().map_err(Str.inspect)?
		Drop => {}
	}
	opened = Surreal.Session.open!(transport(over), login).map_err(Str.inspect)?
	session = opened.knowing(place_defs)
	var $run = { session, failures: 0, record }
	# The queries of `monitoring.roc`, on the rows that `check.py` leaves.
	$run = check!($run, "fevers", fevers, same_rows(kept_vitals.keep_if(|v| fever(v.temp_c, v.pulse)).map(vital_line)))?
	$run = check!($run, "kennel_a_rows", kennel_a_rows, same_readings(kept_vitals.keep_if(|v| v.id.within(kennel_a, day_start, day_end))))?
	$run = check!($run, "daily", daily, same_rows(rollup(kept_vitals)))?
	$run = check!($run, "busy_days", busy_days, same_rows(rollup(kept_vitals).keep_if(|d| d.readings >= 2)))?
	$run = check!($run, "fastest_pulses", fastest_pulses, ordered_rows(kept_vitals.sort_by_reversed(|v| v.pulse).take_first(3).map(|v| v.pulse).keep_if(|n| n < 130)))?
	$run = check!($run, "sites_covering", sites_covering, same_rows(["oslo"]))?
	$run = check!($run, "oslo_site", oslo_site, same_one(Ok(oslo)))?
	$run = check!($run, "oslo_value", oslo_value, same_one(Ok(oslo)))?
	$run = check!($run, "no_site", no_site, same_one(Err(NotFound)))?
	$run = check!($run, "kennel_carers", kennel_carers, same_rows(seed_kennels.map(|k| { label: k.kennel.label, site: k.site, carers: k.carers.map(Surreal.linked), leads: k.leads })))?
	$run = pipelined!($run, fevers, same_rows(kept_vitals.keep_if(|v| fever(v.temp_c, v.pulse)).map(vital_line)), sites_covering, same_rows(["oslo"]))?
	$run = watch_over_http!($run)?
	$run = watch_idle!($run)?
	# Writes of rows of its own, each deleted again.
	$run = check!($run, "create_kennel", kennels.create(quay), same_rows([quay]))?
	$run = check!($run, "create_kennel_again", kennels.create(quay), refused(quay_exists, "`Exists` of `kennel:q`"))?
	$run = check!($run, "relate_carer", cares_for.create(ida_quay), same_rows([ida_quay]))?
	$run = check!($run, "relabel_then_read", relabel, each_of(same_rows([quay_wing]), same_rows([{ label: "Quay wing", carers: 1 }])))?
	$run = check!($run, "insert_carers", carers.insert(new_carers), same_rows(new_carers))?
	$run = check!($run, "upsert_carer", carers.upsert(kim_b), same_rows([kim_b]))?
	$run = check!($run, "create_reading", vitals.create(noon), same_readings([{ ..noon, fevered: Bool.True }]))?
	$run = check!($run, "delete_reading", vitals.edit(Delete(noon)), same_readings([{ ..noon, fevered: Bool.True }]))?
	$run = check!($run, "unrelate_carer", cares_for.delete_at(cares_for.id(ida_quay.id)).prepare({}), same_rows([ida_quay]))?
	$run = check!($run, "delete_carers", remove_carers, same_rows(kept_carers))?
	$run = check!($run, "delete_kennel", remove_quay, same_rows([quay_wing]))?
	# A table of its own with a tag union: each form of an arm is written,
	# read back as `Pay`, and read in a `match` of a clause.
	$run = script!($run, "define_payments", payment_schema)?
	$run = check!($run, "insert_payments", insert_payments, same_rows(paid))?
	$run = check!($run, "payment_rows", payment_rows, same_rows(paid))?
	$run = check!($run, "payment_lines", payment_lines, same_rows(paid.map(payment_line)))?
	$run = script!($run, "remove_payments", Ok("REMOVE TABLE payment;"))?
	# A table of its own with a union of nominal payloads: each arm is
	# written, read back, and written in a clause and as a parameter.
	$run = script!($run, "define_places", place_schema)?
	$run = check!($run, "insert_bins", bins.insert(stock), same_rows(stock))?
	$run = check!($run, "insert_bin_again", bins.create(twin_bin), refused(label_taken, "`Unique` on `bin.label`"))?
	# Transactions: the failure of the insert rolls back the create before
	# it, and the bins are the stock. On their own, the create of the twin
	# fails and the read after it has its rows.
	$run = check!($run, "twin_in_transaction", twin_in_transaction, aborted(1, label_taken, "`Unique` on `bin.label`"))?
	$run = check!($run, "bins_after_abort", bin_rows, same_rows(stock))?
	$run = check!($run, "twin_then_rows", twin_then_rows, each_of(refused(label_taken, "`Unique` on `bin.label`"), same_rows(stock)))?
	$run = check!($run, "stock_up", stock_up, pair_of(pair_of(same_rows([side_bin]), same_rows([low_bin])), same_rows(List.concat(stock, [side_bin, low_bin]))))?
	$run = check!($run, "insert_places", placements.insert(placed), same_rows(placed))?
	$run = check!($run, "place_rows", place_rows, same_rows(placed))?
	$run = check!($run, "place_literal", place_literal, same_rows([placement("away", At(Surreal.point(5, 6)))]))?
	$run = check!($run, "place_bound_point", place_bound(At(here)), same_rows([placement("away", At(here))]))?
	$run = check!($run, "place_bound_link", place_bound(Kept(bins.link("b1"))), same_rows([placement("away", Kept(bins.link("b1")))]))?
	$run = check!($run, "place_bound_datetime", place_bound(Since(day_end)), same_rows([placement("away", Since(day_end))]))?
	$run = check!($run, "place_bound_shelf", place_bound(Shelved(Shelf.({ aisle: "c", bin: 1 }))), same_rows([placement("away", Shelved(Shelf.({ aisle: "c", bin: 1 })))]))?
	$run = check!($run, "place_bound_stack", place_bound(Stacked("f", 6)), same_rows([placement("away", Stacked("f", 6))]))?
	# Each payload read from the row, then the row read back.
	$run = check!($run, "place_row_datetime", place_from_row(since_at), same_rows([since_at(placement("away", Away))]))?
	$run = check!($run, "place_row_link", place_from_row(kept_bin), same_rows([kept_bin(placement("away", Away))]))?
	$run = check!($run, "place_row_shelf", place_from_row(shelved_slot), same_rows([shelved_slot(placement("away", Away))]))?
	$run = check!($run, "place_row_stack", place_from_row(stacked_slot), same_rows([stacked_slot(placement("away", Away))]))?
	$run = check!($run, "place_rows_after", place_rows, same_rows(placed.map(|p| if (p.id == "away") stacked_slot(p) else p)))?
	$run = script!($run, "remove_places", Ok("REMOVE TABLE placement; REMOVE TABLE bin;"))?
	# Tables of its own whose keys the server makes.
	$run = write_forms!(searches!(record_users!(totals!(server_keys!($run)?)?, over)?)?)?
	Ok($run.failures)
}

say! : Str => Try({}, Str)
say! = |line| Stdout.line!(line).map_err(Str.inspect)

## The arguments that are text.
texts_of : List([Utf8(Str), UnixBytes(List(U8)), WindowsU16s(List(U16))]) -> List(Str)
texts_of = |args| args.keep_oks(
	|arg| match arg {
		Utf8(text) => Ok(text)
		UnixBytes(bytes) => Str.from_utf8(bytes)
		WindowsU16s(_) => Err(NotText)
	},
)

## `--http` in the arguments: the session is over HTTP.
over_of : List(Str) -> [WebSocket, Http]
over_of = |texts| if (texts.contains("--http")) Http else WebSocket

## `--record DIR` in the arguments: the folder of the replies.
record_of : List(Str) -> [Keep(Str), Drop]
record_of = |texts| {
	match texts.find_first_index(|t| t == "--record") {
		Ok(at) =>
			match texts.get(at + 1) {
				Ok(folder) => Keep(folder)
				Err(_) => Drop
			}
		Err(_) => Drop
	}
}

main! = |args| match run!(record_of(texts_of(args)), over_of(texts_of(args))) {
	Ok(0) => Ok({})
	Ok(_) => Err(Exit(1))
	Err(problem) => {
		Stdout.line!("FAIL ${problem}")?
		Err(Exit(1))
	}
}

# ---------------------------------------------------------- GROUP ALL

VitalTotals : { readings : I64, pulses : I64, heat : Dec, mean_pulse : F64 }

## The totals of readings in Roc. For no readings they are the values that
## SurrealDB gives: 0, 0, 0 and `NaN`.
vital_totals : List(Vital) -> VitalTotals
vital_totals = |rows| { readings: rows.len().to_i64_wrap(), pulses: rows.map(|v| v.pulse).sum(), heat: rows.map(|v| v.temp_c).sum(), mean_pulse: Surreal.Math.mean(rows.map(|v| v.pulse.to_f64())) }

## `GROUP ALL`: one row of totals, also for a filter that no reading passes.
all_totals : Try(Surreal.Prepared(VitalTotals), Surreal.Error)
all_totals = Surreal.from(vitals).totals(vital_totals).prepare({})

no_totals : Try(Surreal.Prepared(VitalTotals), Surreal.Error)
no_totals = Surreal.from(vitals).filter(|v| v.pulse > 1000).totals(vital_totals).prepare({})

## The one row of totals agrees, compared as text (`NaN` is not `NaN`).
same_total : a -> (Try(a, Surreal.Error) -> Verdict)
same_total = |want| |got| judge(got, want, |x, y| Str.inspect(x) == Str.inspect(y), Str.inspect)

totals! : Run => Try(Run, Str)
totals! = |run| {
	var $run = check!(run, "all_totals", all_totals, same_total(vital_totals(kept_vitals)))?
	$run = check!($run, "no_totals", no_totals, same_total(vital_totals([])))?
	Ok($run)
}

# ---------------------------------------------------------- record users

# Users that sign up and sign in through an access method, and memos that
# each user reads and writes by its owner. The schema is the app's own:
# it defines it as the root user, and removes it at the end.

User : { id : Str, email : Str, pass : Str }

Memo : { id : Str, owner : Surreal.Link(User), text : Str, shared : Bool }

Credentials : { email : Str, pass : Str }

users : Surreal.Table(User)
users = Surreal.table("user")

memos : Surreal.Table(Memo)
memos = Surreal.table("memo")

accounts : Surreal.Access(Credentials, Credentials)
accounts = Surreal.access("account")

## A user reads its own row, without the hash of its password. A memo is
## read by its owner, and by every user when it is shared; only its
## owner writes it, and the text of a shared memo stays as it is.
account_schema : Try(Str, Surreal.Error)
account_schema = Surreal.schema(
	[
		users.define().unique(|u| u.email).permit([Select], |u| users.id(u.id) == users.auth()).deny_field(|u| u.pass, [Select]).done(),
		memos.define()
			.permit([Select], |m| m.owner.id() == users.auth() or m.shared)
			.permit([Create, Update, Delete], |m| m.owner.id() == users.auth())
			.permit_field(|m| m.text, [Update], |m| !m.shared)
			.on_delete(users, Cascade)
			.done(),
		accounts.define(users, |v| { email: v.email, pass: Surreal.Hash.argon2(v.pass) }, |v, u| u.email == v.email and Surreal.Hash.argon2_matches(u.pass, v.pass))
			.token_for(Surreal.Time.hours(1))
			.done(),
	],
)

scope : { ns : Str, db : Str }
scope = { ns: "roc", db: "roc_surreal" }

ann : Credentials
ann = { email: "ann@roc", pass: "ann's secret" }

bob : Credentials
bob = { email: "bob@roc", pass: "bob's secret" }

## The key of the user of the session: the one row of `user` that its
## permission lets it read.
whoami : Try(Surreal.Prepared(List(Str)), Surreal.Error)
whoami = Surreal.from(users).select_value(|u| u.id).prepare({})

memo_rows : Try(Surreal.Prepared(List(Memo)), Surreal.Error)
memo_rows = Surreal.from(memos).select(|r| r).prepare({})

## The memos of the user of the session, a clause that reads `$auth`.
mine : Try(Surreal.Prepared(List(Str)), Surreal.Error)
mine = Surreal.from(memos).filter(|m| m.owner.id() == users.auth()).select_value(|m| m.id).prepare({})

retext : Str, Str -> Try(Surreal.Prepared(List(Memo)), Surreal.Error)
retext = |key, text| memos.update_at_by(memos.id(key), |p, m| { ..m, text: p.text }).prepare({ text: text })

## One row, a key of a user.
one_key : Try(List(Str), Surreal.Error) -> Verdict
one_key = |got| match got {
	Ok([key]) => { agrees: Bool.True, text: "1 key, ${key}" }
	other => { agrees: Bool.False, text: "${Str.inspect(other)}, Roc expects the key of one user" }
}

denied : Surreal.ServerError -> Bool
denied = |e| match e {
	Denied(_) => Bool.True
	_ => Bool.False
}

## The link `owner` points at a user that the session cannot read, so its
## `record::exists` is false.
owner_unseen : Surreal.ServerError -> Bool
owner_unseen = |e| match e {
	Assert({ table: "memo", field: "owner", .. }) => Bool.True
	_ => Bool.False
}

## A session opened with `as_who`, or the error.
login! : [WebSocket, Http], Surreal.Login => Try(Try(Surreal.Session, Surreal.Error), Str)
login! = |over, as_who| Ok(Surreal.Session.open!(transport(over), as_who))

## A login that agrees: a session with a token.
signed! : Run, Str, [WebSocket, Http], Surreal.Login => Try({ run : Run, user : Try(Surreal.Session, Surreal.Error) }, Str)
signed! = |run, name, over, as_who| {
	user = login!(over, as_who)?
	judged = match user {
		Ok(session) if session.token().is_ok() => { agrees: Bool.True, text: "a session with a token" }
		Ok(_) => { agrees: Bool.False, text: "a session with no token" }
		Err(e) => { agrees: Bool.False, text: Str.inspect(e) }
	}
	Ok({ run: tell!(run, run.session, name, judged)?, user })
}

## A login that the server refuses: `Denied`.
refused_login! : Run, Str, [WebSocket, Http], Surreal.Login => Try(Run, Str)
refused_login! = |run, name, over, as_who| {
	judged = match login!(over, as_who)? {
		Err(Server(Denied(why))) => { agrees: Bool.True, text: "Server(Denied(${Str.inspect(why)}))" }
		Ok(_) => { agrees: Bool.False, text: "a session, Roc expects `Denied`" }
		Err(e) => { agrees: Bool.False, text: "${Str.inspect(e)}, Roc expects `Denied`" }
	}
	tell!(run, run.session, name, judged)
}

## [kept!] in the session of a user: the run goes on in its own session,
## and the user's session after the step comes back.
as! : Run, Surreal.Session, Str, Try(Surreal.Prepared(out), Surreal.Error), (Try(out, Surreal.Error) -> Verdict) => Try({ run : Run, user : Surreal.Session, result : Try(out, Surreal.Error) }, Str)
as! = |run, user, name, prepared, verdict| {
	done = kept!({ ..run, session: user }, name, prepared, verdict)?
	Ok({ run: { ..done.run, session: run.session }, user: done.run.session, result: done.result })
}

## The access method and its tables, the record users, and the logins
## that the server refuses. Then the root user removes them.
record_users! : Run, [WebSocket, Http] => Try(Run, Str)
record_users! = |run, over| {
	var $run = script!(run, "define_accounts", account_schema)?
	$run = memo_users!($run, over)?
	$run = refused_login!($run, "wrong_password", over, accounts.sign_in(scope, { ..ann, pass: "guess" }))?
	$run = refused_login!($run, "email_taken", over, accounts.sign_up(scope, ann))?
	ann_in = signed!($run, "signin_ann", over, accounts.sign_in(scope, ann))?
	$run = ann_in.run
	match ann_in.user {
		Ok(session) => {
			$run = as!($run, session, "signin_whoami", whoami, one_key)?.run
		}
		Err(_) => {}
	}
	script!($run, "remove_accounts", Ok("REMOVE ACCESS account ON DATABASE; REMOVE TABLE memo; REMOVE TABLE user;"))
}

## Ann and Bob sign up, each writes and reads memos, and each write of a
## memo of the other changes nothing: SurrealDB 3.3.4 leaves out the rows
## that a permission does not let a statement read or write, with no
## error (verified). Then Ann's session is invalidated, and Ann's token
## opens a session of its own.
memo_users! : Run, [WebSocket, Http] => Try(Run, Str)
memo_users! = |run, over| {
	ann_up = signed!(run, "signup_ann", over, accounts.sign_up(scope, ann))?
	bob_up = signed!(ann_up.run, "signup_bob", over, accounts.sign_up(scope, bob))?
	var $run = bob_up.run
	(ann_signed, bob_signed) = match (ann_up.user, bob_up.user) {
		(Ok(a), Ok(b)) => (a, b)
		_ => return Ok($run)
	}
	ann_me = as!($run, ann_signed, "whoami_ann", whoami, one_key)?
	bob_me = as!(ann_me.run, bob_signed, "whoami_bob", whoami, one_key)?
	$run = bob_me.run
	var $ann = ann_me.user
	var $bob = bob_me.user
	(ann_key, bob_key) = match (ann_me.result, bob_me.result) {
		(Ok([a]), Ok([b])) => (a, b)
		_ => return Ok($run)
	}
	note = { id: "ann_note", owner: users.link(ann_key), text: "Ann's own", shared: Bool.False }
	board = { id: "ann_board", owner: users.link(ann_key), text: "Ann's board", shared: Bool.True }
	bob_note = { id: "bob_note", owner: users.link(bob_key), text: "Bob's own", shared: Bool.False }
	renoted = { ..note, text: "Ann's new" }
	var $step = as!($run, $ann, "ann_writes", memos.insert([note, board]), same_rows([note, board]))?
	$ann = $step.user
	$step = as!($step.run, $bob, "bob_writes", memos.create(bob_note), same_rows([bob_note]))?
	$bob = $step.user
	# A memo of Ann's that Bob writes: its link to Ann does not pass
	# `record::exists`, as Bob cannot read Ann's row.
	$step = as!($step.run, $bob, "bob_forges", memos.create({ ..note, id: "forged" }), refused(owner_unseen, "`Assert` on `memo.owner`"))?
	$bob = $step.user
	$step = as!($step.run, $ann, "ann_reads", memo_rows, same_rows([note, board]))?
	$ann = $step.user
	$step = as!($step.run, $bob, "bob_reads", memo_rows, same_rows([board, bob_note]))?
	$bob = $step.user
	keys = as!($step.run, $bob, "bob_mine", mine, same_rows(["bob_note"]))?
	$bob = keys.user
	$step = { ..$step, run: keys.run }
	# Writes of a memo that Bob reads and may not write: no row.
	$step = as!($step.run, $bob, "bob_updates_ann", retext("ann_board", "Bob was here"), same_rows([]))?
	$bob = $step.user
	$step = as!($step.run, $bob, "bob_deletes_ann", memos.delete_at(memos.id("ann_board")).prepare({}), same_rows([]))?
	# The text of a shared memo stays: the field permission leaves it out
	# of the update, which returns the row.
	$step = as!($step.run, $ann, "ann_retexts_board", retext("ann_board", "New board"), same_rows([board]))?
	$ann = $step.user
	$step = as!($step.run, $ann, "ann_retexts_note", retext("ann_note", "Ann's new"), same_rows([renoted]))?
	$ann = $step.user
	$run = $step.run
	# After `invalidate`, the session is no one, and the server refuses it.
	# The token stays valid: a session of its own opens with it.
	token = match $ann.token() {
		Ok(t) => t
		Err(NoToken) => return tell!($run, $run.session, "token_ann", { agrees: Bool.False, text: "Ann's session has no token" })
	}
	$run = match $ann.invalidate!() {
		Ok(nobody) => as!($run, nobody, "invalidated_reads", memo_rows, refused(denied, "`Denied`"))?.run
		Err(e) => tell!($run, $run.session, "invalidate_ann", { agrees: Bool.False, text: Str.inspect(e) })?
	}
	again = signed!($run, "token_ann", over, Token(token))?
	match again.user {
		Ok(by_token) => as!(again.run, by_token, "token_reads", memo_rows, same_rows([renoted, board])).map_ok(|done| done.run)
		Err(_) => Ok(again.run)
	}
}

# ------------------------------------------------ full-text and vector search

## A note of a case, searched by its text and by its embedding. The
## table is the app's own: it defines it, and removes it at the end.
CaseNote : { id : Str, body : Str, embedding : List(F64) }

case_notes : Surreal.Table(CaseNote)
case_notes = Surreal.table("case_note")

case_terms : Surreal.Analyzer
case_terms = Surreal.analyzer("case_terms", [Blank, Class], [Lowercase])

case_text : Surreal.FullText(CaseNote)
case_text = case_notes.text_index(|n| n.body, case_terms)

case_vectors : Surreal.VectorIndex(CaseNote)
case_vectors = case_notes.vector_index(|n| n.embedding, { dimension: 2, distance: Euclidean })

case_schema : Try(Str, Surreal.Error)
case_schema = Surreal.schema([case_terms.define(), case_notes.define().text_index(case_text).vector_index(case_vectors).done()])

seed_case_notes : List(CaseNote)
seed_case_notes = [
	{ id: "n1", body: "Coughing at night, mild fever.", embedding: [0.0, 1.0] },
	{ id: "n2", body: "Fever gone, eating well.", embedding: [1.0, 1.0] },
	{ id: "n3", body: "Night cough again; X-ray booked.", embedding: [0.2, 0.9] },
	{ id: "n4", body: "Booster given.", embedding: [3.0, 0.0] },
	{ id: "n5", body: "Nail trim, no signs of pain.", embedding: [2.0, 2.0] },
]

## A cough: the probe of the nearest notes.
cough : List(F64)
cough = [0.1, 0.8]

Ranked : { id : Str, score : F64, marked : Str }

## The notes of a fever, the best first, with the term marked.
ranked_notes : Try(Surreal.Prepared(List(Ranked)), Surreal.Error)
ranked_notes = Surreal.from(case_notes).search(case_text, "fever").select(|(n, hit)| { id: n.id, score: hit.score(), marked: hit.highlight("*", "*") }).order_by(|r| r.score, Desc).prepare({})

Close : { id : Str, distance : F64 }

## The two notes nearest a cough, every row measured, the nearest first.
close_notes : Try(Surreal.Prepared(List(Close)), Surreal.Error)
close_notes = Surreal.from(case_notes).nearest(case_vectors, cough, Exact(2)).select(|(n, near)| { id: n.id, distance: near.distance() }).order_by(|r| r.distance, Asc).prepare({})

## The same through the HNSW graph, with a filter of the text.
close_coughs : Try(Surreal.Prepared(List(Str)), Surreal.Error)
close_coughs = Surreal.from(case_notes).filter(|n| n.id != "n3").nearest(case_vectors, cough, Approx({ k: 1, ef: 40 })).select_value(|(n, _)| n.id).prepare({})

## The Roc meaning of `nearest` by the euclidean distance: the rows
## sorted by their distance from the probe, the first `k`.
nearest_notes : List(CaseNote), U64 -> List(Close)
nearest_notes = |rows, k| rows
	.map(|n| { id: n.id, distance: Surreal.Vector.distance_euclidean(n.embedding, cough) })
	.sort_with(|a, b| if (a.distance < b.distance) Before else if (a.distance > b.distance) After else Same)
	.take_first(k)

## The rows of a search: the notes that the analyzer keeps, as Roc
## computes them, each with a score above 0, the best first, and the
## highlights as written. The score has no Roc meaning.
ranked : List(Ranked) -> (Try(List(Ranked), Surreal.Error) -> Verdict)
ranked = |want| |got| {
	kept = seed_case_notes.keep_if(|n| case_terms.matches(n.body, "fever")).map(|n| n.id)
	same : List(Ranked), List(Ranked) -> Bool
	same = |rows, expected| {
		scores = rows.map(|r| r.score)
		descending = List.map2(scores, scores.drop_first(1), |a, b| a >= b).all(|ok| ok)
		same_texts(rows.map(|r| r.id), kept) and rows.map(|r| { id: r.id, marked: r.marked }) == expected.map(|r| { id: r.id, marked: r.marked }) and scores.all(|s| s > 0) and descending
	}
	judge(got, want, same, |rows| "${row_count(rows)}, scores ${Str.inspect(rows.map(|r| r.score))}")
}

## The search and the nearest notes on a table of its own.
searches! : Run => Try(Run, Str)
searches! = |run| {
	var $run = script!(run, "define_case_notes", case_schema)?
	$run = check!($run, "insert_case_notes", case_notes.insert(seed_case_notes), same_rows(seed_case_notes))?
	$run = check!($run, "ranked_notes", ranked_notes, ranked([{ id: "n2", score: 0, marked: "*Fever* gone, eating well." }, { id: "n1", score: 0, marked: "Coughing at night, mild *fever*." }]))?
	# Over a `List(F64)` by `EUCLIDEAN`, the distance of every row
	# measured is the Roc distance to the bit (verified on 3.3.4).
	$run = check!($run, "close_notes", close_notes, ordered_rows(nearest_notes(seed_case_notes, 2)))?
	$run = check!($run, "close_coughs", close_coughs, same_rows(nearest_notes(seed_case_notes.keep_if(|n| n.id != "n3"), 1).map(|c| c.id)))?
	script!($run, "remove_case_notes", Ok("REMOVE TABLE case_note; REMOVE ANALYZER case_terms;"))
}

# ------------------------------------------- merge, patch, insert or update

import cbor.Cbor

## A row with an object and a list, on a table of its own: the app defines
## it, and removes it at the end.
Tally : { id : Str, label : Str, hits : I64, meta : { a : I64, b : I64 }, tags : List(Str) }

tallies : Surreal.Table(Tally)
tallies = Surreal.table("tally")

tally_schema : Try(Str, Surreal.Error)
tally_schema = Surreal.schema([tallies.define().done()])

tally : Str, Str, I64 -> Tally
tally = |id, label, hits| { id, label, hits, meta: { a: 1, b: 2 }, tags: [] }

seed_tallies : List(Tally)
seed_tallies = [tally("t1", "One", 1), tally("t2", "Two", 20)]

## The stored tally takes the new label, and the hits add up. It is the
## patch of `insert_or_update`, with the new row at `$input`, and Roc's own
## merge of a row that exists.
bump : Tally, Tally -> Tally
bump = |new, old| { ..old, label: new.label, hits: old.hits + new.hits }

## A tally of a key that exists and one that does not.
incoming : List(Tally)
incoming = [tally("t1", "Uno", 5), tally("t3", "Three", 3)]

bumped : List(Tally)
bumped = seed_tallies.map(|old| match incoming.find_first(|n| n.id == old.id) {
		Ok(new) => bump(new, old)
		Err(_) => old
	}).concat(incoming.keep_if(|n| !seed_tallies.any(|o| o.id == n.id)))

with_tally : List(Tally), Str, (Tally -> Tally) -> List(Tally)
with_tally = |rows, id, change| rows.map(|t| if (t.id == id) change(t) else t)

tally_rows : Try(Surreal.Prepared(List(Tally)), Surreal.Error)
tally_rows = Surreal.from(tallies).select(|r| r).prepare({})

## `MERGE`: a record of only the fields to change. `meta` is merged into
## the stored object, so `b` stays.
retitle : { label : Str, meta : { a : I64 } }
retitle = { label: "Merged", meta: { a: 9 } }

merged : List(Tally)
merged = with_tally(bumped, "t1", |t| { ..t, label: retitle.label, meta: { ..t.meta, a: retitle.meta.a } })

## `UPSERT .. MERGE` of a key that has no row: the record holds every field.
four : Tally
four = { id: "t4", label: "Four", hits: 12, meta: { a: 3, b: 4 }, tags: ["new"] }

four_fields : { label : Str, hits : I64, meta : { a : I64, b : I64 }, tags : List(Str) }
four_fields = { label: four.label, hits: four.hits, meta: four.meta, tags: four.tags }

with_four : List(Tally)
with_four = merged.append(four)

hot : List(Tally)
hot = with_four.keep_if(|t| t.hits > 10).map(|t| { ..t, tags: ["hot"] })

## JSON Patch ops: a replace, an add at the end of a list, a replace below an object.
patch_ops : List(Surreal.Op)
patch_ops = [Replace(["label"], Cbor.Value.Text("Patched")), Add(["tags", "-"], Cbor.Value.Text("p")), Replace(["meta", "b"], Cbor.Value.Int(7))]

patched_three : Tally -> Tally
patched_three = |t| { ..t, label: "Patched", tags: t.tags.append("p"), meta: { ..t.meta, b: 7 } }

## The server refuses a path that the row does not have.
no_such_field : Surreal.ServerError -> Bool
no_such_field = |e| e.message().contains("no such field")

write_forms! : Run => Try(Run, Str)
write_forms! = |run| {
	var $run = script!(run, "define_tallies", tally_schema)?
	$run = check!($run, "insert_tallies", tallies.insert(seed_tallies), same_rows(seed_tallies))?
	$run = check!($run, "insert_or_update", tallies.insert_or_update(incoming, bump), same_rows(incoming.map(|n| bumped.find_first(|t| t.id == n.id) ?? n)))?
	$run = check!($run, "tallies_bumped", tally_rows, same_rows(bumped))?
	$run = check!($run, "merge_at", tallies.merge_at(tallies.id("t1"), retitle), same_rows(merged.keep_if(|t| t.id == "t1")))?
	$run = check!($run, "upsert_merge_at", tallies.upsert_merge_at(tallies.id("t4"), four_fields), same_rows([four]))?
	$run = check!($run, "merge_where", tallies.merge(|t| t.hits > 10, { tags: ["hot"] }), same_rows(hot))?
	$run = check!($run, "patch_ops_at", tallies.patch_ops_at(tallies.id("t3"), patch_ops), same_rows(bumped.keep_if(|t| t.id == "t3").map(patched_three)))?
	$run = check!($run, "patch_no_such_field", tallies.patch_ops_at(tallies.id("t3"), [Replace(["nope"], Cbor.Value.Int(1))]), refused(no_such_field, "a server error about `nope`"))?
	script!($run, "remove_tallies", Ok("REMOVE TABLE tally;"))
}

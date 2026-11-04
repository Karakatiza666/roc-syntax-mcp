## Database functions, a time series, geometry, a view, read rows and live queries: prints a SurrealQL script, no platform and no server.
# Database functions, time series, geometry, views and live queries, on a
# monitoring domain: sites, the kennels at them, and the vital signs of the
# animals in the kennels. Read `main.roc` first for the basic API.
#
# `fever` is one Roc function. `Surreal.function` makes it `fn::fever` in the
# schema, a query calls it in a `WHERE`, a computed field calls it on every
# write, and a view counts it per day. The `-- roc:` reference of each block
# runs the same `fever` in Roc over the seed rows.
#
# A reading is keyed by its kennel and its time, `vital:[kennel:⟨a⟩, d'..']`:
# a query reads one range of keys, a group buckets the readings by day with
# `Time.floor`, and the view `vital_daily` keeps that rollup in the database.
# Filters of result rows read a projection in the same `SELECT`, and a group,
# an order or a limit as a subquery.
#
# A site has a location and an area. A query finds the sites whose area holds
# a point, and the sites near it, with the point as a parameter.
#
# A read row of a kennel reads its site through a `Linked` field and its
# carers through an `In` field named for the edge table, with no `.get()`
# and no `incoming`. A query of kennels reads the rows of the readings in a
# clause: a count per kennel, and a semi join.
#
# Live queries keep a result current: the fevered readings, the readings
# above a parameter, the daily view, and the kennels with no carer, whose
# carers are the edges `cares_for`, once with `incoming` and once through the
# read row. A watch of the kennels with a fever reads the readings in its
# filter. Each `-- live:` block starts the watch,
# makes writes, and compares the server's notices with the notices that the
# Roc Mirror predicts from the same functions.
#
# `roc examples/monitoring.roc` prints a script in the block format of
# `tests/check.py`, which also runs it, after the scripts of `main.roc` and
# `tests/BuiltinsTest.roc`. The `-- roc:` lines and the `-- live:` blocks are
# that check. Skip them when reading. Its tables are the ones that
# `watch.roc`, `client.roc` and `server.roc` use.

app [main!] { surreal: "https://github.com/Karakatiza666/roc-reify-surrealdb/releases/download/0.0.1/7MmdAaAt5bThg6ih3nR9ewVgw4CtNGvuK5HNQhEgZoSV.tar.zst" }

import surreal.Surreal

Site : { id : Str, name : Str, location : Surreal.Point, area : Surreal.Polygon }

Kennel : { id : Str, label : Str, site : Surreal.Link(Site) }

Vital : { id : Surreal.TimeKey(Surreal.Id(Kennel)), pulse : I64, temp_c : Dec, fevered : Bool }

Carer : { id : Str, name : Str }

## A carer looks after a kennel: an edge from the carer to the kennel.
CaresFor : { id : Str, from : Surreal.Link(Carer), to : Surreal.Link(Kennel), lead : Bool }

## A carer checks a kennel: a second edge from the carer to the kennel.
Checks : { id : Str, from : Surreal.Link(Carer), to : Surreal.Link(Kennel), note : Str }

sites : Surreal.Table(Site)
sites = Surreal.table("site")

kennels : Surreal.Table(Kennel)
kennels = Surreal.table("kennel")

vitals : Surreal.Table(Vital)
vitals = Surreal.table("vital")

carers : Surreal.Table(Carer)
carers = Surreal.table("carer")

cares_for : Surreal.Table(CaresFor)
cares_for = Surreal.relation("cares_for", carers, kennels)

checks : Surreal.Table(Checks)
checks = Surreal.relation("checks", carers, kennels)

## The read row of an edge of `cares_for`: the carer through the link.
CareRead : { id : Str, from : Surreal.Linked(Carer), to : Surreal.Link(Kennel), lead : Bool }

## The read row of a kennel: the site through the link, and the edges of
## `cares_for` that end at the kennel. It is for queries only. The schema
## checks it against `Kennel` (`kennel_read_def`).
KennelRead : { id : Str, label : Str, site : Surreal.Linked(Site), cares_for : Surreal.In(CareRead) }

kennel_reads : Surreal.Table(KennelRead)
kennel_reads = Surreal.table("kennel")

kennel_a : Surreal.Id(Kennel)
kennel_a = kennels.id("a")

# ------------------------------------------------------- database functions

## A fever: a high temperature or a fast pulse.
fever : Dec, I64 -> Bool
fever = |temp_c, pulse| temp_c > 39.0 or pulse > 120

fever_fn : Surreal.DbFn((Dec, I64 -> Bool))
fever_fn = Surreal.db_fn("fever", fever)

expect fever_fn.call2(39.5, 80)
expect fever_fn.call2(38.0, 130)
expect !fever_fn.call2(39.0, 120)

# ------------------------------------------------------------------- schema

site_def : Surreal.Defined
site_def = sites.define().done()

kennel_def : Surreal.Defined
kennel_def = kennels.define().done()

carer_def : Surreal.Defined
carer_def = carers.define().done()

cares_for_def : Surreal.Defined
cares_for_def = cares_for.define().done()

checks_def : Surreal.Defined
checks_def = checks.define().done()

kennel_read_def : Surreal.Defined
kennel_read_def = kennel_reads.define_read()

vital_def : Surreal.Defined
vital_def =
	vitals.define()
		.computed(|v| v.fevered, |v| fever_fn.call2(v.temp_c, v.pulse))
		.changefeed(Surreal.Time.days(7))
		.done()

# ------------------------------------------------------- the daily rollup

DayKey : { kennel : Surreal.Id(Kennel), day : Surreal.Datetime }

## The kennel and the day of a reading: the parts of its key.
day_of : Vital -> DayKey
day_of = |v| { kennel: v.id.series(), day: Surreal.Time.floor(v.id.time(), Surreal.Time.days(1)) }

Daily : { kennel : Surreal.Id(Kennel), day : Surreal.Datetime, readings : I64, fevers : I64 }

day_line : DayKey, List(Vital) -> Daily
day_line = |k, rows| { kennel: k.kennel, day: k.day, readings: rows.len().to_i64_wrap(), fevers: rows.keep_if(|v| fever_fn.call2(v.temp_c, v.pulse)).len().to_i64_wrap() }

## The same rollup that SurrealDB keeps, as a table to read from.
daily : Surreal.Table(Daily)
daily = Surreal.view("vital_daily")

daily_def : Surreal.Defined
daily_def = daily.define_as(Surreal.from(vitals).group_by(day_of), day_line).done()

# -------------------------------------------------------------------- seeds

## A rectangle from its south-west corner to its north-east corner, its ring closed.
rectangle : Surreal.Point, Surreal.Point -> Surreal.Polygon
rectangle = |sw, ne| {
	se = Surreal.point(ne.lon(), sw.lat())
	nw = Surreal.point(sw.lon(), ne.lat())
	Surreal.Polygon.({ exterior: [sw, se, ne, nw, sw], holes: [] })
}

seed_sites : List(Site)
seed_sites = [
	{ id: "oslo", name: "Oslo", location: Surreal.point(10.75, 59.91), area: rectangle(Surreal.point(10.6, 59.85), Surreal.point(10.9, 60.0)) },
	# case: about 33 km from the point of the queries, so near it, and its area does not hold the point
	{ id: "drammen", name: "Drammen", location: Surreal.point(10.2, 59.74), area: rectangle(Surreal.point(10.1, 59.7), Surreal.point(10.3, 59.8)) },
	{ id: "bergen", name: "Bergen", location: Surreal.point(5.32, 60.39), area: rectangle(Surreal.point(5.2, 60.3), Surreal.point(5.45, 60.45)) },
]

seed_kennels : List(Kennel)
seed_kennels = [
	{ id: "a", label: "North", site: sites.link("oslo") },
	{ id: "b", label: "South", site: sites.link("bergen") },
]

jon : Carer
jon = { id: "jon", name: "Jon" }

seed_carers : List(Carer)
seed_carers = [{ id: "ida", name: "Ida" }, jon]

## Kennel `a` has a carer, and kennel `b` has none.
seed_cares_for : List(CaresFor)
seed_cares_for = [{ id: "ida_a", from: carers.link("ida"), to: kennels.link("a"), lead: Bool.True }]

moment : Str -> Surreal.Datetime
moment = |text| match Surreal.datetime(text) {
	Ok(d) => d
	Err(_) => crash "a valid datetime"
}

## A reading. `fevered` is false: the computed field of the database sets it.
reading : Str, Str, I64, Dec -> Vital
reading = |kennel, at, pulse, temp_c| { id: Surreal.time_key(kennels.id(kennel), moment(at)), pulse, temp_c, fevered: Bool.False }

## A reading as the database stores it, with the computed field run in Roc.
stored : Vital -> Vital
stored = |v| { ..v, fevered: fever(v.temp_c, v.pulse) }

seed_vitals : List(Vital)
seed_vitals = [
	# case: the day before, which the retention write deletes
	reading("a", "2026-02-28T23:00:00Z", 70, 38.0),
	# case: exactly the lower bound of `kennel_a_day`, which is in the range
	reading("a", "2026-03-01T00:00:00Z", 82, 38.4),
	reading("a", "2026-03-01T08:00:00Z", 80, 38.5),
	reading("a", "2026-03-01T14:30:00Z", 90, 39.5),
	# case: exactly the upper bound of `kennel_a_day`, which is not in the range
	reading("a", "2026-03-02T00:00:00Z", 85, 38.6),
	reading("a", "2026-03-02T09:15:00Z", 125, 38.0),
	# case: both values exactly at the limit are no fever
	reading("b", "2026-03-01T10:00:00Z", 120, 39.0),
	# case: half a second before midnight is the day before
	reading("b", "2026-03-01T23:59:59.5Z", 130, 38.0),
	reading("b", "2026-03-02T11:00:00Z", 121, 39.1),
]

# ------------------------------------------------------------------ queries

VitalLine : { kennel : Surreal.Id(Kennel), at : Surreal.Datetime, pulse : I64, temp_c : Dec }

vital_line : Vital -> VitalLine
vital_line = |v| { kennel: v.id.series(), at: v.id.time(), pulse: v.pulse, temp_c: v.temp_c }

## The key as a whole: the array `[kennel, time]` that `record::id(id)` reads.
FlagLine : { id : Surreal.TimeKey(Surreal.Id(Kennel)), fevered : Bool, hot : Bool }

## The computed field, and the same call in a projection.
flag_line : Vital -> FlagLine
flag_line = |v| { id: v.id, fevered: v.fevered, hot: fever_fn.call2(v.temp_c, 0) }

HotLine : { kennel : Surreal.Id(Kennel), hot : Bool }

## The kennel of a reading, and whether it is a fever.
hot_line : Vital -> HotLine
hot_line = |v| { kennel: v.id.series(), hot: fever_fn.call2(v.temp_c, v.pulse) }

KennelFevers : { kennel : Surreal.Id(Kennel), fevers : I64 }

kennel_fevers : Surreal.Id(Kennel), List(HotLine) -> KennelFevers
kennel_fevers = |k, rows| { kennel: k, fevers: rows.len().to_i64_wrap() }

## The rows with the highest pulse first, in Roc.
fastest : List(Vital), U64 -> List(Vital)
fastest = |rows, n| rows.sort_by_reversed(|v| v.pulse).take_first(n)

# --------------------------------------------------------------- the script

KennelCarers : { label : Str, site : Str, carers : List(Carer), leads : I64 }

## A kennel, its site and its carers, in Roc from the stored rows.
kennel_carers : Kennel -> KennelCarers
kennel_carers = |k| {
	edges = seed_cares_for.keep_if(|e| e.to.id() == kennels.id(k.id))
	site = seed_sites.keep_if(|s| sites.id(s.id) == k.site.id()).map(|s| s.name)
	{
		label: k.label,
		site: Str.join_with(site, ""),
		carers: edges.join_map(|e| seed_carers.keep_if(|c| carers.id(c.id) == e.from.id())),
		leads: edges.keep_if(|e| e.lead).len().to_i64_wrap(),
	}
}

KennelReadings : { label : Str, readings : I64 }

## The readings of a kennel, in Roc.
readings_of : List(Vital), Kennel -> List(Vital)
readings_of = |rows, k| rows.keep_if(|v| v.id.series() == kennels.id(k.id))

## Whether a kennel has a fevered reading, in Roc.
has_fever : List(Vital), Kennel -> Bool
has_fever = |rows, k| readings_of(rows, k).any(|v| v.fevered)

## A point in Oslo, the parameter of the queries of sites.
here : Surreal.Point
here = Surreal.point(10.75, 59.91)

SiteLat : { id : Str, lat : F64 }

site_lat : Site -> SiteLat
site_lat = |s| { id: s.id, lat: s.location.lat() }

## One block: the statement, then the Roc result for the same question.
block : Str, Try(Surreal.Prepared(out), Surreal.Error), Try(Str, Surreal.Error) -> Str
block = |header, prepared, reference| match (prepared, reference) {
	(Ok(p), Ok(literal)) => p.statement().block(header, ["-- roc: ${literal}"])
	(Err(e), _) | (_, Err(e)) => "-- unsupported ${header}: ${Str.inspect(e)}"
}

## One result row for each kennel and day, in Roc.
rollup : List(Vital) -> List(Daily)
rollup = |rows| {
	keys = rows.map(day_of).fold([], |seen, k| if (seen.contains(k)) seen else seen.append(k))
	keys.map(|k| day_line(k, rows.keep_if(|v| day_of(v) == k)))
}

## One write block: the write, then the read whose result is compared.
then_read : Try(Surreal.Prepared(a), Surreal.Error), Try(Surreal.Prepared(b), Surreal.Error) -> Try(Surreal.Prepared((Try(a, Surreal.Error), Try(b, Surreal.Error))), Surreal.Error)
then_read = |write, read| match (write, read) {
	(Ok(a), Ok(b)) => a.then(b)
	(Err(e), _) | (_, Err(e)) => Err(e)
}

day_start : Surreal.Datetime
day_start = moment("2026-03-01T00:00:00Z")

day_end : Surreal.Datetime
day_end = moment("2026-03-02T00:00:00Z")

## The definitions of the schema. A live query takes them too: a link of
## a watched row finds its table here.
definitions : List(Surreal.Defined)
definitions = [Surreal.function(|_| fever_fn), site_def, kennel_def, carer_def, cares_for_def, checks_def, vital_def, daily_def, kennel_read_def]

schema_block : Str
schema_block = match Surreal.schema(definitions) {
	Ok(text) => "-- schema\n${text}"
	Err(e) => "-- bad schema: ${Str.inspect(e)}"
}

## One seed block for a table, in the block format of `check.py`.
seed : Str, Try(Surreal.Prepared(List(row)), Surreal.Error) -> Str
seed = |name, prepared| match prepared {
	Ok(p) => p.statement().block("-- seed: ${name}", [])
	Err(e) => "-- unsupported -- seed: ${name}: ${Str.inspect(e)}"
}

seed_blocks : List(Str)
seed_blocks = [
	seed("site", sites.insert(seed_sites)),
	seed("kennel", kennels.insert(seed_kennels)),
	seed("carer", carers.insert(seed_carers)),
	seed("cares_for", cares_for.insert(seed_cares_for)),
	seed("vital", vitals.insert(seed_vitals)),
]

queries : List(Str)
queries = [
	block(
		"-- query: fevers",
		Surreal.from(vitals).filter(|v| fever_fn.call2(v.temp_c, v.pulse)).select(vital_line).prepare({}),
		Surreal.Mirror.literal(seed_vitals.keep_if(|v| fever(v.temp_c, v.pulse)).map(vital_line)),
	),
	block("-- query: fever_flags", Surreal.from(vitals).select(flag_line).prepare({}), Surreal.Mirror.literal(seed_vitals.map(|v| flag_line(stored(v))))),
	block(
		"-- query: kennel_a_day",
		Surreal.from(vitals).between(kennel_a, day_start, day_end).select(vital_line).prepare({}),
		Surreal.Mirror.literal(seed_vitals.keep_if(|v| v.id.within(kennel_a, day_start, day_end)).map(vital_line)),
	),
	# The whole rows, with the key as the array `[kennel, time]`.
	block(
		"-- query: kennel_a_rows",
		Surreal.from(vitals).between(kennel_a, day_start, day_end).select(|r| r).prepare({}),
		Surreal.Mirror.literal(seed_vitals.keep_if(|v| v.id.within(kennel_a, day_start, day_end)).map(stored)),
	),
	block("-- query: daily", Surreal.from(vitals).group_by(day_of).aggregate(day_line).prepare({}), Surreal.Mirror.literal(rollup(seed_vitals))),
	# A filter of the result rows. After a projection it is in the same
	# `WHERE`, and reads the projection's fields over the row.
	block(
		"-- query: fever_lines",
		Surreal.from(vitals).select(vital_line).filter(|l| fever_fn.call2(l.temp_c, l.pulse)).prepare({}),
		Surreal.Mirror.literal(seed_vitals.map(vital_line).keep_if(|l| fever(l.temp_c, l.pulse))),
	),
	# After a group it reads a subquery: SQL's `HAVING`. The days with a
	# reading that is not a fever.
	block(
		"-- query: mixed_days",
		Surreal.from(vitals).group_by(day_of).aggregate(day_line).filter(|d| d.fevers < d.readings).prepare({}),
		Surreal.Mirror.literal(rollup(seed_vitals).keep_if(|d| d.fevers < d.readings)),
	),
	# After an order and a limit it reads a subquery, and keeps the order.
	block(
		"-- query: fastest_cool",
		Surreal.from(vitals).select(vital_line).order_by(|l| l.pulse, Desc).limit(3).filter(|l| l.temp_c < 39).prepare({}),
		Surreal.Mirror.literal(fastest(seed_vitals, 3).map(vital_line).keep_if(|l| l.temp_c < 39)),
	),
	block(
		"-- query: fastest_pulses",
		Surreal.from(vitals).select_value(|v| v.pulse).order_by(|n| n, Desc).limit(3).filter(|n| n < 130).prepare({}),
		Surreal.Mirror.literal(fastest(seed_vitals, 3).map(|v| v.pulse).keep_if(|n| n < 130)),
	),
	# The result rows of a projection as the rows of a new query: one `SELECT`.
	block(
		"-- query: kennel_fevers",
		Surreal.from(vitals).select(hot_line).query().filter(|r| r.hot).group_by(|r| r.kennel).aggregate(kennel_fevers).prepare({}),
		Surreal.Mirror.literal([kennels.id("a"), kennels.id("b")].map(|k| kennel_fevers(k, seed_vitals.map(hot_line).keep_if(|r| r.hot and r.kennel == k)))),
	),
	# A parameter of a filter over a subquery.
	block(
		"-- query: busy_days",
		Surreal.from(vitals).group_by(day_of).aggregate(day_line).query().filter_by(|p, d| d.readings >= p.least).select(|r| r).prepare({ least: 2 }),
		Surreal.Mirror.literal(rollup(seed_vitals).keep_if(|d| d.readings >= 2)),
	),
	block(
		"-- query: daily_view",
		Surreal.from(daily).select(|d| { kennel: d.kennel, day: d.day, readings: d.readings, fevers: d.fevers }).prepare({}),
		Surreal.Mirror.literal(rollup(seed_vitals)),
	),
	# The table line has the changefeed, which SurrealDB prints in its own unit.
	"-- query: changefeed\n-- roc: true\nRETURN string::contains((INFO FOR DB).tables.vital, 'CHANGEFEED 1w');",
	block(
		"-- write: vital_retention",
		then_read(vitals.delete_by(|p, v| v.id.time() < p.before).prepare({ before: day_start }), Surreal.from(vitals).select(vital_line).prepare({})),
		Surreal.Mirror.literal(seed_vitals.keep_if(|v| v.id.time() >= day_start).map(vital_line)),
	),
	block("-- query: site_lat", Surreal.from(sites).select(site_lat).prepare({}), Surreal.Mirror.literal(seed_sites.map(site_lat))),
	# `Geo.inside` and `Geo.distance` run in the database only, so the references are by hand.
	block(
		"-- query: sites_covering",
		Surreal.from(sites).filter_by(|p, s| Surreal.Geo.inside(p.here.to_geometry(), s.area.to_geometry())).select_value(|s| s.id).prepare({ here: here }),
		Surreal.Mirror.literal(["oslo"]),
	),
	block(
		"-- query: sites_near",
		Surreal.from(sites).filter_by(|p, s| Surreal.Geo.distance(s.location, p.here) < 50000).select_value(|s| s.id).prepare({ here: here }),
		Surreal.Mirror.literal(["oslo", "drammen"]),
	),
	# The read row: a linked site, and the edges that end at the kennel,
	# each with its linked carer as a whole row.
	block(
		"-- query: kennel_carers",
		Surreal.from(kennel_reads).select(|k| { label: k.label, site: k.site.name, carers: k.cares_for.list().map(|e| e.from), leads: k.cares_for.list().keep_if(|e| e.lead).len().to_i64_wrap() }).prepare({}),
		Surreal.Mirror.literal(seed_kennels.map(kennel_carers)),
	),
	# The rows of another table in a clause: a correlated count, and a semi join.
	block(
		"-- query: kennel_readings",
		Surreal.from(kennels).select(|k| { label: k.label, readings: readings_of(vitals.rows(), k).len().to_i64_wrap() }).prepare({}),
		Surreal.Mirror.literal(seed_kennels.map(|k| { label: k.label, readings: readings_of(kept_vitals, k).len().to_i64_wrap() })),
	),
	block(
		"-- query: kennels_fevered",
		Surreal.from(kennels).filter(|k| has_fever(vitals.rows(), k)).select_value(|k| k.label).prepare({}),
		Surreal.Mirror.literal(seed_kennels.keep_if(|k| has_fever(kept_vitals, k)).map(|k| k.label)),
	),
	# A point out of range: the field asserts `geo::is_valid`.
	match sites.create({ id: "nowhere", name: "Nowhere", location: Surreal.point(200, 2), area: rectangle(Surreal.point(0, 0), Surreal.point(1, 1)) }) {
		Ok(p) => p.statement().block("-- rejects: bad_point", ["-- error: field `location`"])
		Err(e) => "-- unsupported -- rejects: bad_point: ${Str.inspect(e)}"
	},
]

# ------------------------------------------------------------- live queries

## The fevered readings, kept current.
fevered : Try(Surreal.Watch(VitalLine), Surreal.Error)
fevered = Surreal.from(vitals).filter(|v| fever_fn.call2(v.temp_c, v.pulse)).select(vital_line).live({}, definitions)

## The readings above a temperature given when the watch starts. The `LET`
## is read once, so a new limit needs a new watch.
hotter_than : Dec -> Try(Surreal.Watch(VitalLine), Surreal.Error)
hotter_than = |limit| Surreal.from(vitals).filter_by(|p, v| v.temp_c > p.limit).select(vital_line).live({ limit: limit }, definitions)

## The daily rollup, kept current by the database: watch the view.
daily_live : Try(Surreal.Watch(Daily), Surreal.Error)
daily_live = Surreal.from(daily).select(|d| { kennel: d.kennel, day: d.day, readings: d.readings, fevers: d.fevers }).live({}, definitions)

Unattended : { label : Str, carers : I64 }

## A kennel with no carer.
no_carer : (Kennel, List(CaresFor)) -> Bool
no_carer = |(_, edges)| edges.len() == 0

unattended_line : (Kennel, List(CaresFor)) -> Unattended
unattended_line = |(k, edges)| { label: k.label, carers: edges.len().to_i64_wrap() }

## The kennels with no carer. A kennel enters when its last carer goes, and
## leaves when one comes: a second `LIVE` on `cares_for` reports each edge.
unattended : Try(Surreal.Watch(Unattended), Surreal.Error)
unattended = Surreal.from(kennels).incoming(cares_for).filter(no_carer).select(unattended_line).live({}, definitions)

## The same watch through the read row: the `In` field `cares_for` gives the
## second `LIVE` on `cares_for`, as `incoming` does.
unattended_read : Try(Surreal.Watch(Unattended), Surreal.Error)
unattended_read = Surreal.from(kennel_reads).filter(|k| k.cares_for.list().len() == 0).select(|k| { label: k.label, carers: k.cares_for.list().len().to_i64_wrap() }).live({}, definitions)

## The kennels with a fevered reading. The filter reads the readings with
## `rows()`, so a write to a reading sends a notice for each kennel.
fevered_kennels : Try(Surreal.Watch(Str), Surreal.Error)
fevered_kennels = Surreal.from(kennels).filter(|k| has_fever(vitals.rows(), k)).select_value(|k| k.label).live({}, definitions)

Neglected : { label : Str, carers : I64, checks : I64 }

## A kennel with no carer and no check: two edge tables of the kennel.
no_one : (Kennel, List(CaresFor), List(Checks)) -> Bool
no_one = |(_, cares, seen)| cares.len() == 0 and seen.len() == 0

neglected_line : (Kennel, List(CaresFor), List(Checks)) -> Neglected
neglected_line = |(k, cares, seen)| { label: k.label, carers: cares.len().to_i64_wrap(), checks: seen.len().to_i64_wrap() }

## The kennels that no carer looks after and no carer checks: a `LIVE` on
## each of the two edge tables.
neglected : Try(Surreal.Watch(Neglected), Surreal.Error)
neglected = Surreal.from(kennels).incoming(cares_for).and_incoming(checks).filter(no_one).select(neglected_line).live({}, definitions)

KennelSite : { label : Str, site : Str }

## Each kennel with the name of its site, through the `Linked` site of
## the read row. A new name of a site is an update of each kennel at it:
## a `LIVE` on `site` reads the kennels that link to the site.
kennel_sites : Try(Surreal.Watch(KennelSite), Surreal.Error)
kennel_sites = Surreal.from(kennel_reads).select(|k| { label: k.label, site: k.site.name }).live({}, definitions)

## The kennels at the site named Oslo, through the link with `.get()`. A
## new name of the site makes its kennels leave, and the old name brings
## them back.
oslo_kennels : Try(Surreal.Watch(Str), Surreal.Error)
oslo_kennels = Surreal.from(kennels).filter(|k| k.site.get().name == "Oslo").select_value(|k| k.label).live({}, definitions)

## Escape hatch: the server's own events for the fevered readings.
fever_events : Try(Surreal.RawWatch(VitalLine), Surreal.Error)
fever_events = Surreal.from(vitals).filter(|v| fever_fn.call2(v.temp_c, v.pulse)).select(vital_line).live_raw({})

## Escape hatch: the patches of each write to a reading.
vital_patches : Try(Surreal.DiffWatch(Vital), Surreal.Error)
vital_patches = Surreal.from(vitals).live_diff({})

## The readings in the database when the live blocks run: the retention
## write deleted the older ones.
kept_vitals : List(Vital)
kept_vitals = seed_vitals.keep_if(|v| v.id.time() >= day_start).map(stored)

## The writes of a live block of readings, as stored, on a day of their
## own: a fever, a reading that is no fever, the fever cools (it leaves),
## the other heats (it enters), its pulse changes (it stays), a write that
## changes nothing, then both are deleted.
vital_edits : Str -> List(Surreal.Edit(Vital))
vital_edits = |day| {
	hot = stored(reading("a", "${day}T08:00:00Z", 80, 39.6))
	cool = stored(reading("a", "${day}T09:00:00Z", 80, 38.2))
	cooled = stored({ ..hot, temp_c: 38.2 })
	heated = stored({ ..cool, temp_c: 39.8 })
	calmer = stored({ ..heated, pulse: 90 })
	[Create(hot), Create(cool), Replace(hot, cooled), Replace(cool, heated), Replace(heated, calmer), Replace(cooled, cooled), Delete(calmer), Delete(cooled)]
}

## The rows in the result of a watch of readings when it starts, as the
## `-- snapshot:` literal.
vital_snapshot : (Vital -> Bool) -> Try(Str, Surreal.Error)
vital_snapshot = |keep| {
	rows = kept_vitals.keep_if(keep).map_try(|v| Ok({ ref: vitals.ref(v)?, row: vital_line(v) }))?
	Surreal.Mirror.literal(rows)
}

## The Mirror of a watch of readings: the notices of each write.
vital_notices : List(Surreal.Edit(Vital)), (Vital -> Bool) -> Try(Str, Surreal.Error)
vital_notices = |edits, keep| Surreal.Mirror.notices_literal(edits.map_try(|e| Surreal.Mirror.notices(vitals, e, keep, vital_line))?)

## The text of a write, for a `-- live:` block.
text_of : Try(Surreal.Prepared(out), Surreal.Error) -> Try(Surreal.Statement, Surreal.Error)
text_of = |prepared| prepared.map_ok(|p| p.statement())

## The statements of the writes.
vital_writes : List(Surreal.Edit(Vital)) -> Try(List(Surreal.Statement), Surreal.Error)
vital_writes = |edits| edits.map_try(|e| text_of(vitals.edit(e)))

## One `-- live:` block: the watch, the rows of its snapshot and the notices
## of its writes in Roc, and the writes.
live_block : Str, Try(Surreal.Watch(out), Surreal.Error), Try(Str, Surreal.Error), Try(Str, Surreal.Error), Try(List(Surreal.Statement), Surreal.Error) -> Str
live_block = |header, watch, snapshot, notices, writes| match (watch, snapshot, notices, writes) {
	(Ok(w), Ok(rows), Ok(literal), Ok(statements)) => w.block(header, ["-- snapshot: ${rows}", "-- roc: ${literal}"], statements)
	(Err(e), _, _, _) | (_, Err(e), _, _) | (_, _, Err(e), _) | (_, _, _, Err(e)) => "-- unsupported ${header}: ${Str.inspect(e)}"
}

## A reading late on the first day, a fever: it changes one row of the view.
late_fever : Vital
late_fever = stored(reading("a", "2026-03-01T20:00:00Z", 85, 39.4))

## The view row of kennel `a` on the first day, after a write and after
## its delete: SurrealDB updates the row on each write of a reading.
daily_notices : Vital -> Try(Str, Surreal.Error)
daily_notices = |late| {
	key = day_of(late)
	ref = daily.group_ref(key)?
	rows = kept_vitals.keep_if(|v| day_of(v) == key)
	update = |row| [{ action: Update, role: Node, ref, row: Ok(row), now: Bool.True }]
	Surreal.Mirror.notices_literal([update(day_line(key, rows.append(late))), update(day_line(key, rows))])
}

daily_snapshot : Try(Str, Surreal.Error)
daily_snapshot = match rollup(kept_vitals).map_try(|d| daily.group_ref({ kennel: d.kennel, day: d.day }).map_ok(|ref| { ref, row: d })) {
	Ok(rows) => Surreal.Mirror.literal(rows)
	Err(e) => Err(e)
}

east : Kennel
east = { id: "c", label: "East", site: sites.link("oslo") }

east_wing : Kennel
east_wing = { ..east, label: "East wing" }

annex : Kennel
annex = { ..east, label: "Annex" }

ida_east : CaresFor
ida_east = { id: "ida_c", from: carers.link("ida"), to: kennels.link("c"), lead: Bool.True }

jon_east : CaresFor
jon_east = { id: "jon_c", from: carers.link("jon"), to: kennels.link("c"), lead: Bool.False }

## The notices of a write of a kennel, whose carers after the write are `edges`.
kennel_step : Surreal.Edit(Kennel), List(CaresFor) -> Try(List(Surreal.Notice(Unattended)), Surreal.Error)
kennel_step = |edit, edges| Surreal.Mirror.notices(kennels, edit, |k| no_carer((k, edges)), |k| unattended_line((k, edges)))

## The notices of a write of an edge, with its kennel and the kennel's
## carers after the write, or `Gone`.
care_step : Surreal.Edit(CaresFor), Try((Kennel, List(CaresFor)), [Gone]) -> Try(List(Surreal.Notice(Unattended)), Surreal.Error)
care_step = |edit, state| Surreal.Mirror.edge_notices(cares_for, edit, |e| e.to, |_| state, no_carer, unattended_line)

## The writes of the block `unattended` on a new kennel `c`, each with its
## notices. A write to a carer reaches the watch through the edge it deletes.
unattended_steps : List({ write : Try(Surreal.Statement, Surreal.Error), notices : Try(List(Surreal.Notice(Unattended)), Surreal.Error) })
unattended_steps = [
	# case: a new kennel has no carer, so it enters
	{ write: text_of(kennels.edit(Create(east))), notices: kennel_step(Create(east), []) },
	# case: a carer comes, so it leaves
	{ write: text_of(cares_for.edit(Create(ida_east))), notices: care_step(Create(ida_east), Ok((east, [ida_east]))) },
	# case: a new label while it has a carer sends nothing
	{ write: text_of(kennels.edit(Replace(east, east_wing))), notices: kennel_step(Replace(east, east_wing), [ida_east]) },
	# case: the carer goes, so it enters
	{ write: text_of(cares_for.edit(Delete(ida_east))), notices: care_step(Delete(ida_east), Ok((east_wing, []))) },
	# case: a new label while it has no carer, so it stays
	{ write: text_of(kennels.edit(Replace(east_wing, annex))), notices: kennel_step(Replace(east_wing, annex), []) },
	{ write: text_of(cares_for.edit(Create(jon_east))), notices: care_step(Create(jon_east), Ok((annex, [jon_east]))) },
	# case: a delete of the carer deletes its edge, so the kennel enters
	{ write: text_of(carers.edit(Delete(jon))), notices: care_step(Delete(jon_east), Ok((annex, []))) },
	{ write: text_of(cares_for.edit(Create(ida_east))), notices: care_step(Create(ida_east), Ok((annex, [ida_east]))) },
	# case: a delete of the kennel deletes its edge first, with no node, then the kennel
	{ write: text_of(kennels.edit(Delete(annex))), notices: both(care_step(Delete(ida_east), Err(Gone)), kennel_step(Delete(annex), [])) },
]

west : Kennel
west = { id: "d", label: "West", site: sites.link("oslo") }

ida_west : CaresFor
ida_west = { id: "ida_d", from: carers.link("ida"), to: kennels.link("d"), lead: Bool.True }

## The writes of the block `unattended_read` on a new kennel `d`.
read_steps : List({ write : Try(Surreal.Statement, Surreal.Error), notices : Try(List(Surreal.Notice(Unattended)), Surreal.Error) })
read_steps = [
	# case: a new kennel has no carer, so it enters
	{ write: text_of(kennels.edit(Create(west))), notices: kennel_step(Create(west), []) },
	# case: a carer comes, so it leaves
	{ write: text_of(cares_for.edit(Create(ida_west))), notices: care_step(Create(ida_west), Ok((west, [ida_west]))) },
	# case: the carer goes, so it enters
	{ write: text_of(cares_for.edit(Delete(ida_west))), notices: care_step(Delete(ida_west), Ok((west, []))) },
	{ write: text_of(kennels.edit(Delete(west))), notices: kennel_step(Delete(west), []) },
]

## The writes of the block `fevered_kennels`: kennel `a` has a fever, so a
## new label is an update in the result, and so is the old label again. A
## fever of kennel `b` is a write to the readings, which sends nothing.
north : Kennel
north = { id: "a", label: "North", site: sites.link("oslo") }

north_wing : Kennel
north_wing = { ..north, label: "North wing" }

fevered_edits : List(Surreal.Edit(Kennel))
fevered_edits = [Replace(north, north_wing), Replace(north_wing, north)]

fevered_kennels_snapshot : Try(Str, Surreal.Error)
fevered_kennels_snapshot = match seed_kennels.keep_if(|k| has_fever(kept_vitals, k)).map_try(|k| kennels.ref(k).map_ok(|ref| { ref, row: k.label })) {
	Ok(rows) => Surreal.Mirror.literal(rows)
	Err(e) => Err(e)
}

## A fever of kennel `b`, written and deleted.
south_fever : Vital
south_fever = stored(reading("b", "2026-03-07T08:00:00Z", 140, 38.0))

## The notices of a write of a reading to the watch of the kennels with a
## fever: one for each kennel, with the readings `after` the write.
fever_reach : Surreal.Edit(Vital), List(Vital) -> Try(List(Surreal.Notice(Str)), Surreal.Error)
fever_reach = |edit, after| {
	reached = seed_kennels.map_try(|k| kennels.ref(k).map_ok(|ref| { ref, row: k }))?
	Surreal.Mirror.read_notices(vitals, edit, reached, |k| has_fever(after, k), |k| k.label)
}

fevered_kennels_notices : Try(Str, Surreal.Error)
fevered_kennels_notices = match (fevered_edits.map_try(|e| Surreal.Mirror.notices(kennels, e, |k| has_fever(kept_vitals, k), |k| k.label)), fever_reach(Create(south_fever), kept_vitals.append(stored(south_fever))), fever_reach(Delete(south_fever), kept_vitals)) {
	(Ok(lists), Ok(created), Ok(deleted)) => Surreal.Mirror.notices_literal(lists.concat([created, deleted]))
	(Err(e), _, _) | (_, Err(e), _) | (_, _, Err(e)) => Err(e)
}

fevered_kennels_writes : Try(List(Surreal.Statement), Surreal.Error)
fevered_kennels_writes = match (fevered_edits.map_try(|e| text_of(kennels.edit(e))), vital_writes([Create(south_fever), Delete(south_fever)])) {
	(Ok(labels), Ok(readings)) => Ok(labels.concat(readings))
	(Err(e), _) | (_, Err(e)) => Err(e)
}

south : Kennel
south = { id: "e", label: "South east", site: sites.link("bergen") }

## Jon is gone when this block runs: the block `unattended` deletes him.
ida_checks : Checks
ida_checks = { id: "ida_check_e", from: carers.link("ida"), to: kennels.link("e"), note: "water" }

ida_south : CaresFor
ida_south = { id: "ida_e", from: carers.link("ida"), to: kennels.link("e"), lead: Bool.False }

## The state of the watch `neglected`: a kennel with its carers and its checks.
Seen : (Kennel, List(CaresFor), List(Checks))

## The writes of the block `neglected` on a new kennel `e`, each with its
## notices. An edge of either table reaches the kennel.
neglected_steps : List({ write : Try(Surreal.Statement, Surreal.Error), notices : Try(List(Surreal.Notice(Neglected)), Surreal.Error) })
neglected_steps = {
	node = |edit, cares, seen| Surreal.Mirror.notices(kennels, edit, |k| no_one((k, cares, seen)), |k| neglected_line((k, cares, seen)))
	cared = |edit, state| Surreal.Mirror.edge_notices(cares_for, edit, |e| e.to, |_| state, no_one, neglected_line)
	checked = |edit, state| Surreal.Mirror.edge_notices(checks, edit, |e| e.to, |_| state, no_one, neglected_line)
	gone : Try(Seen, [Gone])
	gone = Err(Gone)
	[
		# case: a new kennel has no carer and no check, so it enters
		{ write: text_of(kennels.edit(Create(south))), notices: node(Create(south), [], []) },
		# case: a check, an edge of the second table, so it leaves
		{ write: text_of(checks.edit(Create(ida_checks))), notices: checked(Create(ida_checks), Ok((south, [], [ida_checks]))) },
		# case: a carer comes while it is out of the result: a notice, no change
		{ write: text_of(cares_for.edit(Create(ida_south))), notices: cared(Create(ida_south), Ok((south, [ida_south], [ida_checks]))) },
		{ write: text_of(checks.edit(Delete(ida_checks))), notices: checked(Delete(ida_checks), Ok((south, [ida_south], []))) },
		# case: the carer goes, so it enters
		{ write: text_of(cares_for.edit(Delete(ida_south))), notices: cared(Delete(ida_south), Ok((south, [], []))) },
		{ write: text_of(checks.edit(Create(ida_checks))), notices: checked(Create(ida_checks), Ok((south, [], [ida_checks]))) },
		# case: a delete of the kennel deletes its check first, with no node, then the kennel
		{ write: text_of(kennels.edit(Delete(south))), notices: both_seen(checked(Delete(ida_checks), gone), node(Delete(south), [], [])) },
	]
}

## The kennels with no carer and no check when the watch starts.
neglected_snapshot : Try(Str, Surreal.Error)
neglected_snapshot = {
	seen = seed_kennels.map(|k| (k, seed_cares_for.keep_if(|e| e.to.id() == kennels.id(k.id)), []))
	match seen.keep_if(no_one).map_try(|(k, cares, none)| kennels.ref(k).map_ok(|ref| { ref, row: neglected_line((k, cares, none)) })) {
		Ok(rows) => Surreal.Mirror.literal(rows)
		Err(e) => Err(e)
	}
}

## The notices of one write to two statements of `neglected`.
both_seen : Try(List(Surreal.Notice(Neglected)), Surreal.Error), Try(List(Surreal.Notice(Neglected)), Surreal.Error) -> Try(List(Surreal.Notice(Neglected)), Surreal.Error)
both_seen = |first, second| Ok(first?.concat(second?))

oslo : Site
oslo = match seed_sites.find_first(|site| site.id == "oslo") {
	Ok(site) => site
	Err(_) => crash "a seed site"
}

bergen : Site
bergen = match seed_sites.find_first(|site| site.id == "bergen") {
	Ok(site) => site
	Err(_) => crash "a seed site"
}

## A site that no kennel is at.
trondheim : Site
trondheim = { id: "trondheim", name: "Trondheim", location: Surreal.point(10.39, 63.43), area: rectangle(Surreal.point(10.2, 63.35), Surreal.point(10.6, 63.5)) }

## A kennel and its site, the state of a watch that reads the site.
KennelAt : (Kennel, Site)

## The kennels after a write to the sites: each seed kennel with its site
## in `after`.
kennels_at : List(Site) -> Try(List({ ref : Surreal.Ref, row : KennelAt }), Surreal.Error)
kennels_at = |after| seed_kennels.map_try(
	|k| match after.find_first(|site| sites.id(site.id) == k.site.id()) {
		Ok(site) => kennels.ref(k).map_ok(|ref| { ref, row: (k, site) })
		Err(_) => Err(Unsupported("a seed kennel is at a seed site"))
	},
)

## The notices of a write to the sites, which are `after` it, to a watch
## that reads the site of each kennel: one for each kennel at the site.
site_step : Surreal.Edit(Site), List(Site), (KennelAt -> Bool), (KennelAt -> out) -> Try(List(Surreal.Notice(out)), Surreal.Error)
site_step = |edit, after, keep, show| {
	written = match edit {
		Create(site) | Replace(_, site) | Delete(site) => sites.id(site.id)
	}
	reached = kennels_at(after)?.keep_if(|r| r.row.0.site.id() == written)
	Surreal.Mirror.read_notices(sites, edit, reached, keep, show)
}

## The writes of the site blocks, each with the sites after it: Oslo gets
## a new name, Bergen too, a new site that no kennel is at comes and goes,
## and the old names come back.
site_writes : List({ edit : Surreal.Edit(Site), after : List(Site) })
site_writes = {
	centre = { ..oslo, name: "Oslo centre" }
	sentrum = { ..bergen, name: "Bergen sentrum" }
	renamed = seed_sites.map(|site| if (site.id == "oslo") centre else if (site.id == "bergen") sentrum else site)
	[
		# case: the kennel at the site is reached
		{ edit: Replace(oslo, centre), after: seed_sites.map(|site| if (site.id == "oslo") centre else site) },
		{ edit: Replace(bergen, sentrum), after: renamed },
		# case: a site that no kennel links to sends a notice of no rows
		{ edit: Create(trondheim), after: renamed.append(trondheim) },
		{ edit: Delete(trondheim), after: renamed },
		# case: a write that changes no field sends nothing
		{ edit: Replace(centre, centre), after: renamed },
		{ edit: Replace(centre, oslo), after: seed_sites.map(|site| if (site.id == "bergen") sentrum else site) },
		{ edit: Replace(sentrum, bergen), after: seed_sites },
	]
}

## The rows in the result of a watch that reads the site of each kennel,
## when it starts.
site_snapshot : (KennelAt -> Bool), (KennelAt -> out) -> Try(List({ ref : Surreal.Ref, row : out }), Surreal.Error)
site_snapshot = |keep, show| Ok(kennels_at(seed_sites)?.keep_if(|r| keep(r.row)).map(|r| { ref: r.ref, row: show(r.row) }))

## The notices of `site_writes` to a watch that reads the site of each kennel.
site_notices : (KennelAt -> Bool), (KennelAt -> out) -> Try(List(List(Surreal.Notice(out))), Surreal.Error)
site_notices = |keep, show| site_writes.map_try(|w| site_step(w.edit, w.after, keep, show))

site_label : KennelAt -> KennelSite
site_label = |(k, site)| { label: k.label, site: site.name }

is_oslo : KennelAt -> Bool
is_oslo = |(_, site)| site.name == "Oslo"

kennel_label : KennelAt -> Str
kennel_label = |(k, _)| k.label

kennel_sites_block : Str
kennel_sites_block = match (site_snapshot(|_| Bool.True, site_label), site_notices(|_| Bool.True, site_label)) {
	(Ok(rows), Ok(lists)) => live_block("-- live: kennel_sites", kennel_sites, Surreal.Mirror.literal(rows), Surreal.Mirror.notices_literal(lists), site_writes.map_try(|w| text_of(sites.edit(w.edit))))
	(Err(e), _) | (_, Err(e)) => "-- unsupported -- live: kennel_sites: ${Str.inspect(e)}"
}

oslo_kennels_block : Str
oslo_kennels_block = match (site_snapshot(is_oslo, kennel_label), site_notices(is_oslo, kennel_label)) {
	(Ok(rows), Ok(lists)) => live_block("-- live: oslo_kennels", oslo_kennels, Surreal.Mirror.literal(rows), Surreal.Mirror.notices_literal(lists), site_writes.map_try(|w| text_of(sites.edit(w.edit))))
	(Err(e), _) | (_, Err(e)) => "-- unsupported -- live: oslo_kennels: ${Str.inspect(e)}"
}

## The notices of one write to two statements.
both : Try(List(Surreal.Notice(Unattended)), Surreal.Error), Try(List(Surreal.Notice(Unattended)), Surreal.Error) -> Try(List(Surreal.Notice(Unattended)), Surreal.Error)
both = |first, second| Ok(first?.concat(second?))

unattended_notices : Try(Str, Surreal.Error)
unattended_notices = match unattended_steps.map_try(|step| step.notices) {
	Ok(lists) => Surreal.Mirror.notices_literal(lists)
	Err(e) => Err(e)
}

## The kennels with no carer when the watch starts.
unattended_snapshot : Try(Str, Surreal.Error)
unattended_snapshot = {
	with_edges = seed_kennels.map(|k| (k, seed_cares_for.keep_if(|e| e.to.id() == kennels.id(k.id))))
	match with_edges.keep_if(no_carer).map_try(|(k, edges)| kennels.ref(k).map_ok(|ref| { ref, row: unattended_line((k, edges)) })) {
		Ok(rows) => Surreal.Mirror.literal(rows)
		Err(e) => Err(e)
	}
}

## The writes of the patch block, and the patches SurrealDB sends, by hand:
## a create is the whole row, an update one op for each changed field (the
## computed `fevered` too), and a delete the row replaced with NULL.
patch_edits : List(Surreal.Edit(Vital))
patch_edits = {
	hot = stored(reading("a", "2026-03-06T08:00:00Z", 80, 39.6))
	cooled = stored({ ..hot, temp_c: 38.2 })
	[Create(hot), Replace(hot, cooled), Delete(cooled)]
}

patches_literal : Str
patches_literal = "[[{ action: 'CREATE', ref: vital:[kennel:⟨a⟩, d'2026-03-06T08:00:00Z'], ops: [{ op: 'replace', path: '', value: { fevered: true, id: vital:[kennel:⟨a⟩, d'2026-03-06T08:00:00Z'], pulse: 80, temp_c: 39.6dec } }] }], [{ action: 'UPDATE', ref: vital:[kennel:⟨a⟩, d'2026-03-06T08:00:00Z'], ops: [{ op: 'replace', path: '/fevered', value: false }, { op: 'replace', path: '/temp_c', value: 38.2dec }] }], [{ action: 'DELETE', ref: vital:[kennel:⟨a⟩, d'2026-03-06T08:00:00Z'], ops: [{ op: 'replace', path: '', value: NULL }] }]]"

## The filter of the watches of fevers, in Roc.
is_fever : Vital -> Bool
is_fever = |v| fever(v.temp_c, v.pulse)

live_blocks : List(Str)
live_blocks = [
	live_block("-- live: fevered", fevered, vital_snapshot(is_fever), vital_notices(vital_edits("2026-03-03"), is_fever), vital_writes(vital_edits("2026-03-03"))),
	live_block("-- live: hotter_than", hotter_than(39.2), vital_snapshot(|v| v.temp_c > 39.2), vital_notices(vital_edits("2026-03-04"), |v| v.temp_c > 39.2), vital_writes(vital_edits("2026-03-04"))),
	live_block("-- live: daily_view", daily_live, daily_snapshot, daily_notices(late_fever), vital_writes([Create(late_fever), Delete(late_fever)])),
	live_block(
		"-- live: unattended",
		unattended,
		unattended_snapshot,
		unattended_notices,
		unattended_steps.map_try(|step| step.write),
	),
	live_block(
		"-- live: unattended_read",
		unattended_read,
		unattended_snapshot,
		match read_steps.map_try(|step| step.notices) {
			Ok(lists) => Surreal.Mirror.notices_literal(lists)
			Err(e) => Err(e)
		},
		read_steps.map_try(|step| step.write),
	),
	live_block("-- live: fevered_kennels", fevered_kennels, fevered_kennels_snapshot, fevered_kennels_notices, fevered_kennels_writes),
	kennel_sites_block,
	oslo_kennels_block,
	live_block(
		"-- live: neglected",
		neglected,
		neglected_snapshot,
		match neglected_steps.map_try(|step| step.notices) {
			Ok(lists) => Surreal.Mirror.notices_literal(lists)
			Err(e) => Err(e)
		},
		neglected_steps.map_try(|step| step.write),
	),
	match (fever_events, vital_edits("2026-03-05").map_try(|e| Surreal.Mirror.events(vitals, e, is_fever, vital_line)), vital_writes(vital_edits("2026-03-05"))) {
		(Ok(w), Ok(events), Ok(writes)) =>
			match Surreal.Mirror.events_literal(events) {
				Ok(literal) => w.block("-- live: fever_events", ["-- roc: ${literal}"], writes)
				Err(e) => "-- unsupported -- live: fever_events: ${Str.inspect(e)}"
			}
		(Err(e), _, _) | (_, Err(e), _) | (_, _, Err(e)) => "-- unsupported -- live: fever_events: ${Str.inspect(e)}"
	},
	match (vital_patches, vital_writes(patch_edits)) {
		(Ok(w), Ok(writes)) => w.block("-- live: vital_patches", ["-- roc: ${patches_literal}"], writes)
		(Err(e), _) | (_, Err(e)) => "-- unsupported -- live: vital_patches: ${Str.inspect(e)}"
	},
]

script : Str
script = Str.join_with([schema_block].concat(seed_blocks).concat(queries).concat(live_blocks), "\n\n")

main! = |_args| {
	echo!("${script}\n")
	Ok({})
}

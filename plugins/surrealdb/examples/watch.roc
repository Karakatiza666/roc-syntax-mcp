## Live queries on a basic-cli session: start a watch, write, read each change with next_within!, and compare it with the Mirror's prediction.
# How an app on the basic-cli platform starts live queries (watches) on a
# running SurrealDB and reads their changes.
#
# The app opens a WebSocket session on `/rpc` through
# roc-basic-cli-websocket, starts a watch, and makes groups of writes on
# the same session (`send!` and `await!`, as `run!` does, and two writes
# in flight together). After each group, it reads the changes of the
# result that the server reported for the group (`next_within!`, which
# gives up after 60 s: the line is then a `FAIL` that names the change
# that did not come), then it starts the next group.
#
# It also checks itself. The changes that the Roc Mirror predicts for the
# same writes stand next to the real ones: a line starts with `ok` when the
# two agree, and with `FAIL` when they do not. The exit code is 1 when one
# line fails. `tests/check.py` runs the app for that exit code.
#
# The tables are the tables of `monitoring.roc`, and `check.py` makes them:
# run `python3 tests/check.py` first, then `roc examples/watch.roc`. The
# writes use rows of their own (kennels `w` and `v`, the site `w_site`,
# readings of 2026-03-09), and delete them again. The watches of the links
# that the clauses read run last, in a database of their own, `roc_watch`,
# which the app makes again each time with the tables of the watches.
app [main!] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.4.0/EnfRKFT7uPHmd3zT5PcwAiBWUtGmBXapJqFK5166U33J.tar.zst",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	cli_ws: "https://github.com/Karakatiza666/roc-basic-cli-websocket/releases/download/0.0.3/9c6XLWHRSREuaoELdH1a835Yopw92Jxy2b5e151X6mZj.tar.zst",
	surreal: "https://github.com/Karakatiza666/roc-reify-surrealdb/releases/download/0.0.1/7MmdAaAt5bThg6ih3nR9ewVgw4CtNGvuK5HNQhEgZoSV.tar.zst",
}

import pf.Stdout
import cli_ws.WsClient
import surreal.Surreal
import cbor.Cbor

# ------------------------------------------------- the tables of monitoring.roc

Site : { id : Str, name : Str, location : Surreal.Point, area : Surreal.Polygon }

Kennel : { id : Str, label : Str, site : Surreal.Link(Site) }

Vital : { id : Surreal.TimeKey(Surreal.Id(Kennel)), pulse : I64, temp_c : Dec, fevered : Bool }

Carer : { id : Str, name : Str }

CaresFor : { id : Str, from : Surreal.Link(Carer), to : Surreal.Link(Kennel), lead : Bool }

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

## The tables, where a link of a watched row finds its table.
definitions : List(Surreal.Defined)
definitions = [sites.define().done(), kennels.define().done(), vitals.define().done(), carers.define().done(), cares_for.define().done()]

# ------------------------------------------------------------- the watches

fever : Dec, I64 -> Bool
fever = |temp_c, pulse| temp_c > 39.0 or pulse > 120

fever_fn : Surreal.DbFn((Dec, I64 -> Bool))
fever_fn = Surreal.db_fn("fever", fever)

VitalLine : { kennel : Surreal.Id(Kennel), at : Surreal.Datetime, pulse : I64, temp_c : Dec }

vital_line : Vital -> VitalLine
vital_line = |v| { kennel: v.id.series(), at: v.id.time(), pulse: v.pulse, temp_c: v.temp_c }

is_fever : Vital -> Bool
is_fever = |v| fever(v.temp_c, v.pulse)

## The fevered readings.
fevered : Try(Surreal.Watch(VitalLine), Surreal.Error)
fevered = Surreal.from(vitals).filter(|v| fever_fn.call2(v.temp_c, v.pulse)).select(vital_line).live({}, definitions)

## The patches of each write to a reading.
vital_patches : Try(Surreal.DiffWatch(Vital), Surreal.Error)
vital_patches = Surreal.from(vitals).live_diff({})

Unattended : { label : Str, carers : I64 }

no_carer : (Kennel, List(CaresFor)) -> Bool
no_carer = |(_, edges)| edges.len() == 0

unattended_line : (Kennel, List(CaresFor)) -> Unattended
unattended_line = |(k, edges)| { label: k.label, carers: edges.len().to_i64_wrap() }

## The kennels with no carer.
unattended : Try(Surreal.Watch(Unattended), Surreal.Error)
unattended = Surreal.from(kennels).incoming(cares_for).filter(no_carer).select(unattended_line).live({}, definitions)

KennelSite : { label : Str, site : Str }

## Each kennel with the name of its site, read through the link. A new
## name of a site is an update of each kennel at it: a `LIVE` on `site`
## reads the kennels that link to the site.
kennel_sites : Try(Surreal.Watch(KennelSite), Surreal.Error)
kennel_sites = Surreal.from(kennels).select(|k| { label: k.label, site: k.site.get().name }).live({}, definitions)

# ---------------------------------------------------------------- the writes

watched : Kennel
watched = { id: "w", label: "Watch", site: sites.link("oslo") }

renamed : Kennel
renamed = { ..watched, label: "Watch tower" }

ida_watched : CaresFor
ida_watched = { id: "ida_w", from: carers.link("ida"), to: kennels.link("w"), lead: Bool.True }

## A write of a row of one of the tables.
Write : [Kennel(Surreal.Edit(Kennel)), Care(Surreal.Edit(CaresFor)), Site(Surreal.Edit(Site)), Vital(Surreal.Edit(Vital)), Carer(Surreal.Edit(Carer)), Badge(Surreal.Edit(Badge))]

## One write and the notices that the Mirror predicts for it.
Step(out) : { write : Write, notices : Try(List(Surreal.Notice(out)), Surreal.Error) }

kennel_step : Surreal.Edit(Kennel), List(CaresFor) -> Step(Unattended)
kennel_step = |edit, edges| { write: Kennel(edit), notices: Surreal.Mirror.notices(kennels, edit, |k| no_carer((k, edges)), |k| unattended_line((k, edges))) }

care_step : Surreal.Edit(CaresFor), Try((Kennel, List(CaresFor)), [Gone]) -> Step(Unattended)
care_step = |edit, state| { write: Care(edit), notices: Surreal.Mirror.edge_notices(cares_for, edit, |e| e.to, |_| state, no_carer, unattended_line) }

## A kennel comes (it enters), a carer comes (it leaves), the carer goes
## (it enters), a new label (it stays), and the kennel is deleted (it
## leaves). Each write needs the one before it, so each is a group of one.
unattended_steps : List(List(Step(Unattended)))
unattended_steps = [
	kennel_step(Create(watched), []),
	care_step(Create(ida_watched), Ok((watched, [ida_watched]))),
	care_step(Delete(ida_watched), Ok((watched, []))),
	kennel_step(Replace(watched, renamed), []),
	kennel_step(Delete(renamed), []),
].map(|step| [step])

## A site of its own, a square of 0.1 degrees with its ring closed.
harbour : Site
harbour = {
	sw = Surreal.point(10.7, 59.9)
	se = Surreal.point(10.8, 59.9)
	ne = Surreal.point(10.8, 60.0)
	nw = Surreal.point(10.7, 60.0)
	{ id: "w_site", name: "Harbour", location: Surreal.point(10.75, 59.95), area: Surreal.Polygon.({ exterior: [sw, se, ne, nw, sw], holes: [] }) }
}

old_harbour : Site
old_harbour = { ..harbour, name: "Old harbour" }

pier : Kennel
pier = { id: "v", label: "Pier", site: sites.link("w_site") }

## A write of a kennel, at a site of this name.
pier_step : Surreal.Edit(Kennel), Str -> Step(KennelSite)
pier_step = |edit, name| { write: Kennel(edit), notices: Surreal.Mirror.notices(kennels, edit, |_| Bool.True, |k| { label: k.label, site: name }) }

## A write of a site, which reaches the kennels in `at`.
site_step : Surreal.Edit(Site), List(Kennel) -> Step(KennelSite)
site_step = |edit, at| {
	after = match edit {
		Create(site) | Replace(_, site) | Delete(site) => site
	}
	reached = at.map_try(|k| kennels.ref(k).map_ok(|ref| { ref, row: k }))
	notices = match reached {
		Ok(rows) => Surreal.Mirror.read_notices(sites, edit, rows, |_| Bool.True, |k| { label: k.label, site: after.name })
		Err(e) => Err(e)
	}
	{ write: Site(edit), notices }
}

## A site comes (no kennel is at it), a kennel at it comes (it enters),
## the site gets a new name (the kennel is updated), the kennel is
## deleted (it leaves), then the site. Each is a group of one.
kennel_sites_steps : List(List(Step(KennelSite)))
kennel_sites_steps = [
	site_step(Create(harbour), []),
	pier_step(Create(pier), "Harbour"),
	site_step(Replace(harbour, old_harbour), [pier]),
	pier_step(Delete(pier), "Old harbour"),
	site_step(Delete(old_harbour), []),
].map(|step| [step])

## A reading of kennel `a`, as the database stores it.
reading : Str, I64, Dec -> Vital
reading = |at, pulse, temp_c| match Surreal.datetime(at) {
	Ok(time) => { id: Surreal.time_key(kennels.id("a"), time), pulse, temp_c, fevered: fever(temp_c, pulse) }
	Err(_) => crash "a valid datetime"
}

vital_step : Surreal.Edit(Vital) -> Step(VitalLine)
vital_step = |edit| { write: Vital(edit), notices: Surreal.Mirror.notices(vitals, edit, is_fever, vital_line) }

hot : Vital
hot = reading("2026-03-09T08:00:00Z", 80, 39.6)

cool : Vital
cool = reading("2026-03-09T09:00:00Z", 80, 38.2)

cooled : Vital
cooled = { ..hot, temp_c: 38.2, fevered: Bool.False }

heated : Vital
heated = { ..cool, temp_c: 39.8, fevered: Bool.True }

## A fever (it enters) and a reading with no fever (nothing), in flight
## together; the fever cools (it leaves), the other heats (it enters), then
## both are deleted, in flight together. The two writes of a group are of
## two readings, so their order does not matter.
fevered_steps : List(List(Step(VitalLine)))
fevered_steps = [[Create(hot), Create(cool)], [Replace(hot, cooled)], [Replace(cool, heated)], [Delete(heated), Delete(cooled)]].map(|group| group.map(vital_step))

## The writes of the patch watch, each with the stored row after it.
patch_steps : List({ edit : Surreal.Edit(Vital), after : Try(Vital, [Gone]) })
patch_steps = {
	noon = reading("2026-03-09T12:00:00Z", 85, 39.4)
	calm = { ..noon, temp_c: 37.9, fevered: Bool.False }
	[{ edit: Create(noon), after: Ok(noon) }, { edit: Replace(noon, calm), after: Ok(calm) }, { edit: Delete(calm), after: Err(Gone) }]
}

# ------------------------------------------------ the links that the clauses read

# These watches run in the database `roc_watch`, on the tables below, so
# that each knows every row there is. A live query watches the table of a
# link that a clause reads, at the path of the link, and no other.

## A badge of a kennel. Two hops from a badge reach the site of its kennel.
Badge : { id : Str, note : Str, kennel : Surreal.Link(Kennel) }

badges : Surreal.Table(Badge)
badges = Surreal.table("badge")

## The read row of a kennel: its site and its carers, which a clause may read.
KennelRead : { id : Str, label : Str, site : Surreal.Linked(Site), cares_for : Surreal.In(CaresFor) }

kennel_reads : Surreal.Table(KennelRead)
kennel_reads = Surreal.table("kennel")

## The tables of `roc_watch`.
read_definitions : List(Surreal.Defined)
read_definitions = [sites.define().done(), kennels.define().done(), carers.define().done(), cares_for.define().done(), badges.define().done(), kennel_reads.define_read()]

Label : { label : Str }

## Each kennel by its label. The read row has a site and carers, and the
## clause reads neither, so the watch is the `LIVE` of the kennels alone.
labels : Try(Surreal.Watch(Label), Surreal.Error)
labels = Surreal.from(kennel_reads).select(|k| { label: k.label }).live({}, read_definitions)

CarerNames : { label : Str, carers : List(Str) }

## Each kennel with the names of its carers, read through the `from` of
## each edge: the edge statement, and a `read` statement on `carer` with
## the test `$parent.id IN <-cares_for.in`.
carer_names : Try(Surreal.Watch(CarerNames), Surreal.Error)
carer_names = Surreal.from(kennels).incoming(cares_for).select(|(k, edges)| { label: k.label, carers: edges.map(|e| e.from.get().name) }).live({}, read_definitions)

BadgeSite : { note : Str, site : Str }

## Each badge with the name of the site of its kennel, two hops: a `read`
## statement on `kennel` (`kennel = $parent.id`) and one on `site`
## (`kennel.site = $parent.id`).
badge_sites : Try(Surreal.Watch(BadgeSite), Surreal.Error)
badge_sites = Surreal.from(badges).select(|b| { note: b.note, site: b.kennel.get().site.get().name }).live({}, read_definitions)

CarerName : { name : Str }

## The carers named as the label of a kennel that a badge links to, read
## through the link of each badge of `rows()`: a `read` statement on
## `badge`, and one on `kennel` with the test
## `$parent.id IN (SELECT VALUE id FROM badge).kennel`.
badged_carers : Try(Surreal.Watch(CarerName), Surreal.Error)
badged_carers = Surreal.from(carers).filter(|c| badges.rows().any(|b| b.kennel.get().label == c.name)).select(|c| { name: c.name }).live({}, read_definitions)

dock : Site
dock = { ..harbour, id: "dock", name: "Dock" }

old_dock : Site
old_dock = { ..dock, name: "Old dock" }

quay : Site
quay = { ..harbour, id: "quay", name: "Quay" }

pen : Kennel
pen = { id: "pen", label: "Pen", site: sites.link("dock") }

ada : Carer
ada = { id: "ada", name: "Ada" }

ada_b : Carer
ada_b = { ..ada, name: "Ada B" }

ada_pen : CaresFor
ada_pen = { id: "ada_pen", from: carers.link("ada"), to: kennels.link("pen"), lead: Bool.True }

tag : Badge
tag = { id: "tag", note: "Tag", kennel: kennels.link("pen") }

## A write that the watch does not see.
unseen : Write -> Step(out)
unseen = |write| { write, notices: Ok([]) }

## The rows of the result that a write of a linked row reaches, by their
## records, as they are after the write.
reaching = |table, rows| rows.map_try(|r| table.ref(r).map_ok(|ref| { ref, row: r }))

## A write of a linked table, which reaches `rows` of the result's table.
read_step : Write, Try(List({ ref : Surreal.Ref, row : m }), Surreal.Error), (Try(List({ ref : Surreal.Ref, row : m }), Surreal.Error) -> Try(List(Surreal.Notice(out)), Surreal.Error)) -> Step(out)
read_step = |write, reached, notices_of| { write, notices: notices_of(reached) }

## A new name of the site and a carer that comes and goes send nothing,
## a new label is an update. Each is a group of one.
labels_steps : List(List(Step(Label)))
labels_steps = {
	label = |k| { label: k.label }
	[
		unseen(Site(Create(dock))),
		{ write: Kennel(Create(pen)), notices: Surreal.Mirror.notices(kennels, Create(pen), |_| Bool.True, label) },
		unseen(Site(Replace(dock, old_dock))),
		unseen(Carer(Create(ada))),
		unseen(Care(Create(ada_pen))),
		unseen(Care(Delete(ada_pen))),
		{ write: Kennel(Replace(pen, { ..pen, label: "Pen 2" })), notices: Surreal.Mirror.notices(kennels, Replace(pen, { ..pen, label: "Pen 2" }), |_| Bool.True, label) },
		{ write: Kennel(Delete({ ..pen, label: "Pen 2" })), notices: Surreal.Mirror.notices(kennels, Delete({ ..pen, label: "Pen 2" }), |_| Bool.True, label) },
		unseen(Carer(Delete(ada))),
		unseen(Site(Delete(old_dock))),
	].map(|step| [step])
}

## A carer that cares for no kennel sends nothing; the kennel comes, the
## carer comes to it (the edge), the carer gets a new name (the `read`
## statement on `carer`), the carer goes, and a new name of a carer of no
## kennel sends nothing.
carer_names_steps : List(List(Step(CarerNames)))
carer_names_steps = {
	names = |list| |(k, _)| { label: k.label, carers: list }
	[
		unseen(Site(Create(dock))),
		read_step(Carer(Create(ada)), Ok([]), |reached| Surreal.Mirror.read_notices(carers, Create(ada), reached?, |_| Bool.True, |k| { label: k.label, carers: [] })),
		{ write: Kennel(Create(pen)), notices: Surreal.Mirror.notices(kennels, Create(pen), |_| Bool.True, |k| { label: k.label, carers: [] }) },
		{ write: Care(Create(ada_pen)), notices: Surreal.Mirror.edge_notices(cares_for, Create(ada_pen), |e| e.to, |_| Ok((pen, [ada_pen])), |_| Bool.True, names(["Ada"])) },
		read_step(Carer(Replace(ada, ada_b)), reaching(kennels, [pen]), |reached| Surreal.Mirror.read_notices(carers, Replace(ada, ada_b), reached?, |_| Bool.True, |k| { label: k.label, carers: ["Ada B"] })),
		{ write: Care(Delete(ada_pen)), notices: Surreal.Mirror.edge_notices(cares_for, Delete(ada_pen), |e| e.to, |_| Ok((pen, [])), |_| Bool.True, names([])) },
		read_step(Carer(Replace(ada_b, ada)), Ok([]), |reached| Surreal.Mirror.read_notices(carers, Replace(ada_b, ada), reached?, |_| Bool.True, |k| { label: k.label, carers: [] })),
		unseen(Carer(Delete(ada))),
		{ write: Kennel(Delete(pen)), notices: Surreal.Mirror.notices(kennels, Delete(pen), |_| Bool.True, |k| { label: k.label, carers: [] }) },
		unseen(Site(Delete(dock))),
	].map(|step| [step])
}

## The badge comes; the site of its kennel gets a new name (the second
## hop), the kennel moves to another site (the first hop), and the old
## site, which the badge no longer reaches, gets its name back. A new
## label of the kennel and a new place of its site send nothing: the
## clause reads the `site` of the kennel and the `name` of the site.
badge_sites_steps : List(List(Step(BadgeSite)))
badge_sites_steps = {
	moved = { ..pen, site: sites.link("quay") }
	relabelled = { ..moved, label: "Pen 2" }
	moved_quay = { ..quay, location: Surreal.point(10.76, 59.96) }
	at = |name| |b| { note: b.note, site: name }
	[
		read_step(Site(Create(dock)), Ok([]), |reached| Surreal.Mirror.read_notices(sites, Create(dock), reached?, |_| Bool.True, at("Dock"))),
		read_step(Site(Create(quay)), Ok([]), |reached| Surreal.Mirror.read_notices(sites, Create(quay), reached?, |_| Bool.True, at("Quay"))),
		read_step(Kennel(Create(pen)), Ok([]), |reached| Surreal.Mirror.read_notices(kennels, Create(pen), reached?, |_| Bool.True, at("Dock"))),
		{ write: Badge(Create(tag)), notices: Surreal.Mirror.notices(badges, Create(tag), |_| Bool.True, at("Dock")) },
		read_step(Site(Replace(dock, old_dock)), reaching(badges, [tag]), |reached| Surreal.Mirror.read_notices(sites, Replace(dock, old_dock), reached?, |_| Bool.True, at("Old dock"))),
		read_step(Kennel(Replace(pen, moved)), reaching(badges, [tag]), |reached| Surreal.Mirror.read_notices(kennels, Replace(pen, moved), reached?, |_| Bool.True, at("Quay"))),
		read_step(Site(Replace(old_dock, dock)), Ok([]), |reached| Surreal.Mirror.read_notices(sites, Replace(old_dock, dock), reached?, |_| Bool.True, at("Dock"))),
		unseen(Kennel(Replace(moved, relabelled))),
		unseen(Site(Replace(quay, moved_quay))),
		{ write: Badge(Delete(tag)), notices: Surreal.Mirror.notices(badges, Delete(tag), |_| Bool.True, at("Quay")) },
		read_step(Kennel(Delete(relabelled)), Ok([]), |reached| Surreal.Mirror.read_notices(kennels, Delete(relabelled), reached?, |_| Bool.True, at("Quay"))),
		read_step(Site(Delete(dock)), Ok([]), |reached| Surreal.Mirror.read_notices(sites, Delete(dock), reached?, |_| Bool.True, at("Dock"))),
		read_step(Site(Delete(moved_quay)), Ok([]), |reached| Surreal.Mirror.read_notices(sites, Delete(moved_quay), reached?, |_| Bool.True, at("Quay"))),
	].map(|step| [step])
}

## A carer named "Dock" and a kennel that no badge links to send nothing;
## the badge comes (the `read` statement on `badge`: every carer, none in
## the result); the kennel gets the label "Dock" (the `read` statement on
## `kennel`: every carer, and the carer enters), then its old label (it
## leaves).
badged_carers_steps : List(List(Step(CarerName)))
badged_carers_steps = {
	docker = { id: "docker", name: "Dock" }
	named = |c| { name: c.name }
	labelled = { ..pen, label: "Dock" }
	every = |label| |c| c.name == label
	[
		{ write: Carer(Create(docker)), notices: Surreal.Mirror.notices(carers, Create(docker), |_| Bool.False, named) },
		unseen(Site(Create(dock))),
		read_step(Kennel(Create(pen)), Ok([]), |reached| Surreal.Mirror.read_notices(kennels, Create(pen), reached?, every("Pen"), named)),
		read_step(Badge(Create(tag)), reaching(carers, [docker]), |reached| Surreal.Mirror.read_notices(badges, Create(tag), reached?, every("Pen"), named)),
		read_step(Kennel(Replace(pen, labelled)), reaching(carers, [docker]), |reached| Surreal.Mirror.read_notices(kennels, Replace(pen, labelled), reached?, every("Dock"), named)),
		read_step(Kennel(Replace(labelled, pen)), reaching(carers, [docker]), |reached| Surreal.Mirror.read_notices(kennels, Replace(labelled, pen), reached?, every("Pen"), named)),
		read_step(Badge(Delete(tag)), reaching(carers, [docker]), |reached| Surreal.Mirror.read_notices(badges, Delete(tag), reached?, |_| Bool.False, named)),
		read_step(Kennel(Delete(pen)), Ok([]), |reached| Surreal.Mirror.read_notices(kennels, Delete(pen), reached?, |_| Bool.False, named)),
		unseen(Site(Delete(dock))),
		{ write: Carer(Delete(docker)), notices: Surreal.Mirror.notices(carers, Delete(docker), |_| Bool.False, named) },
	].map(|step| [step])
}

# ------------------------------------------------------------- the platform

## The transport of each session: a WebSocket on `/rpc`, through
## roc-basic-cli-websocket (`WsClient`), whose `receive_within!` lets
## `Session.next_within!` wait for a change with a deadline.
transport : Surreal.Transport
transport = Surreal.Transport.websocket_timed(WsClient.connect, WsClient.ops, "ws://127.0.0.1:8000")

## How long the app waits for a change: a change that does not come in this
## time is a `FAIL`, not a wait with no end. The server sends it in
## milliseconds, not minutes; the limit only ends a run that hangs.
change_limit_ms : U64
change_limit_ms = 60_000

# ------------------------------------------------------------------ the run

## The text of a change.
change_line : Surreal.Change(out) -> Str
change_line = |change| match change {
	Added(ref, row) => "Added ${ref.to_str()} ${Str.inspect(row)}"
	Updated(ref, row) => "Updated ${ref.to_str()} ${Str.inspect(row)}"
	Removed(ref, row) => "Removed ${ref.to_str()} ${Str.inspect(row)}"
}

## The changes that the Mirror predicts for each group of writes, from the
## members of the snapshot.
expected : Surreal.Members, List(List(Step(out))) -> Try(List(List(Surreal.Change(out))), Surreal.Error)
expected = |members, groups| {
	lists = groups.map_try(|steps| steps.map_try(|s| s.notices).map_ok(|each| each.join()))?
	done = lists.fold(
		{ members, out: [] },
		|acc, notices| {
			one = Surreal.Mirror.step_all(acc.members, notices)
			{ members: one.members, out: acc.out.append(one.changes) }
		},
	)
	Ok(done.out)
}

## A reading as text: its record id and its fields. A `TimeKey` has no `==`.
facts : Vital -> Str
facts = |v| "${vitals.ref(v).map_ok(|r| r.to_str()) ?? "?"} pulse ${v.pulse.to_str()} temp_c ${v.temp_c.to_str()} fevered ${Str.inspect(v.fevered)}"

## A write in flight: the ticket of its request, and the statement that
## reads its reply.
Sent : [
	Kennel(Surreal.Ticket(List(Kennel)), Surreal.Prepared(List(Kennel))),
	Care(Surreal.Ticket(List(CaresFor)), Surreal.Prepared(List(CaresFor))),
	Site(Surreal.Ticket(List(Site)), Surreal.Prepared(List(Site))),
	Vital(Surreal.Ticket(List(Vital)), Surreal.Prepared(List(Vital))),
	Carer(Surreal.Ticket(List(Carer)), Surreal.Prepared(List(Carer))),
	Badge(Surreal.Ticket(List(Badge)), Surreal.Prepared(List(Badge))),
]

## Sends one prepared write, with no wait for its reply.
send_one! : Surreal.Session, Try(Surreal.Prepared(a), Surreal.Error) => Try({ session : Surreal.Session, ticket : Surreal.Ticket(a), prepared : Surreal.Prepared(a) }, Str)
send_one! = |session, prepared| {
	statement = prepared.map_err(Str.inspect)?
	sent = session.send!(statement).map_err(Str.inspect)?
	Ok({ session: sent.session, ticket: sent.ticket, prepared: statement })
}

send_write! : Surreal.Session, Write => Try({ session : Surreal.Session, sent : Sent }, Str)
send_write! = |session, write| match write {
	Kennel(edit) => send_one!(session, kennels.edit(edit)).map_ok(|s| { session: s.session, sent: Kennel(s.ticket, s.prepared) })
	Care(edit) => send_one!(session, cares_for.edit(edit)).map_ok(|s| { session: s.session, sent: Care(s.ticket, s.prepared) })
	Site(edit) => send_one!(session, sites.edit(edit)).map_ok(|s| { session: s.session, sent: Site(s.ticket, s.prepared) })
	Vital(edit) => send_one!(session, vitals.edit(edit)).map_ok(|s| { session: s.session, sent: Vital(s.ticket, s.prepared) })
	Carer(edit) => send_one!(session, carers.edit(edit)).map_ok(|s| { session: s.session, sent: Carer(s.ticket, s.prepared) })
	Badge(edit) => send_one!(session, badges.edit(edit)).map_ok(|s| { session: s.session, sent: Badge(s.ticket, s.prepared) })
}

## The reply to a write in flight. A write that fails is an error.
await_write! : Surreal.Session, Sent => Try(Surreal.Session, Str)
await_write! = |session, sent| match sent {
	Kennel(ticket, prepared) => written(session.await!(ticket, prepared))
	Care(ticket, prepared) => written(session.await!(ticket, prepared))
	Site(ticket, prepared) => written(session.await!(ticket, prepared))
	Vital(ticket, prepared) => written(session.await!(ticket, prepared))
	Carer(ticket, prepared) => written(session.await!(ticket, prepared))
	Badge(ticket, prepared) => written(session.await!(ticket, prepared))
}

written : { session : Surreal.Session, result : Try(List(row), Surreal.Error) } -> Try(Surreal.Session, Str)
written = |got| match got.result {
	Ok(_) => Ok(got.session)
	Err(e) => Err("a write failed: ${Str.inspect(e)}")
}

## Sends a group of writes with no wait, then reads their replies, the
## last write first. The server runs the requests in flight with no order
## between them, so the writes of a group do not depend on each other.
write_group! : Surreal.Session, List(Write) => Try(Surreal.Session, Str)
write_group! = |session, writes| {
	var $session = session
	var $sent = []
	for write in writes {
		one = send_write!($session, write)?
		$session = one.session
		$sent = $sent.append(one.sent)
	}
	for one in $sent.rev() {
		$session = await_write!($session, one)?
	}
	Ok($session)
}

## Changes of the watch, read until there are as many as `want` holds, after
## those in `have`. The notices came while the session ran the writes: the
## inbox of the session kept them. A change that does not come in
## `change_limit_ms` is an error that names the changes still missing.
take_changes! : Surreal.Session, Surreal.Live(out), List(Surreal.Change(out)), List(Surreal.Change(out)) => Try({ session : Surreal.Session, live : Surreal.Live(out), changes : List(Surreal.Change(out)) }, Str) where [out.Cbor.Readable(errs), out.is_eq : out, out -> Bool]
take_changes! = |session, live, have, want|
	if have.len() >= want.len() {
		Ok({ session, live, changes: have })
	} else {
		got = session.next_within!(live, change_limit_ms).map_err(Str.inspect)?
		match got.next {
			Got(more) => take_changes!(got.session, got.live, have.concat(more), want)
			Ended => Err("the watch ended before ${want.len().to_str()} changes")
			Unread(e) => Err(Str.inspect(e))
			TimedOut => Err("no change in ${(change_limit_ms // 1000).to_str()} s: ${have.len().to_str()} of ${want.len().to_str()} came, and the Mirror predicts ${Str.join_with(missing(want, have).map(change_line), "; ")} for the rest")
		}
	}

## The predicted changes that none of `have` equals, each `have` taking one.
missing : List(Surreal.Change(out)), List(Surreal.Change(out)) -> List(Surreal.Change(out)) where [out.is_eq : out, out -> Bool]
missing = |want, have| have.fold(want, |left, got|
	match left.find_first_index(|one| one == got) {
		Ok(at) => left.drop_at(at)
		Err(_) => left
	})

## Runs one watch: for each group of writes, the writes on the session,
## then the changes of the group, read from the session. The changes of a
## group must be the changes that the Mirror predicts for it, in any order.
## The count of the lines that fail.
##
## The next group starts after the changes of the group came. SurrealDB
## does not send the notices of two requests in the order of the
## requests, also when the app waited for the reply to the first request
## before it sent the second (`README.md`, the session). Only a notice
## that came before the app sent a write is before the notice of that
## write.
check_watch! : Surreal.Session, Str, Try(Surreal.Watch(out), Surreal.Error), List(List(Step(out))) => Try({ session : Surreal.Session, failures : U64 }, Str) where [out.Cbor.Readable(errs), out.is_eq : out, out -> Bool]
check_watch! = |session, name, watch, groups| {
	started = session.live!(watch.map_err(Str.inspect)?).map_err(Str.inspect)?
	say!("${name}: ${started.view.rows().len().to_str()} rows in the snapshot")?
	predicted = expected(started.live.members(), groups).map_err(Str.inspect)?
	var $session = started.session
	var $live = started.live
	var $have = []
	var $failures = 0
	for (group, want) in groups.map2(predicted, |g, w| (g, w)) {
		$session = write_group!($session, group.map(|step| step.write))?
		read = take_changes!($session, $live, $have, want)?
		$session = read.session
		$live = read.live
		$have = read.changes.drop_first(want.len())
		var $left = want
		for got in read.changes.take_first(want.len()) {
			match $left.find_first_index(|one| one == got) {
				Ok(at) => {
					$left = $left.drop_at(at)
					say!("ok   ${change_line(got)}")?
				}
				Err(_) => {
					$failures = $failures + 1
					say!("FAIL ${change_line(got)}, the Mirror predicts ${Str.join_with(want.map(change_line), "; ")}")?
				}
			}
		}
	}
	next = $session.kill!($live.lives()).map_err(Str.inspect)?
	Ok({ session: next, failures: $failures })
}

## Runs the patch watch: for each write, the write on the session, then
## its patch, applied to a view of the stored rows. The row of the view
## must be the row that Roc wrote. The next write starts after the patch
## came, as in `check_watch!`.
check_patches! : Surreal.Session => Try({ session : Surreal.Session, failures : U64 }, Str)
check_patches! = |session| {
	started = session.live!(vital_patches.map_err(Str.inspect)?).map_err(Str.inspect)?
	say!("vital_patches:")?
	var $session = started.session
	var $live = started.live
	var $view = Surreal.DiffView.empty({})
	var $failures = 0
	for step in patch_steps {
		$session = write_group!($session, [Vital(step.edit)])?
		got_patch = $session.next_within!($live, change_limit_ms).map_err(Str.inspect)?
		$session = got_patch.session
		$live = got_patch.live
		match got_patch.next {
			TimedOut => return Err("no patch in ${(change_limit_ms // 1000).to_str()} s for ${Str.inspect(step.edit)}")
			Got(patch) => {
				$view = $view.apply(patch).map_err(Str.inspect)?
				temp = patch.field(|v| v.temp_c).map_err(Str.inspect)?
				got = $view.get(patch.ref())
				line = "${Str.inspect(patch.action())} ${patch.ref().to_str()}, temp_c ${Str.inspect(temp)}"
				match (got, step.after) {
					(Ok(row), Ok(want)) if facts(row) == facts(want) => say!("ok   ${line}, row ${facts(row)}")?
					(Err(UnknownRef(_)), Err(Gone)) => say!("ok   ${line}, no row")?
					_ => {
						$failures = $failures + 1
						say!("FAIL ${line}: the view holds ${Str.inspect(got.map_ok(facts))}")?
					}
				}
			}
			Unread(e) => {
				$failures = $failures + 1
				say!("FAIL ${Str.inspect(e)}")?
			}
			Ended => {
				$failures = $failures + 1
				say!("FAIL the watch ended")?
			}
		}
	}
	next = $session.kill!($live.lives()).map_err(Str.inspect)?
	Ok({ session: next, failures: $failures })
}

## Each watch in turn on one session. The count of the lines that fail.
run! : {} => Try(U64, Str)
run! = |{}| {
	session = Surreal.Session.open!(transport, Root({ ns: "roc", db: "roc_surreal", user: "root", pass: "root" })).map_err(Str.inspect)?
	first = check_watch!(session, "unattended", unattended, unattended_steps)?
	second = check_watch!(first.session, "fevered", fevered, fevered_steps)?
	third = check_watch!(second.session, "kennel_sites", kennel_sites, kennel_sites_steps)?
	fourth = check_patches!(third.session)?
	reads = check_reads!(fourth.session)?
	Ok(first.failures + second.failures + third.failures + fourth.failures + reads)
}

## The watches of the links that the clauses read, in a session on
## `roc_watch`, which `session` makes again with their tables first.
check_reads! : Surreal.Session => Try(U64, Str)
check_reads! = |session| {
	schema = Surreal.schema(read_definitions).map_err(Str.inspect)?
	_ = Surreal.Unchecked.query!(session, "REMOVE DATABASE IF EXISTS roc_watch; DEFINE DATABASE roc_watch;").map_err(Str.inspect)?
	opened = Surreal.Session.open!(transport, Root({ ns: "roc", db: "roc_watch", user: "root", pass: "root" })).map_err(Str.inspect)?
	defined = Surreal.Unchecked.query!(opened, schema).map_err(Str.inspect)?
	first = check_watch!(defined.session, "labels", labels, labels_steps)?
	second = check_watch!(first.session, "carer_names", carer_names, carer_names_steps)?
	third = check_watch!(second.session, "badge_sites", badge_sites, badge_sites_steps)?
	fourth = check_watch!(third.session, "badged_carers", badged_carers, badged_carers_steps)?
	Ok(first.failures + second.failures + third.failures + fourth.failures)
}

say! : Str => Try({}, Str)
say! = |line| Stdout.line!(line).map_err(Str.inspect)

main! = |_args| match run!({}) {
	Ok(0) => Ok({})
	Ok(_) => Err(Exit(1))
	Err(problem) => {
		Stdout.line!("FAIL ${problem}")?
		Err(Exit(1))
	}
}

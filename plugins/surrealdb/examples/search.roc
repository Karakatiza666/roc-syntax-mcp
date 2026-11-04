## Full-text and vector search: an analyzer, indexes, scores, highlights and nearest-neighbour queries; prints a SurrealQL script, no platform.
# Full-text and vector search over the chart notes of a clinic: an analyzer,
# a full-text index and a vector index, and queries that use them.
#
# One table, `chart`: a note of a visit with its text and a short
# embedding. An analyzer cuts the text into terms, a full-text index and a
# vector index of the table make the searches, and the same values build
# the definitions and the queries. Which rows a search keeps has a Roc
# meaning (`Analyzer.matches`, the `Vector` distances), so its `-- roc:`
# reference is computed over the seed rows. A score, a highlight and the
# distance of a KNN have none: they are intrinsics, SurrealDB computes them,
# and the block of each query says which columns read one (`-- intrinsic:`).
# The literal leaves out such a column, or writes its value by hand, as the
# order and the highlights are.
#
# `roc examples/search.roc` prints a script in the block format of
# `tests/check.py`, which also runs it, after the script of `monitoring.roc`.
# The `-- roc:` and `-- intrinsic:` lines are that check. Skip them when
# reading.

app [main!] { surreal: "https://github.com/Karakatiza666/roc-reify-surrealdb/releases/download/0.0.1/7MmdAaAt5bThg6ih3nR9ewVgw4CtNGvuK5HNQhEgZoSV.tar.zst" }

import surreal.Surreal

Chart : { id : Str, patient : Str, body : Str, embedding : List(F64) }

charts : Surreal.Table(Chart)
charts = Surreal.table("chart")

## Terms are the runs of letters, of digits and of other characters, in
## lower case: `Limping,` is `limping` and `,`. The Roc meaning of a
## search is this analyzer's (`Analyzer.matches`).
clinical : Surreal.Analyzer
clinical = Surreal.analyzer("clinical", [Class], [Lowercase])

chart_text : Surreal.FullText(Chart)
chart_text = charts.text_index(|c| c.body, clinical)

chart_vectors : Surreal.VectorIndex(Chart)
chart_vectors = charts.vector_index(|c| c.embedding, { dimension: 3, distance: Cosine })

chart_def : Surreal.Defined
chart_def = charts.define().text_index(chart_text).vector_index(chart_vectors).done()

seed_charts : List(Chart)
seed_charts = [
	{ id: "c1", patient: "rex", body: "Rex limps on the left hind leg after a walk.", embedding: [0.9, 0.1, 0.0] },
	{ id: "c2", patient: "rex", body: "Rex limping again, left leg swollen.", embedding: [0.8, 0.3, 0.1] },
	{ id: "c3", patient: "luna", body: "Luna vomits after meals; diet changed.", embedding: [0.1, 0.9, 0.2] },
	{ id: "c4", patient: "mimi", body: "Mimi has a limping gait, right leg sore.", embedding: [0.6, 0.2, 0.5] },
	{ id: "c5", patient: "kiwi", body: "Kiwi plucks feathers; stress likely.", embedding: [0.0, 0.2, 0.95] },
	{ id: "c6", patient: "bo", body: "Bo eats well and no limping.", embedding: [0.3, 0.6, 0.3] },
	{ id: "c7", patient: "pip", body: "Pip: booster given, left ear clean.", embedding: [0.2, 0.1, 0.8] },
]

## The probe of the nearest notes: a limp.
limp_probe : List(F64)
limp_probe = [1.0, 0.0, 0.0]

## A probe of the `Vector` functions, read in a clause.
probe : List(F64)
probe = [0.5, 0.25, 0.125]

ChartId : { id : Str }

## Where `left` and `leg` are in the notes that have both, by hand: the
## offsets have no Roc meaning.
left_leg_offsets : List({ id : Str, at : List({ start : I64, end : I64 }) })
left_leg_offsets = [{ id: "c1", at: [{ start: 17, end: 21 }, { start: 27, end: 30 }] }, { id: "c2", at: [{ start: 19, end: 23 }, { start: 24, end: 27 }] }]

Measures : { id : Str, cosine : F64, euclidean : F64, manhattan : F64, chebyshev : F64, dot : F64, magnitude : F64 }

## The `Vector` functions of the embedding of a note, in a clause and in Roc.
measures : Chart -> Measures
measures = |c| {
	id: c.id,
	cosine: Surreal.Vector.similarity_cosine(c.embedding, probe),
	euclidean: Surreal.Vector.distance_euclidean(c.embedding, probe),
	manhattan: Surreal.Vector.distance_manhattan(c.embedding, probe),
	chebyshev: Surreal.Vector.distance_chebyshev(c.embedding, probe),
	dot: Surreal.Vector.dot(c.embedding, probe),
	magnitude: Surreal.Vector.magnitude(c.embedding),
}

## The cosine distance of the index, `1 - similarity`, from the probe.
from_limp : Chart -> F64
from_limp = |c| 1 - Surreal.Vector.similarity_cosine(c.embedding, limp_probe)

## The Roc meaning of `nearest(chart_vectors, limp_probe, Exact(k))`:
## the rows nearest the probe, the first `k`.
nearest : List(Chart), U64 -> List(Chart)
nearest = |rows, k| rows.sort_with(|a, b| if (from_limp(a) < from_limp(b)) Before else if (from_limp(a) > from_limp(b)) After else Same).take_first(k)

ids : List(Chart) -> List(ChartId)
ids = |rows| rows.map(|c| { id: c.id })

found : Str -> List(Chart)
found = |terms| seed_charts.keep_if(|c| clinical.matches(c.body, terms))

expect clinical.tokens("Rex limping again, left leg.") == ["rex", "limping", "again", ",", "left", "leg", "."]
expect ids(found("limping")) == [{ id: "c2" }, { id: "c4" }, { id: "c6" }]
expect ids(found("Left LEG")) == [{ id: "c1" }, { id: "c2" }]
expect found("").is_empty()
expect ids(nearest(seed_charts, 3)) == [{ id: "c1" }, { id: "c2" }, { id: "c4" }]

# ------------------------------------------------------------------ blocks

block : Str, List(Str), Try(Surreal.Prepared(out), Surreal.Error), Try(Str, Surreal.Error) -> Str
block = |header, flags, prepared, reference| match (prepared, reference) {
	(Ok(p), Ok(literal)) => p.statement().block(header, flags.append("-- roc: ${literal}"))
	(Err(e), _) | (_, Err(e)) => "-- unsupported ${header}: ${Str.inspect(e)}"
}

plain : Str, List(Str), Try(Surreal.Prepared(out), Surreal.Error) -> Str
plain = |header, flags, prepared| match prepared {
	Ok(p) => p.statement().block(header, flags)
	Err(e) => "-- unsupported ${header}: ${Str.inspect(e)}"
}

schema_block : Str
schema_block = match Surreal.schema([clinical.define(), chart_def]) {
	Ok(text) => "-- schema\n${text}"
	Err(e) => "-- bad schema: ${Str.inspect(e)}"
}

queries : List(Str)
queries = [
	block(
		"-- query: search_limping",
		[],
		Surreal.from(charts).search(chart_text, "limping").select(|(c, _)| { id: c.id }).prepare({}),
		Surreal.Mirror.literal(ids(found("limping"))),
	),
	block(
		"-- query: search_two_terms",
		[],
		Surreal.from(charts).search(chart_text, "Left LEG").select(|(c, _)| { id: c.id }).prepare({}),
		Surreal.Mirror.literal(ids(found("Left LEG"))),
	),
	block(
		"-- query: search_no_term",
		[],
		Surreal.from(charts).search(chart_text, "").select(|(c, _)| { id: c.id }).prepare({}),
		Surreal.Mirror.literal(ids(found(""))),
	),
	block(
		"-- query: search_after_filter",
		[],
		Surreal.from(charts).filter(|c| c.patient == "rex").search(chart_text, "limping").select(|(c, _)| { id: c.id }).prepare({}),
		Surreal.Mirror.literal(ids(found("limping").keep_if(|c| c.patient == "rex"))),
	),
	# The score has no Roc meaning: the order, the best first, and the
	# highlights are written by hand.
	block(
		"-- query: search_ranked",
		["-- ordered"],
		Surreal.from(charts)
			.search(chart_text, "limping")
			.select(|(c, hit)| { id: c.id, score: hit.score(), marked: hit.highlight("<b>", "</b>") })
			.order_by(|r| r.score, Desc)
			.prepare({}),
		Surreal.Mirror.literal(
			[
				{ id: "c6", marked: "Bo eats well and no <b>limping</b>." },
				{ id: "c2", marked: "Rex <b>limping</b> again, left leg swollen." },
				{ id: "c4", marked: "Mimi has a <b>limping</b> gait, right leg sore." },
			],
		),
	),
	block(
		"-- query: search_offsets",
		[],
		Surreal.from(charts).search(chart_text, "left leg").select(|(c, hit)| { id: c.id, at: hit.offsets() }).prepare({}),
		Surreal.Mirror.literal(left_leg_offsets),
	),
	block(
		"-- query: vector_measures",
		[],
		Surreal.from(charts).select(measures).prepare({}),
		Surreal.Mirror.literal(seed_charts.map(measures)),
	),
	block(
		"-- query: vector_filter",
		[],
		Surreal.from(charts).filter(|c| Surreal.Vector.similarity_cosine(c.embedding, probe) > 0.9).select(|c| { id: c.id }).prepare({}),
		Surreal.Mirror.literal(ids(seed_charts.keep_if(|c| Surreal.Vector.similarity_cosine(c.embedding, probe) > 0.9))),
	),
	# The distance of a KNN has no Roc meaning, and the order by it is
	# the order of `from_limp`.
	block(
		"-- query: nearest_exact",
		["-- ordered"],
		Surreal.from(charts).nearest(chart_vectors, limp_probe, Exact(3)).select(|(c, near)| { id: c.id, distance: near.distance() }).order_by(|r| r.distance, Asc).prepare({}),
		Surreal.Mirror.literal(ids(nearest(seed_charts, 3))),
	),
	block(
		"-- query: nearest_approx",
		[],
		Surreal.from(charts).nearest(chart_vectors, limp_probe, Approx({ k: 3, ef: 40 })).select(|(c, _)| { id: c.id }).prepare({}),
		Surreal.Mirror.literal(ids(nearest(seed_charts, 3))),
	),
	block(
		"-- query: nearest_after_filter",
		[],
		Surreal.from(charts).filter(|c| c.patient != "rex").nearest(chart_vectors, limp_probe, Exact(2)).select(|(c, _)| { id: c.id }).prepare({}),
		Surreal.Mirror.literal(ids(nearest(seed_charts.keep_if(|c| c.patient != "rex"), 2))),
	),
]

refusals : List(Str)
refusals = [
	plain("-- rejects: vector_dimension", ["-- error: Incorrect vector dimension (2)"], charts.create({ id: "c9", patient: "rex", body: "Short.", embedding: [1.0, 0.0] })),
]

script : Str
script = Str.join_with([schema_block, plain("-- seed: chart", [], charts.insert(seed_charts))].concat(queries).concat(refusals), "\n\n")

main! = |_args| {
	echo!("${script}\n")
	Ok({})
}

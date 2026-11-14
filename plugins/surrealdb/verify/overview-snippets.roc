## Every snippet the overview page shows, in one app, so the page cannot drift.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.27.0/9yjxqdGTP4xSpSEmDazwTmRsehfRZzA19pwEKkR6fj1g.tar.zst",
	cli_ws: "https://github.com/Karakatiza666/roc-basic-cli-websocket/releases/download/0.0.4/B5j45zNdyW8Qxq6GpQ6ZVNmcPC5hwx3TxPRW4cq8wiLV.tar.zst",
	surreal: "https://github.com/Karakatiza666/roc-reify-surrealdb/releases/download/0.0.4/CkLUeGcqAc6kNLaDf5rMbQEaZAE7nxapCE4EsHnqh5HY.tar.zst",
}

import pf.Stdout
import surreal.Surreal

Owner : { id : Str, name : Str, city : Str }

owners : Surreal.Table(Owner)
owners = Surreal.table("owner")

CityParam : { city : Str }

in_city : CityParam, Owner -> Bool
in_city = |p, o| o.city == p.city

oslo : Surreal.Prepared(List({ id : Str, name : Str }))
oslo =
	Surreal.from(owners).filter_by(in_city).select(|o| { id: o.id, name: o.name }).prepare({ city: "Oslo" })
# LET $city = 'Oslo'; SELECT record::id(id) AS id, name AS name FROM owner WHERE city = $city;

show : Surreal.Prepared(out) -> Str
show = |prepared| match prepared.statement() {
	Ok(statement) => statement.to_script()
	Err(e) => Str.inspect(e)
}

main! = |_args| Stdout.line!(show(oslo))

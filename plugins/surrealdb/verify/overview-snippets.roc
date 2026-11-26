## Every snippet the overview page shows, in one app, so the page cannot drift.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	cli_ws: "https://github.com/Karakatiza666/roc-basic-cli-websocket/releases/download/0.0.5/AZpgG3RszEahBa67zc9yCJcAKe4MKw5HucDouNpi727b.tar.zst",
	surreal: "https://github.com/Karakatiza666/roc-reify-surrealdb/releases/download/0.0.6/2tpVeMyJCHagfi9hgtFKLe9SZVEwKoHzWxxwwk33Anfk.tar.zst",
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

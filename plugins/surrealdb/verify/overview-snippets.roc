## Every snippet the overview page shows, in one app, so the page cannot drift.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	cli_ws: "https://github.com/Karakatiza666/roc-basic-cli-websocket/releases/download/0.0.3/9c6XLWHRSREuaoELdH1a835Yopw92Jxy2b5e151X6mZj.tar.zst",
	surreal: "https://github.com/Karakatiza666/roc-reify-surrealdb/releases/download/0.0.1/7MmdAaAt5bThg6ih3nR9ewVgw4CtNGvuK5HNQhEgZoSV.tar.zst",
}

import pf.Stdout
import surreal.Surreal

Owner : { id : Str, name : Str, city : Str }

owners : Surreal.Table(Owner)
owners = Surreal.table("owner")

CityParam : { city : Str }

in_city : CityParam, Owner -> Bool
in_city = |p, o| o.city == p.city

oslo : Try(Surreal.Prepared(List({ id : Str, name : Str })), Surreal.Error)
oslo =
	Surreal.from(owners).filter_by(in_city).select(|o| { id: o.id, name: o.name }).prepare({ city: "Oslo" })
# LET $city = 'Oslo'; SELECT record::id(id) AS id, name AS name FROM owner WHERE city = $city;

main! = |_args| match oslo {
	Ok(p) => Stdout.line!(p.statement().to_script())
	Err(e) => Stdout.line!(Str.inspect(e))
}

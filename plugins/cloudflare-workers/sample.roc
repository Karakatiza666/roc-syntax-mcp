db = D1.binding("DB")

Item : { id : I64, name : Str }

fetch! : Request => Try(Response, _)
fetch! = |req| match (req.method(), req.segments()) {
	(GET, ["items", id_text]) => {
		id = I64.from_str(id_text) ? |_| BadId
		item : Item
		item = db.first!("SELECT id, name FROM items WHERE id = ?", [id])?
		Ok(Response.from_json(200, item))
	}
	_ => Ok(Response.from_status(404))
}

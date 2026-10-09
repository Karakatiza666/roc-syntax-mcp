## A list of expenses. Amounts are whole cents, never fractional dollars.
Ledger := [].{
	## One line of a ledger.
	Entry : { label : Str, cents : I64 }

	## Appends an entry. Entries keep the order they were added in.
	add : List(Entry), Str, I64 -> List(Entry)
	add = |entries, label, cents| List.append(entries, { label, cents })

	## The sum of all entries, in cents.
	total : List(Entry) -> I64
	total = |entries| List.fold(entries, 0, |sum, e| sum + e.cents)

	## Formats cents as dollars with two decimals, so `1825` is `"$18.25"`.
	dollars : I64 -> Str
	dollars = |cents| {
		rest = cents % 100
		pad = if rest < 10 "0" else ""
		"$${(cents // 100).to_str()}.${pad}${rest.to_str()}"
	}

	## One line per entry, as `label  $1.25`.
	lines : List(Entry) -> List(Str)
	lines = |entries| List.map(entries, |e| "${e.label}  ${dollars(e.cents)}")
}

## The bundled roc-random release, compiled with basic-cli, so that the gate
## checks the pin in UPSTREAM and the nightly as a pair. Every call here is a
## call that an app makes.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst",
	rand: "https://github.com/kili-ilo/roc-random/releases/download/0.9.2/2ZXLX8WRqrosGu1V3VL5aXqgtfTRvJmjFPx8a26ecVmc.tar.zst",
}

import pf.Stdout
import rand.Random

Point : { x : U8, y : U8 }

point : Random.Generator(Point)
point = Random.map2(Random.bounded_u8(0, 9), Random.bounded_u8(0, 9), |x, y| { x, y })

main! = |_args| {
	first = Random.step(Random.seed(42), Random.u8)
	second = Random.next(first, Random.list(point, 3))
	dice = Random.next(second, Random.list(Random.bounded_u8(1, 6), 5))
	picked = Random.next(dice, Random.choice("red", ["green", "blue"]))
	deck = Random.next(picked, Random.shuffle([1, 2, 3, 4]))
	Stdout.line!("${first.value.to_str()} ${second.value.len().to_str()} ${dice.value.len().to_str()} ${picked.value} ${deck.value.len().to_str()}")?
	Ok({})
}

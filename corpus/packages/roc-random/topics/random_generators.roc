## Pseudorandom values with kili-ilo/roc-random: generators composed as values,
## a `State` threaded by hand from one draw to the next, and a seed that comes
## from the platform.
##
## Nothing here is effectful. A `Generator(a)` is a function from a `State` to a
## `Generation(a)`, which is `{ value, state }`, so the same seed always gives
## the same values. So you can test a game step or a simulation with `expect`.
## The only effect is to read a seed, and the platform does that.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst",
	rand: "https://github.com/kili-ilo/roc-random/releases/download/0.9.2/2ZXLX8WRqrosGu1V3VL5aXqgtfTRvJmjFPx8a26ecVmc.tar.zst",
}

# basic-cli has its own `Random` module, which only reads OS entropy. Importing
# both by their own names is a "duplicate definition" of `Random`, so the
# platform's module gets another name.
import pf.Random as Entropy
import pf.Stdout
import rand.Random

# --- Generators are values ---------------------------------------------------
#
# Build them from the primitives and combine them with map, map2 and chain.
# Bounds are inclusive for integers. `f64(lo, hi)` excludes `hi`.

Point : { x : I32, y : I32 }

point : Random.Generator(Point)
point = Random.map2(Random.bounded_i32(-10, 10), Random.bounded_i32(-10, 10), |x, y| { x, y })

die : Random.Generator(U8)
die = Random.bounded_u8(1, 6)

# `choice` takes the first item apart from the rest, so it can never get an
# empty list. `choice_try` takes a plain list and returns a `Try`.
suit : Random.Generator(Str)
suit = Random.choice("hearts", ["spades", "diamonds", "clubs"])

# `chain` is for a generator that depends on an earlier value: here, how many
# dice to roll is itself random.
hand : Random.Generator(List(U8))
hand = Random.chain(die, |count| Random.list(die, count.to_u64()))

# --- Threading the state -----------------------------------------------------
#
# `step` starts from a `State`, and `next` continues from the previous
# `Generation`. Reusing one state for two draws gives the same value twice.
# This is the usual mistake. Every draw must take the state that the last draw
# returned.

two_rolls : Random.State -> (U8, U8)
two_rolls = |state| {
	first = Random.step(state, die)
	second = Random.next(first, die)
	(first.value, second.value)
}

# A loop carries the state from one draw to the next. `Random.list` does this
# for you when every element comes from the same generator.
walk : Random.State, U64 -> (I32, Random.State)
walk = |start, steps| {
	var $state = start
	var $pos = 0
	for _ in 0.U64.until(steps) {
		drawn = Random.step($state, Random.choice(-1, [1]))
		$pos = $pos + drawn.value
		$state = drawn.state
	}
	($pos, $state)
}

# A fixed seed makes every draw reproducible, so a test can rely on it.
expect {
	seeded = Random.seed(42)
	two_rolls(seeded) == two_rolls(seeded)
}

expect {
	(pos, _) = walk(Random.seed(7), 10)
	pos >= -10 and pos <= 10
}

expect Random.step(Random.seed(1), Random.list(die, 4)).value.len() == 4

# --- The seed ----------------------------------------------------------------
#
# `Random.seed` takes a `U32`. Reading one from the OS is an effect, so the app
# does it once, at the edge of the program, and everything after it is pure.
main! = |_args| {
	seed = Entropy.seed_u32!()?
	at = Random.step(Random.seed(seed), point)
	cards = Random.next(at, Random.list(suit, 3))
	rolled = Random.next(cards, hand)
	Stdout.line!("point ${at.value.x.to_str()},${at.value.y.to_str()}")?
	Stdout.line!("suits ${Str.join_with(cards.value, " ")}")?
	Stdout.line!("rolled ${rolled.value.len().to_str()} dice")?
	Ok({})
}

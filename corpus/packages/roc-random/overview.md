# roc-random

`kili-ilo/roc-random`: pseudorandom numbers, choices and shuffles from a seed.
Generation is pure. A `Generator(a)` turns a `State` into a `Generation(a)`,
which is `{ value, state }`, so one seed always gives the same values and a
test can rely on them. It works on any platform. Only the seed is an effect,
and the platform supplies it.

```roc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	rand: "https://github.com/kili-ilo/roc-random/releases/download/0.9.2/2ZXLX8WRqrosGu1V3VL5aXqgtfTRvJmjFPx8a26ecVmc.tar.zst",
}

import pf.Random as Entropy
import rand.Random
```

| Need | Use |
|---|---|
| A starting state | `Random.seed(u32)`. From OS entropy on basic-cli: `Entropy.seed_u32!()` |
| One value | `Random.step(state, generator)`, then `Random.next(previous, generator)` |
| Integers | `Random.u8` to `Random.i64` for the full range. `Random.bounded_i32(lo, hi)` and its siblings, both ends inclusive |
| Floats | `Random.f64(lo, hi)`, `hi` excluded |
| Picking | `Random.choice(first, rest)`, `Random.choice_weighted`, `Random.shuffle(list)` |
| Combining | `Random.map`, `Random.map2`, `Random.chain`, `Random.list(generator, count)` |

## Traps

- Each draw returns a new state. Passing the same state to two draws gives the
  same value twice. Use `Random.next` on the last `Generation`, or carry the
  state in a loop.
- basic-cli has its own `Random` module, which only reads OS entropy. Importing
  both under one name is a "duplicate definition". Import
  `pf.Random as Entropy`, as above.
- `Random.choice` takes the first item apart from the rest, so it cannot get an
  empty list. `Random.choice_try` takes a plain list and returns a `Try`.

The worked program is the `random_generators` topic:
`get_roc_syntax(topic: "random_generators")`.

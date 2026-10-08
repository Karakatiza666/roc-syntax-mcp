# Range operators `..<` and `..=`, and the `Range(num)` value they build.
#
# `start..<end` excludes `end`, and `start..=end` includes it. Both build a
# reusable `Range(num)` that describes the span. Neither is a lazy stream.

# `for` calls the range's `iter` method automatically.
sum_to : U64 -> U64
sum_to = |n| {
	var $total = 0

	for i in 0..<n {
		$total = $total + i
	}

	$total
}

# Both bounds must have the same type, and the result is a `Range` of that
# type: a `U8` range is a `Range(U8)`, a `Dec` range is a `Range(Dec)`. When
# nothing pins the bounds' type, range literals default the way other number
# literals do.
byte_range : Range(U8)
byte_range = 0.U8..<16

# A range starts with a step of 1. `step_by` sets the absolute step and does not
# compose with the old one, so a second call replaces the first step.
#   Range.step_by : Range(num), num -> Range(num)
every_third : Range(U64)
every_third = (0..<30).step_by(3)

# `size_hint` returns `Known(count)` when the exact count fits in a `U64`, and
# `Unknown` otherwise.
#   Range.size_hint : Range(num) -> [Known(U64), Unknown]
hint = (0..<30).size_hint()

# `iter` walks forwards. `iter_rev` walks the same lower-anchored members
# backwards, so `(5.I64..=12).step_by(2).iter_rev()` yields 11, 9, 7, 5.
#   Range.iter     : Range(num) -> Iter(num)
#   Range.iter_rev : Range(num) -> Iter(num)
descending : List(I64)
descending = (5.I64..=12).step_by(2).iter_rev().collect()

# Integer and `Dec` ranges support `iter_rev`. `F32` and `F64` support forward
# ranges but deliberately do not support `iter_rev`, because repeated
# floating-point addition is not exactly reversible. Forward iteration over a
# float range ends when adding the step cannot produce a larger float. The
# range yields the current value once and then ends.

# A range is empty when its lower bound is not below (`..<`) or at (`..=`) its
# upper bound, or when its step is not positive. So `5..<5` yields nothing,
# but `5..=5` yields 5.

# Range operators bind more loosely than the other binary operators, so
# `1..<n + 1` parses as `1..<(n + 1)`. They cannot be chained: `1..<5..<10`
# is an error.

# Ranges use static dispatch like every other operator: `..<` calls
# `range_exclusive_to` on the bounds' type and `..=` calls
# `range_inclusive_to`. A custom numeric type opts into range syntax by
# defining them and building the stored value with `Range.custom`.
PageNum := { num : U32 }.{
	range_exclusive_to : PageNum, PageNum -> Range(PageNum)
	range_exclusive_to = |start, end|
		Range.custom({
			lower: start,
			upper: end,
			step: PageNum.{ num: 1 },
			upper_bound: Exclusive,
			direction: To,
			len_if_known: Unknown,
		})
}

# To iterate that value, `PageNum` also defines `range_iter` in terms of its own
# representation. Defining `range_exclusive_from` and `range_inclusive_from`
# opts it into `Range.iter_rev`. A type whose stepping is not exactly reversible
# can omit them. `range_len_if_known` supplies an exact `U64` count when the
# type can represent one.

# `Range` is in scope unqualified, but `search_symbols` lists these methods
# under their full path `Num.Range.*`.

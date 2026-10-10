# Memory in Roc: values, reference counting, and in-place updates.
#
# Roc manages memory automatically. A value is immutable. Roc has no pointers,
# no reference equality and no way to read the address of a value, so `==`
# compares contents only.
expect [1, 2] == [1, 2]

# `Str`, `List` and `Box` are on the heap, and have a reference count. A
# record, a tuple and a non-recursive tag union are stored inline, with no
# allocation of their own: in a local on the stack, or inside the value that
# holds them. Only their `Str`, `List` and `Box` parts have a reference count.
# Each place where a recursive nominal type refers to itself is a separate heap
# allocation with a reference count, so a recursive type needs no `Box`. The
# count of a value that the host can see is atomic, so host threads can share
# it. A value that never reaches the host has a faster, non-atomic count. Roc
# cannot express a reference cycle, so it needs no cycle collector and no weak
# references.
#
# Pure code can allocate memory. A failed allocation crashes the program.

# `Box.box(value)` copies a value into its own heap allocation, and
# `Box.unbox` copies it back. A `Box` is one pointer, whatever the size of its
# value. A tag union is as large as its largest payload, so to make a big list
# of a union smaller, box a large payload that few values use.
expect Box.unbox(Box.box(42)) == 42

# A `Box` has no `is_eq`. To compare the values, write
# `Box.unbox(a) == Box.unbox(b)`.
#
# @rejects missing method
# same_box = Box.box(1.U8) == Box.box(1.U8)

# A builtin update such as `List.set` changes a unique value (reference count
# 1) in place. It first makes a shallow copy of a shared value, so other names
# keep the old contents. To get the in-place update, do not keep a second
# reference to the old value. The in-place update matters most in a loop or a
# recursive function that updates a large collection. A top-level value such as
# `original` is evaluated at compile time and never freed, so its first update
# is a copy (see the `compile_time` topic).
original = [1, 2, 3]
changed = original.set(0, 9) ?? []

expect original == [1, 2, 3] and changed == [9, 2, 3]

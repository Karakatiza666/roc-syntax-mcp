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
# A recursive tag union refers to itself through a `Box`, so each level is on
# the heap. The count is atomic, so threads can share a value. Roc cannot
# express a reference cycle, so it needs no cycle collector and no weak
# references.
#
# Pure code can allocate memory. A failed allocation crashes the program.

# A builtin update such as `List.set` changes a unique value (reference count
# 1) in place. It first makes a shallow copy of a shared value, so other names
# keep the old contents. To get the in-place update, do not keep a second
# reference to the old value.
original = [1, 2, 3]
changed = original.set(0, 9) ?? []

expect original == [1, 2, 3] and changed == [9, 2, 3]

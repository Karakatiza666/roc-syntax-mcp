# Hashing: the `to_hash` method, the `Hasher` builder, and `Crypto` digests.
#
# `to_hash` is the well-known method that hash-based APIs use. It does not
# return a number: it feeds data into a `Hasher` and returns the updated hasher,
# so nested values can each contribute in turn.
#
#   to_hash : T, Hasher -> Hasher

# Every `Hasher.write_*` method takes the hasher first and returns a new one, so
# writes chain:
#   write_bool  write_str   write_bytes
#   write_u8  write_u16  write_u32  write_u64  write_u128
#   write_i8  write_i16  write_i32  write_i64  write_i128
#   write_f32  write_f64  write_dec
Point := { x : I64, y : I64 }.{
	to_hash : Point, Hasher -> Hasher
	to_hash = |point, hasher| hasher.write_i64(point.x).write_i64(point.y)

	is_eq : Point, Point -> Bool
	is_eq = |a, b| a.x == b.x and a.y == b.y
}

# `Dict` and `Set` keys must be both hashable and comparable, so a key type
# needs `to_hash` and `is_eq`. If you define custom equality, keep the hash
# consistent with it: values that compare equal must feed the same hash data,
# or lookups will miss. A function has neither method, so it cannot be a key.
# See the `dict_set` topic.
#
# A `Dict` built at runtime hashes with a seed that the program chooses at
# random each time it runs. This protects against hash flooding, an attack
# that sends many keys with the same hash to slow the program down.

# Most types can let the compiler derive both. See the `derived_methods` topic.
Model := { value : Str }.{
	is_eq : _
	to_hash : _
}

# `Crypto` provides cryptographic digests, which are a separate concern from
# `to_hash`. `to_hash` feeds Roc's internal hasher for collections. `Crypto`
# produces a stable digest value you can print or compare.
#
#   Crypto.SHA256.hash        : List(U8) -> Digest
#   Crypto.SHA256.hash_chunks : Iter(List(U8)) -> Digest
#   Crypto.BLAKE3.hash        : List(U8) -> Digest
#   Crypto.BLAKE3.hash_chunks : Iter(List(U8)) -> Digest
digest_of : Str -> Str
digest_of = |text| Crypto.SHA256.hash(text.to_utf8()).to_hex()

# A `Digest` converts both ways, and the parsing directions return a `Try`.
#   Digest.to_bytes   : Digest -> List(U8)
#   Digest.to_hex     : Digest -> Str
#   Digest.from_bytes : List(U8) -> Try(Digest, Crypto.DigestBytesErr)
#   Digest.from_hex   : Str -> Try(Digest, Crypto.DigestHexErr)
#
# `DigestBytesErr` is `[WrongLength({ expected : U64, actual : U64 })]`, and
# `DigestHexErr` adds `InvalidHex({ index : U64, byte : U8 })`.
parse_digest : Str -> Try(Crypto.SHA256.Digest, Crypto.DigestHexErr)
parse_digest = |hex| Crypto.SHA256.Digest.from_hex(hex)

# `hash_chunks` takes an `Iter` of byte chunks, so a large input never has to be
# concatenated into one list first.
digest_chunks : List(List(U8)) -> Crypto.SHA256.Digest
digest_chunks = |chunks| Crypto.SHA256.hash_chunks(chunks.iter())

# For a streaming digest, use the incremental `Hasher` form of the algorithm.
#   Crypto.SHA256.Hasher.empty  : () -> Hasher
#   Crypto.SHA256.Hasher.write  : Hasher, List(U8) -> Hasher
#   Crypto.SHA256.Hasher.finish : Hasher -> Digest
digest_incremental : List(List(U8)) -> Crypto.SHA256.Digest
digest_incremental = |chunks|
	chunks
		.iter()
		.fold(Crypto.SHA256.Hasher.empty(), Crypto.SHA256.Hasher.write)
		.finish()

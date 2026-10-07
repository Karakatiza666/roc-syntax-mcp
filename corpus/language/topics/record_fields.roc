# Defaulted and optional record fields, and the `..rest` pattern.
#
# A record field can have a default value or be optional. Both let you leave
# the field out when you build the record, but they read differently:
#
#   field : Type ?? default   defaulted. Always present when read, so plain
#                             `.field` works and needs no unwrapping.
#   field ?: Type             optional. May be absent, so read it with
#                             `.?field`, which gives a `Try(Type, [MissingField])`.
#
# A default belongs to one named type, so it is only allowed on the backing
# record of a nominal (`:=`) declaration. A structural record type (an alias,
# an inline annotation or a nested record) cannot carry one, and every
# construction names the type: `ServerConfig.{ ... }`.

ServerConfig := { host : Str, port : U16 ?? 8080, timeout_ms ?: U64 }

describe_config : ServerConfig -> Str
describe_config = |config| {
	timeout_str = match config.?timeout_ms {
		Ok(ms) => "${ms.to_str()}ms"
		Err(MissingField) => "no timeout"
	}

	# `config.port` needs no unwrapping. It holds the default when the record omits it.
	"${config.host}:${config.port.to_str()} (${timeout_str})"
}

# Only `host` is required, so this builds fine.
minimal_config : ServerConfig
minimal_config = ServerConfig.{ host: "localhost" }

# Reading an omitted optional field gives `Err(MissingField)`. An omitted
# defaulted field reads as its default.
expect minimal_config.?timeout_ms == Err(MissingField)
expect minimal_config.port == 8080

full_config : ServerConfig
full_config = ServerConfig.{ host: "example.com", port: 80, timeout_ms: 5000 }

expect full_config.?timeout_ms == Ok(5000)

# `..rest` in a record pattern binds every field you did not name as a new
# record, so it is also a way to remove a field: `rest` is `person` without
# `email`.
remove_record_field : { name : Str, age : I64, email : Str } -> { name : Str, age : I64 }
remove_record_field = |person| {
	{ email: _, ..rest } = person
	rest
}

# Record update copies a record with some fields replaced.
bump_age : { name : Str, age : I64 } -> { name : Str, age : I64 }
bump_age = |person| { ..person, age: 31 }

# Field names are lowercase. They are a compile-time concept: field access is a
# fixed offset, and the name strings are not stored at runtime.

# Imports bring types from other modules into scope.
#
# `import` may appear only at the top level of a module, and it imports types:
# each type module exposes exactly one type. It cannot be used with other
# categories of module.

# Plain import.
# import Color
# import pf.Stdout
# import json.Parser

# `exposing` brings specific items in without a qualifier or module prefix, so
# `to_str(x)` works instead of `Json.to_str(x)`, and `Request` can be written in
# an annotation without the `Http.` prefix.
# import pkg.Json exposing [to_str, decode]
# import Http exposing [Request, Response]

# `as` renames the import.
# import Color as CC
# import json.Parser as JP

# Subdirectories: `/` traverses source directories, `.` selects a type nested
# inside a module. `as` and `exposing` never change which file is selected.
#
#   import Url.ParseErr    loads Url.roc and imports the nested ParseErr
#   import Url/ParseErr    loads Url/ParseErr.roc
#
# A bare target or one starting with `./` is relative to the importing file.
# `../` moves toward the package root, and a leading `/` starts at the package
# root.
# import Helper
# import ./Internal/Parser
# import ../Shared/Codec
# import /Public/Api

# Package-qualified imports use one dot after the lowercase package alias, then
# the public module name. Further dots select nested types.
# import json.Parser
# import json.Parser.ParseErr as PE
#
# Package aliases come from the module header:
#   app [main!] { pf: platform "https://...", json: "https://..." }
#
# Directory traversal is private to the package that declares a public module,
# so consumers use the public name rather than the internal source path.

# Embed a file's contents as a constant at compile time. The path is relative to
# the importing file.
# import "../../README.md" as readme : Str
#
# Once imported, the embedded constant is used like any other Str:
#   readme.contains("Roc")

# Mutually recursive types cannot both be exposed from one type module, since a
# type module exposes a single type. Wrap them in a void module instead:
#
#   # FooBar.roc
#   FooBar :: {}.{
#       Foo := [BarVal(Bar), Nothing]
#       Bar := [FooVal(Foo), Nothing]
#   }
#
# Then `import FooBar` and reference `FooBar.Foo` and `FooBar.Bar`, or
# `import FooBar.Foo` and `import FooBar.Bar` to get them unqualified.
# Separate alias modules would also work, but alias modules are not implemented
# yet.

# `echo!` is provided by the built-in Echo platform and needs no import. See
# the `app_header` topic.

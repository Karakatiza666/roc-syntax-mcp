# Imports bring types from other modules into scope.
#
# `import` may appear only at the top level of a module, and it imports types:
# each type module exposes exactly one type. It cannot be used with other
# categories of module. See the `modules` topic for what a type module exposes.
#
# @rejects import must be top level
# load_color = |x| {
# 	import Color
# 	x
# }

# Plain import. `import Color` brings in the type itself, so `Color.all`,
# `Color.to_str(c)` and `Color -> Str` all name it. No `exposing [Color]` is
# needed.
# import Color
# import pf.Stdout
# import json.Parser

# `exposing` brings specific items in without a qualifier or module prefix, so
# `to_str(x)` works instead of `Json.to_str(x)`, and `Request` can be written in
# an annotation without the `Http.` prefix. The qualified `Json.to_str(x)`
# works too.
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
# A bare target or one starting with `./` is relative to the directory of the
# importing file. `../` goes up one directory, and a leading `/` starts at the
# package root.
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
# so consumers use the public name rather than the internal source path. See
# the `packages` topic for how a package exposes a module from a subdirectory.

# Embed a file's contents as a constant at compile time. The path is relative to
# the importing file. The type is `Str` or `List(U8)`. A `Str` import of a file
# that is not UTF-8 fails with "file not utf-8". The build embeds the content,
# so the binary runs without the file.
# import "../../README.md" as readme : Str
# import "logo.png" as logo : List(U8)
#
# @rejects file not found
# import "missing.txt" as missing : Str
#
# @rejects invalid file import type
# import "missing.txt" as size : U64
#
# Once imported, the embedded constant is used like any other Str:
#   readme.contains("Roc")

# Mutually recursive types cannot both be exposed from one type module, since a
# type module exposes a single type. Wrap them in a void module instead:
#
#   # FooBar.roc
#   FooBar :: [].{
#       Foo := [BarVal(Bar), Nothing]
#       Bar := [FooVal(Foo), Nothing]
#   }
#
# `[]` makes FooBar a void module: a namespace with no values (see `modules`).
# Then `import FooBar` and reference `FooBar.Foo` and `FooBar.Bar`, or
# `import FooBar.Foo` and `import FooBar.Bar` to get them unqualified.
# Alias modules (Foo.roc with `Foo : FooBar.Foo`) are planned, so a package
# could expose Foo and Bar and hide FooBar.

# `echo!` is provided by the built-in Echo platform and needs no import. See
# the `app_header` topic.

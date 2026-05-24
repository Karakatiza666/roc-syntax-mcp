# Imports bring values from other modules into scope.

# Plain import — exposes `pf.Stdout` etc.
# import pf.Stdout

# Import with an alias.
# import pf.Stdout as StdoutAlias

# Embed a file's contents as a constant at compile time.
# The path is relative to the importing file.
# import "../../README.md" as readme : Str

# Once imported, the embedded constant is used like any other Str:
#   readme.contains("Roc")

# Note: in the new compiler, `echo!` (write a line to stdout) is built in
# and does NOT require an import.

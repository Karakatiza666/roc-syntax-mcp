# Packages: package headers, URL and path dependencies, versions, shorthands,
# platform-specific packages, and type identity across packages.
#
# A topic is one headerless file, so every header here is a comment. Each
# rule comes from a test with a scratch multi-file project. Error titles are
# in quotes.
#
# The root module of a package, usually main.roc, lists the type modules that
# the package exposes and the dependencies of the package:
#
#   package [Parser, Encoder, Widget] { json: "https://.../json/2.1.0/<hash>.tar.zst" }
#
#   import Src/Widget as Widget
#
# A module in a subdirectory is exposed by its import alias (`Widget` above).
# Every module of the package can import a module that the header does not
# list. Outside the package, `import pkg.Private` fails with "package module is
# private". Consumers use the public name (`import pkg.Widget`), never the
# source path.
#
# An app, package or platform header ends with a record of dependencies. Each
# entry is `shorthand: "location"`:
#
#   app [main!] {
#       pf: platform "https://example.com/basic-cli/1.0.0/<hash>.tar.zst",
#       json: "https://example.com/json/2.1.0/<hash>.tar.zst",
#       util: "../util/main.roc",
#   }
#
# A path dependency names the main.roc of a package, relative to the file that
# declares it. Roc reads it from disk, with no download, cache or version.
# `roc test` runs the `expect`s of path packages, but not of URL packages.
#
# A URL dependency is a .tar.zst bundle:
#   - It must use https. Plain http works only for localhost ("insecure package url").
#   - The last path segment before .tar.zst is the hash of the content. Roc
#     checks it after the download and refuses a mismatch ("package download
#     failed"). So one URL always gives the same files.
#   - Roc caches each download.
#   - `roc bundle main.roc Parser.roc ...` writes the bundle, named by its hash,
#     for any static https host. See the `compiler` topic.
#
# A URL can hold one MAJOR.MINOR.PATCH segment before the hash. Two segments
# give "ambiguous package version". When the dependency graph has one package
# at more than one version:
#   1.2.0 and 1.3.0   same major: the whole build uses 1.3.0
#   1.2.0 and 2.0.0   different majors: two separate packages, both used
#   0.3.0 and 0.4.0   below 1.0.0 the minor acts as the major: both used
#   0.3.0 and 0.3.5   the whole build uses 0.3.5
# The entries in the app header are exact. If a dependency needs a higher
# version than the app declares, the build fails with "package version
# conflict" and prints the chain of packages. A URL with no version segment is
# a separate package from every other URL.
#
# A shorthand is a lowercase name. The dependent chooses it, and it is in scope
# only in the module whose header declares it. So an app can call a package
# `json` while a package it uses calls the same package `j`. The name `roc` is
# reserved for the compiler pin (see `compiler`). An import of a shorthand that
# the header does not declare gives no error until a name from it is used
# ("does not exist").
#
# A package header can name a platform the same way an app does. The package
# can then use the whole platform API, hosted effects included:
#
#   package [FxHttp] { pf: platform "https://.../platform/1.0.0/<hash>.tar.zst" }
#
#   import pf.Http
#
# Only the app provides the values that the platform `requires`. Every platform
# declaration in one build must be identical: the same URL with its version and
# hash, or a path to the same root file. If not, the build fails with "platform
# dependency mismatch". A headerless app gets the Echo platform, so it cannot
# use such a package.
#
# Packages cannot depend on each other in a cycle ("package cycle").
#
# Two nominal types are the same type when they have the same name and their
# modules have byte-identical content, through every module they import. So a
# module that did not change between two versions, two mirror URLs or a
# vendored copy declares the same types, and values pass between them. Any
# change to the module, a comment included, makes new distinct types, and a
# value of the old type is a "type mismatch".
#
# `roc deps` prints the dependency graph and `--replace-dep` loads a local copy
# in place of a declared one. See the `compiler` topic.

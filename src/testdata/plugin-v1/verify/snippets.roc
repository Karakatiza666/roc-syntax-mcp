## Every snippet the overview page shows, in one app, so the page cannot drift.
app [main!] { pf: platform "https://github.com/example/frozen-v1/releases/download/1.2.3/AAAA.tar.br" }

import pf.Widget

main! = |_args| Ok(Widget.render!("hi"))

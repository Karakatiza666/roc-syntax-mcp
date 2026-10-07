## TCP streams and URL parsing: the two places basic-cli makes you name a
## timeout, and the one place it parses text for you.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst" }

import pf.OsStr
import pf.Stdout
import pf.Tcp
import pf.Url

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	# Connecting takes a timeout in milliseconds that covers DNS resolution and
	# every address it resolves to. Zero fails immediately rather than blocking.
	stream : Tcp.Stream
	stream = Tcp.connect!("127.0.0.1", 8085, 1_000) ? |err| ConnectFailed(err)

	# Every read and write takes its own timeout too. There is no deadline to
	# set once for the whole stream. The calls look verbose, but without a
	# timeout a call could hang forever.
	stream.write_utf8!("PING\n", 5_000)?
	reply = stream.read_line!(1_048_576, 5_000)?
	Stdout.line!("got ${reply}")?

	# The four reads differ in where they stop, not in how they fail.
	stream.write!([1, 2, 3], 1_000)?
	exact = stream.read_exactly!(3, 1_000)?          # exactly n bytes
	upto = stream.read_up_to!(8, 1_000)?             # at most n, whatever arrived
	until = stream.read_until!('|', 64, 1_000)?      # through a delimiter byte
	Stdout.line!("${exact.len().to_str()} ${upto.len().to_str()} ${until.len().to_str()}")?

	urls!()?
	Ok({})
}

## `read_line!` is the only read that returns `Str`. The others return bytes,
## because a stream is not always text.
lines! : Tcp.Stream => Try(List(Str), _)
lines! = |stream| {
	first = stream.read_line!(4096, 1_000)?
	second = stream.read_line!(4096, 1_000)?
	Ok([first, second])
}

## Connect failures and stream failures are separate closed unions, so a caller
## can match either exhaustively.
explain_connect : Tcp.ConnectErr -> Str
explain_connect = |err|
	match err {
		ConnectionRefused => "nothing is listening"
		TimedOut => "the connection attempt ran out of time"
		AddrNotAvailable => "that address is not one we can bind"
		other => Str.inspect(other)
	}

expect explain_connect(TimedOut) == "the connection attempt ran out of time"

## `Url` parses and normalizes. It never fetches. Only http and https parse.
urls! : () => Try({}, _)
urls! = || {
	# A bare `?` would merge `Url.ParseErr`'s tags straight into the union.
	# A tag of your own around them records where the error came from.
	url = Url.parse("https://example.com:8443/a/b?q=1#frag") ? |err| BadUrl(err)

	Stdout.line!(Str.inspect(url.scheme()))?
	Stdout.line!(url.host())?
	Stdout.line!(Str.inspect(url.port()))?
	Stdout.line!(url.path())?
	Stdout.line!(Str.inspect(url.query()))?
	Stdout.line!(Str.inspect(url.fragment()))?

	# Relative resolution, the same rule a browser follows.
	nested = url.resolve("../c") ? |err| BadUrl(err)
	Stdout.line!(nested.to_str())?
	Stdout.line!(url.without_fragment().to_str())?
	Ok({})
}

expect Url.parse("https://example.com/a").map_ok(|u| u.host()) == Ok("example.com")
expect Url.parse("ftp://example.com").is_err()

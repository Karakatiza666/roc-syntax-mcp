## TCP connections and URL parsing: the two places basic-cli makes you name a
## timeout, and the one place it parses text for you.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst" }

import pf.Duration
import pf.IOErr
import pf.OsStr
import pf.Stdout
import pf.Tcp
import pf.Url

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	# Connecting takes two timeouts. `connect_timeout` covers DNS resolution and
	# every address it resolves to. `io_timeout` is held by the connection and
	# bounds each of its reads and writes. `Duration.zero` expires immediately.
	conn : Tcp.Connection
	conn = Tcp.connect!("127.0.0.1", 8085, { connect_timeout: Duration.seconds(1), io_timeout: Duration.seconds(5) })?

	# Calls take no timeout argument. `conn.with_timeout(d)` and
	# `conn.with_line_limit(n)` return the same connection with another setting.
	conn.write_utf8!("PING\n")?
	reply = conn.read_line!()?
	Stdout.line!("got ${reply}")?

	# The four reads differ in where they stop, not in how they fail. The end of
	# input is `Err(EndOfInput)`, never an empty `Ok`.
	conn.write_bytes!([1, 2, 3])?
	exact = conn.read_exactly!(3)?          # exactly n bytes
	upto = conn.read_up_to!(8)?             # at most n, whatever arrived
	until = conn.read_until!('|')?          # through a delimiter byte
	Stdout.line!("${exact.len().to_str()} ${upto.len().to_str()} ${until.len().to_str()}")?

	urls!()?
	Ok({})
}

## `read_line!` is the only read that returns `Str`, without the `\n`. The others
## return bytes, because a connection is not always text.
two_lines! : Tcp.Connection => Try(List(Str), _)
two_lines! = |conn| {
	first = conn.read_line!()?
	second = conn.read_line!()?
	Ok([first, second])
}

## Anything you can read, you can loop over. A line that is not valid UTF-8, or
## longer than the limit, is one `Err` item and the loop carries on. A failure of
## the connection is the last item.
echo_lines! : Tcp.Connection => Try({}, _)
echo_lines! = |conn| {
	for! item in conn.lines() {
		match item {
			Ok(line) => Stdout.line!(line)?
			Err(BadUtf8(_)) => {}
			Err(ReadLimitExceeded(_)) => {}
			Err(TcpErr(err)) => { return Err(TcpErr(err)) }
			Err(Interrupted) => { return Err(Interrupted) }
		}
	}
	Ok({})
}

## Every failure of the network arrives as `TcpErr(IOErr)`, so a result can be
## compared directly: `result == Err(TcpErr(TimedOut))`. Conditions such as
## `EndOfInput`, `BadUtf8` and `Interrupted` stay bare tags.
explain : IOErr -> Str
explain = |err|
	match err {
		ConnectionRefused => "nothing is listening"
		TimedOut => "the connection attempt ran out of time"
		AddrNotAvailable => "that address is not one we can bind"
		other => Str.inspect(other)
	}

expect explain(TimedOut) == "the connection attempt ran out of time"

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

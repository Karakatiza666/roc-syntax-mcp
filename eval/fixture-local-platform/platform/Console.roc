import Host

## The terminal. Every write ends its own line.
Console := [].{
	## Writes the text and a newline.
	say! : Str => Try({}, [ConsoleErr(Str)])
	say! = |text|
		match Host.console_write!(text) {
			Ok({}) => Ok({})
			Err(ConsoleErr(err)) => Err(ConsoleErr(err))
		}

	## Writes the prompt, then reads one line without its newline.
	ask! : Str => Try(Str, [ConsoleErr(Str)])
	ask! = |prompt|
		match Host.console_read!(prompt) {
			Ok(line) => Ok(line)
			Err(ConsoleErr(err)) => Err(ConsoleErr(err))
		}
}

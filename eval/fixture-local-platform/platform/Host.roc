## Internal hosted-effect boundary. Applications import `Console` instead.
Host := [].{
	console_read! : Str => Try(Str, [ConsoleErr(Str)])
	console_write! : Str => Try({}, [ConsoleErr(Str)])
}

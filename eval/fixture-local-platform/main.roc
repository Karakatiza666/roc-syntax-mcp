app [main!] { pf: platform "platform/main.roc" }

import pf.Console

main! = |_args| {
	Console.say!("Expenses")?
	Ok({})
}

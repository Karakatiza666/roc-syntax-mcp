## A test fixture, not a corpus. It stands in for a package plugin that claims a
## module name a platform also claims, which is what `Http.send!` below does
## against basic-cli's own `Http`. No app pins it, so no gate compiles it.
Http :: [].{

	## Send a request. The signature differs from the platform's on purpose: a
	## collision the caller cannot see is the failure this fixture exists for.
	send! : Request => Try(Response, [ForkErr(Str)])
	send! = |_request| Ok({})
}

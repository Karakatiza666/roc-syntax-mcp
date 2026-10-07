## A test fixture, not a corpus. See Http.roc in this directory.
Response :: {
	status : U16,
}.{

	## Whether the status is in the 2xx range.
	is_ok : Response -> Bool
	is_ok = |resp| resp.status >= 200 and resp.status < 300
}

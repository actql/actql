# Native credential transport for bounded Effect writes

## Changes

The existing Native credential-use Owner could authorize and durably consume an
operation, but its physical request was fixed to GET. Add an explicit installed
HTTP verb and request-byte bound, and connect exact checked write bytes through
the same claim, current authorization, revocation, lifetime and outcome path.

Every existing read installation explicitly selects GET with a zero-byte body
bound. The read entry points cannot invoke a write installation. The request
entry point checks the installed verb, exact path and byte bound before any
authorization callback, durable use consumption or I/O. Installation arrays and
request bodies are snapshotted; callbacks receive their own copy of the exact
request rather than a mutable reference to bytes subsequently sent.

Native HTTPS adds PATCH and consolidates operation-specific bearer requests with
the existing bounded request engine. Credential files remain resolved inside the
physical adapter; redirects stay disabled, CA verification and response bounds
remain enforced, and caller-supplied Authorization is refused. The credential
deadline is checked after file resolution. Existing configured-client and
operation-file credential limits and privacy checks are preserved.

## Scope and compatibility

This is physical credential transport under Cloud #138, not complete Effect
execution. A credential claim is not a signed Effect approval or an Effect
Ledger dispatch claim. The higher resident connection still must validate the
original signed Resolution, obtain the common Ledger claim, durably retain the
raw Provider response before interpreting it, and connect outcome, publication
and release. The existing credential `succeeded` outcome describes the HTTP
exchange; it does not prove the semantic Effect outcome.

Native installation and authorization observation types change. All repository
read callers are updated explicitly; no default-verb compatibility fallback is
added. Credential grant/use wire, canonical request identities and contract
versions are unchanged. Non-Native transport remains explicitly unsupported.

OSS #1239 is merged. The branch includes a normal merge of main
`0c6538b53f63a3c8a42770092e16035103749e9e`, including the reviewed admission fix
`fe9174d9c2112f752f8b4b1552a8722dcaf78e84`. The final current-authority check
remains after the clock callback. The integration retains main's separate Native
physical test package and its signed Resolution regression while preserving the
existing default and Core entry points and adding the write cases. Final merge
target is OSS main, with no unmerged parent dependency. No formal package cohort, Native
deployment binary, Cloud deployment or public approval role is changed here.

## Validation

The existing HTTPS fixture executes the actual Native libcurl, OpenSSL and
SQLite adapters. Its independent checked Catalog request supplies the exact
PATCH body; a separately signed write grant cannot be replaced by the observe
grant. Fixture current authorization is explicit and is not a production
reviewer-role assignment.

The three added physical cases verify:

- Wrong verb, path, oversized body, missing authorization, observe grant,
  read-entry misuse, Authorization substitution and expired deadline send
  nothing. The authorized operation sends exactly one checked body. After a
  database close/reopen, replay sends nothing and retains the original use CID
  and successful HTTP outcome.
- The fixture accepts one write and deliberately loses its response. Native
  records `unknown`; reconstruction and retry do not send another write or
  convert the outcome into success or non-execution.
- Revocation during the send authorization callback is observed again after
  durable claim. No write occurs, and the same failed use remains inspectable.

The fixture requires exactly two accepted PATCH requests overall, three existing
GET observations, exact independent request bodies and all registered tests.
It records the physical requests and status in a private receipt. The signed
Resolution admission case remains part of the same default test invocation.

Before the final fixed-source run, the Native fixture passed 10/10; Native
consuming-package compilation and interface generation passed. An earlier 9/9
diagnostic passed with new-field reserved-keyword warnings; those fields were
renamed to `verb`, and the later compile has no such warnings. Final source,
commands, counts and evidence paths are recorded in the PR validation section.

Hosted CI is intentionally stopped. Full Native/Core, whole packed acceptance,
public Cloud Effect approval, retained Source/Compute restart, saved-response
Ledger projection, formal release and Preview are not established by this unit.
The original failed Run responsibilities under Cloud #88 remain separate.

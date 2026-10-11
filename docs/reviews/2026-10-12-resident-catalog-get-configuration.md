# Resident Catalog GET configuration

## Changes

The Resident Catalog installer selected a GET operation with a 65,536-byte
request-body allowance. The existing Credential Resource Owner rejects any
GET operation with a nonzero allowance, so even otherwise valid installation
materials could not install this service. Select zero request-body bytes for
the existing Salesforce describe GET. Preserve the original resource origin,
operation, path, secret reference, signature verification and current fences.

The same private operation constructor is used by the production installer and
its Native fixture. The shared Resource validation is unchanged: GET remains
bodyless and the existing origin, path, secret and size checks remain mandatory.
Response byte limits are independent and unchanged.

## Scope and compatibility

Final merge target: OSS main. This independent branch starts at accepted main
23697f7430c227327b4b0b3735ad14806eed321a. It does not depend on the unmerged
#1513 stamp cleanup or its Local preparation ancestry. No public API, wire,
identity, grant, Resource implementation or cleanup contract changes.

This repairs installation configuration, not authorization supply. Production
evidence-read remains default deny. Actual authenticated Host admission,
current Account read and separate publication permission, original credential
continuity, stamp funding and public Effect acceptance remain separate unfinished
connections. No Provider, Source, Compute or Effect is executed by this unit.

## Validation

The bounded non-heavy guard selects two JS tests against the actual existing
Resource `valid_operation` predicate. The former nonzero GET allowance is
rejected; zero is accepted. Invalid origin, operation, path, secret and body
limits remain rejected. This is configuration admission evidence, not physical
service installation or Provider I/O.

Matching Native Resource compilation uses `--deny-warn`. Matching Resident CLI
compilation includes the production constructor and its new fixture, which
asserts the independently expected Salesforce path, original scope, secret
reference and bodyless GET. Native fixture execution is not performed. Existing
uninstalled Host-supplier warnings are retained; this change does not create
dummy contexts or suppress them. Record final command results against the exact
submitted clean SHA separately from preparation checks.

No Heavy, package producer, Native executable, deploy, Provider request or Hosted
CI is started. The existing fixed limits, per-worktree lock and group closure
checks remain in force.

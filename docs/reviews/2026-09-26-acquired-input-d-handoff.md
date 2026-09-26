# Acquired-input Client handoff to Checkpoint D-next-2

## Fixed base and product route

This branch descends from the integrated OSS base
`c12deddfb23fcafa6dc68d90772436d26cb1f3cb`. The preserved acquired-input
work was restored onto this branch, not into the D or integration worktrees.
The committed route before this handoff is
`0ab1a72c7b79456749205926715f35f084e2d22f`.
The checked acquisition preparation seam is committed at
`9915c7d38cc955de78f4c33939a61d50fd1f5594`; D can adopt it after its
seven acquired-input ancestors. No uncommitted source is needed.
The D cancellation series `768141d84f9975a894adec4ee118b962ac5a2dce`
was merged into this branch at `fe5e491b3`; the acquired preparation and
held-request cancellation now have one committed Host call site.

An installed Host source profile selects one DuckDB source and Check
Environment. The public `@actql/node` Client uses the same `aql()` and
`start()` calls with embedded Local or a real HTTP Remote Host. The Host checks
the Program, admits the common task Run Definition, reserves the existing Run
start, captures the source, issues Source Evidence, computes downstream tasks,
publishes named Results and serves reads and attach. The packed test runs a
real DuckDB table with duplicate and NULL values through both modes. Neither
mode uses a fixture provider or a caller-supplied Source Evidence CID.

## Entry points and custody

| Entry | Inputs and result | Owner and D use |
| --- | --- | --- |
| `openInstalledRemoteHttpHost()` and its `prepareSubmit()` / `submit()` | Public AQL document, parameters and request ID become a checked `PreparedClientProgram`, `ClientRequestIdentity`, durable `RunRef` and declared Result names. | Distribution owns `embedded-local.mjs`, compiler and request journal. D uses the same request identity and the captured submission held by `client-checkpoints.mjs`. |
| `prepareCapturedDuckDBSource()` | Checked Program and Host-installed source profile produce an opaque in-process preparation, checked source facts and the Host-configured read tuple `{connection, resource, operation:'read'}`. It performs no provider acquisition. `openCapturedDuckDBSource()` accepts only that exact preparation and profile. | Distribution owns `captured-duckdb-source.mjs` and calls it before `acceptRun()`. The serialized checked source and tuple are placed in the existing encrypted Checkpoint captured submission and re-derived and compared on resume. D owns the authorization/hold decision in `client-checkpoints.mjs`; a CID or serialized tuple alone is not a grant. |
| `authorizeSourceAccess()` | The DuckDB grant and current account configuration decide `acquisition` for that tuple immediately before a provider session opens. Non-dispatch decisions prevent I/O. | Connector physical adapter owns `session.mjs`; Distribution wires the installed profile. D must add its pre-acquisition Checkpoint decision, cancellation and claim validation to the captured request before physical acquisition. The current Run-acceptance write decision is not a read decision. |
| `openCapturedDuckDBSource().issueSourceEvidence()` | The exact checked requirement, native completed observation, actual schema/capability and current read grant yield formal Source Evidence. | Distribution owns the production DuckDB issuer in `host.mjs` and MoonBit `source_evidence_capture.mbt`. D consumes this output; it does not issue or reseal evidence. |
| `client-request-journal.lookupRunDefinition()`, `inspectHeld()` and Host-private `inspectAcquisition()` | The durable Run owner distinguishes `not_started`, `started_unknown` and `completed_retained`. The last state requires a successful formal publication and currently available named Results from the existing Store. | Distribution owns the request journal and acquired output custody. D owns its existing Checkpoint resume claim and sweep. No state permits an implicit refetch. |

The prepared acquisition is a private handle, not wire authority. Its checked
source facts and read tuple are carried as review and continuation facts only.
On resume, the Host rechecks them against the retained Program and currently
installed profile. The physical DuckDB adapter checks current read permission
again before acquisition and again before Source Evidence issuance.

The minimal Host-side call sequence is:

```js
const preparedSource = await prepareCapturedDuckDBSource({
  moon, preparedProgram, registry, values, fragment, ordered,
  database, schema, table, sourceAccess,
});
const captured = {requestId, principalId, connection, kind, input,
  parameters, resultNames, acquisition: {
    checkedSource: preparedSource.checkedSource,
    readTuple: preparedSource.readTuple,
  }};
await checkpoints.acceptRun({requested, captured});
await openCapturedDuckDBSource({moon, preparedProgram, registry, values,
  fragment, ordered, database, schema, table, sourceAccess,
  transportLimits, signal, preparedSource});
```

`checkedSource` contains the checked requirement, source, carrier schema,
policy, view, input and output contract identities. The read tuple has the
existing account `connection`, `resource`, `operation` fields. The Host
re-derives both after restart and rejects a changed source profile or forged
preparation before provider I/O. D's additional read decision and physical
claim check still have to be inserted; this sequence alone does not
authorize acquisition.

## Required D connection and remaining Distribution work

The current `client-checkpoints.mjs` calls `acceptRun()` for the protected
Site write tuple. D-next-2 must also decide the checked read tuple before the
first source fetch, using the existing encrypted preparation, account
allow/deny/delegate decision, claim, lease, cancellation and current authority.
An unresolved decision must remain held without starting provider I/O. The
Host must not represent the approval as a fabricated formal Invocation CID if
that CID depends on the later source observation.

The current source capture handle is process-local. The Host-private recovery
projection returns `not_started` only before the common physical start
reservation. After that reservation it returns `started_unknown` unless the
existing publication owner confirms both formal success and currently
available named Results. Only then does it return `completed_retained`; the
packed test checks this again after a Host process restart. This recovers a
finished Result from the existing Store without reacquiring the source.
There is no durable reopen of an intermediate captured input before
publication. A crash there remains `started_unknown`, and D must use the
Source contract's reconciliation rules; neither D nor Distribution may infer
that a fresh fetch is the old observation. The request journal's start bit
alone is not a completed-acquisition proof.

File ownership for the next shared edits: Distribution owns
`embedded-local.mjs`, `captured-duckdb-source.mjs`,
`client-request-journal.mjs`, the DuckDB issuer and packed acquired-input
tests. D owns `client-checkpoints.mjs`, its Checkpoint journal, pre-acquisition
authorization/hold/resume logic and D-next-2 packed approval tests. Changes to
the shared `embedded-local.mjs` call site should be integrated once on the
Distribution branch; D should supply the Checkpoint method and its exact
decision contract without maintaining a second Host copy.

## Verification scope

At `c12deddfb23fcafa6dc68d90772436d26cb1f3cb`, local clean-source docs,
distribution, Salesforce, Local assets, Checkpoint runtime, Run Host core and
the JS/Wasm/native Run publication MoonBit suites passed. That is partial
local validation, not all CI: no hosted Linux run of that exact integration
SHA was verified. The D branch's `768141d84f9975a894adec4ee118b962ac5a2dce`
held-request cancellation is separate and remains under same-SHA CI review;
it is not a prerequisite for this acquired-input handoff.

The known Linux `workers` failure is generated fixture parsing
(`UnknownManifestDirective: options`); `connector-addition` fails when its
isolated tree cannot find `./scripts/ar`. These are shared build/CI fixture
issues for the Distribution integration owner to fix, not evidence that the
D Checkpoint behavior passed full CI. The acquired branch's local
`check:distribution-client` passed at `0ab1a72c7`, including the packed
Local/HTTP Remote acquired-input lifecycle cases. At `9915c7d38`, the new
preparation test and clean packed Local/Remote acquired-input smoke passed.
A full distribution-gate attempt failed in its Remote Checkpoint TLS fixture
at connect: `DEPTH_ZERO_SELF_SIGNED_CERT`. The identical single test also
fails under the same local Node environment at clean `c12deddfb`; a
diagnostic certificate bypass confirms the functional case but is not a
valid TLS gate. No same-SHA hosted Linux CI has run for this acquired branch.
The merged branch's local packed Checkpoint, packed standard Node
Local/Remote, Checkpoint runtime and contract checks passed. Its full
distribution gate did not pass: 21 Remote Checkpoint cases failed at the
test fixture's self-signed TLS connection, while 111 other cases passed.
The identical Remote Checkpoint fixture failure was reproduced at clean
`c12deddfb`; this is not an all-gates or Linux CI success claim.

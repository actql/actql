# Native original Host identity read

## Changes

The existing retained consumer exposes its own original dispatch only after
`effect_computation(journal)` has checked completion, original Site journal,
Runtime evidence, cancellation, physical output and receiver borrow. This is a
read-only projection; it grants no identity or permission and transfers no hold.

`NativeEffectCloudHostIdentityRead.read_original_consumer` selects this dispatch
and compares the consumer's original request and Run definition with the retained
producer's own materials/request. It sends only query correlation and dispatch
CID through the installed authenticated Cloud control client. The private decoder
binds the response to original dispatch, Run, checked task, runtime, Site generation,
Workspace, authority scope, installation and trusted local lifetime. The existing
Timestamp Owner parses timestamps. Missing custody or unavailable HTTP returns
unavailable, with no reprepare, Source read, retry or replacement Run.

The existing Host evidence decision caller checks the same actual HTTP client and
operator-installed observation route and its physical original task/consumer.
It rereads original identity before and after the Account decision and compares
it to the independently installed original Host subject. The same current Account
fence follows the final identity read. Read and publication still use separate
existing `read`/Acquisition and `write`/Transfer tuples.

## Scope and compatibility

Final merge target: OSS main. Cloud counterpart #273 is merged at
`59cf14e5d7cabce2ee27cff3794320e311d98848`. This source adds no Cloud adoption,
wire/CID replacement, Run state, permission, Ledger, scheduler, retry or Provider
operation. The two generated Native interfaces are produced by `moon info`.
Identity snapshots are ephemeral facts, not Account Allow or approval tokens.
There is no public arbitrary-wire identity decoder.

Production `effect_host_admission` remains `None`. The authenticated transport
is connected into its existing private seam, but the actual trusted Account
installation is not supplied. Its three existing never-constructed Host structs
remain visible compiler warnings; no dummy constructor or suppression hides them.

## Actual installation inputs still missing

| Input | Existing admission/consumer | Required source |
| --- | --- | --- |
| Original HTTP principal | Private authenticated Site read and retained original context | Initial Cloud Run metadata plus current Identity Owner; not Site operator/signer/Reviewer/body |
| Account configuration JSON and account/configuration CID | `execution_authorization.admit_account_configuration_json` and `AdmittedAccountConfiguration` | Actual trusted Host installation; not Workspace role or Source grant |
| Read connection/resource and publication connection/resource | `HolderEffectHostSubject`; existing Account tuple/decision Owner | Host application's exact configured selectors, separately for evidence read and transfer |
| Original authorization context CID | `bind_dispatch_authorization` | Original admitted execution policy; not approval or Source authorization scope |
| Current authentication/policy, delegation, expiry/revocation | `HolderEffectHostCurrent.current`, current Site callback and credential lifetime | Actual installed current Owners, not a restored constant or identity match |

No actual configuration path/selector payload for those permission inputs has
been verified. An application can explicitly install them through the existing
Account admission seam; this change does not invent or default that policy.

## Validation

Six independent private query/reply framing cases run on JS. They cover exact
query fields, foreign original coordinates, replay, extra authority, duplicate or
malformed JSON, principal syntax, Timestamp Owner rejection, expiry and byte/node
limits. These are decoding tests, not live Host admission or physical acceptance.

Matching Native CLI/Owner compilation includes the real consumer projection,
HTTP adapter and two caller fence counterexamples (original identity loss after
permission selection; Account revocation during final identity read). Those two
Native assertions have not been executed. No actual TLS, Native physical I/O,
Provider, public approval, Result, release, Heavy, producer or Hosted CI is run.

Initial preparation failed on the required StringView end label. Initial JS test
compilation failed on authored replacement labels, with counts unavailable.
Both original failures are retained, fixed locally, and kept separate from the
subsequent clean fixed-source verification.

## Remaining acceptance

Supply the actual original Host admission and current Account installation,
then execute the already agreed finite public approval/same-Run recovery/Effect/
Receipt/Named Result/Release acceptance. Before that, execute actual authenticated
DO/TLS and physical original-custody/revocation cases in an allocated window.
Current default deny is not successful public acceptance.

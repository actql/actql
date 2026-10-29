# Host capacity policy admission

`capacity_policy.admit` validates canonical policy bytes against a CID selected
by the trusted Check Environment. It admits the closed policy contract
owned by [protocol contracts](../spec/protocols/contracts.md#capacity-host-policy).
Each ceiling is a positive safe integer; the original 17 limits are required
and `max_aggregate_string_bytes` is optional. The returned
Policy is opaque and immutable. Field lookup returns an opaque Ceiling retaining
the exact Policy, field name and value, not a detached caller-asserted number.
Unknown field names yield no ceiling.

The pinned CID is checked against the input bytes before parsing. Parsing is
bounded by bytes, nodes and depth and rejects duplicate normalized keys. The
admitted values are re-emitted in canonical order directly to a hash sink and
compared with the original byte identity. Alternate number spellings, escaped
key spellings, whitespace, BOM and other repairs do not become accepted
artifacts merely because their input hash matches a caller-supplied CID.
The numeric policy has fixed field count; parsing memory/work remain bounded by
the supplied input limits. It does not materialize a second serialized string.

## Decision and reference boundary

The closed policy shape and positive safe-integer constraints follow the fixed
Sketch `src/actql-bounds.ts` capacity policy. The shape was not yet a standalone
owned contract in this repository; this change explicitly adopts it rather
than treating reference code as an implicit normative owner. No reference
deployment default is imported: a policy whose every ceiling is one is only a
synthetic test fixture, not a recommended production setting.

The optional string-aggregate ceiling is an explicit extension to that shape.
It measures an individual output's raw UTF-8 payload, unlike the nested-value
ceiling's JSON encoding scope. Reusing the latter would change the measured
quantity. Absence neither supplies a default nor invalidates existing policy
bodies: their canonical bytes and CIDs stay unchanged. Supplying the extension
changes the policy CID and requires the corresponding contract and law pins.
The field is not evidence of a data bound or completed aggregate enforcement.

Integrity relative to a selected CID is not authentication of the Host making
that selection. A self-CID does not grant authority. Host policy deployment,
selection and authentication remain outside this library. Policy values are
restrictions requiring enforcement, not observations of input or output size.
Units and governing law IDs are not inferred from a matching numeric value.
Some fields, such as depth and model duration, belong to additional consumer
envelopes rather than the current bound-witness unit enumeration.

This boundary closes policy-body admission only. Witness-law validation,
source dependency closure, exact consumer/enforcement binding, resolved limits
and whole-pipeline discharge remain open. There is no API that turns Policy or
Ceiling directly into a runnable Plan or a proven data bound.

The [Host source witness constructor](host-capacity-witness.md) now supplies
the closed field/unit/law mapping and canonical source-witness identity for
supported quantities. Other source laws and consumer enforcement remain open.

## Regression coverage

Tests fix an independent Node-computed policy CID and verify source retention,
policy changes, exact fields, missing/unknown fields, version, positive/safe
integer boundaries, duplicate keys, noncanonical encodings and exact byte/node/
depth limits. The documentation gate compares the schema and the product's
closed ordered field inventory. Passing these checks does not demonstrate
Host authorization or runtime enforcement.

## Implementation accounting granularity

The preparation migration must preserve the original Program, Parameters,
Catalog, CheckedProgram, Plan and Ledger through execution, publication and
cleanup. A missing handoff must not trigger another parse, check, compilation,
capacity calculation or independent reservation. Approval, currentness,
cancellation, Unknown and actual physical retirement remain distinct duties.

Resource accounting has three scopes:

- Physical resources such as Buffers, files, DB sessions, Store bytes,
  transfers and actual attempts follow their existing reservation, use,
  retention and release boundaries. Native arenas and Wasm linear-memory
  allocations must respect their actual physical capacities.
- Input-proportional JSON, ASTs, Maps, Arrays, strings, Stages, rows, schemas,
  indexes, workspaces and Results use the existing shared size/count estimators.
  Retain observations with the original input. Include genuinely simultaneous
  input, workspace, output and old/new growth storage; take the maximum for
  sequential scratch that has already retired. Estimation must not rescan or
  reconstruct the Program, and must not count the same retained storage twice.
- Fixed internal Records, Some/Result wrappers, closures, getters, tuples,
  error packets and small FFI argument records belong to a conservative
  Host/target overhead. Do not add an inventory, receipt, work phase or external
  current callback merely to count another such object. This overhead is
  trusted Host implementation policy, not a caller-supplied capacity authority
  or a new field in the canonical policy admitted above.

Detailed constructor inventories do not require exhaustive modeling of every
GC/VM wrapper. Existing fixed estimates need not be deleted in bulk: first
complete ordinary Request-to-CheckedProgram-to-Plan-to-Run adoption and remove
the replaced legacy paths, then consolidate redundant fixed accounting under
the existing Host policy owner. Do not turn a supported operation into
Unsupported merely because a microscopic inventory is absent. Logical byte
ceilings, including existing Local policy constants, do not establish reserved
or isolated process RAM. Do not change them without evidence of the actual
resource need or erroneous refusal.

New resource-management code must address an input-proportional increment, an
unmanaged physical-use boundary, a broken original/ownership handoff, or an
observed false refusal or material memory/performance problem. Its review must
state that problem, why existing shared estimation plus fixed overhead is
insufficient, and its added runtime/current-callback cost. Greater precision
for one fixed wrapper alone is not a reason. Keep semantic work finite through
the existing continuation and receipt; do not reset consumed work, reissue a
claimed phase per Snapshot, or introduce a separate Ledger per helper.

Connectors describe pagination, response/transfer bounds, meaningful physical
resources, simultaneous holdings and operation boundaries. Shared Hosts own the
accounting; connector authors must not derive internal header or scalar-word
counts or create another resource framework.

Completion requires ordinary supported inputs and operations to execute,
publish and clean up without legacy fallbacks on one integrated source.
Representative parse/check/compile/Plan, current, resize and I/O counts must
show no redundant work; Node, Native and Python latency and peak-memory
measurements remain separate from logical accounting. Test counts and detailed
inventories alone do not establish normal package or physical acceptance.

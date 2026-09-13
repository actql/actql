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

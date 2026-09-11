# Host capacity source witnesses

`capacity_host_witness.create` accepts only an opaque Ceiling obtained from
canonical [policy admission](capacity-policy.md). The pinned policy contract
owns a closed field/unit/law table. The constructor chooses the unit and law
from that table; callers cannot provide an independent role, source, law,
unit, value or dependency list. The result retains the exact Ceiling and its
admitted Policy.

The resulting wire format is `actql-bound-witness/0.1`, with role
`host_ceiling`, source kind `host_policy`, source derivation and a singleton
policy-CID dependency. Identity hashes the canonical preimage without the
`witness_cid` member. `emit` outputs the complete body including that member.
Both paths use the same bounded emitter; neither materializes an intermediate
JSON tree or serialized string for hashing. Construction limits bound the
preimage; the Writer supplied to `emit` independently limits the full artifact,
which contains an additional identity member.

## Law and reference decisions

The fixed Sketch compiler's `hostBound` call sites establish the existing
field/unit/law combinations, including inference items as `distinct_keys`,
aggregate items as `array_items`, and temporal matches as `matches_per_key`.
This library makes those combinations non-overridable instead of exposing the
reference helper's three independent arguments. The exact mapping is now
normative rather than merely inferred from reference call sites.

`max_model_request_bytes_per_item` also has an explicit byte witness law,
`actql.host.model-request-bytes`, under the already-defined per-item policy
scope. This is a newly named source law, not a claim that the reference used
that identifier. Depth, model token count and model duration have no compatible
unit in the current witness vocabulary. Their ceilings remain available from
Policy but witness creation reports `UnsupportedPolicyField`. This is not a
language prohibition on those consumer envelopes or an implicit conversion of
depth, tokens or milliseconds to bytes/rows.

The table is the Host-source branch of governing witness laws, not a complete
registry for Program proofs, author guards, Contract facts, language ceilings or
derived proofs. The operation transfer classification registry serves another
purpose and cannot replace this table.

## Trust and downstream obligations

A Host source witness is a validated restriction relative to the selected
policy, not a proven data bound, Host authorization or completed enforcement.
Consumer matching must retain field scope even when two fields have equal
numbers and units. Resolved limits must still collect all applicable candidates,
compute their minimum and guard binding, retain dependency closure and bind
the exact enforcement target. No current pipeline input accepts this witness as
an observed count. Other witness sources and whole-pipeline discharge remain
required work.

## Fixed evidence

The portable corpus fixes all 14 supported field mappings, wire bytes and CIDs
using an independently computed synthetic policy. Node rechecks every preimage
and the source table; MoonBit compares full emitted text and identity on all
targets. Tests also cover unsupported quantities, exact preimage/artifact
budgets, retained policy provenance, equal-valued different fields, and a
change to an unrelated policy field changing the witness's policy identity.
These checks are not runtime enforcement conformance.

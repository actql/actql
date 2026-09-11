# Capacity witness law names

The [normative registry](../spec/protocols/contracts.md#capacity-law-registry)
pins the closed vocabulary of governing witness names. It is separate from the
operation transfer classification and the Host field/unit/law table. Its initial
68 IDs consisted of the fixed Sketch witness-name inventory plus the already
adopted `actql.host.model-request-bytes` law. The names are sorted explicitly;
the old reference array order and global created-witness cache are not imported.
This adds an owned registry where the repository previously had only a
normative requirement to check known law IDs, not a pinned registry body.

The registry now also fixes eleven author-guard scope mappings to field, unit
and law. Three new names cover already-admitted nest item, string-aggregate byte
and shortest-path output guards; the inventory is now 71 names. Join, cross-join
and interval-join share the existing join-output law but retain distinct owners.
The generated pipeline accessors derive law and unit from an opaque occurrence,
not independent caller strings. Scope and bound quantity still do not establish
Program source identity or enforcement. Existing guard syntax and Program
identities are unchanged; the registry body and its pinned CID change.

This closes a source-law naming gap against the current specification, not a
claim that the fixed reference already implemented these three new names.
The expression-fragment capacity law remains extension-local and is not added.

`capacity_law.admit` returns an opaque `RegisteredLaw` only for an exact name.
It proves membership alone. It is not a witness, source fact, authorization or
certificate that an operation applied the law correctly. Host witness creation
now retains this value in addition to its existing exact policy-field mapping;
the emitted witness bytes and identities are unchanged.

The small generated matcher comes from the pinned body and is checked for
staleness by `check:bound-transfer`. All Host IDs must match the policy table
exactly, including detecting omitted entries. Regression tests reject malformed,
duplicate, unsorted and wrong-version registries and check exact spelling of
every admitted name on all targets. A fixed independently computed registry CID
guards accidental inventory changes; intentional new laws require coordinated
normative, pin and fixture updates.

Program/Contract/author/language source validation, individual law application,
mixed-source dependency closure and enforced resolved limits remain required.
Listing a name here is not completion of those semantics. The closed Host-source
application is implemented separately by `capacity_host_witness`.

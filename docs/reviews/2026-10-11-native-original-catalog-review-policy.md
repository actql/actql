# Original Catalog custody to checked Review policy

## Scope and parent

This connection consumes authenticated Catalog response custody and an actual
`ResidentEffectReviewInputContext`. It assembles dynamic Mapping and Result
selection through the original checked/capture Owners before calling the
existing original-material normalization and Review entry. It does not query a
Source, execute Compute, read Provider metadata again, approve or write.

Parent: #1460 `5579bff81f8dfa86221e7ab5d30a47e9de8fa9e0`. The stack includes
main `1be54e6e47083d8df2b8ed1672ea1cc57cdf7639`. Final target is OSS main,
after #1460. Submitted parent heads remain unchanged.

## Original selection and ownership

`prepare_native_resident_create_review_mapping` selects the Effect member from
`client_effect_member_descriptor` and the same prepared Owner's checked Mapping
rules. `check_mapping_row_fields` supplies source-field/null behavior facts;
the existing Salesforce declaration and execution-Mapping factories consume the
observed metadata. Both Mapping reference and full CID must equal the original
checked shape. Same field names with different types or Connector identity are
not an acceptable replacement.

This finite adapter supports the existing one-member result-backed create
capability. Literal mappings and other operations are explicitly refused here,
without narrowing the language or adding a fallback. The final Connector
Mapping/Projection agreement is checked by `check_execution_write`.

`prepare_native_resident_effect_review_from_catalog_custody` confirms the
existing Store custody, validates the independently supplied original binding,
and matches Site/generation/Invocation/dispatch against the actual holder and
producer context. Current disclosure and live receiver/context are checked
before and after Store readback, and again before preparing the Review. It
selects the sole matching captured Result through
`captured_effect_local_result_matches_member`, never a proposed Result index.

Configuration supplies already trusted Host retention, dependencies, source
binding, actual Store authority and bounds. It grants no permission. The existing
context verifies retention before capture; the existing Review/Original Owners
verify the retained input and restore normalization from original materials.
Production `source_binding_cid` is the original consumer input binding projected
from the existing live holder/context, independently checked against the Policy.
It is neither the producer Source binding nor a CID selected from Catalog bytes.
A foreign/missing original binding must not be backfilled.

The Review consumes the context on success. Rejection uses its existing close
Owner and returns the same pending context if cleanup is not confirmed. Catalog
custody remains independently caller-owned, including on rejection; context
close or borrow return does not retire that holding or return its reservation.
No new cleanup Owner or ledger is introduced.

## Validation and unfinished public connection

The five focused JS cases compose genuine Catalog and checked Mapping Owners:
matching result-backed create; four foreign original scopes; changed field type
and Connector identity; limits; and unsupported literal mapping. Metadata values
are independent fixtures. Generated Mapping input in these composition tests is
original authoring input, not an independent expected CID vector.

Matching Native package/holder/API compilation is selected. Store readback,
actual captured-input selection and the new live-context entry are compile-only.
No Native executable, cryptographic grant, Provider transport or public approval
is executed. Caller configuration loading, holder retention of Catalog failures,
production Review routing, restart and final Result/release remain unfinished.
Hosted CI is stopped; Draft is intentional. An ENOSPC while first writing this
note prevented a commit; existing code and test evidence remained preserved.

## Original consumer Source binding

The existing `ResidentRetainedConsumer.effect_source_binding_cid` projection
requires the actual journal's completed Effect computation, current receiver
borrow, original captured inputs and transported request. The input context
projects that same identity only while its retained facts remain current.
Neither projection captures input, issues authority nor creates another binding.

Review preparation independently compares the configured Source binding CID to
this projection before Result export or Catalog readback. Review's current check
retains that comparison before Provider operations. The existing Result
occurrence, Artifact, Invocation, Retention and Store checks remain required.
The initial Source producer binding is not the consumer binding.

Existing physical fixture callers now obtain this CID from the actual holder.
Additional Native assertions compare the projection to the saved consumer
journal envelope, refuse the initial producer binding and a fixture CID, and
reject foreign journals and closed contexts. These assertions are compiler
checked only until a separately authorized physical verification window.
An initial diagnostic compiler failure (an unnecessary optional unwrap on the
non-optional protocol binding projection) remains recorded and was corrected.

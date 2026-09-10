# Semantic decision criteria

This guide governs design proposals and reviews. It is not a second language
specification: accepted behavior belongs in the normative owners, grammar and
applicable machine contracts. A preference below does not authorize an
implementation to accept syntax that the specification has not admitted.

## Evidence and authority

Start with explicit normative requirements and recorded agreements. Compare
prose, grammar, machine schemas, acceptance cases and relevant decision records.
If they disagree, report the disagreement instead of silently choosing the
most permissive, strictest or easiest source. Distinguish a clarification from
a change to an existing rule, including an exception to a general rule.

Inspect relevant reference implementations at fixed revisions. Their code,
tests and adapters are evidence and reusable implementation material, not
automatic authority over ActQL. Record meaningful differences rather than
assuming all reference implementations agree. Backend limitations belong in
the implementation compatibility plan, not in an invented language prohibition.
An unresolved backend gap also prevents claiming execution support.

## Unspecified boundaries

For an empty collection, repetition or other edge case, first apply the ordinary
meaning of the operation. Describe the resulting values, multiplicity, schema,
order and evidence. Prefer acceptance when that meaning is unambiguous and
preserves existing invariants; this is a design preference, not a claim that
the current specification already accepts the case.

Additional rejection needs a concrete reason: for example duplicate output
names, an unrepresentable result, unresolved ambiguity or an explicit contract
violation. Low expected usage, possible authoring mistakes, ease of implementation
or rejection by reference code alone are insufficient. Advisory lint may flag
suspicious but valid input. An intentional product restriction is still possible,
but needs an explicit rationale and agreement rather than being disguised as
semantic necessity.

Shared syntax should reuse shared meaning where applicable. Similar spelling
does not erase operation-specific behavior: an empty partition key can denote
one global partition, while aggregation and representative-row selection still
differ on empty input. Likewise, repeated partition keys do not create output
columns, whereas repeated projection fields can create forbidden duplicate names.

## Keep the boundaries separate

- Syntax acceptance is not proof of type correctness or execution support.
- Type checking is not proof of stable order, uniqueness, bounded execution,
  identity evidence or permission to publish.
- Unfinished obligations must remain explicit and be discharged at the required
  boundary. They are not permission to postpone static errors until runtime.
- A no-op preserves its input evidence; it does not fabricate new evidence or
  prevent a later consumer from establishing evidence by its own permitted rules.
- Acceptance of a no-op or repeated condition does not authorize operation
  deletion, preimage deduplication or CID equivalence with a different source.
- Bounded implementation support is not a restriction on the entire language.

## Decision record and completion

For each disputed case, state: the current requirements; reference behavior;
the proposed semantics and reason; whether this clarifies or changes a rule;
effects on identities, proofs and consumers; and remaining implementation gaps.
Get agreement before changing acceptance. A later proposal should identify new
evidence or an explicit decision change, not merely a different reviewer preference.

After agreement, update normative prose, structural grammar, applicable schemas
and their dependent pins/requirement records together. Add fixed positive,
negative and boundary expectations when implementing the affected operation.
Verify the implementation on all supported targets and report execution evidence
separately from documentation and regeneration checks.

## Ordering and deduplication decisions

The normative owners are [sort](../spec/language.md#sort) and
[distinct and dedupe](../spec/language.md#distinct-and-dedupe).

| Case | Decision and rationale |
| --- | --- |
| Empty sort | Identity operation, retaining existing order and evidence. This is an explicit exception to sort's candidate-key completion, not an instruction to synthesize a sort. |
| Empty keyed distinct | Rejected, consistent with its select projection and the existing prohibition on empty select. Never reinterpreted as whole-row distinct. |
| Repeated distinct fields | Rejected because projection cannot create duplicate output names. |
| Repeated dedupe keys | Accepted and retained; they do not duplicate output fields or strengthen uniqueness/tie evidence. |
| Empty dedupe keys | Accepted as one global partition; a nonempty order selects its first existing row, with top ties failing and empty input yielding no row. |

Empty dedupe keys are not a no-op. Their acceptance follows partition semantics,
not an assertion that every empty operation is an identity. Global aggregation
can emit an aggregate row for empty input; dedupe cannot invent a representative
row. It also differs from sort followed by take-one because dedupe retains its
mandatory top-tie failure rule.

Implementation follow-through remains necessary: the existing AoA adapters reject
empty order terms and empty dedupe keys, and the limit adapter does not forward
offset. Lowering must implement the admitted behavior without removing the
authored semantic operation or claiming unsupported execution conformance.
The type-checking increment does not implement those adapters or proof propagation.

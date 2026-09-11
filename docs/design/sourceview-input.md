# Authored SourceView input syntax

`sourceview_input.collect` reads connector/resource input declarations from one
prepared staged source. It retains that exact owner, the stage ordinal, input
name and original cursor. Local declarations and Result/receipt imports belong
to separate passes; an empty collection does not certify that those inputs are
valid. In particular, a malformed local object lacking both connector and
resource is not silently certified as a SourceView. Final Input dispatch must
account for every input through its corresponding reader.

## Admitted fields

The normative owners are [Connector SourceViews](../spec/language.md#sourceviews),
[Input duplicate normalization](../spec/language.md#input-normalization),
[External joins](../spec/language.md#external-joins) and
[Authoring Context](../spec/language.md#authoring-context).

The closed connector form contains required nonempty connector/resource, optional
nonempty view, request, scan, minimum_classification, meta and duplicates. A
present request is a nonempty object, matching the pinned Program schema;
absence is retained, not replaced by an empty object. A present scan is exactly
`{mode: snapshot|changes}`. Classification admits the existing four strings.
Metadata is a nonempty free-form object with only top-level actql_ keys reserved.
Local carrier, schema, expected columns and identity-role overrides are rejected:
the SourceView contract owns output Carrier and facts. No schema_ref alias or
default view spelling is introduced.

Duplicate policy uses the language's existing materialized-Relation extension:
reject or a nonempty first_by_order.order_by list. Omission and explicit reject
have no order terms, but remain distinguishable in the original source cursor.
Common OrderKey decoding preserves term order, repetitions and explicit null
placement. Returned term arrays are copies. This is not evidence of total order,
raw-row validity or normalized-key uniqueness.

Sketch `87dc7144:src/actql.ts` corroborates the connector field vocabulary;
its obsolete schema_ref spelling and implementation-specific defaults are not
imported. Existing machine schemas provide the request/scan/classification shapes;
the duplicate extension follows the normative Input rule, not a claim that every
historical embedded Program schema expresses all dependent Input constraints.

## Remaining resolution obligations

The reader deliberately does not determine whether an input is materialized,
keyed or a search template. Catalog resolution must use all SourceViews for the
exact connector/resource pair when view is omitted, with zero/ambiguous matches
rejected and sole-view completion recorded. No filtering by permission, request
compatibility or downstream use is allowed during that selection.

After resolution, keyed templates reject scan and duplicate-policy fields;
duplicates are available only to materialized Relation inputs and cannot repair
authoritative SourceView uniqueness violations. Requested scan modes must be
supported by the resolved contract. A parsed scan or duplicate policy is not
proof of this compatibility. Classification is an authored floor only, not an
observed value or egress grant.

`source_request_slots` independently resolves whole-value Parameter/Binding holes
under the same source owner. This syntax reader does not interpret or substitute
request data. Full request type/coverage checks, Catalog identity/membership,
concrete binding issuer evidence, acquisition authority and backend support are
not yet certified. Final assembly must join these results by exact source and
input coordinates. No SourceView acquisition, lowerer or evaluation is added.

## Limits and tests

One work budget covers stage/input enumeration and each selected declaration's
whole subtree, including request and metadata data. Traversal is iterative and
charges nodes, child edges and UTF-16 text units before further expansion.
Shared order-key capacity applies across all inputs, not per input. Source
parsing already establishes scalar validity and NFC/LF; this API cannot accept a
freely constructed cursor as a substitute source owner. These limits do not
claim exact wall time or heap size.

Tests cover unresolved/explicit view, scan forms, imports across stages, nested
business data, closed fields, null versus absence, classification and metadata,
order repetition/copy isolation, exact/insufficient work and key caps, and a
request nested 10,000 levels deep. Successful syntax fixtures are not claims of
valid Catalog-bound executable inputs.

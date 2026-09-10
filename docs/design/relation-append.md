# Relation append type checking

`relation_append.check` checks a closed `{with: name}` body against two supplied
complete Relation schemas. The caller resolves that name; the
[pipeline checker](pipeline-typing.md) retains both operand coordinates.
This implements [append's static contract](../spec/language.md#append), not
row execution, lowering, key/order/completeness proof propagation or publication.

Field sets match by typed name, including left/right qualification, independently
of input construction order. A flat field and a qualified field never match by
spelling alone. Empty schemas are compatible and both operand occurrences remain
present. Appending the same input retains twice its row multiplicity; it does
not become a no-op or an identity assertion.

Each paired field uses `value_contract.join_nullability` recursively: nullable
flags combine with OR, collection/string limits admit either input, decimal
precision/scale and vector dimensions must match, and resource kinds must match.
Different artifact media types join to an unspecified media type. There is no
field filling, base-type coercion or author-selectable union schema mode.
The retained output schema is canonical; detached `alignment` entries carry
left/right schema positions for later name alignment, not physical row offsets.

## Resource and diagnostic boundaries

Both entire input schemas and the output schema are preflighted, including
otherwise unused children. Contract traversal is iterative. Work and text
budgets are cumulative; syntax nodes account for the closed append body.
Depth limits bound body and contract traversal independently. Invalid bodies
are rejected without traversing irrelevant invalid payloads; this does not
exempt either supplied contract from preflight.

A bounded pair walk locates compatibility failures and counts the exact pairs
needed for recursive contract construction. That count is debited before
calling `join_nullability`, never reset to the whole-call allowance per field.
Field lookups use one name index, not a rebuilt object map for every field.
Mismatch paths use one mutable traversal stack and are copied only on failure.

`IncompatibleContracts` includes the top-level typed field and a separate
contract path (`Field(name)` / `Item`). The source diagnostic points to `with`
in the original operation. Supplied opaque contracts have no authored source
coordinates here, so the checker does not fabricate a span for their nested
definitions. Missing fields identify the missing side and typed field.

## Deferred execution obligations

Every success retains `ValidateInputRows`, `PreserveLeftThenRightOrder`,
`ResolveOutputEnvelope`, and `ResolveIdentityAndCompleteness`. These are
unfinished checks, not proven facts. Left rows precede right rows; neither
input order becomes a new global uniqueness proof. Disjoint discriminator
evidence, input completeness, retained provenance and consumer identity
requirements need the later proof boundary. Lack of such evidence alone does
not reject an otherwise valid static append.

The reference TypeScript compiler already uses recursive contract joining;
the older MoonBit compiler only combined root nullability in some paths.
This implementation uses the current recursive contract. The AoA union adapter
can union column sets, which is not permission to accept incompatible schemas
here. Execution adapters must preserve checked alignment, left-then-right
multiplicity and empty-schema rows before execution conformance can be claimed.

The fixed [corpus](../../portability/corpus/actql-relation-append-v0.1.json),
handwritten deep/wide/budget tests, and pipeline/Result tests run on all three
targets. Expectations are fixed independently of product output. There is no
dedicated append-body machine schema to regenerate; the normative grammar and
requirement metadata track the clarified contract.

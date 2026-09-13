# Query Acquisition residual execution

The shared [query acquisition contract](query-acquisition.md) owns the semantic
scan/filter/select boundary. The local `execution_query.QuerySequence` binds
that opaque derivation to an already admitted `GeneratedSequence`; it does not
derive another canonical query or Plan.

Preparation requires the same checked pipeline and exact bound Parameter owner.
Equal-looking source, schema or parameter values from another preparation do not
establish that ownership. An absent lowering binding is only compatible with an
empty shared binding. Preparation is physically work-bounded before retained
identifier comparison; it does not discharge the query's runtime obligations.

The narrow local adapter supports exactly one source input and two steps, filter
then select. Only select's output is retained. The shared derivation may describe
a capture within a larger pipeline, but the local sequence driver executes all
steps. Such a sequence is rejected by this adapter, not silently shortened or
executed past capture. This is an execution support limit, not a language rule.

For a broad receipt, `evaluate_query_receipt` admits all supplied rows under the
original source-input schema before calling the existing generated-sequence
driver. A malformed late row therefore precedes an expression failure in an
earlier row. It retains the existing input, expression, output and workspace
budgets, immutable completion and producer ownership checks. Receipt row limits
are physical admission limits, not the canonical acquisition output-row guard.

An already admitted typed source may instead use the engine's one-shot
`AdmittedInput` builder. Each cell must carry the exact input field contract;
the builder does not substitute type equality or repeat admission. It allocates
bounded row containers, shares immutable payloads, and measures every retained
row/key/value occurrence with the existing capture ledger. Failure clears pending
rows and closes the builder; cancellation after sealing cannot clear captured
storage. No partial `CapturedRows` can escape. This is a row-layout conversion,
not a promise of zero-copy column transfer.
`bind_query_receipt` checks the exact bound preparation and supplied input origin
before retaining that material. It neither copies rows nor grants source,
snapshot, attempt or execution authority. These remain upper-layer obligations.

Its successful `CompletedSequence` proves local residual computation only. It
does not prove that a source was exhausted, authority was granted, a snapshot
was matched or acquisition guards were enforced. Native receipt of filtered rows
cannot use this adapter as evidence of full-scan validation. Source validation,
filter and select execution records, actual access, immutable observation capture
and verification against the canonical requirement remain separate acquisition
responsibilities. Neither an offered candidate nor local computation success may
be substituted for those records.

This boundary uses the ordinary completed-output and producer-input APIs. It
adds no private alternative completion, suspension protocol or public Connector
SPI, and performs no I/O. It must not be presented as an Acquisition entry point
or permission to execute a Program.

## Dependency and ownership boundary

The dependency direction is:

```text
query_planning → execution_query → execution_relation → lowering_relation
                       ↓
              sourceview_resolution
```

`execution_query` resolves the acquisition's input/capture ports and checks the
exact checked pipeline, Parameter bindings and retained target. It owns
`QuerySequence`, `QueryReceipt`, and query diagnostic translation. No compatibility
facade lives in the row engine: package/API locations may change without changing
semantic contracts, wire forms, identities or failure precedence.

`execution_relation` knows only fixed admitted input, checked computation and
completion. Its read-only `generated_sequence_owner`, `generated_retained_count`
and `generated_retained_at` expose the exact retained owner and bounded metadata,
not mutable context or storage. The query adapter's `query_sequence_owner` returns
that same owner; it does not reconstruct an equivalent preparation.

`execute_fixed_input_guarded` is a synchronous single-fixed-input operation, not
a generic acquisition executor. It measures all input values, charges context
constraints before allocating their copies, tightens demanded-root byte ceilings,
executes the existing driver, checks the selected retained output's row ceiling,
and measures its values. One private ledger spans these phases. It cannot export
partial success or a mutable ledger. Context tightening uses the smaller existing
and requested ceilings; the original preparation remains reusable. No guard
reevaluates an expression, and the driver's original input accounting still runs.
Query ownership rejection precedes that operation, after invalid-limit checks;
query error translation preserves phase, row, column and nested failure kind.

Canonical logical row hashing also stays in `execution_relation`.
`identify_captured_rows` retains the exact `CapturedRows` handle, while
`identify_completed_rows` retains `CompletedOutput`. Query receipts retain those
same inputs; the upper verifier combines exact input/output identity matches with
its existing live issuer, attempt and record-set checks. A matching row CID is
never a substitute for those relationships. Passing handles across the package
boundary adds no row copies, re-admission or additional measurement traversal.

Query E2E fixtures live in the test-only `query_integration` package. They use
public checked construction and opaque execution APIs through capture and the
consumer. Layout, measurement-ledger, expression and completion whitebox tests
stay with the engine. Integration fixtures grant no test-only production authority.

# Query Acquisition residual execution

The shared [query acquisition contract](query-acquisition.md) owns the semantic
scan/filter/select boundary. The local `execution_relation.QuerySequence` binds
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

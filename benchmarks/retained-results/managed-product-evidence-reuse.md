# Managed product evidence-reuse checkpoint

Date: 2026-09-17. Implementation checkpoint:
`409ccb14f0c1814cd64b256afbd257a240e5ea55`.

This checkpoint connects the registered managed-retained profile's finite
checked-row-selection rule to the standard DuckDB strategy Host. It is product
execution evidence for one supported rule, not completion of every Q6 rule or
the final performance acceptance suite.

## Executed path

The real standard Host regression executes this serial graph:

```text
three-row, two-column managed result
  -> checked filter/select retaining two rows
  -> checked filter/select retaining the same two rows
```

Both downstream tasks read the exact graph-bound Store material, import it with
the connector-generated DuckDB file SQL, execute the selected query, seal an
independent output body and publish through the common managed DAG. The second
task consumes the first task's output rather than returning to legacy rows.

The installed physical frame carries explicit logical row ordinals and stores
columns in checked logical-schema order. The fixture deliberately receives the
DuckDB columns in the opposite order and observes the mapping `[1, 0]`. It also
rejects a frame without its required starting ordinal. This prevents DuckDB
field order, internal `rowid`, or a user column from silently becoming the
logical occurrence mapping.

## Deterministic work measurements

The following counters are asserted independently for each downstream task:

| Counter | Measured value |
| --- | ---: |
| Complete Store integrity passes | 1 |
| Native file-import commands | 1 |
| Parameter INSERT rows | 0 |
| Logical content CID computations | 0 |
| Core output-value admission cells | 0 |
| Reused measurement cells | 4 |
| Selected logical occurrences | 2 |
| Output physical frames | 1 |

The result therefore establishes that eight downstream cell uses across two
tasks do not repeat Core value admission. It does not claim zero predicate
evaluation, zero physical reads, or zero metadata work. Each task still checks
physical integrity, occurrence framing, logical schema order, selected count,
demand, current authority, native settlement, independent holding and common
graph publication.

The exact retained-accounting sequence is:

| Boundary | Held bytes |
| --- | ---: |
| Initial 896-byte index plus 43-byte body | 939 |
| First selected 768-byte index plus 36-byte body | 1,743 |
| Second selected 768-byte index plus 36-byte body | 2,547 |
| Revoke initial output and release its index | 1,651 |
| Close second selected output | 847 |
| Close first selected output | 43 |
| Close initial execution and confirm cleanup | 0 |

This demonstrates independent body/index ownership and reclamation. It is not
a memory-resident-table estimate or a substitute for the separate 1 GiB
experiment.

## Verification

At this checkpoint:

- `execution_relation`: 455/455 passed on JS, Wasm and native;
- DuckDB adapter: 23/23 passed on JS, Wasm and native;
- DuckDB Compute and driver checked without warnings on all three targets;
- the Node Host and managed column codec tests passed against actual DuckDB;
- the complete documentation, contract, link and independent-fixture gate
  passed; and
- generated public interfaces were regenerated and matched on all targets.

The standard Host test took about 12 seconds on this development machine, but
that duration includes builds and unrelated standard-Host coverage. It is
reported only as test-run context and is not a performance comparison.

## Remaining measurement and implementation

This checkpoint covers a checked filter/select with unchanged Number columns,
multiple columns and repeated downstream use. The ordinary typed-admission
fallback remains for unsupported shapes. General projection/rename, derive,
sort/take, join/group-result reuse, other codecs and schemas, Local execution,
named Result/legacy bridging and accepted process delegation still need their
product-path evidence.

The unchanged old-contract 27-case/1 GiB run and its independent
same-obligation comparator remain separate required measurements. The new
profile also needs registered large-case runs that compare total decode,
admission, canonicalization, hash, copy, read/write, holding and cleanup work;
the zero-admission counters above are not by themselves a throughput claim.

## Subsequent standard-dispatch integration

The managed path is no longer limited to a test that manually assembles the
receiving request, candidate and per-task configuration. The generated DuckDB
bundle registers a managed-dispatch entrypoint. Given only a checked
Program-derived setup and explicit Host `managedOutput` policy, the ordinary
serial dispatcher now:

1. runs the first selected DuckDB task through managed completion;
2. obtains the exact next task and unary producer from the common captured DAG;
3. constructs and compares the installed managed candidate;
4. runs the consumer against the producer's exact managed material; and
5. owns every task close handle through graph close and cleanup.

The black-box product regression covers a three-task A-to-B-to-C chain and a
global group whose new one-cell result is reused by two downstream consumers.
The group value is admitted once; both consumers perform zero logical-content
CID computations and reuse the producer measurement. Separate regressions stop
after A when B's Store cannot start and when cancellation is requested after A
completion. Neither case authorizes B or C. Graph close and explicit cleanup
return held, retention-reserved and execution-reserved bytes to zero.

The failure regression also found a pre-native-session settlement gap. Managed
consumer setup could reserve common task capacity and then fail while creating
its output Store, before the native session's accounting callback ran. The Host
now records whether a native session started. A pre-start failure settles the
confirmed zero physical execution before task disposal; a started session still
requires its own receipt. This distinction is lifecycle correctness, not a
performance shortcut.

This closes standard-dispatch wiring and the required finite graph lifecycle
cases.

## Subsequent direct-output increment

> **Superseded for product selection.** The direct-output implementation below
> established the stated functional counters, but its `COPY TO` destination
> was checked against the Store reservation only after DuckDB had finished
> writing. A native write could therefore exceed the admitted physical bytes
> before rejection. The standard managed Host no longer selects this path.
> It writes every output through the Store's bounded `appendBytes` sink, which
> rejects the next frame before I/O when the reservation would be exceeded.
> Consequently, current product diagnostics report zero direct copies and the
> actual JavaScript materialization/frame counts. Direct native output may be
> restored only with a sink or filesystem quota that enforces the reservation
> while bytes are written. The historical measurements below remain evidence
> for the removed implementation, not evidence for the current product path.

The value-preserving downstream path now writes DuckDB output directly into a
Store-owned Parquet generation. The Host reads back only the source occurrence
and dense output ordinal needed for the registered selection rule. It does not
materialize output value cells in JavaScript and does not encode a second
managed-column frame.

The product regression fixes the following counters for each direct downstream
task:

| Counter | Required value |
| --- | ---: |
| Direct native output copies | 1 |
| Output value cells materialized in JavaScript | 0 |
| Output managed-frame re-encodes | 0 |
| Logical content CID computations | 0 |
| Physical Store integrity passes | 1 |

A global group remains the deliberate contrast. Its new aggregate value is
typed-admitted and encoded once, so its direct-copy count is zero and its value
admission/frame counters are one. Two later consumers reuse that established
measurement and use direct Parquet output without repeating admission.

The Store regression separately covers successful native-created-file adoption,
capacity overflow and a generation replacement between native report and Store
adoption. Cancellation retains the output reservation until native cleanup is
terminal; only then can the Store confirm writer stop and reclaim a failed
generation.

The direct-output counters establish removal of the control-side value relay for
the covered path. The registered new-profile matrix, controller-memory samples
and final paired timing report remain separate measurements; these functional
counters alone are not a speed ratio.

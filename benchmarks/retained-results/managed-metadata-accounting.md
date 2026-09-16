# Managed metadata accounting frontier

Inspection after `321c099d` confirms that index entry/work ceilings are not
physical allocation reservations. The Node fixture's previous wording called
its four-cell cap a reservation; that comment is corrected. No claim of full
metadata capacity accounting follows from that fixture's successful execution.

## Concrete allocation and ownership boundaries

| Boundary | Current allocation / responsibility |
| --- | --- |
| `enable_managed_row_measurements` | Fixed-capacity byte/node/null index. The managed retained DuckDB strategy path now reserves and owns this allocation through the existing task ledger; non-strategy Hosts still require their own accounting boundary. |
| `prepare_managed_take_selection` | Creates the expected occurrence array before Core preparation. |
| `prepare_managed_view_selection_base` | Defensively copies occurrences, builds column summaries, copies cell metadata; source and destination overlap. |
| `managed_view_selection_measurements` | Reads the source index; arbitrary permutations require temporary duplicate-detection metadata. |
| computed view preparation | Uses the same independent index, including slots for new values; admission/encoding scratch is additional. |
| successful view issuance | Index moves into the output receipt; its lifetime is not just the executor's running time. |
| `managedOutputRetain` in the Node fixture | Receives `body.bytes`, i.e. physical file bytes. The managed retained strategy entry now converts that exact count from its admitted file ceiling into a task-ledger holding before issuing material. This does not include the separate MoonBit index or selection metadata. |

The existing `physical_resources` ledger already separates reserved execution,
reserved retention and held allocations. Its cleanup-pending and settlement
operations distinguish cancellation from acknowledged reclamation. It should
remain the accounting owner; a separate metadata quota must not silently enlarge
the selected physical allowance.

The retained body and fixed index connections are now implemented for the
managed retained DuckDB strategy entry: reservation precedes execution, exact
Store body bytes and exact index capacity create separate holdings from the
same task reservation, and output revocation clears the index before releasing
both holdings. The remaining connection concerns occurrence arrays, summaries,
maps and copy overlap, plus transfer of the body holding into production
managed graph completion.
Preparation temporaries and retained indexes have different release times.
Dropping a reference or marking the body file unavailable is not proof that all
metadata allocation has been reclaimed. Entry count, canonical value bytes and
physical file bytes must not be substituted for one another. The old bounded
row executor's separate `generated_sequence_capacity` estimate does not
establish these remaining bounds.

## Remove a needless temporary before reserving it

Strictly increasing source occurrence indices prove uniqueness during the
already-required range/order pass. The metadata reader now uses this fact for
ordered take/filter selections and exact-order views instead of building a
row-sized temporary hash map. It does not skip range validation or accept
duplicate occurrences as distinct source occurrences.

For a non-increasing permutation, the reader still creates a duplicate map and
charges an additional bounded pass before doing so. Insufficient metadata work
returns the existing `Limit` outcome; it is not a data violation or permission
to reset the consumer's budget. Logical value measurements are unchanged.

The regression fixes exact work boundaries (eight units for a two-row/two-column
ordered selection; ten for its permutation), equal summary results, and duplicate
rejection. This is a structural reduction of temporary allocation, not a timing
or RSS claim. The retained index, occurrence-array copies and column summaries
still exist, and the physical reservation connection above remains unfinished.

Verification: execution-relation tests passed 450/450 on JS, Wasm and Native.
Strict JS checking, six managed DuckDB/manifest integration tests, cross-target
public API checking, formatting and diff checks passed. No identity definition
or logical guard changed.

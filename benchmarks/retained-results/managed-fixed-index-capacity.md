# Fixed-capacity managed measurement index

The retained per-cell measurement index now uses a fixed-capacity array rather
than a growable array of `(bytes, nodes, is_null)` tuples. The conservative
cross-target allowance is 64 bytes per cell, covering the pinned JS runtime's
array slot and tuple object; Native and Wasm use no more storage than this.
Successful logical measurement budgets already bound both integers to a
nonnegative `Int`, so the representation preserves the prior domain.

The buffer is allocated once from the admitted cell ceiling. It does not grow
while values are measured, and selected/computed output indexes use the same
representation. Cancellation and failed one-shot installation replace the
backing buffer with an empty one; successful issuance transfers the same packed
index into the output receipt. The representation retains exact cell order,
including equal values at distinct row occurrences, and leaves aggregate
measurements, diagnostic precedence and logical charges unchanged.

`managed_row_measurement_capacity_bytes` exposes a conservative retained
capacity for this allocation: 64 bytes per admitted cell plus a fixed
512-byte owner/array header allowance. It rejects negative and overflowing
counts.
This makes the index itself reservable before allocation; it is not a claim
that selection occurrence arrays, copied column summaries, duplicate-detection
maps or other preparation scratch fit within that amount. Those allocations
need their own execution/overlap capacity and ledger connection.

The fixed representation removes the previous runtime-dependent tuple and
growable-array sizing problem. It does **not** by itself complete physical
resource accounting: the installed Host must still reserve the returned index
capacity before enabling it, convert the reservation to a retained holding on
successful issuance, and release it only after use and reclamation are
confirmed. Existing entry/work limits remain logical preparation limits, not a
physical-byte reservation.

Regression coverage fixes empty, ordinary and maximum signed measurement
round-trips; exact allocation length; overflow and invalid-position rejection;
selected, computed and slice index transfer; diagnostic fault injection; and
terminal cleanup. This increment changes no CID, logical value measure or
public evidence shape.

The existing opt-in metadata diagnostic was rerun after the representation
change (one warmup pair, seven recorded alternating pairs, ten preparations per
sample). For 100,000 rows and two columns, the recorded medians were:

| target | explicit occurrence array | contiguous slice | paired median ratio |
| --- | ---: | ---: | ---: |
| JS | 27.177 ms | 21.020 ms | 0.774 |
| Native | 65.877 ms | 53.870 ms | 0.818 |

The previous diagnostic record reported JS 40.523/35.613 ms and Native
62.871/50.953 ms. These are separate diagnostic runs, not the formal paired
baseline comparison: JS improved substantially, while Native was about 5–6%
slower in this run. The retained goal remains predictable capacity without a
material cross-target regression; the full registered workload and physical
ledger integration still determine acceptance.

# Selected Relation fragment capacity

## Finding

The 512 MiB Run execution ceiling is unchanged. The two source-free Group
counterexamples handed off by Frontend were refused with zero prior execution
reservation. Their reported requirements, 550,139,392 and 626,696,448 bytes,
are exactly explained by repeated fragment allowance in the selected Relation
chain, not by one fragment requiring over 500 MiB.

Under the installed Local limits, a generated sequence reserves 14,240,000
retained bytes and 32,531,200 base execution bytes. One fragment's maximum
allowance is 29,785,600 bytes: `100000 * 264` for live values plus
`(10000 + 100) * 256 + 100000 * 8` for physical traversal. The selected chain
capacity sums each child completion and execution allowance because its child
owners and private outputs remain live until reverse-order cleanup. Dispatch
also reserves the parent result's 14,240,000-byte independent-copy allowance.

The source-free examples contain seven and eight selected operations. Before
this change, each selected child retained the original sequence's entire
fragment context inventory. `generated_sequence_capacity` therefore charged
the same maximum fragment allowance to every child, including Values, Group
count and Sort steps that cannot run that fragment:

```text
7 * (14,240,000 + 32,531,200 + 29,785,600 + 256) + 14,240,000
  = 550,139,392
8 * (14,240,000 + 32,531,200 + 29,785,600 + 256) + 14,240,000
  = 626,696,448
```

The correction retains the full context inventory for checked ownership but
charges a context's live-value and traversal allowance only when its original
step belongs to the selected execution view. Full sequences remain unchanged;
single-step, prefix and range views are covered by an exact-byte regression.
Child output holdings, child cleanup order, imported-input retention, parent
result copying, and the Run ceiling are unchanged. In particular, this does
not replace the sum of live child capacities with a serial maximum: downstream
readers still borrow predecessor completions until cleanup.

## Evidence boundary

The fixed regression checks independent arithmetic for a full sequence and
selected Values, ordered binding, filter, projection, prefix and range views.
The affected `execution_relation` JS package and a focused existing Relation
chain integration selection pass. The Frontend Group examples and their
independent expected rows live on an unmerged Frontend branch; packed public
acceptance on that branch remains separate. The historical capacity readings
are not relabeled as a successful public Result.

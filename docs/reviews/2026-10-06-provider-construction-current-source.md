# Current Relation provider construction premises

Reviewed product source: `2fa9a8dfe3d9589083d4db0846f53ec7a112d0f0`
(#485). The subtraction source is
`cec9df396e18bff4b206c80130bdb607fa29b84a` (#501, dependent on #485).
This review does not authorize adoption of the still-failing mandatory suite.
The initial inspection below preserved product source, the original recipe,
allocation inventory, Native observer, retained declarations and model theorem.
The source-only supplement now implemented is recorded separately at the end.

## Constructor correspondence

The eleven-candidate recipe introduced at
`58fd19eade59cf3bcbf6a859c9821471346e3b41` remains the historical reference.
The selected source is now
`7662c1e802515661034647ae045a03bccfdd69f25d88710ae467f644c14a3b9a`.
It cannot satisfy the old whole-file source pin by relabeling it.

Independent extraction of the actual functions confirms byte equality of the
three wrapper bodies with their introduction revision:

| Function | Body SHA-256 |
| --- | --- |
| managed_provider | 97c7881276b3a72486a9095b5c320496b231e97ef7aef148f6e3a45f8e52128b |
| managed_provider_with_inputs | 05787bfa023bb449803474bb51ad5f68a91ae5d9d5bdf536e20d6cee24ad5438 |
| managed_provider_with_numeric | 6e0874df3465c9ec6b0fcba89e3f2a38be09ed117746d522dd2120ec272c0cb9 |

The entire selected factory outside the first accepts callback is also
byte-equal to its introduction source. The actual accepts callback continues
reading only the outer `limits`, `measurement` and `family` bindings; its new
`used_by_later` Array is allocated when accepts runs, not when the callback is
constructed. The capacity and start callbacks and the numeric compatibility
wrapper remain unchanged. This supports retaining the source-level *conditional*
eleven-record/four-callback recipe. It does not determine compiled scalar
callback allocation extents or prove all memory needed to select or run a chain.

C's same-source Native constructor-only receipt was inspected directly:
`run-I6XlmY`, one passed test, exit 0, complete output and released locks.
Its unchanged reader observes eleven distinct records, eleven array slots,
twenty indexed callbacks, one default Array, zero unclassified captures,
1184 classified indexed bytes and twenty dynamic scalar callbacks.
The output digest is
`f3fdc315b9a5bfc65b0f4308566a72c94c77d6f6b6cac83ed756fc21241de925`.
Neither 1184 nor the conditional 2344 includes an observed extent for those
scalar callbacks. Neither is a complete constructor, parent or Graph heap bound.

## Changes outside the construction-only subject

- `f261c2bff682fed6aad85464bb4a42e5a952885c` replaces the single previous
  output with `Ref[Array[CompletedOutput?]]`. The Array owner, backing slots,
  nullable retained output references and old/new release overlap require their
  own correspondence. The same change allocates branch-use state in accepts.
- `a0dc67bac44b4ce28b60c2f6cf7570f00562c561` adds Waiting/Settling and
  their work extraction. The wrapper-body equality does not imply that this
  whole file differs only by the older handoff helper. Pauses and reported work
  must retain the existing accounting and stopping contract.
- GeneratedSequence's traversal configuration belongs to the prepared
  configuration owner. Its allocation is excluded from constructor-only bytes,
  but is an explicit outstanding lifetime/parent obligation. The exact Graph
  union/subtraction row-kernel exclusions do not add a candidate factory.

## Required supplement and remaining acceptance

Keep the original recipe and archived facts. Add a reviewed current-source
supplement which binds the original recipe, actual change revisions, exact
source digests, wrapper bodies, constructor captures and same-source Native
census. Reject an unreviewed capture, field, factory count or source change;
do not turn every poll or Graph change into a wildcard allowance. Preserve
historical correspondence tests as historical tests and require the current
correspondence separately. Run the complete mandatory source-premise file on
the adoption head, not merely the passing Graph exclusion case.

The retained parent observer is independently stale: overlay.mjs still emits
`parent_control_probe(..., previous, ...)`, helper.mbt expects a single nullable
output Ref, allocations.json names previous, and both C readers enumerate its
old captures. Renaming the local is insufficient. Before issuing current parent
correspondence, adapt the existing borrowed observer/census to the actual
completed Array owner and backing, cardinality, nullable output identities,
retained generations and release overlap. It must add no persistent reference,
not double-count shared CompletedOutput payloads, retain references until actual
parent cleanup, and distinguish source/ABI assumptions from measured bytes.
The historical parent theorem/receipt is not current-source execution evidence.

Actual retained-history success is already independently evidenced on both C
heads (`run-vsHF7z`, 1734 commits; `run-VznLqz`, 1747 commits). It is not the
missing constructor or parent correspondence. No repeat history campaign was
performed for this review. The mandatory premise suite remains 2 passed /
5 failed at the union head; Actions billing is a separate limitation.

G's source-review extraction is retained under
`_build/repro/provider-source-review-2fa9a8d.json`, SHA-256
`1cb78fb7a451ef8388967558d9a6be3e62f2787d3d9889987e82ab6766425ec6`.
It is source analysis, not a new Native execution or a passing mandatory test.

## Implemented construction-only supplement

G's independent branch starts from integrated main
`d093bcedf8b64b5d7b3e8fdecc988310c51bff90`. It does not include either C PR's
Graph product changes. The original `provider-construction.json` remains
byte-for-byte unchanged (`cf00b1b46f2ce78e37ab22eb14872dbfb63c1607c0382fc27124fa6b1ff0dc71`).

`provider-construction-source-review.json` records exact reviewed source
variants and change subjects. Its checker requires all three original wrapper
bodies, the original selected factory outside accepts, and the entire historical
managed source after removing only the exact Waiting/Settling additions. The
generated source must equal the historical source after removing only the
reviewed Graph exclusions from the existing false branch. Arbitrary source,
capture, field, poll work, recipe or factory changes remain rejected.

The two older whole-file delta tests now explicitly read their actual reviewed
Git tree, `7d7cc6cfc6e7b46379fc85c8ac223bd380cbd200`. They retain their original
expectations and hashes. They are historical correspondence, not a substitution
for current source. Four additional tests independently require current bodies,
all three exact main/union/subtraction variants, refusal of a historical-source
fallback, and rejection of additional fields/captures/changed pause work.

The complete source-premise file passes **10/10 Node**:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  proofs/relation-pipeline/provider-construction.test.mjs
```

Receipt `run-CxhgYd`, focused `focused-test-Yp8YG6`, records the working diff
on `d093bcedf8b64b5d7b3e8fdecc988310c51bff90`; it is not retagged as a later
commit or as C's adoption run. Initial `run-Zrnreh` failed because the new
source extraction omitted a reviewed separator newline and a negative test's
substring occurred in two functions. Both implementation errors were corrected;
that failed receipt remains preserved. No Native, packed, all-Core or history
campaign was repeated. Dependencies borrow the existing root `node_modules`.

This closes source correspondence for the **conditional 2344-byte construction
component**. It does not close dynamic scalar payload extents, current completed
Array/backing/output generations or release overlap. Neither the 1184 classified
Native bytes nor this source test is a parent/Graph/pipeline capacity upper bound.
The C adoption head still needs its full mandatory file, including its own
Graph-specific rejection case. #485 remains pending that adoption and the
separate completed-output lifetime correspondence; #501 retains #485 dependency.

# Incremental keyed request wire and construction DATA

- Responsibility: continue the existing encoding of one selected keyed request
  and describe its immediate original Writer and typed-emitter constructors.
  This unit does not implement assembly funding, provider I/O or a scheduler.
- Inputs and outputs: the cursor borrows one KeyedRowRequest and explicit byte,
  node and depth limits. Polls return no output, a bounded wire fragment, final
  usage or the existing encoding issue. Separate start/next inventories return
  constructor DATA before the corresponding step allocates. The synchronous
  keyed_row_request_wire compatibility function remains unchanged.
- Identity: the cursor retains the exact original request. Its owner accessor
  exposes that same object; equal wire or a copied request cannot replace it.
  Progress and inventory generation identify mutable progress only, not
  Source authority, resource admission or a reusable permission token.
- Ownership: the original request, names, checked values and reference envelopes
  stay borrowed. One existing buffered Writer owns duplicate-key Maps, frame
  backing and its current output builder. One active typed emitter owns its
  frames and any selected canonical-reference emitter. Returned fragments and
  final concatenation belong to the caller and are outside these inventories.
- Synchronization: before start or advance the caller must fund the selected
  inventory. After any resource or liveness callback, it must recheck the exact
  request/cursor, generation and original resource lifetime before advancing.
  Every advance changes generation, including a step that emits no bytes.
  No Source scan, typed-value measurement pass or second serialization occurs.
- Failure: original byte/node/depth, duplicate-field and scalar checks remain
  authoritative. An exhausted limit can leave a bounded partial emission;
  WireFailed is not a complete request. The caller retains and cleans up its
  previously returned fragments. Overflow or unavailable inventory is refusal,
  never zero capacity or permission to continue.
- Cancellation: cancellation closes the same active typed/canonical emitter and
  Writer and invalidates progress. Vacated native stack slots are overwritten
  with payload-free sentinels before logical truncation so they do not retain
  completed reference cursors or object Maps. Logical truncation does not prove
  array backing was released; inventories retain the original capacity/peak.
- Resources: constructor inventories use existing logical collection ownership,
  not a policy-sized preallocation or a physical heap claim. Typed frames use
  O(1) actual pending capacity plus the selected canonical child's capacity.
  Writer frames use original maximum depth and observed node/key construction.
  An outer name is bounded by six bytes per actual retained UTF16 unit plus
  punctuation. Existing nested emission uses bounded64-unit fragments. Native
  BufferedText drains replace only its builder with a fresh minimum-capacity
  builder, avoiding reset proportional to a previous large name. The quote
  includes old/new growth or original/drained String overlap and the fresh
  one-slot backing. Prior fragments, dedup storage and final concat are OUT.
- Extension: this is one selected request with the existing authored field order,
  typed encoding and reference rules. It does not add general unordered key
  emission, a new canonical format, concurrent cursor mutation, a new resource
  owner, runtime census growth or automatic capacity admission. The existing
  Writer, typed wire and canonical emitter have only targeted lifetime/buffer
  changes described below; this document does not claim their unrelated APIs.
- Verification: focused tests cover exact wire, authored literal and parameter
  values, nested escaping, Decimal and reference fragments, failure/cancellation,
  deep-to-shallow capacity, stale native slots and dense nonempty emission after
  a long name. Matching JS/native executions are required for those respective
  claims. Ledger callback admission, cumulative key retention, final concat and
  provider lifecycle integration are separate, unverified caller obligations.

## Targeted changes to existing emitters

In encode_core/writer.mbt, BufferedText owns a replaceable builder; its nonempty
output drain preserves the returned String and installs a fresh empty builder.
BufferedHash is unchanged. Completed Array/Object frame slots and cancellation
slots are replaced with RetiredFrame before logical truncation. Frame ordering,
node/byte/depth limits and duplicate-key detection are unchanged.

In value_admission/wire.mbt, typed frames are replaced with WireRetired before
truncation. The selected ReferenceNext remains registered around a potentially
failing child advance so existing cancellation still reaches that child.

In canonical_json/encode.mbt, canonical frames similarly use EmitRetired.
emit_storage_frames reports O(1) retained pending capacity for its immediate
constructor inventory; it grants neither emission nor resource authority.

No claim is made about cumulative historical allocation, prompt garbage
collection, engine allocator metadata or RSS. The caller must keep its admitted
workspace high-water until it can prove the original owners retired.

///|
/// Named local constructor dependencies outside the context scaffold. The
/// original source, topology, identity, capacity proofs and Unit publication
/// payloads are borrowed/separately reserved. This does not grant preparation.
pub(all) struct ClosedValuesLocalOwnerLayout {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  owned_utf16_units : Int64
  owned_wire_bytes : Int64
} derive(Eq, Debug)

///|
/// Before-construction bound for one literal Values producer and one Result.
/// D bounds original Cursor paths, not measured constructed output. Copies of
/// empty declaration indices in this earlier PipelineContext are distinct from
/// the later ProgramSourceIdentity indices and are intentionally included.
pub fn closed_values_local_owner_layout(
  original_depth : Int,
) -> ClosedValuesLocalOwnerLayout? {
  if original_depth < 0 {
    return None
  }
  let d = original_depth.to_int64() + 1L
  // ContextualClosure/ContextualOrders/AuthorGuards, guard Budget+Limits,
  // one step-range tuple and the authored-guard collector closure:7H12R19W.
  // Seven Arrays have zero/one item; eight slots each cover append/copy.
  let orders_h = 7L + 7L * 3L
  let orders_r = 12L + 7L * 9L
  let orders_w = 19L + 7L * 10L
  // Pipeline parameter collection: Collected, ExpressionSlots, ParameterSlots,
  // two collectors, Budget, two Limits, PointerBudget, Index, PreparedValues,
  // two BoundIndex construction versions:13H23R22W. Seven empty Arrays;
  // two empty Maps; two sort closures; pinned empty Map.keys().collect control.
  let parameter_h = 13L + 7L * 2L + 2L * 2L + 2L + 8L
  let parameter_r = 23L + 7L + 2L * 2L + 8L
  let parameter_w = 22L + 7L * 2L + 2L * 13L + 12L
  // Three fresh cursor_path Arrays, with freshly allocated Key/Index variants.
  // Array growth overlap12+3D; both typed-slot alternatives are reserved.
  let path_h = 9L + 3L * d
  let path_r = 3L * (1L + 12L + 3L * d) + 3L * d
  let path_w = 6L + 3L * (12L + 3L * d) + 6L * d
  // build_units:14 Arrays (eight retained initial arrays plus sorting/import
  // staging),122 total backing slots incl selected old backing16;32 selected
  // (CID,body) tuples; completed Map1; two CID Strings; preimage record7refs;
  // three outer IdentityBudgets; final owner-join tuple5refs. Unit top records
  // and later replacement publications Array belong to their payload owners.
  let unit_h = 29L + 32L + 5L + 2L + 1L + 3L + 1L
  let unit_r = 136L + 64L + 8L + 7L + 5L
  let unit_w = 28L + 17L + 12L
  // Guarded acyclic scaffold + empty-sourceview carrier-site inventory:
  // closed-context-carrier-site-inventory.json, 76 explicit source files.
  // 6985 weighted syntax sites /11471 weighted payload slots. This includes
  // declarations and unreachable branches deliberately; it is an upper, not
  // actual allocation telemetry. A site may own one direct tagged/tuple value
  // and one returned Result/Some carrier. Each payload slot is conservatively
  // projected as both reference and scalar; tags add one word per carrier.
  // capacity_witness/witness.mbt has a five-live-instance multiplier for
  // emit_cursor recursion: fixed metadata maximum depth4 plus scalar leaf.
  // Other scaffold sites have multiplier1 on this guarded acyclic route.
  // The one-stage/no-expression/no-source guard excludes nested producer and
  // expression recursion. Sequential loop iterations replace transient return
  // carriers; escaping collections are in their named retained inventories.
  // Generic recursive source/tree visitors and dependency internals belong to
  // their separate source/walk recipes. Fixed VM frames are not charged here.
  // This replaces the unjustified record-count81/dispatch31/helper16 proxy.
  // Eleven actual scalar budget records remain distinct (16 scalar fields).
  let sites = 6985L
  let payload_slots = 11471L
  let control_h = 2L * sites + 11L
  let control_r = sites + payload_slots
  let control_w = 2L * sites + payload_slots + 16L
  Some({
    record_headers: orders_h + parameter_h + path_h + unit_h + control_h,
    reference_slots: orders_r + parameter_r + path_r + unit_r + control_r,
    scalar_words: orders_w + parameter_w + path_w + unit_w + control_w,
    owned_utf16_units: 142L,
    owned_wire_bytes: 0L,
  })
}

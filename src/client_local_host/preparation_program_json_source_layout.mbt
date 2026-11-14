///|
/// Installed quote-construction DATA, not represented source/index payload.
/// begin_program_json_preparation adds this domain packet ONCE to the existing
/// outside debit. It is not a prepaid-original entrance. The entering debit
/// getter, checked additions and original resize/current frame need the actual
/// caller's independent first-prelude backing before that grow can complete.
/// After the grow this stays on the SAME capacity, without spending
/// unrelated old-supplier slack or treating policy ceilings as actual demand.
/// Call-expanded peak, conservatively summed sequentially (H,R,W):
/// - Source grammar quote20,5,46: existing key/map12,2,24; canonical3,1,8;
///   original Source3,1,9; staged Source descriptor/carrier2,1,5.
/// - index quote18,7,37: key/map12,2,24 +six records/carriers6,5,13.
/// - five unit conversions5,0,25; literal six-item Array2,7,2; shared
///   six-item composition37,1,76; five-field tariff5,0,10.
/// - initial and later checked additions4,0,8; two-scalar quote result2,1,3;
///   typed failure alternatives2,2,2. Original95,23,209 is preserved.
/// Retained projection adds59H14R126W: Source extent2,1,5; existing
/// index quote18,7,37; three Unit conversions3,0,15; four-item sum29,6,58;
/// tariff+three checked additions8,0,16. The returned Unit record1H5W is excluded
/// from scratch and counted once by the retained driver plan below.
/// The begin operation reserves this packet before later projection and
/// reconciliation calls. That reservation does not retroactively supply the
/// begin operation's own pre-resize frame or the backend's borrowed inputs.
// Generic structural continuation adds386H118R818W, funded BEFORE its first
// descriptor/receipt/observer allocation. Conservative call-expanded families:
// - original Program base quote182,55,382: unchanged152,28,322 plus
//   the SAME one container quote30,26,60 and retained-original holder1R;
// - aggregate +two canonical normalization descriptors/conversions14,2,56;
// - three additional sum2/literal scopes60,15,120;
// - original Resource work receipt/closures and slot12,16,18;
//   this also covers the shared explicit-wide state8,10,6; no second
//   work engine, receipt overlap or future Catalog domain is added.
// - same-index usage/bound/control projection10,2,20;
// - phase compositions/tariffs/checked peaks100,20,210;
// - original typed-return and retry carriers8,8,12.
// These are fixed quote constructors, NOT represented name/Program storage.
// The new four optional phase fields and their same-live tags/quote tuple add
//8H12R11W to the original driver below. No old quote slack is spent.
// Observed Source shape plus canonical scratch/output and checked Text joins
// add8H4R20W, conservatively co-counting their descriptor/return alternatives.
let program_json_quote_controls : @execution.PreparationRepresentationUnits = {
  let work = @resources.preparation_phase_work_construction_inventory()
  let container = @syntax.program_container_quote_control_extent()
  // Keep the unchanged Source/index/driver roles and use each original
  // receipt/container owner for its quote-construction DATA exactly once.
  {
    record_headers: 8L +
    154L +
    356L +
    container.record_headers -
    12L +
    work.record_headers,
    reference_slots: 4L +
    37L +
    92L +
    container.reference_slots -
    16L +
    work.reference_slots,
    scalar_words: 20L +
    335L +
    758L +
    container.scalar_words -
    18L +
    work.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
// Same immutable layout, priced once by the existing shared tariff during
// installed module initialization. No per-input result/grant is cached here.
let program_json_quote_control_bytes : Int64 = @execution.preparation_representation_cost(
  program_json_quote_controls,
).unwrap()

///|
// Phase holder adds one optional retained-plan slot; its Some and returned
// Unit record add2H2R7W to the original13H17R21W. The same returned
// Unit record is excluded from quote scratch, not counted twice.
// Original holder1H6R8W and four Some fields4H4R4W; typed return/issue
// carriers4H4R4W; ready forward alternatives2H2R2W; original debit tuple
// and Result2H1R3W. Record/Some alternatives are conservatively co-counted.
let program_json_driver_controls : @execution.PreparationRepresentationUnits = {
  // One optional original-error alias and its conservative Some carrier stay
  // live beside the existing failed index until the same parent's cleanup.
  record_headers: 15L + 8L + 1L,
  reference_slots: 19L + 12L + 2L,
  scalar_words: 28L + 11L + 2L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
let program_json_post_preflight_controls : @execution.PreparationRepresentationUnits = {
  let stage = @syntax.program_json_input_control_extent()
  @execution.compose_preparation_representation([
    program_json_quote_controls,
    program_json_driver_controls,
    {
      record_headers: stage.record_headers,
      reference_slots: stage.reference_slots,
      scalar_words: stage.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ]).unwrap()
}

///|
let program_json_initial_controls : @execution.PreparationRepresentationUnits = {
  let source = @source.json_source_preflight_control_extent()
  @execution.compose_preparation_representation([
    program_json_post_preflight_controls,
    {
      record_headers: source.record_headers,
      reference_slots: source.reference_slots,
      scalar_words: source.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ]).unwrap()
}

///|
let program_json_initial_control_bytes : Int64 = @execution.preparation_representation_cost(
  program_json_initial_controls,
).unwrap()

///|
/// Return the existing installed immutable recipe DATA, not a prepaid token.
/// Do not pre-add it to the outside debit passed to begin: begin adds it once.
/// Source/input, Limits/path and the backend's first-prelude/outer backing
/// remain borrowed and independently funded. This getter reserves nothing.
pub fn program_json_preparation_initial_inventory() -> @execution.PreparationRepresentationUnits {
  program_json_initial_controls
}

///|
fn program_json_source_index_quote(
  geometry : @source.JsonSourceGeometry,
  limits : @syntax.Limits,
) -> (Int64, Int64)? {
  // Zero is a valid refusal path. A one-slot constructor envelope covers its
  // original failure controls without changing any original parser limit.
  let nodes = Int::max(
    1,
    Int::min(geometry.node_upper, limits.source.max_nodes),
  )
  let depth = Int::max(
    1,
    Int::min(geometry.depth_upper, limits.source.max_depth),
  )
  guard @source.json_source_geometry_construction_extent(geometry, nodes, depth)
    is Some(source) &&
    @decode.admission_construction_inventory(
      nodes,
      Int::min(geometry.fields, nodes),
      Int::min(geometry.objects, nodes),
      Int::min(geometry.arrays, nodes),
      depth,
    )
    is Some(index) else {
    return None
  }
  let whole = @execution.compose_preparation_representation([
    program_json_post_preflight_controls,
    {
      record_headers: source.record_headers,
      reference_slots: source.reference_slots,
      scalar_words: source.scalar_words,
      owned_utf16_units: source.owned_utf16_units,
      owned_wire_bytes: 0L,
    },
    decode_construction_preparation_units(index.indexed),
    decode_construction_preparation_units(index.keys),
    decode_construction_preparation_units(index.ancestry),
    decode_construction_preparation_units(index.controls),
  ])
  guard whole is Some(whole) &&
    @execution.preparation_representation_cost(whole) is Some(peak) else {
    return None
  }
  // Preflight ended before the first grammar transition. Same parser bodies
  // move, they do not duplicate. One ready report remains in the Source quote.
  let peak = Int64::max(peak, program_json_initial_control_bytes)
  Some((peak, peak))
}

///|
// After index construction, the SAME ready geometry is now retained by this
// phase rather than its retired Source view. Its one1H12W body moves between
// phases; do not add it beside the Source grammar snapshot in the prior peak.
let program_json_retained_driver_controls : @execution.PreparationRepresentationUnits = {
  ..program_json_driver_controls,
  record_headers: program_json_driver_controls.record_headers + 1L,
  scalar_words: program_json_driver_controls.scalar_words + 12L,
}

///|
fn program_json_retained_index_units(
  indexed : @syntax.ParsedProgramInput,
  geometry : @source.JsonSourceGeometry,
) -> @execution.PreparationRepresentationUnits? {
  program_index_retained_units(
    indexed,
    geometry.fields,
    geometry.quoted_tokens,
    geometry.objects,
    geometry.arrays,
  )
}

///|
// Both document grammars produce the SAME immutable index/retained Strings.
// JSON preflight and actual admitted YAML geometry supply only these counts;
// neither can substitute a parsed owner or another semantic interpretation.
fn program_index_retained_units(
  indexed : @syntax.ParsedProgramInput,
  fields : Int,
  strings : Int,
  objects : Int,
  arrays : Int,
) -> @execution.PreparationRepresentationUnits? {
  let root = @syntax.program_input_cursor(indexed)
  let actual = @decode.admission_usage(root)
  guard @source.indexed_source_dependency_extent(
      actual.nodes,
      fields,
      strings,
      actual.total_string_bytes.to_int64(),
    )
    is Some(source) &&
    @decode.admission_construction_inventory(
      actual.nodes,
      fields,
      objects,
      arrays,
      actual.depth,
    )
    is Some(index) else {
    return None
  }
  let stage = @syntax.program_input_retained_control_extent()
  @execution.compose_preparation_representation([
    program_json_retained_driver_controls,
    {
      record_headers: source.record_headers,
      reference_slots: source.reference_slots,
      scalar_words: source.scalar_words,
      owned_utf16_units: source.owned_utf16_units,
      owned_wire_bytes: 0L,
    },
    decode_construction_preparation_units(index.indexed),
    {
      record_headers: stage.record_headers,
      reference_slots: stage.reference_slots,
      scalar_words: stage.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ])
}

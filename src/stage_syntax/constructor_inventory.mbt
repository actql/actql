///|
/// All container constructions of decode_envelope, conservatively summed even
/// when their scopes do not overlap. Source/index backing, identifier text,
/// inspection/control carriers and diagnostics are separate owners. This is
/// DATA, not a semantic verdict, byte tariff or physical reservation.
pub(all) struct ProgramConstructorInventory {
  retained : ProgramConstructionExtent64
  array_owners : Int64
  array_items : Int64
  map_owners : Int64
  map_entries : Int64
  object_views : Int64
  key_pairs : Int64
  normalization_calls : Int64
  retained_name_input_utf16 : Int64
  max_name_input_utf16 : Int
  input_bindings : Int64
  element_cursor_slots : Int64
  field_name_reads : Int64
  closed_key_checks : Int64
  indexed_key_arrays : Int64
  name_reads : Int64
  retained_name_calls : Int64
  max_retained_name_input_utf16 : Int
  max_temporary_name_input_utf16 : Int
  inspection_work : Int64
} derive(Eq, Debug)

///|
priv struct ConstructorInventoryState {
  work : ConstructionExtentWork
  mut arrays : Int64
  mut items : Int64
  mut maps : Int64
  mut entries : Int64
  mut views : Int64
  mut pairs : Int64
  mut names : Int64
  mut retained_text : Int64
  mut max_text : Int
  mut inputs : Int64
  mut elements : Int64
  mut field_reads : Int64
  mut closed_checks : Int64
  mut key_arrays : Int64
  mut name_reads : Int64
  mut retained_names : Int64
  mut max_retained : Int
  mut max_temporary : Int
}

///|
priv suberror ConstructorInventoryStop {
  Stop
}

///|
fn constructor_spend(
  state : ConstructorInventoryState,
  count : Int,
) -> Unit raise ConstructorInventoryStop {
  if count < 0 || count.to_int64() > state.work.remaining {
    raise Stop
  }
  state.work.remaining -= count.to_int64()
}

///|
fn constructor_field(
  node : @wire.Cursor,
  key : String,
  state : ConstructorInventoryState,
) -> @wire.Cursor? raise ConstructorInventoryStop {
  let value = construction_field(node, key, state.work)
  if state.work.exhausted {
    raise Stop
  }
  value
}

///|
fn constructor_object_size(
  node : @wire.Cursor,
  state : ConstructorInventoryState,
) -> Int raise ConstructorInventoryStop {
  let size = @wire.object_length(node).unwrap_or(0)
  constructor_spend(state, size)
  size
}

///|
fn constructor_array(state : ConstructorInventoryState, items : Int64) -> Unit {
  state.arrays += 1L
  state.items += items
}

///|
fn constructor_open(state : ConstructorInventoryState, keys : Int) -> Unit {
  state.views += 1L
  state.maps += 1L
  state.entries += keys.to_int64()
}

///|
fn constructor_closed(
  node : @wire.Cursor,
  allowed : Int,
  state : ConstructorInventoryState,
) -> Unit raise ConstructorInventoryStop {
  let keys = constructor_object_size(node, state)
  state.closed_checks += 1L
  constructor_open(state, keys)
  // allowed, copied source keys, and empty required-key array.
  state.arrays += 3L
  state.items += allowed.to_int64() + keys.to_int64()
  let check = @shape.object_key_construction_counts(keys, 0, allowed).unwrap()
  state.maps += check.maps.to_int64()
  state.entries += check.map_entries
  state.arrays += check.pair_arrays.to_int64()
  state.key_arrays += check.pair_arrays.to_int64()
  state.items += check.pairs
  state.pairs += check.pairs
}

///|
fn constructor_name(
  node : @wire.Cursor?,
  retained : Bool,
  state : ConstructorInventoryState,
) -> Unit raise ConstructorInventoryStop {
  constructor_spend(state, 1)
  state.name_reads += 1L
  if node is Some(value) && @wire.is_text(value) {
    let size = @wire.text(value).unwrap().length()
    state.names += 1L
    state.max_text = Int::max(state.max_text, size)
    if retained {
      state.retained_names += 1L
      state.max_retained = Int::max(state.max_retained, size)
      guard @counts.checked_nonnegative_add_product(
          state.retained_text,
          size.to_int64(),
          1L,
        )
        is Some(total) else {
        raise Stop
      }
      state.retained_text = total
    } else {
      state.max_temporary = Int::max(state.max_temporary, size)
    }
  }
}

///|
fn constructor_metadata(
  node : @wire.Cursor,
  state : ConstructorInventoryState,
) -> Unit raise ConstructorInventoryStop {
  if constructor_field(node, "meta", state) is Some(meta) {
    let count = constructor_object_size(meta, state)
    state.field_reads += 1L
    constructor_array(state, count.to_int64())
    constructor_open(state, count)
  }
}

///|
/// Observe only envelope metadata through the original indexed cursor. No row,
/// parameter, step body, Source payload or arbitrary nested value is walked.
/// Missing/wrong-kind fields contribute no children; the original decoder,
/// not this observer, still issues the precise structural refusal. None means
/// inspection work/count exhaustion, never proof of invalid/unsupported input.
/// The caller must fund this bounded inspection before calling it.
pub fn program_constructor_inventory(
  root : @wire.Cursor,
  max_work : Int64,
) -> ProgramConstructorInventory? {
  let (inventory, _) = observe_program_constructor_inventory(root, max_work)
  inventory
}

///|
/// Report the original observer's charged visits on success OR failure. This
/// does not turn its DATA inventory into a structural/semantic verdict.
pub fn observe_program_constructor_inventory(
  root : @wire.Cursor,
  max_work : Int64,
) -> (ProgramConstructorInventory?, Int64) {
  if max_work < 1 {
    return (None, 0L)
  }
  let state : ConstructorInventoryState = {
    work: { remaining: max_work - 1, exhausted: false, },
    arrays: 0L,
    items: 0L,
    maps: 1L,
    entries: 0L,
    views: 0L,
    pairs: 0L,
    names: 0L,
    retained_text: 0L,
    max_text: 0,
    inputs: 0L,
    elements: 0L,
    field_reads: 0L,
    closed_checks: 0L,
    key_arrays: 0L,
    name_reads: 0L,
    retained_names: 0L,
    max_retained: 0,
    max_temporary: 0,
  }
  let value = Some(inspect_program_constructor(root, max_work, state)) catch {
    Stop => None
  }
  (value, max_work - state.work.remaining)
}

///|
fn inspect_program_constructor(
  root : @wire.Cursor,
  max_work : Int64,
  state : ConstructorInventoryState,
) -> ProgramConstructorInventory raise ConstructorInventoryStop {
  constructor_closed(root, 7, state)
  constructor_name(constructor_field(root, "version", state), false, state)
  constructor_name(constructor_field(root, "id", state), true, state)
  constructor_metadata(root, state)
  constructor_array(state, 2L) // params/bindings loop's original array
  for key in ["params", "bindings"] {
    if constructor_field(root, key, state) is Some(value) {
      let size = constructor_object_size(value, state)
      state.field_reads += 1L
      constructor_array(state, size.to_int64())
    }
  }
  let nodes = constructor_field(root, "stages", state)
  let stage_count = match nodes {
    Some(value) => @wire.array_length(value).unwrap_or(0)
    None => 0
  }
  constructor_spend(state, stage_count)
  state.elements += stage_count.to_int64()
  constructor_array(state, stage_count.to_int64()) // elements(stages)
  let mut imports = 0L
  let mut indexed_names = 0L
  for index in 0..<stage_count {
    let stage = @wire.element_at(nodes.unwrap(), index).unwrap()
    constructor_closed(stage, 9, state)
    constructor_name(constructor_field(stage, "id", state), true, state)
    constructor_metadata(stage, state)
    if index > 0 {
      if constructor_field(stage, "after", state) is Some(value) {
        constructor_name(Some(value), false, state)
      }
    }
    let inputs = constructor_field(stage, "inputs", state)
    if inputs is Some(inputs) {
      let count = constructor_object_size(inputs, state)
      state.inputs += count.to_int64()
      state.field_reads += 1L
      constructor_array(state, count.to_int64())
      constructor_open(state, count)
      for position in 0..<count {
        let (_, input) = @wire.field_at(inputs, position).unwrap()
        if @wire.is_text(input) {
          continue
        }
        let fields = constructor_object_size(input, state)
        state.field_reads += 1L
        constructor_array(state, fields.to_int64())
        constructor_array(state, 2L) // result/receipt loop, also on refusal
        for kind in ["result", "receipt"] {
          if constructor_field(input, kind, state) is Some(target) {
            imports += 1L
            constructor_closed(input, 2, state)
            constructor_metadata(input, state)
            constructor_closed(target, 2, state)
            let target_key = if kind == "result" { "result" } else { "effect" }
            constructor_name(
              constructor_field(target, "stage", state),
              true,
              state,
            )
            constructor_name(
              constructor_field(target, target_key, state),
              true,
              state,
            )
          }
        }
      }
    }
    if constructor_field(stage, "from", state) is Some(value) {
      constructor_name(Some(value), false, state)
      // UnknownInput's original diagnostic calls name again on the same value.
      constructor_name(Some(value), false, state)
    }
    let steps = match constructor_field(stage, "steps", state) {
      Some(value) => @wire.array_length(value).unwrap_or(0)
      None => 0
    }
    constructor_spend(state, steps)
    state.elements += steps.to_int64()
    constructor_array(state, steps.to_int64())
    // These three arrays/maps are retained below, including actual absent
    // optional declarations' empty arrays and empty maps.
    for key in ["results", "table_inputs", "effects"] {
      if constructor_field(stage, key, state) is Some(value) {
        indexed_names += constructor_object_size(value, state).to_int64()
        state.field_reads += 1L
      }
    }
  }
  let exports = constructor_field(root, "results", state)
  let export_count = match exports {
    Some(value) => constructor_object_size(value, state)
    None => 0
  }
  state.field_reads += 1L
  constructor_array(state, export_count.to_int64())
  constructor_open(state, export_count)
  for index in 0..<export_count {
    let (_, export_) = @wire.field_at(exports.unwrap(), index).unwrap()
    constructor_closed(export_, 1, state)
    if constructor_field(export_, "from", state) is Some(from) {
      constructor_closed(from, 2, state)
      constructor_name(constructor_field(from, "stage", state), true, state)
      constructor_name(constructor_field(from, "result", state), true, state)
    }
  }
  let stages = stage_count.to_int64()
  let arrays = 2L + 4L * stages
  let items = stages + export_count.to_int64() + imports + indexed_names
  state.arrays += arrays
  state.items += items
  state.maps += 3L * stages
  state.entries += stages + indexed_names // seen plus three Stage indexes
  let work = max_work - state.work.remaining
  {
    retained: {
      stage_records: stage_count,
      import_tuple_bound: imports,
      export_tuples: export_count,
      name_index_entries: indexed_names,
      retained_array_capacity_bound: 8L * arrays + 2L * items,
      retained_map_capacity_bound: 24L * stages + 4L * indexed_names,
      inspection_work: work,
    },
    array_owners: state.arrays,
    array_items: state.items,
    map_owners: state.maps,
    map_entries: state.entries,
    object_views: state.views,
    key_pairs: state.pairs,
    normalization_calls: state.names,
    retained_name_input_utf16: state.retained_text,
    max_name_input_utf16: state.max_text,
    input_bindings: state.inputs,
    element_cursor_slots: state.elements,
    field_name_reads: state.field_reads,
    closed_key_checks: state.closed_checks,
    indexed_key_arrays: state.key_arrays,
    name_reads: state.name_reads,
    retained_name_calls: state.retained_names,
    max_retained_name_input_utf16: state.max_retained,
    max_temporary_name_input_utf16: state.max_temporary,
    inspection_work: work,
  }
}

///|
/// Logical container peak from the same decoder's inventory. This includes
/// retained containers and their shallow records. Do not add retained again
/// within this peak. Text, control carriers and one diagnostic path still need
/// their own simultaneous inventory before a caller can reserve the phase.
pub(all) struct ProgramConstructorContainerExtent {
  retained : ProgramContainerConstructionExtent
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
} derive(Eq, Debug)

///|
fn constructor_add_product(
  total : Int64,
  count : Int64,
  coefficient : Int64,
) -> Int64 raise ConstructorInventoryStop {
  guard @counts.checked_nonnegative_add_product(total, count, coefficient)
    is Some(value) else {
    raise Stop
  }
  value
}

///|
pub fn program_constructor_container_extent(
  inventory : ProgramConstructorInventory,
) -> ProgramConstructorContainerExtent? {
  guard program_container_construction_extent64(inventory.retained)
    is Some(retained) else {
    return None
  }
  if inventory.inspection_work < 0 ||
    inventory.normalization_calls < 0L ||
    inventory.retained_name_input_utf16 < 0L ||
    inventory.max_name_input_utf16 < 0 {
    return None
  }
  Some(constructor_container_extent(inventory, retained)) catch {
    Stop => None
  }
}

///|
fn constructor_container_extent(
  inventory : ProgramConstructorInventory,
  retained : ProgramContainerConstructionExtent,
) -> ProgramConstructorContainerExtent raise ConstructorInventoryStop {
  // Keep the retained shallow records; all actual Map/Array construction
  // recipes now come from the shared collection owner, without parallel
  // copies of its growth constants in this domain.
  let h = constructor_add_product(retained.shallow_record_headers, 1L, 1L)
  let h = constructor_add_product(h, inventory.object_views, 1L)
  let h = constructor_add_product(h, inventory.key_pairs, 1L)
  let r = constructor_add_product(retained.shallow_reference_slots, 1L, 5L)
  let r = constructor_add_product(r, inventory.object_views, 2L)
  let r = constructor_add_product(r, inventory.key_pairs, 1L)
  guard @shape.collection_construction_extent({
      records: h,
      record_references: r,
      record_words: retained.shallow_scalar_words,
      reference_arrays: inventory.array_owners,
      reference_items: inventory.array_items,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: inventory.map_owners,
      map_entries: inventory.map_entries,
    })
    is Some(value) else {
    raise Stop
  }
  {
    retained,
    record_headers: value.record_headers,
    reference_slots: value.reference_slots,
    scalar_words: value.scalar_words,
  }
}

///|
/// Logical control storage, with no tariff or reservation authority. The
/// envelope observation owns these actual Cursor/read/closure counts.
pub(all) struct ProgramConstructorControlExtent {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
} derive(Eq, Debug)

///|
/// Decoder controls beside the separately inventoried containers and one
/// normalization workspace. These are conservative sums of sequential reads;
/// only one failure lookup/path is possible because the decoder unwinds at its
/// first typed error. All names, source spans and Cursor trees remain borrowed.
pub fn program_constructor_control_extent(
  inventory : ProgramConstructorInventory,
) -> ProgramConstructorControlExtent? {
  guard program_container_construction_extent64(inventory.retained) is Some(_) else {
    return None
  }
  if inventory.name_reads < inventory.normalization_calls ||
    inventory.retained_name_calls < 0L ||
    inventory.retained_name_calls > inventory.normalization_calls ||
    inventory.max_retained_name_input_utf16 < 0 ||
    inventory.max_temporary_name_input_utf16 < 0 ||
    inventory.element_cursor_slots < inventory.retained.stage_records.to_int64() {
    return None
  }
  Some(constructor_control_extent(inventory)) catch {
    Stop => None
  }
}

///|
fn constructor_control_extent(
  inventory : ProgramConstructorInventory,
) -> ProgramConstructorControlExtent raise ConstructorInventoryStop {
  let s = inventory.retained.stage_records.to_int64()
  let i = inventory.retained.import_tuple_bound
  let x = inventory.retained.export_tuples.to_int64()
  // Required reads: root4, Stage4, each input1, each import3, export4.
  let mut required = constructor_add_product(4L, s, 4L)
  required = constructor_add_product(required, inventory.input_bindings, 1L)
  required = constructor_add_product(required, i, 3L)
  required = constructor_add_product(required, x, 4L)
  // Optional reads: root meta/params/bindings3; Stage meta/after/from/
  // table_inputs/effects5; one metadata read per import. A failing diagnostic
  // can repeat one required read or select one reserved metadata key.
  let mut optional = constructor_add_product(3L, s, 5L)
  optional = constructor_add_product(optional, i, 1L)
  let reads = constructor_add_product(
    constructor_add_product(required, optional, 1L),
    1L,
    1L,
  )
  let elements = constructor_add_product(1L, s, 1L)
  let cursors = constructor_add_product(
    reads,
    inventory.element_cursor_slots - s,
    1L,
  )
  // Map::get constructs an entry option and value option. wire.lookup then
  // maps that to a Cursor option; charge three alternatives per read. The
  // separate seen.get reads for import/export also need both options. Contains
  // uses its allocation-free probe; Map construction controls belong above.
  let mut tags = constructor_add_product(0L, reads, 3L)
  tags = constructor_add_product(tags, i, 2L)
  tags = constructor_add_product(tags, x, 2L)
  tags = constructor_add_product(tags, required, 1L)
  tags = constructor_add_product(tags, 1L, 1L) // repeated required on failure
  tags = constructor_add_product(tags, inventory.object_views, 1L)
  tags = constructor_add_product(tags, inventory.closed_key_checks, 1L)
  tags = constructor_add_product(tags, inventory.field_name_reads, 1L)
  tags = constructor_add_product(tags, elements, 1L)
  tags = constructor_add_product(tags, inventory.name_reads, 1L) // text()
  tags = constructor_add_product(tags, 1L, 1L) // final Program Result
  let mut closures = constructor_add_product(reads, elements, 1L)
  closures = constructor_add_product(closures, inventory.field_name_reads, 1L)
  closures = constructor_add_product(closures, inventory.closed_key_checks, 1L)
  closures = constructor_add_product(closures, inventory.indexed_key_arrays, 1L)
  closures = constructor_add_product(closures, 2L, 1L) // exports.map/stages.any
  let h = constructor_add_product(
    constructor_add_product(cursors, tags, 1L),
    closures,
    1L,
  )
  let mut r = constructor_add_product(0L, cursors, 2L)
  r = constructor_add_product(r, tags, 1L)
  r = constructor_add_product(r, reads, 2L)
  r = constructor_add_product(r, elements, 1L)
  r = constructor_add_product(r, 1L, 2L) // export closure's seen/original slots
  // A generic payload-bearing tag can carry a scalar or reference. This
  // componentwise envelope covers one reference OR scalar plus its tag; it
  // does not claim that both alternatives are physically allocated.
  let w = constructor_add_product(cursors, tags, 2L)
  { record_headers: h, reference_slots: r, scalar_words: w, }
}

///|
/// path_at reverses its single growable array in place. At most depth+1
/// borrowed path segments accompany the first Issue/Structure/Abort/Result.
pub fn program_constructor_failure_extent(
  source_depth : Int,
) -> ProgramConstructorControlExtent? {
  if source_depth < 0 {
    return None
  }
  let d = source_depth.to_int64() + 1L
  Some({
    record_headers: 7L + d,
    reference_slots: 20L + 4L * d,
    scalar_words: 6L + 2L * d,
  })
}

///|
/// Fixed live inspection packet, independent of fields/rows/payload size:
/// state+work2H1R20W; returned inventory/retained-facts/Some3H2R27W;
/// ten active Cursor slots, three tuple slots and twelve option alternatives
/// 25H38R34W; three fixed loop arrays6H10R6W; one key-count/arithmetic/text
/// projection packet4H3R9W; observation tuple1H1R1W. The caller funds this BEFORE inspecting its source.
/// This counts explicit data, not fixed VM frames, a byte price or a grant.
pub fn program_constructor_inspection_extent() -> ProgramConstructorControlExtent {
  { record_headers: 41L, reference_slots: 55L, scalar_words: 97L, }
}

///|
/// Work bound from the SAME admitted index, with no payload walk. Each field's
/// object is scanned at most twelve times, including malformed dual imports;
/// array visits and name reads contribute at most nine per indexed node. A
/// tree has at most nodes-1 field edges, so nodes bounds both arms. Only actual
/// visits are spent. This is not memory demand, a policy or semantic verdict.
/// Int64 preserves the entire original Int-sized source domain, unsaturated.
pub fn program_constructor_inspection_work_bound(
  original : ParsedProgramInput,
) -> Int64 {
  1L + 21L * @wire.admission_usage(original.root).nodes.to_int64()
}

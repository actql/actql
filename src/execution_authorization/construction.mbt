///|
/// Closed Account constructor DATA only. The actual caller prices these units
/// and grows its SAME original resource before allowing the next constructor.
/// No field is an Account decision, grant, current witness or cleanup receipt.
pub(all) struct AccountConfigurationConstructionUnits {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  owned_utf16_units : Int64
  owned_wire_bytes : Int64
} derive(Eq, Debug)

///|
pub(all) struct AccountConfigurationConstruction {
  retained : AccountConfigurationConstructionUnits
  execution : AccountConfigurationConstructionUnits
} derive(Eq, Debug)

///|
priv suberror AccountConstructionStop {
  AccountConstructionStop
}

///|
// A synchronous preparation continuation in the existing Account codec, not
// another resource owner. The Native caller retains its original refusal.
priv struct AccountConstructionContext {
  prepare : (AccountConfigurationConstruction) -> Bool
  mut wire_live : AccountConfigurationConstructionUnits
}

///|
let account_construction_zero : AccountConfigurationConstructionUnits = {
  record_headers: 0L,
  reference_slots: 0L,
  scalar_words: 0L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
fn account_construction_units(
  headers : Int64,
  references : Int64,
  words : Int64,
  text : Int64,
  wire? : Int64 = 0L,
) -> AccountConfigurationConstructionUnits {
  {
    record_headers: headers,
    reference_slots: references,
    scalar_words: words,
    owned_utf16_units: text,
    owned_wire_bytes: wire,
  }
}

///|
fn account_construction_sum(
  left : AccountConfigurationConstructionUnits,
  right : AccountConfigurationConstructionUnits,
) -> AccountConfigurationConstructionUnits? {
  guard @counts.checked_nonnegative_add_product(
      left.record_headers,
      right.record_headers,
      1L,
    )
    is Some(h) &&
    @counts.checked_nonnegative_add_product(
      left.reference_slots,
      right.reference_slots,
      1L,
    )
    is Some(r) &&
    @counts.checked_nonnegative_add_product(
      left.scalar_words,
      right.scalar_words,
      1L,
    )
    is Some(w) &&
    @counts.checked_nonnegative_add_product(
      left.owned_utf16_units,
      right.owned_utf16_units,
      1L,
    )
    is Some(t) &&
    @counts.checked_nonnegative_add_product(
      left.owned_wire_bytes,
      right.owned_wire_bytes,
      1L,
    )
    is Some(b) else {
    return None
  }
  Some(account_construction_units(h, r, w, t, wire=b))
}

///|
fn account_prepare_construction(
  context : AccountConstructionContext?,
  retained : AccountConfigurationConstructionUnits,
  execution : AccountConfigurationConstructionUnits,
) -> Unit raise AccountConstructionStop {
  if context is Some(original) {
    guard account_construction_sum(original.wire_live, execution) is Some(peak) &&
      (original.prepare)({ retained, execution: peak, }) else {
      raise AccountConstructionStop
    }
  }
}

///|
// The callback/quote/context/error alternatives are a fixed initial cohort.
// Reading this installed DATA must precede the first request-owned staging
// record. Input String backing is borrowed from the caller's original intake.
let account_construction_initial : AccountConfigurationConstructionUnits = {
  record_headers: 12L,
  reference_slots: 21L,
  scalar_words: 18L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
// Installed first-cohort request. It is read before creating the private
// continuation or Source staging controls, not constructed inside that phase.
let account_construction_initial_request : AccountConfigurationConstruction = {
  retained: account_construction_zero,
  execution: {
    let source = @source.json_source_preflight_control_extent()
    account_construction_units(
      source.record_headers + account_construction_initial.record_headers,
      source.reference_slots + account_construction_initial.reference_slots,
      source.scalar_words + account_construction_initial.scalar_words,
      0L,
    )
  },
}

///|
fn account_construction_source(
  value : @source.JsonConstructionExtent,
) -> AccountConfigurationConstructionUnits {
  account_construction_units(
    value.record_headers,
    value.reference_slots,
    value.scalar_words,
    value.owned_utf16_units,
  )
}

///|
fn account_construction_index(
  value : @decode.AdmissionConstructionUnits,
) -> AccountConfigurationConstructionUnits {
  account_construction_units(
    value.record_headers,
    value.reference_slots,
    value.scalar_words,
    0L,
  )
}

///|
fn account_construction_add(
  left : AccountConfigurationConstructionUnits,
  right : AccountConfigurationConstructionUnits,
) -> AccountConfigurationConstructionUnits raise AccountConstructionStop {
  account_construction_sum(left, right).unwrap_or_else(() => {
    raise AccountConstructionStop
  })
}

///|
// Only cached original preflight counts size this next constructor. The
// Source owner retains its Unicode/normalization and parser-growth recipe.
fn account_prepare_json_tree(
  context : AccountConstructionContext,
  geometry : @source.JsonSourceGeometry,
) -> Unit raise AccountConstructionStop {
  let nodes = Int::max(1, geometry.node_upper)
  let fields = Int::min(geometry.fields, nodes - 1)
  let objects = Int::min(geometry.objects, nodes)
  let arrays = Int::min(geometry.arrays, nodes - objects)
  let grammar = @source.json_source_geometry_construction_extent(
    geometry, nodes, 7,
  ).unwrap_or_else(() => raise AccountConstructionStop)
  account_prepare_construction(
    Some(context),
    account_construction_zero,
    account_construction_source(grammar),
  )
  let text = @canonical.nfc_lf_retained_output_units(
    geometry.quoted_raw_utf16_units.to_int64(),
  ).unwrap_or_else(() => raise AccountConstructionStop)
  let tree = @source.json_tree_retained_construction_extent(
    nodes, fields, objects, arrays, text,
  ).unwrap_or_else(() => raise AccountConstructionStop)
  context.wire_live = account_construction_add(
    account_construction_initial,
    account_construction_source(tree),
  )
}

///|
fn account_prepare_json_index(
  context : AccountConstructionContext,
  geometry : @source.JsonSourceGeometry,
) -> Unit raise AccountConstructionStop {
  let nodes = Int::max(1, geometry.node_upper)
  let fields = Int::min(geometry.fields, nodes - 1)
  let objects = Int::min(geometry.objects, nodes)
  let arrays = Int::min(geometry.arrays, nodes - objects)
  let index = @decode.admission_construction_inventory(
    nodes, fields, objects, arrays, 7,
  ).unwrap_or_else(() => raise AccountConstructionStop)
  let peak = account_construction_add(
    account_construction_index(index.indexed),
    account_construction_add(
      account_construction_index(index.keys),
      account_construction_add(
        account_construction_index(index.ancestry),
        account_construction_index(index.controls),
      ),
    ),
  )
  account_prepare_construction(Some(context), account_construction_zero, peak)
  context.wire_live = account_construction_add(
    context.wire_live,
    account_construction_index(index.indexed),
  )
}

///|
// One observed wire-decoder cohort, including duplicate/invalid-key refusal.
// It retains only the returned typed records/arrays/normalized text. The
// original Source/index remains a separate coheld temporary until decode ends.
fn account_prepare_wire_decode(
  context : AccountConstructionContext,
  geometry : @source.JsonSourceGeometry,
) -> AccountConfigurationConstructionUnits raise AccountConstructionStop {
  let n = Int::max(1, geometry.node_upper).to_int64()
  let o = Int::max(0, geometry.objects).to_int64()
  let a = Int::max(0, geometry.arrays).to_int64()
  let f = Int::min(
    Int::max(0, geometry.fields),
    Int::max(1, geometry.node_upper),
  ).to_int64()
  // RawAccount/Entry/Box/Selector alternatives and their actual input-bound
  // array growth. No input-byte value occupies a node/record count position.
  let typed = @shape.collection_construction_extent({
    records: 2L + 3L * o + n,
    record_references: 3L + 8L * o + 2L * n,
    record_words: n,
    reference_arrays: a + o + 2L,
    reference_items: 4L * n + 4L * o,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap_or_else(() => raise AccountConstructionStop)
  let text = @canonical.nfc_lf_retained_output_units(
    geometry.quoted_raw_utf16_units.to_int64(),
  ).unwrap_or_else(() => raise AccountConstructionStop)
  let retained = account_construction_units(
    typed.record_headers,
    typed.reference_slots,
    typed.scalar_words,
    text,
  )
  let maps = @shape.map_construction_extent(o, f).unwrap_or_else(() => {
    raise AccountConstructionStop
  })
  let lookups = @shape.scale_collection_construction_extent(
    @decode.indexed_child_construction_extent(),
    8L * o + n + 4L,
  ).unwrap_or_else(() => raise AccountConstructionStop)
  let nfc = @canonical.nfc_lf_construction_scratch_extent(
    geometry.longest_quoted_raw_utf16,
  ).unwrap_or_else(() => raise AccountConstructionStop)
  let controls = account_construction_units(
    maps.record_headers + lookups.record_headers + nfc.record_headers + 16L,
    maps.reference_slots + lookups.reference_slots + nfc.reference_slots + 24L,
    maps.scalar_words + lookups.scalar_words + nfc.scalar_words + 24L,
    nfc.owned_utf16_units +
    4L * (7L * geometry.longest_quoted_raw_utf16.to_int64() + 100L),
  )
  account_prepare_construction(
    Some(context),
    account_construction_zero,
    account_construction_add(retained, controls),
  )
  retained
}

///|
// The canonical Account has the same closed tree shape as its wire. Count
// containers/fields/names separately from text, including failed from_json,
// normalization, exclusion sort and writer children. Overlap is separately
// observed from the decoded original before admission enters that algorithm.
fn account_prepare_admission(
  context : AccountConstructionContext,
  geometry : @source.JsonSourceGeometry,
  typed : AccountConfigurationConstructionUnits,
) -> Unit raise AccountConstructionStop {
  let n = Int::max(1, geometry.node_upper).to_int64()
  let o = Int::max(0, geometry.objects).to_int64()
  let a = Int::max(0, geometry.arrays).to_int64()
  let f = Int::max(0, geometry.fields).to_int64()
  let t = @canonical.nfc_lf_retained_output_units(
    geometry.quoted_raw_utf16_units.to_int64(),
  ).unwrap_or_else(() => raise AccountConstructionStop)
  // Coheld Json/CanonicalValue alternatives, Visit/Append/Next build frames,
  // canonical tuple/frozen-array wrappers, compiled/canonical entry tuples and
  // sort cursors. Two object maps are the document and normalization's seen
  // keys; their buckets/growth belong to the shared collection constructor.
  let collections = @shape.collection_construction_extent({
    records: 8L * n + 8L * o + 32L,
    record_references: 12L * n + 16L * o + 64L,
    record_words: 8L * n + 32L,
    reference_arrays: 6L * a + 8L * o + 16L,
    reference_items: 12L * n + 8L * f + 32L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 2L * o,
    map_entries: 2L * f,
  }).unwrap_or_else(() => raise AccountConstructionStop)
  // CompileEntry retains four DimSets per scope/exclusion, copied/sorted name
  // arrays and the final Account/CID. Typed source arrays remain coheld only
  // as execution scratch. Count occurrences even when the runtime shares them.
  let admitted = @shape.collection_construction_extent({
    records: 8L * o + n + 8L,
    record_references: 12L * o + 2L * n + 16L,
    record_words: 4L * o + 8L,
    reference_arrays: 6L * o + a + 2L,
    reference_items: 8L * o + 4L * n,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap_or_else(() => raise AccountConstructionStop)
  let retained = account_construction_units(
    admitted.record_headers + n + 1L,
    admitted.reference_slots,
    admitted.scalar_words,
    t + 71L,
  )
  let normalization = @canonical.nfc_lf_construction_scratch_extent(
    geometry.longest_quoted_raw_utf16,
  ).unwrap_or_else(() => raise AccountConstructionStop)
  // Every actual canonical exclusion output is bounded by this SAME forest's
  // names/keys and JSON punctuation. This is an output-byte bound only.
  let output = account_representation_limit(6L * t + 8L * n + 2L * f + 256L)
  let writer = @encode.text_writer_construction_inventory(
    output,
    Int::max(1, geometry.node_upper),
    CANONICAL_MAX_DEPTH,
  ).unwrap_or_else(() => raise AccountConstructionStop)
  let scratch = account_construction_units(
    collections.record_headers +
    normalization.record_headers +
    writer.record_headers +
    n,
    collections.reference_slots +
    normalization.reference_slots +
    writer.reference_slots,
    collections.scalar_words +
    normalization.scalar_words +
    writer.scalar_words +
    64L,
    // canonical normalized forest, coheld keyed exclusion texts, the previous
    // wire-order key, writer growth and the next NFC child's scratch.
    3L * t +
    2L * output.to_int64() +
    normalization.owned_utf16_units +
    writer.owned_utf16_units,
    wire=256L,
  )
  account_prepare_construction(
    Some(context),
    retained,
    account_construction_add(typed, account_construction_add(retained, scratch)),
  )
}

///|
fn account_selector_name_count(selector : Selector) -> Int64 {
  match selector {
    All => 0L
    AnyOf(values) => values.length().to_int64()
  }
}

///|
fn account_box_name_count(box : SelectorBox) -> Int64 {
  account_selector_name_count(box.principal) +
  account_selector_name_count(box.connection) +
  account_selector_name_count(box.resource) +
  account_selector_name_count(box.operation)
}

///|
// Observe the SAME decoded typed original without copying/sorting it. Equal
// outcomes skip the split algorithm entirely. In a differing pair, at most
// two original entries contribute exclusions and names to the live DFS stack.
fn account_prepare_overlap(
  context : AccountConstructionContext,
  raw : RawAccountConfiguration,
) -> Unit raise AccountConstructionStop {
  let mut outcome : ConfiguredOutcome? = None
  let mut mixed = false
  let mut max_exclusions = 0L
  let mut max_names = 0L
  for entry in raw.entries {
    match outcome {
      None => outcome = Some(entry.outcome)
      Some(first) => if first != entry.outcome { mixed = true }
    }
    let mut names = account_box_name_count(entry.scope)
    for exclusion in entry.exclusions {
      names += account_box_name_count(exclusion)
    }
    max_names = Int64::max(max_names, names)
    max_exclusions = Int64::max(
      max_exclusions,
      entry.exclusions.length().to_int64(),
    )
  }
  let frames = if mixed { 2L * max_exclusions + 1L } else { 1L }
  let names = if mixed { 2L * max_names + 1L } else { 1L }
  let slots = @counts.checked_nonnegative_add_product(0L, frames, names).unwrap_or_else(() => {
      raise AccountConstructionStop
    },
  )
  let items = @counts.checked_nonnegative_add_product(0L, slots, 16L).unwrap_or_else(() => {
      raise AccountConstructionStop
    },
  )
  let overlap = @shape.collection_construction_extent({
    records: 16L * frames,
    record_references: 32L * frames,
    record_words: 16L * frames,
    reference_arrays: 12L * frames,
    reference_items: items,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap_or_else(() => raise AccountConstructionStop)
  account_prepare_construction(
    Some(context),
    account_construction_zero,
    account_construction_units(
      overlap.record_headers + 16L,
      overlap.reference_slots + 32L,
      overlap.scalar_words + 32L,
      0L,
    ),
  )
}

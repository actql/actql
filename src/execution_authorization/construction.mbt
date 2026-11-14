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
) -> Unit raise AccountConstructionStop {
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
    retained,
    account_construction_add(retained, controls),
  )
}

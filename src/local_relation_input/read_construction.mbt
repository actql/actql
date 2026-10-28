///|
/// Original local declaration geometry. Field/array metadata and String length
/// are observed without running its semantic reader, admitting a carrier/key,
/// normalizing names or copying input bodies. Caller backs this metadata pass.
pub(all) struct ReadConstructionGeometry {
  body : @decode.SubtreeGeometry
  expected_names : Int
  key_fields : Int
  order_keys : Int
  max_name_utf16_units : Int
  inspection_work : Int64
} derive(Eq, Debug)

///|
fn local_name_array_geometry(at : @decode.Cursor) -> (Int, Int, Int64) {
  let count = @decode.array_length(at).unwrap_or(0)
  let mut largest = 0
  for i in 0..<count {
    let item = @decode.element_at(at, i).unwrap()
    if @decode.text(item) is Ok(name) {
      largest = Int::max(largest, name.length())
    }
  }
  (count, largest, 1L + 2L * count.to_int64())
}

///|
pub fn observe_read_construction_geometry(
  root : @decode.Cursor,
) -> ReadConstructionGeometry {
  let body = @contract.observe_read_construction_geometry(root)
  let width = @decode.object_length(root).unwrap_or(0)
  let mut work = body.work + 1L
  let mut expected_names = 0
  let mut key_fields = 0
  let mut order_keys = 0
  let mut max_name = body.max_selected_text_units
  for i in 0..<width {
    let (name, value) = @decode.field_at(root, i).unwrap()
    work += 2L
    if name == "expected_columns" || name == "primary_key" {
      let (count, largest, spent) = local_name_array_geometry(value)
      work += spent
      max_name = Int::max(max_name, largest)
      if name == "expected_columns" {
        expected_names = count
      } else {
        key_fields = count
      }
    } else if name == "duplicates" {
      // Borrow the exact selected original order path; malformed shapes still
      // belong to the original reader and cannot become a known refusal here.
      if @decode.object_length(value) is Some(fields) {
        for j in 0..<fields {
          let (key, child) = @decode.field_at(value, j).unwrap()
          work += 2L
          if key == "first_by_order" &&
            @decode.object_length(child) is Some(inner) {
            for k in 0..<inner {
              let (key, terms) = @decode.field_at(child, k).unwrap()
              work += 2L
              if key == "order_by" {
                order_keys = @decode.array_length(terms).unwrap_or(0)
              }
            }
          }
        }
      }
    }
  }
  {
    body,
    expected_names,
    key_fields,
    order_keys,
    max_name_utf16_units: max_name,
    inspection_work: work,
  }
}

///|
/// Existing local read's owned output and sequential constructor scratch.
/// peak scratch can coexist with the retained output; all Source/Contract text
/// stays original. This DATA is not a Checked declaration, budget or grant.
pub(all) struct ReadConstructionInventory {
  retained : @shape.CollectionConstructionExtent
  scratch : @shape.CollectionConstructionExtent
  scratch_utf16_units : Int64
} derive(Eq, Debug)

///|
pub fn read_construction_inventory(
  geometry : ReadConstructionGeometry,
) -> ReadConstructionInventory? {
  let g = geometry.body
  if geometry.expected_names < 0 ||
    geometry.key_fields < 0 ||
    geometry.order_keys < 0 ||
    geometry.max_name_utf16_units < 0 ||
    geometry.inspection_work < 0L {
    return None
  }
  guard @contract.read_construction_inventory(g) is Some(contracts) &&
    @carrier.unqualified_rows_construction_inventory(
      g.fields,
      geometry.max_name_utf16_units,
    )
    is Some(rows) &&
    @evidence.primary_key_read_construction_inventory(
      geometry.key_fields,
      geometry.max_name_utf16_units,
      g.outer_depth.to_int64() + 1L,
    )
    is Some(key) &&
    @order.read_construction_extent(
      g.max_fields,
      g.outer_depth.to_int64() + g.nodes.to_int64(),
    )
    is Some(order) &&
    @decode.closed_object_field_construction_extent(
      Some(g.max_fields),
      7,
      g.outer_depth.to_int64(),
    )
    is Some(view) &&
    @decode.issue_construction_extent(g.nodes) is Some(issue) else {
    return None
  }
  let n = g.nodes.to_int64()
  let f = g.fields.to_int64()
  let e = geometry.expected_names.to_int64()
  let k = geometry.order_keys.to_int64()
  let order_held = @order.read_retained_construction_extent()
  // Checked1H7R, Usage1H2W and Carrier wrapper1H1R1W. The original optional
  // classification/key/order wrappers3H3R3W are retained separately from their
  // borrowed values. expected and order Arrays own references, never text.
  let output = @shape.collection_construction_extent({
    records: 6L + k * order_held.record_headers,
    record_references: 11L + k * order_held.reference_slots,
    record_words: 6L + k * order_held.scalar_words,
    reference_arrays: 2L,
    reference_items: e + k,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let retained = @shape.add_collection_construction_extents(
    output,
    @shape.add_collection_construction_extents(
      contracts.retained,
      @shape.add_collection_construction_extents(rows.retained, key.retained).unwrap(),
    ).unwrap(),
  ).unwrap()
  let field = @decode.indexed_field_construction_extent()
  let utf8 = @scalar.utf8_length_admission_construction_units()
  let nfc = @canonical.nfc_lf_construction_extent(geometry.max_name_utf16_units).unwrap()
  // Original preflight has one (Cursor,depth) per node plus one active indexed
  // field family. names/schema input projections own their tuples and Arrays;
  // seen/metadata/name assembly maps are original loops. Body Strings borrow.
  // Fixed scalar/required/lookup/issue/result and view alternatives32H30R32W
  // are co-counted once, never per recursive validation call or character.
  let frame = @shape.collection_construction_extent({
    records: 3L * n +
    2L * f +
    32L +
    field.record_headers +
    utf8.0 +
    nfc.record_headers,
    record_references: 5L * n +
    4L * f +
    30L +
    field.reference_slots +
    utf8.1 +
    nfc.reference_slots,
    record_words: 3L * n +
    2L * f +
    32L +
    field.scalar_words +
    utf8.2 +
    nfc.scalar_words,
    reference_arrays: g.objects.to_int64() + 8L,
    reference_items: 3L * n + 3L * f + e + k + 10L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 3L,
    map_entries: 3L * f + e,
  }).unwrap()
  // These nested original constructors run sequentially. Co-counting their
  // bounds is conservative DATA; it does not schedule or preallocate all VM
  // heap. No field-level semantic ceiling or fallback reader is introduced.
  let mut scratch = frame
  for
    child in [contracts.scratch, rows.scratch, key.scratch, order, view, issue] {
    scratch = @shape.add_collection_construction_extents(scratch, child).unwrap()
  }
  Some({
    retained,
    scratch,
    scratch_utf16_units: contracts.scratch_utf16_units +
    rows.scratch_utf16_units +
    key.scratch_utf16_units +
    nfc.owned_utf16_units,
  })
}

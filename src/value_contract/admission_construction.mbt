///|
pub fn observe_read_construction_geometry(
  root : @decode.Cursor,
) -> @decode.SubtreeGeometry {
  @decode.observe_subtree_geometry(root, [
    read_contract_type_field, read_contract_resource_kind_field, read_contract_element_type_field,
  ])
}

///|
/// Original typed values coexist; traversal/maps/normalization are sequential
/// scratch. All source Strings/index/span backing stays borrowed. Shared units
/// are not byte tariffs, an allocation measurement, policy or admission grant.
pub(all) struct ReadConstructionInventory {
  retained : @shape.CollectionConstructionExtent
  scratch : @shape.CollectionConstructionExtent
  scratch_utf16_units : Int64
} derive(Eq, Debug)

///|
pub fn read_construction_inventory(
  g : @decode.SubtreeGeometry,
) -> ReadConstructionInventory? {
  if g.nodes < 1 ||
    g.objects < 0 ||
    g.arrays < 0 ||
    g.fields < 0 ||
    g.objects > g.nodes ||
    g.arrays > g.nodes - g.objects ||
    g.fields >= g.nodes ||
    g.max_fields < 0 ||
    g.max_fields > g.fields ||
    g.max_array_items < 0 ||
    g.max_array_items >= g.nodes ||
    g.max_selected_text_units < 0 ||
    g.outer_depth < 0 ||
    g.work < 0L {
    return None
  }
  let n = g.nodes.to_int64()
  let o = g.objects.to_int64()
  let a = g.arrays.to_int64()
  let f = g.fields.to_int64()
  let m = g.max_fields.to_int64()
  let path = n + g.outer_depth.to_int64()
  // Per typed node: Contract1H1R1W, composite Shape1H2R2W,
  // TextLimits1H4R, up to3 scalar-bound carriers3H3W or one media
  // String option1H1R. Components deliberately co-count those alternatives.
  // Fields1H1R1W per object, Field1H2R per original field, enum/Some2H2R
  // per array. Nested typed field/enum arrays remain owned, Strings borrowed.
  let retained = @shape.collection_construction_extent({
    records: 6L * n + o + f + 2L * a,
    record_references: 8L * n + o + 2L * f + 2L * a,
    record_words: 6L * n + o,
    reference_arrays: o + a,
    reference_items: n + f,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let type_keys = @shape.object_key_construction_counts(g.max_fields, 0, 6).unwrap()
  let name_keys = @shape.object_key_construction_counts(
    g.max_fields,
    0,
    g.max_fields,
  ).unwrap()
  let pairs = Int64::max(type_keys.pairs, name_keys.pairs)
  let maps = Int::max(type_keys.maps, name_keys.maps).to_int64()
  let entries = Int64::max(type_keys.map_entries, name_keys.map_entries)
  let pair_arrays = Int::max(type_keys.pair_arrays, name_keys.pair_arrays).to_int64()
  let child = @decode.indexed_child_construction_extent()
  // Pending Read/Build frames2N H4N R6N W, their Cursor N H2N RN W.
  // Pinned in-place sort has at most3 views,2 scalar tuples,1 Some per active
  // smaller partition:6N H4N R10N W is a conservative logical bound. It
  // constructs no copied field array. Error ancestry uses actual nodes+outer.
  // Fixed62H48R31W: budget1/0/4, views6/9/0, scalar-result8/0/8,
  // required-result19/19/0, enum/media8/5/5, return2/2/2, error7/8/4,
  // field-filter2/2/1, iterator2/1/2, UTF8-result6/2/5, sort closure1/0/0.
  let scratch = @shape.collection_construction_extent({
    records: 62L + 19L * child.record_headers + 9L * n + path + pairs,
    record_references: 48L +
    19L * child.reference_slots +
    10L * n +
    path +
    2L * pairs,
    record_words: 31L + 19L * child.scalar_words + 17L * n + path,
    reference_arrays: o + 7L + pair_arrays,
    reference_items: 4L * n +
    f +
    2L * m +
    g.outer_depth.to_int64() +
    10L +
    pairs,
    scalar_arrays: 1L,
    scalar_items: 15L,
    maps: 3L + maps,
    map_entries: 3L * m + entries,
  }).unwrap()
  let nfc = @canonical.nfc_lf_construction_extent(g.max_selected_text_units).unwrap()
  Some({
    retained,
    scratch: @shape.add_collection_construction_extents(scratch, {
      record_headers: nfc.record_headers,
      reference_slots: nfc.reference_slots,
      scalar_words: nfc.scalar_words,
    }).unwrap(),
    scratch_utf16_units: nfc.owned_utf16_units,
  })
}

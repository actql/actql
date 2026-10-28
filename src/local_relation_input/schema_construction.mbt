///|
/// Original check_schema overlap for one actual declaration/Snapshot pair.
/// Counts come from their original owned source occurrences, not max_nodes or
/// a policy ceiling. The semantic reader still performs every original check.
pub fn schema_agreement_construction_inventory(
  declaration : ReadConstructionGeometry,
  schema_nodes : Int,
  schema_fields : Int,
) -> ReadConstructionInventory? {
  let g = declaration.body
  if schema_nodes < 0 ||
    schema_fields < 0 ||
    schema_fields > schema_nodes ||
    g.nodes < 1 ||
    schema_nodes > 2147483647 - g.nodes {
    return None
  }
  let nodes = schema_nodes + g.nodes
  guard @contract.relation_construction_inventory(nodes) is Some(comparison) &&
    @carrier.typed_rows_construction_inventory(schema_fields) is Some(rows) &&
    @evidence.primary_key_read_construction_inventory(
      declaration.key_fields,
      declaration.max_name_utf16_units,
      g.outer_depth.to_int64() + 1L,
    )
    is Some(key) else {
    return None
  }
  // SchemaAgreement1H5R, Usage1H2W, Relation Carrier1H1R1W and keySome1H1R1W.
  // Original declaration/schema are borrowed; their independently admitted
  // bodies remain at their old owners. Only key/row wrappers are constructed.
  let output : @shape.CollectionConstructionExtent = {
    record_headers: 4L,
    reference_slots: 7L,
    scalar_words: 4L,
  }
  let retained = @shape.add_collection_construction_extents(
    output,
    @shape.add_collection_construction_extents(rows.retained, key.retained).unwrap(),
  ).unwrap()
  let n = nodes.to_int64()
  let utf8 = @scalar.utf8_length_admission_construction_units()
  // The original sequential type_scan owns explicit (Contract,depth) work.
  // Budget1H3W; actual/expected Some2H2R2W; current field+lookup families
  //8H10R8W; five payload failure/return alternatives5H5R5W; key-field Some,
  // stack-pop Some and contract-field Some3H3R3W; iteration3H2R3W and the
  // original relation_rows Some1H1R1W total23H23R25W. Comparison helpers
  // remain in their existing owner's inventory; no VM frames are added.
  let scan = @shape.collection_construction_extent({
    records: n + 23L + utf8.0,
    record_references: n + 23L + utf8.1,
    record_words: n + 25L + utf8.2,
    reference_arrays: 1L,
    reference_items: n,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let mut scratch = scan
  for original in [comparison.scratch, rows.scratch, key.scratch] {
    scratch = @shape.add_collection_construction_extents(scratch, original).unwrap()
  }
  Some({ retained, scratch, scratch_utf16_units: key.scratch_utf16_units, })
}

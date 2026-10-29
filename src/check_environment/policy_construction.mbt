///|
pub(all) struct DataPolicyConstructionGeometry {
  envelopes : Int
  policies : Int
  references : Int
  policy_references : Int
} derive(Eq, Debug)

///|
/// Only original registry kind and admitted reference-role DATA. No policy
/// body parse or permission is performed by this measurement.
pub fn observe_data_policy_construction_geometry(
  references : CatalogReferences,
) -> DataPolicyConstructionGeometry {
  let mut policies = 0
  let mut linked = 0
  for envelope in references.contents.registry.entries {
    if envelope.kind == "data_policy" {
      policies += 1
    }
  }
  for reference in references.references {
    if reference.contract.kind == "data_policy" {
      linked += 1
    }
  }
  {
    envelopes: references.contents.registry.entries.length(),
    policies,
    references: references.references.length(),
    policy_references: linked,
  }
}

///|
fn data_policy_geometry_valid(g : DataPolicyConstructionGeometry) -> Bool {
  g.envelopes >= 0 &&
  g.policies >= 0 &&
  g.policies <= g.envelopes &&
  g.references >= 0 &&
  g.policy_references >= 0 &&
  g.policy_references <= g.references &&
  (g.policies > 0 || g.policy_references == 0)
}

///|
/// Original policy bodies must have exactly three fields BEFORE any field
/// map is allocated. Their Strings/cursors are borrowed; even unused policies
/// and repeated output ownership remain counted. Classification is DATA, not
/// effective Host policy or publisher authorization.
pub fn data_policy_construction_extent(
  g : DataPolicyConstructionGeometry,
) -> RegistryConstructionExtent? {
  if !data_policy_geometry_valid(g) {
    return None
  }
  let p = g.policies.to_int64()
  let v = g.policy_references.to_int64()
  let counts : @shape.CollectionConstructionInventory = if g.policies == 0 {
    {
      records: 4L,
      record_references: 6L,
      record_words: 2L,
      reference_arrays: 1L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 2L,
      map_entries: 0L,
    }
  } else {
    let child = @decode.indexed_child_construction_extent()
    let field = @decode.indexed_field_construction_extent()
    // Root+work cell2H4R2W; retained policy1H2R1W and output-owner1H2R.
    // Three original lookup sites + shared field accessor; required/text return
    // carriers6H6R, ObjectView/result2H3R, tuple/Some2H4R, length1H1W,
    // Map lookup1H1R and bounded depth4 error family13H13R13W.
    {
      records: 27L + 3L * child.record_headers + field.record_headers + p + v,
      record_references: 31L +
      3L * child.reference_slots +
      field.reference_slots +
      2L * p +
      2L * v,
      record_words: 16L + 3L * child.scalar_words + field.scalar_words + p,
      reference_arrays: 2L,
      reference_items: p + 4L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 3L,
      map_entries: p + v + 3L,
    }
  }
  let x = @shape.collection_construction_extent(counts).unwrap()
  Some({
    record_headers: x.record_headers,
    reference_slots: x.reference_slots,
    scalar_words: x.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
pub fn data_policy_retained_extent(
  g : DataPolicyConstructionGeometry,
) -> RegistryConstructionExtent? {
  if !data_policy_geometry_valid(g) {
    return None
  }
  let p = g.policies.to_int64()
  let v = g.policy_references.to_int64()
  let x = @shape.collection_construction_extent({
    records: 1L + p + v,
    record_references: 4L + 2L * p + 2L * v,
    record_words: 1L + p,
    reference_arrays: 1L,
    reference_items: p,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 2L,
    map_entries: p + v,
  }).unwrap()
  Some({
    record_headers: x.record_headers,
    reference_slots: x.reference_slots,
    scalar_words: x.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
pub fn data_policy_construction_observation_work(
  references : CatalogReferences,
) -> Int64 {
  2L +
  references.contents.registry.entries.length().to_int64() +
  references.references.length().to_int64()
}

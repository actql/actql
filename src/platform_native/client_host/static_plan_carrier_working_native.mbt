///|
// Construction DATA only. The caller backs the scalar scan and these quote
// controls before calling this helper. The returned tuple is not admission.
// No output escapes measurement; its writers, cursors, and copied Graph arrays
// coexist with the outer plan measurement until the original call returns.
fn native_static_plan_carrier_measurement_working(
  data : @host.ClientCarrierMeasurementConstruction,
) -> (Int64, Int64, Int64)? {
  guard @host.client_carrier_measurement_variable_layout(data) is Some(variable) else {
    return None
  }
  let operation = @encode.measurement_operation_construction_extent()
  let mut collections = @shape.add_collection_construction_extents(
    variable.collections,
    operation.collections,
  ).unwrap()
  let mut references = 12L + 3L * variable.reference_array_items
  if variable.presence_fields is Some(_) {
    let presence = @execution.relation_schema_measurement_control_extent()
    collections = @shape.add_collection_construction_extents(
      collections,
      presence.collections,
    ).unwrap()
    references = Int64::max(references, presence.reference_array_slots)
  }
  let mut units : @execution.PreparationRepresentationUnits = {
    record_headers: collections.record_headers,
    reference_slots: collections.reference_slots,
    scalar_words: collections.scalar_words,
    owned_utf16_units: variable.owned_utf16_units + operation.owned_utf16_units,
    owned_wire_bytes: 0L,
  }
  if data.graph_branch {
    guard @local.client_static_plan_array_sort_layout(data.graph_nodes)
      is Some(nodes) &&
      @local.client_static_plan_array_sort_layout(data.graph_edges)
      is Some(edges) &&
      @execution.compose_preparation_representation([units, nodes, edges])
      is Some(combined) else {
      return None
    }
    units = combined
  }
  guard @execution.preparation_representation_cost(units) is Some(execution) &&
    @local.client_static_plan_map_bucket_slots(data.value_nodes)
    is Some(buckets) &&
    native_static_plan_variable_raw(
      Int64::max(variable.string_utf16_units, operation.max_string_utf16_units),
      0L,
      0L,
      references,
      buckets,
      0L,
    )
    is Some(variable_raw) else {
    return None
  }
  let (header, _, _, _, pointer) = @bootstrap.native_managed_value_layout()
  // Presence preparation has 8 reference fields and 11 scalar words. Sort
  // continuation has 8 reference slots and 15 scalar slots. Writer/checked
  // emission/operation records are smaller; count each scalar at native Int64
  // width so this endpoint also covers mixed Int/Int64 records.
  let record_raw = header + 8L * pointer + 15L * 8L
  Some((0L, execution, Int64::max(variable_raw, record_raw)))
}

///|
// Unlike logical_map/plan_view, a Carrier port identity is NOT parsed/sealed
// through RunEvidence validation. Object/Record and Graph hash their original
// checked typed body. Presence also constructs an identity wire and names.
// Compose those original constructors; never substitute a zero validator into
// the unrelated generic artifact codec. The complete byte geometry was already
// measured under the same original Read before this quote is consumed.
fn native_static_plan_carrier_codec_layout(
  data : @host.ClientCarrierMeasurementConstruction,
  geometry : (Int, Int, Int),
) -> @local.ClientStaticPlanCodecLayout? {
  let (bytes, nodes, depth) = geometry
  if bytes < 1 || nodes < 1 || depth < 0 {
    return None
  }
  guard @host.client_carrier_measurement_variable_layout(data) is Some(variable) &&
    @encode.hash_writer_construction_inventory(nodes, depth) is Some(hash) else {
    return None
  }
  // The shared measuring writer contribution is deliberately kept alongside
  // the hash writer. It is an explicit named sequential constructor overcount,
  // not a multiplier or a policy-derived grant.
  let operation = @encode.measurement_operation_construction_extent()
  let mut scratch : @execution.PreparationRepresentationUnits = {
    record_headers: variable.collections.record_headers +
    hash.record_headers +
    operation.collections.record_headers,
    reference_slots: variable.collections.reference_slots +
    hash.reference_slots +
    operation.collections.reference_slots,
    scalar_words: variable.collections.scalar_words +
    hash.scalar_words +
    operation.collections.scalar_words,
    owned_utf16_units: variable.owned_utf16_units +
    hash.owned_utf16_units +
    operation.owned_utf16_units,
    owned_wire_bytes: hash.owned_wire_bytes,
  }
  let mut string_units = Int64::max(71L, variable.string_utf16_units)
  let mut builder_units = 0L
  let mut refs = 12L + 3L * variable.reference_array_items
  if data.presence_fields is Some(fields) {
    guard fields >= 0 &&
      @encode.text_writer_construction_inventory(bytes, nodes, depth)
      is Some(text) &&
      @shape.collection_construction_extent({
        // RelationSchemaIdentity(3R3W), hash/wire finalization Option and
        // identity Result/Option wrappers, and the appended name Strings.
        records: 5L + data.reference_name_headers,
        record_references: 7L,
        record_words: 3L,
        reference_arrays: 1L,
        reference_items: fields.to_int64(),
        scalar_arrays: 0L,
        scalar_items: 0L,
        maps: 0L,
        map_entries: 0L,
      })
      is Some(names) else {
      return None
    }
    let presence = @execution.relation_schema_measurement_control_extent()
    guard @execution.compose_preparation_representation([
        scratch,
        {
          record_headers: text.record_headers +
          presence.collections.record_headers +
          names.record_headers,
          reference_slots: text.reference_slots +
          presence.collections.reference_slots +
          names.reference_slots,
          scalar_words: text.scalar_words +
          presence.collections.scalar_words +
          names.scalar_words,
          owned_utf16_units: text.owned_utf16_units + data.reference_name_utf16,
          owned_wire_bytes: 0L,
        },
      ])
      is Some(combined) else {
      return None
    }
    scratch = combined
    string_units = Int64::max(string_units, bytes.to_int64())
    builder_units = bytes.to_int64()
    refs = Int64::max(refs, 12L + 3L * fields.to_int64())
  }
  if data.graph_branch {
    guard @local.client_static_plan_array_sort_layout(data.graph_nodes)
      is Some(node_sort) &&
      @local.client_static_plan_array_sort_layout(data.graph_edges)
      is Some(edge_sort) &&
      @execution.compose_preparation_representation([
        scratch, node_sort, edge_sort,
      ])
      is Some(combined) else {
      return None
    }
    scratch = combined
  }
  guard @local.client_static_plan_map_bucket_slots(nodes) is Some(buckets) else {
    return None
  }
  Some({
    // Only the returned pair and complete CID escape client_task_carrier_contract.
    retained: {
      record_headers: 2L,
      reference_slots: 2L,
      scalar_words: 0L,
      owned_utf16_units: 71L,
      owned_wire_bytes: 0L,
    },
    scratch,
    string_utf16_units: string_units,
    builder_utf16_bound: builder_units,
    wire_bytes: hash.owned_wire_bytes,
    reference_array_slots: refs,
    scalar_array_items: 64L,
    map_bucket_slots: buckets,
  })
}

///|
pub(all) enum RelationSamplePrefixIssue {
  Unavailable
  NotCellRepresentation
  InvalidLimits
  InvalidLayout
  Schema(RelationSchemaIdentityIssue)
  Encoding(@encode.EncodeFailure)
}

///|
/// Constructor peak while the original schema identity and prefix coexist.
/// The calling Run owner separately retains the input pin and commit record.
pub fn completed_relation_sample_prefix_construction_bytes(
  schema : RelationSchemaIdentityLimits,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Int64? {
  guard schema.max_fields >= 0 &&
    @encode.text_writer_construction_inventory(
      schema.max_bytes,
      schema.max_nodes,
      schema.max_depth,
    )
    is Some(schema_text) &&
    @encode.hash_writer_construction_inventory(
      schema.max_nodes,
      schema.max_depth,
    )
    is Some(schema_hash) &&
    @contract.checked_emission_construction_extent(schema.max_nodes)
    is Some(contract) &&
    @encode.text_writer_construction_inventory(max_bytes, max_nodes, max_depth)
    is Some(prefix) else {
    return None
  }
  let fields = schema.max_fields.to_int64()
  // One typed or canonical reference cursor, including the old/new backing
  // during growth. Each open ancestor retains a continuation; double the
  // combined depth for child/key overlap, then allow three backing arrays.
  let slots = 3L * (2L * max_depth.to_int64() + 8L)
  // Schema receipt/control and two arrays, original field/name observations,
  // one (contract CID, required) record per field, the document/result, value
  // and decimal-cursor scratch, plus one co-held column hash and emitter.
  preparation_representation_cost({
    record_headers: schema_text.record_headers +
    2L * schema_hash.record_headers +
    2L * contract.record_headers +
    prefix.record_headers +
    80L +
    5L * fields +
    2L * slots,
    reference_slots: schema_text.reference_slots +
    2L * schema_hash.reference_slots +
    2L * contract.reference_slots +
    prefix.reference_slots +
    70L +
    8L * fields +
    5L * slots,
    scalar_words: schema_text.scalar_words +
    2L * schema_hash.scalar_words +
    2L * contract.scalar_words +
    prefix.scalar_words +
    90L +
    3L * fields +
    5L * slots,
    // Qualified original names and retained CIDs, plus a largest decimal
    // spelling and its old/new UTF-16 builder overlap.
    owned_utf16_units: schema_text.owned_utf16_units +
    2L * schema_hash.owned_utf16_units +
    prefix.owned_utf16_units +
    4L * schema.max_bytes.to_int64() +
    71L * fields +
    1024L,
    owned_wire_bytes: 2L * schema_hash.owned_wire_bytes,
  })
}

///|
fn emit_relation_sample_value(
  value : Value,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  if value is Captured(captured) {
    let cursor = @admitted.start_wire_emit(captured, writer)
    while true {
      @encode.construction_work_step(writer, 1)
      if @admitted.advance_wire_emit(cursor) {
        break
      }
    }
  } else {
    emit_runtime_value(value, writer)
  }
}

///|
// Checked object and enumeration frames yield one sibling per level. The
// ordered schema writer adds no unordered key entries. Bound the active
// stack independently of the total number of fields or schema wire bytes.
fn relation_sample_schema_measurement_frames(depth : Int) -> Int? {
  if depth < 1 || depth > (2147483647 - 32) / 12 {
    None
  } else {
    Some(12 * depth + 32)
  }
}

///|
/// Cost of measuring the original schema before constructing the prefix.
/// Neither the measured Schema identity nor any row data is allocated here.
pub fn completed_relation_sample_schema_measurement_bytes(
  depth : Int,
) -> Int64? {
  guard relation_sample_schema_measurement_frames(depth) is Some(frames) &&
    @encode.measuring_writer_construction_extent(0, depth) is Some(writer) &&
    @contract.checked_emission_construction_extent(frames) is Some(emitter) else {
    return None
  }
  let codec = relation_schema_measurement_control_extent()
  let operation = @encode.measurement_operation_construction_extent()
  preparation_representation_cost({
    record_headers: writer.record_headers +
    emitter.record_headers +
    codec.collections.record_headers +
    operation.collections.record_headers +
    27L,
    reference_slots: writer.reference_slots +
    emitter.reference_slots +
    codec.collections.reference_slots +
    operation.collections.reference_slots +
    53L,
    scalar_words: writer.scalar_words +
    emitter.scalar_words +
    codec.collections.scalar_words +
    operation.collections.scalar_words +
    41L,
    owned_utf16_units: operation.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
/// Measure exactly the checked schema of the live completed output. The
/// selected validation ceilings and schema bytes remain the original ones.
pub fn measure_completed_relation_sample_schema(
  output : CompletedOutput,
  limits : RelationSchemaIdentityLimits,
  work : (Int) -> Bool,
) -> Result[RelationSchemaIdentityLimits, RelationSamplePrefixIssue] {
  guard completed_output_available(output) && output.table is Some(_) else {
    return Err(Unavailable)
  }
  guard relation_sample_schema_measurement_frames(limits.max_depth)
    is Some(frames) else {
    return Err(InvalidLimits)
  }
  let schema = completed_output_relation_schema(output)
  measure_relation_schema_identity_with_frames(
    schema,
    limits,
    frames,
    work=Some(work),
  )
  .map_err(issue => RelationSamplePrefixIssue::Schema(issue))
  .map(geometry => {
    max_fields: @schema.field_count(schema),
    max_bytes: geometry.0,
    max_nodes: geometry.1,
    max_depth: geometry.2,
  })
}

///|
/// Project a bounded prefix in the admitted material's stored row and column
/// order. The caller funds schema, writer, document and their coexistence
/// before entry and retains the original output pin through consumption.
/// The result is private DATA until that owner admits the durable adoption.
pub fn encode_completed_relation_sample_prefix(
  output : CompletedOutput,
  max_items : Int,
  schema_limits : RelationSchemaIdentityLimits,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  work : (Int) -> Bool,
  original_current? : () -> Bool = () => true,
) -> Result[(@encode.EncodedDocument, Int, Int), RelationSamplePrefixIssue] {
  if max_items < 1 || max_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(InvalidLimits)
  }
  if !completed_output_available(output) || !original_current() {
    return Err(Unavailable)
  }
  guard output.table is Some(table) else { return Err(NotCellRepresentation) }
  let total = IndexedRows::row_count(table)
  let items = Int::min(total, max_items)
  let names = RelationRows::field_names(table)
  let schema = completed_output_relation_schema(output)
  guard names.length() == IndexedRows::column_count(table) &&
    names.length() == @schema.field_count(schema) else {
    return Err(InvalidLayout)
  }
  let schema_cid = match
    identify_relation_sample_schema_cid(schema, schema_limits, work) {
    Ok(value) => value
    Err(issue) => return Err(Schema(issue))
  }
  // Same continuation bound used by the retained Relation schema writer.
  let frames = Int64::min(
    2147483647L,
    2L * schema_limits.max_nodes.to_int64() + 8L,
  ).to_int()
  let document = try {
    let writer = @encode.work_writer(max_bytes, max_nodes, max_depth, work)
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "columns")
    @encode.begin_array(writer)
    let contracts : Array[(String, Bool)] = Array(capacity=names.length())
    // Each lookup compares at most one exact field per halving of the
    // admitted width, then verifies equality with the borrowed spelling.
    let mut probes = 2L
    let mut width = names.length()
    while width > 0 {
      @encode.construction_work_step(writer, 1)
      width = width / 2
      probes += 1L
    }
    for index, name in names {
      let units = probes * (1L + name.length().to_int64())
      if units > 2147483647L {
        return Err(InvalidLimits)
      }
      @encode.construction_work_step(writer, units.to_int())
      guard @schema.lookup_reference(schema, name) is Some(field) else {
        return Err(InvalidLayout)
      }
      let hash = @encode.work_hashing_writer(
        schema_limits.max_bytes,
        schema_limits.max_nodes,
        schema_limits.max_depth,
        work,
      )
      let emitter = @contract.start_checked_emission(
        field.contract,
        hash,
        frames,
      )
      while !@contract.advance_checked_emission(emitter) {
        ()
      }
      let contract = "sha256:" + @encode.finish_hash(hash)
      let required = field.presence == @schema.Required
      contracts.push((contract, required))
      @encode.begin_ordered_object(writer)
      @encode.ordered_key(writer, "name")
      @encode.string_value(writer, name)
      @encode.ordered_key(writer, "position")
      @encode.number_value(writer, index.to_double())
      @encode.ordered_key(writer, "required")
      @encode.bool_value(writer, required)
      @encode.ordered_key(writer, "value_contract_cid")
      @encode.string_value(writer, contract)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.ordered_key(writer, "kind")
    @encode.string_value(writer, "relation")
    @encode.ordered_key(writer, "ordering_evidence_cid")
    @encode.null_value(writer)
    @encode.ordered_key(writer, "rows")
    @encode.begin_array(writer)
    for row in 0..<items {
      @encode.construction_work_step(writer, 1)
      if IndexedRows::row_width(table, row) != contracts.length() {
        return Err(InvalidLayout)
      }
      @encode.begin_array(writer)
      for column, entry in contracts {
        @encode.construction_work_step(writer, 1)
        let (contract, required) = entry
        let present = IndexedRows::cell_present(table, row, column)
        if required && !present {
          return Err(InvalidLayout)
        }
        @encode.begin_ordered_object(writer)
        @encode.ordered_key(writer, "presence")
        if present {
          @encode.string_value(writer, "present")
          @encode.ordered_key(writer, "value")
          emit_relation_sample_value(
            IndexedRows::read_cell(table, row, column),
            writer,
          )
          @encode.ordered_key(writer, "value_contract_cid")
          @encode.string_value(writer, contract)
        } else {
          @encode.string_value(writer, "absent")
        }
        @encode.end_object(writer)
      }
      @encode.end_array(writer)
    }
    @encode.end_array(writer)
    @encode.ordered_key(writer, "schema_cid")
    @encode.string_value(writer, schema_cid)
    @encode.ordered_key(writer, "version")
    @encode.string_value(writer, "actql-sample-relation/0.1")
    @encode.end_object(writer)
    @encode.finish_document(writer)
  } catch {
    issue => return Err(Encoding(issue))
  }
  if completed_output_available(output) && original_current() {
    Ok((document, items, total))
  } else {
    Err(Unavailable)
  }
}

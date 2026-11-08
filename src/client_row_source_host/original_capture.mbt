///|
/// Private original-input facts under the existing Source capture/Store
/// custody. No Source observation, authority or physical owner is issued here.
struct RowOriginalCaptureExport {
  schema_cid : String
  rows_cid : String
  rows : Array[String]
}

///|
/// Private backing of the existing receiving Source allocation. This has no
/// Ledger, Source observation or independent physical lifetime.
struct RowRestoredOriginalInput {
  input : @execution.AdmittedInput
  read : @execution.SuppliedRelationRead
  live : Ref[Bool]
}

///|
/// Eight bounded wire/text representations, admitted/decode tree slots and
/// schema/control slots. Transient parse/hash representations need four more
/// wires. These conservative logical slots are not an allocator/RSS bound.
pub fn row_original_input_capacity() -> (Int64, Int64) {
  let retained = 2000000L * 8L + 100000L * 64L + 4096L
  (retained, retained + 2000000L * 4L)
}

///|
pub fn restored_row_original_read(
  value : RowRestoredOriginalInput,
) -> @execution.SuppliedRelationRead? {
  if value.live.val && @execution.supplied_relation_read_available(value.read) {
    Some(value.read)
  } else {
    None
  }
}

///|
/// Invalidate readers before sliced reclamation of only this receiving buffer.
/// Existing Source cleanup keeps its allocation until this reports completion.
pub fn close_restored_row_original_input(
  value : RowRestoredOriginalInput,
  quantum : Int,
) -> Bool {
  value.live.val = false
  @execution.reclaim_admitted_input(value.input, quantum)
}

///|
/// No imported read escaped on these failures. Reclaim the bounded receiving
/// buffer before its caller can settle the existing Source reservation.
fn discard_failed_original_input(input : @execution.AdmittedInput) -> Unit {
  while !@execution.reclaim_admitted_input(input, 64) {

  }
}

///|
pub(all) enum RowOriginalCaptureIssue {
  Unavailable
  InvalidBinding
  Schema(@execution.RelationSchemaIdentityIssue)
  Wire(@execution.RowWireIssue)
  Admission(RowSourceIssue)
}

///|
fn original_capture_wire_limits() -> @execution.RowWireLimits {
  {
    max_columns: 100,
    max_order_work: 10000,
    max_bytes: 2000000,
    max_nodes: 100000,
    max_depth: 64,
  }
}

///|
// The checked Query owner supplies the INPUT schema, never the capture port.
fn original_query_input_schema(
  requirement : @planning.QueryRequirement,
) -> @schema.Schema? {
  let query = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  @lower.preparation_input_schema(
    @lower.bound_preparation(@query.query_sequence_owner(query)),
    @query.query_receipt_input_index(query),
  )
}

///|
/// Same existing receiver allocation, including original checked INPUT metadata.
/// Shared representation units add no physical quota or execution permission.
pub fn row_original_input_query_capacity(
  requirement : @planning.QueryRequirement,
) -> (Int64, Int64)? {
  guard original_query_input_schema(requirement) is Some(schema) &&
    row_schema_measurement_capacity(schema) is Some((workspace, retained)) else {
    return None
  }
  let (base_retained, base_execution) = row_original_input_capacity()
  guard @execution.checked_preparation_add_product(base_retained, retained, 1L)
    is Some(retained) &&
    @execution.checked_preparation_add_product(base_execution, workspace, 1L)
    is Some(execution) &&
    @execution.checked_preparation_add_product(
      execution,
      retained - base_retained,
      1L,
    )
    is Some(execution) else {
    return None
  }
  Some((retained, execution))
}

///|
/// Export only the SAME checked Query's live original input binding. Legacy
/// generic export policy remains separate; equal schema DATA is not a binding.
pub fn export_query_row_original_read(
  read : @execution.SuppliedRelationRead,
  requirement : @planning.QueryRequirement,
) -> Result[RowOriginalCaptureExport, RowOriginalCaptureIssue] {
  let query = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  guard @execution.supplied_relation_read_matches_input(
      read,
      @query.query_sequence_owner(query),
      @query.query_receipt_input_index(query),
    ) &&
    original_query_input_schema(requirement) is Some(schema) else {
    return Err(InvalidBinding)
  }
  let columns = @schema.field_count(schema)
  export_original_read_with_limits(
    read,
    100,
    { ..original_capture_wire_limits(), max_columns: columns, },
    { ..original_capture_schema_limits(), max_fields: columns, },
  )
}

///|
pub fn export_row_original_read(
  read : @execution.SuppliedRelationRead,
) -> Result[RowOriginalCaptureExport, RowOriginalCaptureIssue] {
  export_original_read_with_limits(
    read,
    100,
    original_capture_wire_limits(),
    original_capture_schema_limits(),
  )
}

///|
fn export_original_read_with_limits(
  read : @execution.SuppliedRelationRead,
  max_rows : Int,
  wire : @execution.RowWireLimits,
  schema_limits : @execution.RelationSchemaIdentityLimits,
) -> Result[RowOriginalCaptureExport, RowOriginalCaptureIssue] {
  if !@execution.supplied_relation_read_available(read) ||
    @execution.supplied_relation_read_row_count(read) > max_rows {
    return Err(Unavailable)
  }
  let schema = @execution.supplied_relation_read_schema(read)
  let identity = match
    @execution.identify_relation_schema(schema, schema_limits) {
    Ok(value) => value
    Err(issue) => return Err(Schema(issue))
  }
  let rows_identity = match
    @execution.supplied_relation_read_rows_identity(read, wire) {
    Ok(value) => value
    Err(issue) => return Err(Wire(issue))
  }
  let rows : Array[String] = []
  for row in 0..<@execution.supplied_relation_read_row_count(read) {
    match @execution.supplied_relation_read_row_wire(read, row, wire) {
      Ok(wire) => rows.push(wire)
      Err(issue) => return Err(Wire(issue))
    }
  }
  if !@execution.supplied_relation_read_available(read) {
    return Err(Unavailable)
  }
  Ok({
    schema_cid: @execution.relation_schema_cid(identity),
    rows_cid: @execution.row_wire_cid(rows_identity),
    rows,
  })
}

///|
pub fn row_original_capture_export_facts(
  value : RowOriginalCaptureExport,
) -> (String, String, Array[String]) {
  (value.schema_cid, value.rows_cid, value.rows.copy())
}

///|
/// Host authenticates the original Run/occurrence record and owns the existing
/// receiving allocation before calling this. This restores typed input only;
/// the separately verified capture still owns Source evidence and completion.
pub fn restore_row_original_read(
  requirement : @planning.QueryRequirement,
  schema_cid : String,
  rows_cid : String,
  rows : Array[String],
  available : () -> Bool,
  reference_issuer? : @admitted.ReferenceIssuer,
) -> Result[RowRestoredOriginalInput, RowOriginalCaptureIssue] {
  let query = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  guard original_query_input_schema(requirement) is Some(schema) else {
    return Err(InvalidBinding)
  }
  let columns = @schema.field_count(schema)
  restore_original_read_with_limits(
    @query.query_sequence_owner(query),
    @query.query_receipt_input_index(query),
    schema_cid,
    rows_cid,
    rows,
    100,
    {
      max_nodes: 100000,
      max_text_bytes: 2000000,
      max_depth: 64,
      max_work: 20000000,
    },
    { ..original_capture_wire_limits(), max_columns: columns, },
    { ..original_capture_schema_limits(), max_fields: columns, },
    available,
    reference_issuer?,
  )
}

///|
fn original_capture_schema_limits() -> @execution.RelationSchemaIdentityLimits {
  { max_fields: 100, max_bytes: 100000, max_nodes: 10000, max_depth: 64, }
}

///|
fn restore_original_read_with_limits(
  owner : @lower.BoundPrepared,
  input_index : Int,
  schema_cid : String,
  rows_cid : String,
  rows : Array[String],
  max_rows : Int,
  retention : @execution.ValueLimits,
  wire_limits : @execution.RowWireLimits,
  schema_limits : @execution.RelationSchemaIdentityLimits,
  available : () -> Bool,
  reference_issuer? : @admitted.ReferenceIssuer,
) -> Result[RowRestoredOriginalInput, RowOriginalCaptureIssue] {
  if rows.length() > max_rows || !available() {
    return Err(Unavailable)
  }
  guard @lower.preparation_input_schema(
      @lower.bound_preparation(owner),
      input_index,
    )
    is Some(schema) else {
    return Err(InvalidBinding)
  }
  let identity = match
    @execution.identify_relation_schema(schema, schema_limits) {
    Ok(value) => value
    Err(issue) => return Err(Schema(issue))
  }
  if @execution.relation_schema_cid(identity) != schema_cid {
    return Err(InvalidBinding)
  }
  let input = match
    @execution.prepare_bounded_admitted_input(
      owner, input_index, max_rows, retention,
    ) {
    Ok(input) => input
    Err(issue) => return Err(Admission(Capture(issue)))
  }
  let declared_fields = @execution.relation_schema_field_names(identity)
  let references : (@admitted.ReferenceIssuer, @admitted.ReferenceLimits)? = reference_issuer.map(issuer => {
      (
        issuer,
        {
          max_bytes: wire_limits.max_bytes,
          max_nodes: wire_limits.max_nodes,
          max_depth: wire_limits.max_depth,
          max_text_units: wire_limits.max_bytes,
        },
      )
    },
  )
  let mut remaining = wire_limits.max_bytes
  for wire in rows {
    if !available() {
      discard_failed_original_input(input)
      return Err(Unavailable)
    }
    // Bound the aggregate input before parsing, not only each individual row.
    if wire.length() > remaining {
      discard_failed_original_input(input)
      return Err(InvalidBinding)
    }
    let bytes = @utf8.encode(wire).length()
    if bytes > remaining {
      discard_failed_original_input(input)
      return Err(InvalidBinding)
    }
    remaining -= bytes
    guard @source.parse_json(wire, {
        max_input_bytes: wire_limits.max_bytes,
        max_nodes: wire_limits.max_nodes,
        max_depth: wire_limits.max_depth,
      })
      is Ok(node) &&
      @decode.admit(node, {
        max_nodes: wire_limits.max_nodes,
        max_depth: wire_limits.max_depth,
        max_string_bytes: wire_limits.max_bytes,
        max_total_string_bytes: wire_limits.max_bytes,
      })
      is Ok(cursor) else {
      discard_failed_original_input(input)
      return Err(InvalidBinding)
    }
    match
      append_row_source_object(
        input,
        schema,
        declared_fields,
        cursor,
        {
          max_nodes: wire_limits.max_nodes,
          max_depth: wire_limits.max_depth,
          max_text_bytes: wire_limits.max_bytes,
        },
        retention,
        references~,
      ) {
      Ok(_) => ()
      Err(issue) => {
        discard_failed_original_input(input)
        return Err(Admission(issue))
      }
    }
  }
  let captured = match @execution.finish_admitted_input(input) {
    Ok(value) => value
    Err(issue) => {
      discard_failed_original_input(input)
      return Err(Admission(Capture(issue)))
    }
  }
  let actual = match @execution.identify_captured_rows(captured, wire_limits) {
    Ok(value) => value
    Err(issue) => {
      discard_failed_original_input(input)
      return Err(Wire(issue))
    }
  }
  if !available() || @execution.row_wire_cid(actual) != rows_cid {
    discard_failed_original_input(input)
    return Err(InvalidBinding)
  }
  let live = Ref(true)
  let read = match
    @execution.prepare_supplied_relation_read(owner, input_index, captured, () => {
      live.val && available()
    }) {
    Ok(read) => read
    Err(_) => {
      discard_failed_original_input(input)
      return Err(Unavailable)
    }
  }
  Ok({ input, read, live, })
}

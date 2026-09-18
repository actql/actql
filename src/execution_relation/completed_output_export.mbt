///|
/// Bounded serialization of an existing immutable cell representation. This is
/// conversion, never execution or a way to admit caller-supplied output values.
struct CompletedOutputExport {
  mut source : CompletedOutput?
  rows : CompletedExportRows
  order : RowWireOrder
  schema : RelationSchemaIdentity?
  writer : @encode.Writer
  logical_writer : @encode.Writer?
  budget : ValueBudget
  mut row : Int
  mut reading : Bool
}

///|
/// One exact export, consumable only with storage bound to its content receipt.
struct CompletedOutputExportReceipt {
  mut source : CompletedOutput?
  content : AdmittedOutputStreamReceipt
  mut binding : Bool
}

///|
/// One publication export establishes the bare ordered-row receipt and the
/// registered logical Relation identity from the same immutable traversal.
struct CompletedRelationExportReceipt {
  rows : CompletedOutputExportReceipt
  logical : LogicalRelationIdentity
  schema : RelationSchemaIdentity
  fields : Array[String]
}

///|
pub(all) enum CompletedExportIssue {
  Unavailable
  NotCellRepresentation
  InvalidTarget
  NotFinished
  Closed
  ForeignMaterial
  Admission(CaptureIssue)
  Wire(RowWireIssue)
  Schema(RelationSchemaIdentityIssue)
  ResultView(CompletedResultViewIssue)
}

///|
pub fn prepare_completed_output_export(
  source : CompletedOutput,
  max_rows : Int,
  values : ValueLimits,
  wire : RowWireLimits,
  max_batch_bytes : Int,
) -> Result[CompletedOutputExport, CompletedExportIssue] {
  prepare_completed_export(
    source,
    None,
    max_rows,
    values,
    wire,
    None,
    None,
    max_batch_bytes,
  )
}

///|
/// Publication export hashes the registered logical Relation preimage while
/// returning only the physical ordered-row batches to the environment adapter.
pub fn prepare_completed_relation_export(
  source : CompletedOutput,
  max_rows : Int,
  values : ValueLimits,
  payload_wire : RowWireLimits,
  logical_wire : RowWireLimits,
  schema_limits : RelationSchemaIdentityLimits,
  max_batch_bytes : Int,
) -> Result[CompletedOutputExport, CompletedExportIssue] {
  prepare_completed_export(
    source,
    None,
    max_rows,
    values,
    payload_wire,
    Some(logical_wire),
    Some(schema_limits),
    max_batch_bytes,
  )
}

///|
/// Export one exact checked Named Result occurrence. Projection and total
/// publication order are applied as bounded index views before any identity is
/// established; cells remain in the completed producer representation.
pub fn prepare_completed_result_relation_export(
  source : CompletedOutput,
  occurrence : ManagedResultOccurrence,
  result_view : CompletedResultViewLimits,
  max_rows : Int,
  values : ValueLimits,
  payload_wire : RowWireLimits,
  logical_wire : RowWireLimits,
  schema_limits : RelationSchemaIdentityLimits,
  max_batch_bytes : Int,
) -> Result[CompletedOutputExport, CompletedExportIssue] {
  prepare_completed_export(
    source,
    Some((occurrence, result_view)),
    max_rows,
    values,
    payload_wire,
    Some(logical_wire),
    Some(schema_limits),
    max_batch_bytes,
  )
}

///|
fn prepare_completed_export(
  source : CompletedOutput,
  result_view : (ManagedResultOccurrence, CompletedResultViewLimits)?,
  max_rows : Int,
  values : ValueLimits,
  wire : RowWireLimits,
  logical_wire : RowWireLimits?,
  schema_limits : RelationSchemaIdentityLimits?,
  max_batch_bytes : Int,
) -> Result[CompletedOutputExport, CompletedExportIssue] {
  if !completed_output_available(source) {
    return Err(Unavailable)
  }
  guard source.table is Some(_) else { return Err(NotCellRepresentation) }
  guard source.target is Step(_) else { return Err(InvalidTarget) }
  let rows = match result_view {
    None => completed_output_export_rows(source)
    Some((occurrence, limits)) =>
      match completed_result_export_rows(source, occurrence, limits) {
        Ok(value) => value
        Err(issue) => return Err(ResultView(issue))
      }
  }
  if max_rows < 0 || IndexedRows::row_count(rows) > max_rows {
    return Err(Admission(CaptureLimit))
  }
  if !row_wire_valid_limits(wire) ||
    (logical_wire is Some(limits) && !row_wire_valid_limits(limits)) ||
    max_batch_bytes < 1 {
    return Err(Wire(InvalidLimits))
  }
  let budget = match value_budget(values) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  let order = match
    prepare_row_wire_order(
      completed_export_field_names(rows),
      wire.max_columns,
      wire.max_order_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Wire(issue))
  }
  let schema_identity = match schema_limits {
    None => None
    Some(limits) =>
      match identify_relation_schema(rows.schema, limits) {
        Ok(value) => Some(value)
        Err(issue) => return Err(Schema(issue))
      }
  }
  if logical_wire is Some(limits) &&
    (
      limits.max_columns < wire.max_columns ||
      limits.max_order_work < wire.max_order_work
    ) {
    return Err(Wire(OrderLimit))
  }
  try {
    let writer = @encode.buffered_hashing_writer(
      wire.max_bytes,
      wire.max_nodes,
      wire.max_depth,
      max_batch_bytes,
    )
    @encode.begin_array(writer)
    let logical_writer = logical_wire.map(limits => {
      let value = @encode.hashing_writer(
        limits.max_bytes,
        limits.max_nodes,
        limits.max_depth,
      )
      @encode.begin_object(value)
      @encode.key(value, "sort")
      @encode.string_value(value, "relation")
      @encode.key(value, "value")
      @encode.begin_array(value)
      value
    })
    Ok({
      source: Some(source),
      rows,
      order,
      schema: schema_identity,
      writer,
      logical_writer,
      budget,
      row: 0,
      reading: false,
    })
  } catch {
    issue => Err(Wire(Encoding(issue)))
  }
}

///|
pub fn cancel_completed_output_export(value : CompletedOutputExport) -> Unit {
  value.source = None
}

///|
/// Returns one canonical row batch, or None once all original rows were read.
/// The final array delimiter and receipt still require finish; None is not proof
/// of storage, success, or a complete identity.
pub fn next_completed_output_export(
  value : CompletedOutputExport,
) -> Result[String?, CompletedExportIssue] {
  if value.reading {
    return Err(Closed)
  }
  value.reading = true
  let result = next_completed_export_row(value)
  value.reading = false
  result
}

///|
fn next_completed_export_row(
  value : CompletedOutputExport,
) -> Result[String?, CompletedExportIssue] {
  guard value.source is Some(source) else { return Err(Closed) }
  if !completed_output_available(source) {
    value.source = None
    return Err(Unavailable)
  }
  if value.source is None {
    return Err(Closed)
  }
  if value.row == IndexedRows::row_count(value.rows) {
    return Ok(None)
  }
  let result = export_completed_row(value, value.rows)
  match result {
    Ok(text) => {
      value.row += 1
      Ok(Some(text))
    }
    Err(issue) => {
      value.source = None
      Err(issue)
    }
  }
}

///|
fn export_completed_row(
  value : CompletedOutputExport,
  table : CompletedExportRows,
) -> Result[String, CompletedExportIssue] {
  if IndexedRows::row_width(table, value.row) !=
    IndexedRows::column_count(table) {
    return Err(Wire(InvalidLayout))
  }
  if !charge_node(value.budget, 1) {
    return Err(Admission(CaptureLimit))
  }
  try {
    for (name, column) in value.order.columns {
      let cell = IndexedRows::read_cell(table, value.row, column)
      if !charge_text(value.budget, name) || !measure_result(cell, value.budget) {
        return Err(Admission(CaptureLimit))
      }
    }
    emit_completed_export_row(value, table, value.writer)
    if value.logical_writer is Some(writer) {
      emit_completed_export_row(value, table, writer)
    }
    Ok(@encode.drain_hash_output(value.writer))
  } catch {
    issue => Err(Wire(Encoding(issue)))
  }
}

///|
fn emit_completed_export_row(
  value : CompletedOutputExport,
  table : CompletedExportRows,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  for (name, column) in value.order.columns {
    let cell = IndexedRows::read_cell(table, value.row, column)
    @encode.key(writer, name)
    emit_runtime_value(cell, writer)
  }
  @encode.end_object(writer)
}

///|
/// Reify the already admitted Result view for a Captured Run without routing
/// cells through an environment adapter. The finished receipt keeps the exact
/// completed output alive while this second, bounded canonical encoding is
/// produced. Its logical identity is checked again by the publication owner.
pub fn completed_relation_export_snapshot(
  value : CompletedOutputExport,
  receipt : CompletedRelationExportReceipt,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(String, Array[String]), CompletedExportIssue] {
  guard receipt.rows.source is Some(source) else { return Err(Closed) }
  if !completed_output_available(source) {
    return Err(Unavailable)
  }
  if value.source is Some(_) ||
    value.row != IndexedRows::row_count(value.rows) ||
    max_bytes < 0 ||
    max_nodes < 0 ||
    max_depth < 0 {
    return Err(NotFinished)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    issue => return Err(Wire(Encoding(issue)))
  }
  try {
    @encode.begin_array(writer)
    for row = 0; row < IndexedRows::row_count(value.rows); row = row + 1 {
      @encode.begin_object(writer)
      for (name, column) in value.order.columns {
        let cell = IndexedRows::read_cell(value.rows, row, column)
        @encode.key(writer, name)
        emit_runtime_value(cell, writer)
      }
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    let wire = @encode.finish(writer)
    Ok((wire, completed_export_field_names(value.rows)))
  } catch {
    issue => Err(Wire(Encoding(issue)))
  }
}

///|
pub fn finish_completed_output_export(
  value : CompletedOutputExport,
) -> Result[(CompletedOutputExportReceipt, String), CompletedExportIssue] {
  if value.reading {
    return Err(Closed)
  }
  value.reading = true
  let result = finish_completed_export_stream(value)
  value.reading = false
  result.map(finished => (finished.0, finished.1))
}

///|
pub fn finish_completed_relation_export(
  value : CompletedOutputExport,
) -> Result[(CompletedRelationExportReceipt, String), CompletedExportIssue] {
  if value.reading {
    return Err(Closed)
  }
  value.reading = true
  let result = finish_completed_export_stream(value)
  value.reading = false
  result.bind(finished => {
    guard finished.2 is Some(logical) else { return Err(Closed) }
    guard value.schema is Some(schema) else { return Err(Closed) }
    Ok(
      (
        {
          rows: finished.0,
          logical,
          schema,
          fields: completed_export_field_names(value.rows),
        },
        finished.1,
      ),
    )
  })
}

///|
/// Return the checked Result field order retained by the same immutable
/// export receipt that established the logical and physical identities.
pub fn completed_relation_export_field_names(
  value : CompletedRelationExportReceipt,
) -> Array[String] {
  value.fields.copy()
}

///|
fn finish_completed_export_stream(
  value : CompletedOutputExport,
) -> Result[
  (CompletedOutputExportReceipt, String, LogicalRelationIdentity?),
  CompletedExportIssue,
] {
  guard value.source is Some(source) else { return Err(Closed) }
  if !completed_output_available(source) {
    value.source = None
    return Err(Unavailable)
  }
  if value.source is None {
    return Err(Closed)
  }
  if value.row != IndexedRows::row_count(value.rows) {
    return Err(NotFinished)
  }
  value.source = None
  let owner = @lower.sequence_owner(source.completion.sequence)
  try {
    @encode.end_array(value.writer)
    let tail = @encode.drain_hash_output(value.writer)
    let (hash, bytes, nodes, depth) = @encode.finish_hash_metrics(value.writer)
    let logical = value.logical_writer.map(writer => {
      @encode.end_array(writer)
      @encode.end_object(writer)
      let (logical_hash, logical_bytes, logical_nodes, _) = @encode.finish_hash_metrics(
        writer,
      )
      {
        cid: "sha256:" + logical_hash,
        bytes: logical_bytes,
        nodes: logical_nodes,
        rows: value.row,
      }
    })
    let content : AdmittedOutputStreamReceipt = {
      owner,
      target: source.target,
      schema: value.rows.schema,
      rows: value.row,
      cid: "sha256:" + hash,
      bytes,
      nodes,
      depth,
      usage: {
        nodes: value.budget.nodes,
        text_bytes: value.budget.text,
        work: value.budget.work,
      },
      measurement_identity: None,
    }
    Ok(({ source: Some(source), content, binding: false, }, tail, logical))
  } catch {
    issue => Err(Wire(Encoding(issue)))
  }
}

///|
pub fn completed_export_content(
  receipt : CompletedOutputExportReceipt,
) -> AdmittedOutputStreamReceipt {
  receipt.content
}

///|
pub fn completed_relation_export_content(
  receipt : CompletedRelationExportReceipt,
) -> AdmittedOutputStreamReceipt {
  receipt.rows.content
}

///|
pub fn completed_relation_export_identity(
  receipt : CompletedRelationExportReceipt,
) -> LogicalRelationIdentity {
  receipt.logical
}

///|
pub fn completed_relation_export_schema_identity(
  receipt : CompletedRelationExportReceipt,
) -> RelationSchemaIdentity {
  receipt.schema
}

///|
pub fn cancel_completed_export_receipt(
  receipt : CompletedOutputExportReceipt,
) -> Unit {
  receipt.source = None
}

///|
pub fn cancel_completed_relation_export_receipt(
  receipt : CompletedRelationExportReceipt,
) -> Unit {
  cancel_completed_export_receipt(receipt.rows)
}

///|
/// Preserve the same completion identity and logical liveness, replacing only
/// its physical representation. Installed Store wiring must verify its batches
/// before supplying material; a matching CID cannot replace the exact receipt.
pub fn bind_completed_output_export(
  receipt : CompletedOutputExportReceipt,
  material : RetainedOutputMaterial,
) -> Result[CompletedOutput, CompletedExportIssue] {
  if receipt.binding {
    return Err(Closed)
  }
  receipt.binding = true
  let result = bind_completed_export_material(receipt, material)
  receipt.binding = false
  result
}

///|
fn bind_completed_export_material(
  receipt : CompletedOutputExportReceipt,
  material : RetainedOutputMaterial,
) -> Result[CompletedOutput, CompletedExportIssue] {
  guard receipt.source is Some(source) else { return Err(Closed) }
  if !completed_output_available(source) {
    receipt.source = None
    return Err(Unavailable)
  }
  if receipt.source is None {
    return Err(Closed)
  }
  if !retained_output_matches_receipt(material, receipt.content) {
    return Err(ForeignMaterial)
  }
  // The installed liveness callback cannot revoke the source during admission.
  if !completed_output_available(source) {
    receipt.source = None
    return Err(Unavailable)
  }
  if receipt.source is None {
    return Err(Closed)
  }
  receipt.source = None
  let completion : CompletedSequence = {
    ..source.completion,
    store: RetainedStore(
      source.completion.store.input_count(),
      source.target,
      material,
    ),
    _producer_inputs: [],
  }
  Ok({
    completion,
    target: source.target,
    table: None,
    representation: Some(material),
  })
}

///|
/// Bounded serialization of an existing immutable cell representation. This is
/// conversion, never execution or a way to admit caller-supplied output values.
struct CompletedOutputExport {
  mut source : CompletedOutput?
  order : RowWireOrder
  writer : @encode.Writer
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
pub(all) enum CompletedExportIssue {
  Unavailable
  NotCellRepresentation
  InvalidTarget
  NotFinished
  Closed
  ForeignMaterial
  Admission(CaptureIssue)
  Wire(RowWireIssue)
}

///|
pub fn prepare_completed_output_export(
  source : CompletedOutput,
  max_rows : Int,
  values : ValueLimits,
  wire : RowWireLimits,
  max_batch_bytes : Int,
) -> Result[CompletedOutputExport, CompletedExportIssue] {
  if !completed_output_available(source) {
    return Err(Unavailable)
  }
  guard source.table is Some(table) else { return Err(NotCellRepresentation) }
  guard source.target is Step(_) else { return Err(InvalidTarget) }
  if max_rows < 0 || IndexedRows::row_count(table) > max_rows {
    return Err(Admission(CaptureLimit))
  }
  if !row_wire_valid_limits(wire) || max_batch_bytes < 1 {
    return Err(Wire(InvalidLimits))
  }
  let budget = match value_budget(values) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  let order = match
    prepare_row_wire_order(
      RelationRows::field_names(table),
      wire.max_columns,
      wire.max_order_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Wire(issue))
  }
  try {
    let writer = @encode.buffered_hashing_writer(
      wire.max_bytes,
      wire.max_nodes,
      wire.max_depth,
      max_batch_bytes,
    )
    @encode.begin_array(writer)
    Ok({ source: Some(source), order, writer, budget, row: 0, reading: false, })
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
  let table = source.table.unwrap()
  if value.row == IndexedRows::row_count(table) {
    return Ok(None)
  }
  let result = export_completed_row(value, table)
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
  table : CompletedTable,
) -> Result[String, CompletedExportIssue] {
  if IndexedRows::row_width(table, value.row) !=
    IndexedRows::column_count(table) {
    return Err(Wire(InvalidLayout))
  }
  if !charge_node(value.budget, 1) {
    return Err(Admission(CaptureLimit))
  }
  try {
    @encode.begin_object(value.writer)
    for (name, column) in value.order.columns {
      let cell = IndexedRows::read_cell(table, value.row, column)
      if !charge_text(value.budget, name) || !measure_result(cell, value.budget) {
        return Err(Admission(CaptureLimit))
      }
      @encode.key(value.writer, name)
      emit_runtime_value(cell, value.writer)
    }
    @encode.end_object(value.writer)
    Ok(@encode.drain_hash_output(value.writer))
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
  result
}

///|
fn finish_completed_export_stream(
  value : CompletedOutputExport,
) -> Result[(CompletedOutputExportReceipt, String), CompletedExportIssue] {
  guard value.source is Some(source) else { return Err(Closed) }
  if !completed_output_available(source) {
    value.source = None
    return Err(Unavailable)
  }
  if value.source is None {
    return Err(Closed)
  }
  if value.row != completed_row_count(source) {
    return Err(NotFinished)
  }
  value.source = None
  let owner = @lower.sequence_owner(source.completion.sequence)
  let schema = @lower.preparation_schema_at(
    @lower.bound_preparation(owner),
    source.target,
  ).unwrap()
  try {
    @encode.end_array(value.writer)
    let tail = @encode.drain_hash_output(value.writer)
    let (hash, bytes, nodes, depth) = @encode.finish_hash_metrics(value.writer)
    let content : AdmittedOutputStreamReceipt = {
      owner,
      target: source.target,
      schema,
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
    Ok(({ source: Some(source), content, binding: false, }, tail))
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
pub fn cancel_completed_export_receipt(
  receipt : CompletedOutputExportReceipt,
) -> Unit {
  receipt.source = None
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

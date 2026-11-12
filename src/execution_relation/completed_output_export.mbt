///|
/// Bounded serialization of an existing immutable cell representation. This is
/// conversion, never execution or a way to admit caller-supplied output values.
struct CompletedOutputExport {
  export_identity : Ref[Unit]
  mut source : CompletedOutput?
  rows : CompletedExportRows
  order : RowWireOrder
  schema : RelationSchemaIdentity?
  writer : @encode.Writer
  logical_writer : @encode.Writer?
  budget : ValueBudget
  mut column_rows : Array[Int]
  mut column_bytes : Array[Int]
  mut column_nodes : Array[Int]
  mut column_max_value_bytes : Array[Int]
  mut column_null_rows : Array[Int]
  mut column_admitted_depths : Array[Int]
  measurement_max_bytes : Int
  measurement_max_nodes : Int
  measurement_max_depth : Int
  max_batch_bytes : Int
  mut drained_bytes : Int
  // 0 is unread, 1 preserves row consumers, 2 is physical publication only.
  mut batch_mode : Int
  mut row : Int
  mut reading : Bool
  mut poll_steps : Int
  mut pending_row : CompletedExportRowProgress?
  mut references : CompletedExportReferences?
}

///|
/// Resumable preparation for a checked Named Result view. Projection mapping
/// and stable ordering complete before the canonical row stream is exposed.
struct CompletedResultRelationExportPreparation {
  rows : CompletedResultRowsPreparation
  max_rows : Int
  values : ValueLimits
  payload_wire : RowWireLimits
  logical_wire : RowWireLimits
  schema_limits : RelationSchemaIdentityLimits
  max_batch_bytes : Int
  mut metadata : CompletedOutputExportPreparation?
  mut stream : CompletedOutputExport?
  mut closed : Bool
  mut advancing : Bool
  mut poll_work : Int
}

///|
/// One exact export, consumable only with storage bound to its content receipt.
struct CompletedOutputExportReceipt {
  export_identity : Ref[Unit]
  mut source : CompletedOutput?
  content : AdmittedOutputStreamReceipt
  mut binding : Bool
  mut references : CompletedExportReferences?
}

///|
/// One publication export establishes the bare ordered-row receipt and the
/// registered logical Relation identity from the same immutable traversal.
struct CompletedRelationExportReceipt {
  rows : CompletedOutputExportReceipt
  logical : LogicalRelationIdentity
  schema : RelationSchemaIdentity
  fields : Array[String]
  measurement : CompletedRelationExportMeasurement
}

///|
/// Exact column summaries established by the same bounded traversal that
/// identifies a completed Relation. This is reusable measurement data, not an
/// issuer capability or physical-retention evidence.
pub(all) struct CompletedRelationExportMeasurement {
  row_count : Int
  admission_nodes : Int
  admission_text_bytes : Int
  admission_work : Int
  column_rows : Array[Int]
  column_bytes : Array[Int]
  column_nodes : Array[Int]
  column_max_value_bytes : Array[Int]
  column_null_rows : Array[Int]
  column_admitted_depths : Array[Int]
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
  CanonicalRow
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
pub fn start_completed_result_relation_export(
  source : CompletedOutput,
  occurrence : ManagedResultOccurrence,
  result_view : CompletedResultViewLimits,
  max_rows : Int,
  values : ValueLimits,
  payload_wire : RowWireLimits,
  logical_wire : RowWireLimits,
  schema_limits : RelationSchemaIdentityLimits,
  max_batch_bytes : Int,
) -> Result[CompletedResultRelationExportPreparation, CompletedExportIssue] {
  let rows = match
    start_completed_result_rows(source, occurrence, result_view) {
    Ok(value) => value
    Err(issue) => return Err(ResultView(issue))
  }
  Ok({
    rows,
    max_rows,
    values,
    payload_wire,
    logical_wire,
    schema_limits,
    max_batch_bytes,
    metadata: None,
    stream: None,
    closed: false,
    advancing: false,
    poll_work: 0,
  })
}

///|
pub fn cancel_completed_result_relation_export(
  value : CompletedResultRelationExportPreparation,
) -> Bool {
  if value.closed {
    false
  } else {
    value.closed = true
    cancel_completed_result_rows(value.rows) |> ignore
    if value.metadata is Some(metadata) {
      cancel_completed_output_export_preparation(metadata) |> ignore
    }
    value.metadata = None
    if value.stream is Some(stream) {
      cancel_completed_output_export(stream)
    }
    true
  }
}

///|
pub fn advance_completed_result_relation_export(
  value : CompletedResultRelationExportPreparation,
  quantum : Int,
) -> Result[(Bool, Int), CompletedExportIssue] {
  if value.closed || value.advancing || quantum <= 0 {
    return Err(Closed)
  }
  value.poll_work = 0
  value.advancing = true
  let result = (fn() -> Result[(Bool, Int), CompletedExportIssue] {
    if !completed_output_available(value.rows.source) || value.closed {
      return Err(ResultView(Unavailable))
    }
    if value.stream is Some(_) {
      return Ok((true, 0))
    }
    let mut steps = 0
    while steps < quantum {
      if value.metadata is Some(metadata) {
        let (done, used) = match
          advance_completed_output_export_preparation(metadata, quantum - steps) {
          Ok(value) => value
          Err(issue) => {
            value.poll_work = steps + metadata.poll_work
            return Err(issue)
          }
        }
        steps += used
        value.poll_work = steps
        if done {
          value.stream = Some(
            match finish_completed_output_export_preparation(metadata) {
              Ok(value) => value
              Err(issue) => return Err(issue)
            },
          )
          value.metadata = None
          return Ok((true, steps))
        }
      } else if value.rows.done {
        steps += 1
        value.poll_work = steps
        let rows = match finish_completed_result_rows(value.rows) {
          Ok(value) => value
          Err(issue) => return Err(ResultView(issue))
        }
        guard completed_export_preparation_workspace_slots(
            value.payload_wire.max_columns,
          )
          is Some(slots) else {
          return Err(Wire(InvalidLimits))
        }
        value.metadata = Some(
          match
            start_completed_export_rows_metadata(
              value.rows.source,
              rows,
              value.max_rows,
              value.values,
              value.payload_wire,
              Some(value.logical_wire),
              Some(value.schema_limits),
              value.max_batch_bytes,
              slots,
            ) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          },
        )
      } else {
        let (_, used) = match
          advance_completed_result_rows(value.rows, quantum - steps) {
          Ok(value) => value
          Err(issue) => {
            value.poll_work = steps + value.rows.poll_work
            return Err(ResultView(issue))
          }
        }
        steps += used
        value.poll_work = steps
      }
    }
    Ok((false, steps))
  })()
  value.advancing = false
  if result is Err(_) {
    cancel_completed_result_relation_export(value) |> ignore
  }
  result
}

///|
/// Transport the SAME bounded view's observed poll work even if a later frame
/// fails. Successful work is unchanged; failure/cancel/re-read never synthesizes
/// work or releases the borrowed producer. Reentrant/closed entry performs none.
pub fn advance_completed_result_relation_export_progress(
  value : CompletedResultRelationExportPreparation,
  quantum : Int,
) -> (Bool, Int, CompletedExportIssue?) {
  if value.closed || value.advancing || quantum <= 0 {
    return (false, 0, Some(Closed))
  }
  match advance_completed_result_relation_export(value, quantum) {
    Ok((ready, work)) => (ready, work, None)
    Err(issue) => (false, value.poll_work, Some(issue))
  }
}

///|
pub fn finish_completed_result_relation_export_preparation(
  value : CompletedResultRelationExportPreparation,
) -> Result[CompletedOutputExport, CompletedExportIssue] {
  if value.closed || value.advancing {
    return Err(Closed)
  }
  guard value.stream is Some(stream) else { return Err(NotFinished) }
  value.advancing = true
  let available = completed_output_available(value.rows.source)
  value.advancing = false
  if value.closed {
    return Err(Closed)
  }
  if !available {
    cancel_completed_result_relation_export(value) |> ignore
    return Err(ResultView(Unavailable))
  }
  value.closed = true
  Ok(stream)
}

///|
/// A completed receipt may be used as evidence for this checked preparation
/// only when it came from the exact export stream owned by that preparation.
pub fn completed_result_export_preparation_matches_receipt(
  value : CompletedResultRelationExportPreparation,
  receipt : CompletedRelationExportReceipt,
) -> Bool {
  guard value.closed &&
    value.stream is Some(stream) &&
    receipt.rows.source is Some(source) else {
    return false
  }
  let available = completed_output_available(source)
  // Availability may synchronously cancel this exact receipt/stream. Its
  // earlier alias is not a successful observation after that callback.
  available &&
  value.closed &&
  (value.stream is Some(actual) && physical_equal(actual, stream)) &&
  (receipt.rows.source is Some(actual) && physical_equal(actual, source)) &&
  physical_equal(stream.export_identity, receipt.rows.export_identity)
}

///|
/// The prepared view must belong to this exact named Result occurrence and
/// the completed generation returned by its managed import bridge.
pub fn completed_result_export_preparation_matches_owner(
  value : CompletedResultRelationExportPreparation,
  occurrence : ManagedResultOccurrence,
  completed : CompletedOutput,
) -> Bool {
  managed_result_occurrence_same(value.rows.occurrence, occurrence) &&
  physical_equal(value.rows.source, completed) &&
  completed_output_available(completed)
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
  start_completed_export(
    source, result_view, max_rows, values, wire, logical_wire, schema_limits, max_batch_bytes,
  ).bind(drain_completed_export_preparation)
}

///|
// Same export owner and original validation order, without hiding metadata,
// schema or writer construction inside a draining constructor. Its caller can
// back each next transition before advancing this original preparation.
fn start_completed_export(
  source : CompletedOutput,
  result_view : (ManagedResultOccurrence, CompletedResultViewLimits)?,
  max_rows : Int,
  values : ValueLimits,
  wire : RowWireLimits,
  logical_wire : RowWireLimits?,
  schema_limits : RelationSchemaIdentityLimits?,
  max_batch_bytes : Int,
) -> Result[CompletedOutputExportPreparation, CompletedExportIssue] {
  if !completed_output_available(source) {
    return Err(Unavailable)
  }
  guard source.table is Some(_) else { return Err(NotCellRepresentation) }
  guard admitted_relation_output_target(
    @lower.sequence_owner(source.completion.sequence),
    source.target,
  ) else {
    return Err(InvalidTarget)
  }
  let rows = match result_view {
    None => completed_output_export_rows(source)
    Some((occurrence, limits)) =>
      match completed_result_export_rows(source, occurrence, limits) {
        Ok(value) => value
        Err(issue) => return Err(ResultView(issue))
      }
  }
  guard completed_export_preparation_workspace_slots(wire.max_columns)
    is Some(slots) else {
    return Err(Wire(InvalidLimits))
  }
  start_completed_export_rows_metadata(
    source, rows, max_rows, values, wire, logical_wire, schema_limits, max_batch_bytes,
    slots,
  )
}

///|
fn prepare_completed_export_rows(
  source : CompletedOutput,
  rows : CompletedExportRows,
  max_rows : Int,
  values : ValueLimits,
  wire : RowWireLimits,
  logical_wire : RowWireLimits?,
  schema_limits : RelationSchemaIdentityLimits?,
  max_batch_bytes : Int,
) -> Result[CompletedOutputExport, CompletedExportIssue] {
  guard completed_export_preparation_workspace_slots(wire.max_columns)
    is Some(slots) else {
    return Err(Wire(InvalidLimits))
  }
  start_completed_export_rows_metadata(
    source, rows, max_rows, values, wire, logical_wire, schema_limits, max_batch_bytes,
    slots,
  ).bind(drain_completed_export_preparation)
}

///|
/// Re-open the exact finished Result view as a bounded physical byte stream.
/// The first traversal establishes logical identity; this traversal lets a
/// durable adapter consume the same immutable view after its exact binding is
/// known. It neither re-evaluates the task nor re-admits caller data.
pub fn replay_completed_relation_export(
  value : CompletedOutputExport,
  receipt : CompletedRelationExportReceipt,
  values : ValueLimits,
  wire : RowWireLimits,
  max_batch_bytes : Int,
) -> Result[CompletedOutputExport, CompletedExportIssue] {
  guard receipt.rows.source is Some(source) else { return Err(Closed) }
  if !physical_equal(value.export_identity, receipt.rows.export_identity) ||
    value.source is Some(_) ||
    value.row != IndexedRows::row_count(value.rows) {
    return Err(NotFinished)
  }
  if !completed_output_available(source) {
    return Err(Unavailable)
  }
  if !row_wire_valid_limits(wire) || max_batch_bytes < 1 {
    return Err(Wire(InvalidLimits))
  }
  prepare_completed_export_rows(
    source,
    value.rows,
    IndexedRows::row_count(value.rows),
    values,
    wire,
    None,
    None,
    max_batch_bytes,
  )
}

///|
pub fn cancel_completed_output_export(value : CompletedOutputExport) -> Unit {
  value.source = None
  if value.references is Some(references) && !references.complete {
    references.revoked = true
  }
  // An active callback only revokes; the enclosing poll closes its private
  // cursor after the current emitter transition has returned.
  if !value.reading {
    if value.pending_row is Some(cursor) {
      close_completed_export_row(cursor)
    }
    value.pending_row = None
    @encode.cancel_writer(value.writer)
    if value.logical_writer is Some(writer) {
      @encode.cancel_writer(writer)
    }
  }
}

///|
/// Returns one canonical row batch, or None once all original rows were read.
/// The final array delimiter and receipt still require finish; None is not proof
/// of storage, success, or a complete identity.
pub fn next_completed_output_export(
  value : CompletedOutputExport,
  batch? : Bool = false,
) -> Result[String?, CompletedExportIssue] {
  guard completed_output_export_workspace_slots(value.budget.limits, {
      max_columns: 0,
      max_order_work: 0,
      max_bytes: value.measurement_max_bytes,
      max_nodes: value.measurement_max_nodes,
      max_depth: value.measurement_max_depth,
    })
    is Some(slots) else {
    return Err(Admission(InvalidCaptureLimits))
  }
  while true {
    let result = match
      advance_completed_output_export(value, 64, slots, batch~) {
      Ok(result) => result
      Err(issue) => return Err(issue)
    }
    if result.batch is Some(batch) {
      return Ok(Some(batch))
    }
    if result.complete {
      return Ok(None)
    }
  } nobreak {
    Err(Closed)
  }
}

///|
/// Return the next checked Result row as an owned canonical value alongside
/// the same bounded bytes already hashed by the export. Only one row is
/// parsed at a time; no environment adapter reconstructs the full Relation.
/// The leading array delimiter is part of the stored byte batch, but not of
/// the row value. A conversion failure poisons this export occurrence.
pub fn next_completed_output_export_canonical_row(
  value : CompletedOutputExport,
  max_nodes : Int,
  max_depth : Int,
  max_utf16_units : Int,
) -> Result[(Int, String, @identity.CanonicalValue)?, CompletedExportIssue] {
  if max_nodes < 1 || max_depth < 1 || max_utf16_units < 0 {
    return Err(CanonicalRow)
  }
  let index = value.row
  let batch = match next_completed_output_export(value) {
    Ok(Some(batch)) => batch
    Ok(None) => return Ok(None)
    Err(issue) => return Err(issue)
  }
  if batch.length() < 2 ||
    batch[0].to_int() != (if index == 0 { 91 } else { 44 }) {
    value.source = None
    return Err(CanonicalRow)
  }
  let row = @identity.from_json(
    @json.parse(batch[1:].to_owned()),
    max_nodes,
    max_depth,
    max_utf16_units,
    data_keys=true,
  ) catch {
    _ => {
      value.source = None
      return Err(CanonicalRow)
    }
  }
  if @identity.object_field_count(row) is None {
    value.source = None
    return Err(CanonicalRow)
  }
  Ok(Some((index, batch, row)))
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
  // A snapshot must borrow the exact finished export view that issued this
  // receipt. Equal rows or even the same completion cannot substitute it.
  if !physical_equal(value.export_identity, receipt.rows.export_identity) {
    return Err(ForeignMaterial)
  }
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
        if !IndexedRows::cell_present(value.rows, row, column) {
          continue
        }
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
          // Names belong to this immutable export view and are never exposed
          // directly; public readers still return independent snapshots.
          fields: value.rows.names,
          measurement: take_completed_export_measurement(value),
        },
        finished.1,
      ),
    )
  })
}

///|
fn take_completed_export_measurement(
  value : CompletedOutputExport,
) -> CompletedRelationExportMeasurement {
  let measurement : CompletedRelationExportMeasurement = {
    row_count: value.row,
    admission_nodes: value.budget.nodes,
    admission_text_bytes: value.budget.text,
    admission_work: value.budget.work,
    column_rows: value.column_rows,
    column_bytes: value.column_bytes,
    column_nodes: value.column_nodes,
    column_max_value_bytes: value.column_max_value_bytes,
    column_null_rows: value.column_null_rows,
    column_admitted_depths: value.column_admitted_depths,
  }
  value.column_rows = []
  value.column_bytes = []
  value.column_nodes = []
  value.column_max_value_bytes = []
  value.column_null_rows = []
  value.column_admitted_depths = []
  measurement
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
/// Observe the finished original logical writer, not a new traversal or a
/// policy ceiling. The receipt and stream must be the same completed export.
/// The existing writer retains peak open-container depth even after finish.
pub fn completed_relation_export_snapshot_extent(
  stream : CompletedOutputExport,
  receipt : CompletedRelationExportReceipt,
) -> Result[(Int, Int, Int, Int), CompletedExportIssue] {
  if !physical_equal(stream.export_identity, receipt.rows.export_identity) {
    return Err(ForeignMaterial)
  }
  guard completed_relation_export_receipt_live(receipt) &&
    stream.source is None &&
    stream.row == IndexedRows::row_count(stream.rows) &&
    stream.logical_writer is Some(writer) else {
    return Err(NotFinished)
  }
  let (bytes, nodes, depth) = @encode.observed_writer_usage(writer)
  let (original_bytes, original_nodes, rows) = logical_relation_usage(
    receipt.logical,
  )
  if bytes != original_bytes || nodes != original_nodes {
    return Err(ForeignMaterial)
  }
  Ok((bytes, nodes, rows, depth))
}

///|
/// An export receipt attests only to its exact immutable completed source.
/// Equal content or an independently reconstructed completion is insufficient.
/// Upstream liveness is not rechecked after completion.
pub fn completed_relation_export_matches_output(
  value : CompletedRelationExportReceipt,
  output : CompletedOutput,
) -> Bool {
  guard value.rows.source is Some(source) &&
    completed_output_occurrence_identity_matches(output, source) else {
    return false
  }
  // The expected original and the receipt's converted view have separate
  // availability. Observe each once, then fence the exact mutable receipt alias.
  let available = completed_output_available(output) &&
    completed_output_available(source)
  available &&
  value.rows.source is Some(actual) &&
  physical_equal(actual, source)
}

///|
/// Project immutable completion/target identity only, before selecting a
/// current-aware direct or derived consumer. This observes no availability,
/// Source, Host or current callback and cannot authorize use of the receipt.
pub fn completed_relation_export_has_output_identity(
  value : CompletedRelationExportReceipt,
  output : CompletedOutput,
) -> Bool {
  match value.rows.source {
    Some(source) => completed_output_occurrence_identity_matches(output, source)
    None => false
  }
}

///|
/// Return an independent snapshot of the exact successful export
/// measurement. Mutating the returned arrays cannot alter the receipt.
pub fn completed_relation_export_measurement(
  value : CompletedRelationExportReceipt,
) -> CompletedRelationExportMeasurement {
  let measurement = value.measurement
  {
    ..measurement,
    column_rows: measurement.column_rows.copy(),
    column_bytes: measurement.column_bytes.copy(),
    column_nodes: measurement.column_nodes.copy(),
    column_max_value_bytes: measurement.column_max_value_bytes.copy(),
    column_null_rows: measurement.column_null_rows.copy(),
    column_admitted_depths: measurement.column_admitted_depths.copy(),
  }
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
      value_measurement: None,
    }
    let references = value.references
    if references is Some(references) {
      references.complete = true
    }
    value.references = None
    Ok(
      (
        {
          export_identity: value.export_identity,
          source: Some(source),
          content,
          binding: false,
          references,
        },
        tail,
        logical,
      ),
    )
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
  if receipt.references is Some(references) {
    references.revoked = true
  }
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
/// Bind the same exact row receipt carried by a logical Relation export.
/// This preserves the original completion and all receiving-grant checks;
/// a logical identity alone never authorizes retained representation.
pub fn bind_completed_relation_export(
  receipt : CompletedRelationExportReceipt,
  material : RetainedOutputMaterial,
) -> Result[CompletedOutput, CompletedExportIssue] {
  bind_completed_output_export(receipt.rows, material)
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
  material.references = receipt.references
  receipt.references = None
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

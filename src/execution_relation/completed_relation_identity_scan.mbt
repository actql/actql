///|
priv enum RelationIdentityPhase {
  BeginRow
  BeginColumn
  MeasureName(SteppedValueMeasure)
  MeasureCell(SteppedValueMeasure)
  MeasureWire(IdentityWireCursor, @encode.Writer)
  EmitPayload(IdentityWireCursor)
  EmitLogical(IdentityWireCursor)
  Done
}

///|
/// Identify the exact completed Relation without retaining a row-sized JSON
/// value or draining nested values within one advance. This owns the existing
/// export and receipt machinery, not a second identity or completion format.
struct CompletedRelationIdentityScan {
  stream : CompletedOutputExport
  workspace : RowWorkspace
  max_work : Int
  mut work : Int
  mut column : Int
  mut phase : RelationIdentityPhase
  mut advancing : Bool
  mut closed : Bool
}

///|
priv enum IdentityWireCursor {
  CapturedWire(@admitted.WireEmitCursor)
  ScalarWire(Value, @encode.Writer)
}

///|
pub fn start_completed_relation_identity_scan(
  source : CompletedOutput,
  max_rows : Int,
  values : ValueLimits,
  payload_wire : RowWireLimits,
  logical_wire : RowWireLimits,
  schema_limits : RelationSchemaIdentityLimits,
  max_work : Int,
  max_workspace_slots : Int,
) -> Result[CompletedRelationIdentityScan, CompletedExportIssue] {
  if !completed_output_available(source) {
    return Err(Unavailable)
  }
  guard source.table is Some(table) else { return Err(NotCellRepresentation) }
  if max_work < 0 || max_workspace_slots < 0 {
    return Err(Admission(InvalidCaptureLimits))
  }
  if !row_wire_valid_limits(payload_wire) ||
    !row_wire_valid_limits(logical_wire) {
    return Err(Wire(InvalidLimits))
  }
  let width = IndexedRows::column_count(table)
  let workspace = row_workspace(max_workspace_slots)
  // Reserve metadata and a conservative envelope for the three writers'
  // open key/frame storage before creating them. Traversal frames reserve
  // incrementally from the remaining allowance. No payload copy is retained.
  guard checked_row_slots_add(payload_wire.max_nodes, logical_wire.max_nodes)
    is Some(writer_slots) &&
    checked_row_slots_add(writer_slots, payload_wire.max_nodes)
    is Some(writer_slots) &&
    width >= 0 &&
    width <= (2147483647 - writer_slots) / 8 &&
    reserve_slots(workspace, writer_slots + width * 8) else {
    return Err(Admission(CaptureLimit))
  }
  let stream = match
    prepare_completed_relation_export(
      source,
      max_rows,
      values,
      payload_wire,
      logical_wire,
      schema_limits,
      Int::max(1, payload_wire.max_bytes),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    stream,
    workspace,
    max_work,
    work: 0,
    column: 0,
    phase: BeginRow,
    advancing: false,
    closed: false,
  })
}

///|
fn identity_scan_cell(value : CompletedRelationIdentityScan) -> Value {
  let column = value.stream.order.columns[value.column].1
  IndexedRows::read_cell(value.stream.rows, value.stream.row, column)
}

///|
fn identity_scan_emit(
  cell : Value,
  writer : @encode.Writer,
) -> IdentityWireCursor {
  match cell {
    Captured(value) => CapturedWire(@admitted.start_wire_emit(value, writer))
    scalar => ScalarWire(scalar, writer)
  }
}

///|
fn advance_identity_wire(
  cursor : IdentityWireCursor,
) -> Bool raise @encode.EncodeFailure {
  match cursor {
    CapturedWire(cursor) => @admitted.advance_wire_emit(cursor)
    ScalarWire(cell, writer) => {
      emit_runtime_value(cell, writer)
      true
    }
  }
}

///|
fn cancel_identity_wire(cursor : IdentityWireCursor) -> Unit {
  match cursor {
    CapturedWire(cursor) => @admitted.cancel_wire_emit(cursor)
    ScalarWire(_, _) => ()
  }
}

///|
/// Poison only this unfinished export. The completed input remains owned by
/// its producer, including when identity or cancellation fails.
pub fn cancel_completed_relation_identity_scan(
  value : CompletedRelationIdentityScan,
) -> Bool {
  if value.closed || value.advancing {
    return false
  }
  match value.phase {
    MeasureName(cursor) | MeasureCell(cursor) => clear_stepped_measure(cursor)
    MeasureWire(cursor, _) | EmitPayload(cursor) | EmitLogical(cursor) =>
      cancel_identity_wire(cursor)
    BeginRow | BeginColumn | Done => ()
  }
  cancel_completed_output_export(value.stream)
  release_slots(value.workspace, value.workspace.live)
  value.closed = true
  true
}

///|
fn advance_identity_scan_frame(
  value : CompletedRelationIdentityScan,
) -> Result[Unit, CompletedExportIssue] {
  let stream = value.stream
  try {
    match value.phase {
      BeginRow => {
        if stream.row == IndexedRows::row_count(stream.rows) {
          value.phase = Done
          return Ok(())
        }
        if IndexedRows::row_width(stream.rows, stream.row) !=
          IndexedRows::column_count(stream.rows) {
          return Err(Wire(InvalidLayout))
        }
        if !charge_node(stream.budget, 1) {
          return Err(Admission(CaptureLimit))
        }
        @encode.begin_object(stream.writer)
        if stream.logical_writer is Some(writer) {
          @encode.begin_object(writer)
        }
        value.column = 0
        value.phase = BeginColumn
      }
      BeginColumn => {
        if value.column == stream.order.columns.length() {
          @encode.end_object(stream.writer)
          if stream.logical_writer is Some(writer) {
            @encode.end_object(writer)
          }
          stream.row += 1
          value.phase = BeginRow
          return Ok(())
        }
        let name = stream.order.columns[value.column].0
        if !reserve_slots(value.workspace, 1) {
          return Err(Admission(CaptureLimit))
        }
        value.phase = MeasureName({
          frames: [SteppedTextNext(name, 0)],
          workspace: value.workspace,
          workspace_failed: false,
        })
      }
      MeasureName(cursor) | MeasureCell(cursor) =>
        match advance_stepped_measure_result(cursor, stream.budget) {
          SteppedMeasureContinue => ()
          SteppedMeasureLimit | SteppedMeasureWorkspaceLimit =>
            return Err(Admission(CaptureLimit))
          SteppedMeasureComplete => {
            clear_stepped_measure(cursor)
            if value.phase is MeasureName(_) {
              guard start_stepped_measure_result(
                  identity_scan_cell(value),
                  value.workspace,
                )
                is Some(measure) else {
                return Err(Admission(CaptureLimit))
              }
              value.phase = MeasureCell(measure)
            } else {
              let writer = @encode.measuring_writer(
                stream.measurement_max_bytes,
                stream.measurement_max_nodes,
                stream.measurement_max_depth,
              )
              value.phase = MeasureWire(
                identity_scan_emit(identity_scan_cell(value), writer),
                writer,
              )
            }
          }
        }
      MeasureWire(cursor, writer) =>
        if advance_identity_wire(cursor) {
          let (bytes, nodes, depth) = @encode.finish_measurement_usage(writer)
          let column = value.column
          // Per-cell writer limits and aggregate value admission precede
          // every checked accumulation into the export's column summaries.
          if bytes > 2147483647 - stream.column_bytes[column] ||
            nodes > 2147483647 - stream.column_nodes[column] {
            return Err(Admission(CaptureLimit))
          }
          stream.column_rows[column] += 1
          stream.column_bytes[column] += bytes
          stream.column_nodes[column] += nodes
          stream.column_max_value_bytes[column] = Int::max(
            stream.column_max_value_bytes[column],
            bytes,
          )
          stream.column_admitted_depths[column] = Int::max(
            stream.column_admitted_depths[column],
            depth,
          )
          let cell = identity_scan_cell(value)
          if cell is Null || cell is Captured(@admitted.Null) {
            stream.column_null_rows[column] += 1
          }
          @encode.key(stream.writer, stream.order.columns[column].0)
          value.phase = EmitPayload(identity_scan_emit(cell, stream.writer))
        }
      EmitPayload(cursor) =>
        if advance_identity_wire(cursor) {
          if stream.logical_writer is Some(writer) {
            @encode.key(writer, stream.order.columns[value.column].0)
            value.phase = EmitLogical(
              identity_scan_emit(identity_scan_cell(value), writer),
            )
          } else {
            return Err(Closed)
          }
        }
      EmitLogical(cursor) =>
        if advance_identity_wire(cursor) {
          value.column += 1
          value.phase = BeginColumn
        }
      Done => ()
    }
    // Identity-only traversal consumes provisional bytes immediately. It
    // never materializes a whole row or exposes an unfinished payload.
    @encode.drain_hash_output(stream.writer) |> ignore
    Ok(())
  } catch {
    issue => Err(Wire(Encoding(issue)))
  }
}

///|
/// Return completion and work consumed in this call. Nested measurement and
/// emission frames are included in the same quantum, not hidden in one row.
pub fn advance_completed_relation_identity_scan(
  value : CompletedRelationIdentityScan,
  quantum : Int,
) -> Result[(Bool, Int), CompletedExportIssue] {
  if value.closed || value.advancing || quantum <= 0 {
    return Err(Closed)
  }
  guard value.stream.source is Some(source) &&
    completed_output_available(source) else {
    cancel_completed_relation_identity_scan(value) |> ignore
    return Err(Unavailable)
  }
  value.advancing = true
  let mut consumed = 0
  let mut issue : CompletedExportIssue? = None
  while consumed < quantum && !(value.phase is Done) {
    if value.work >= value.max_work {
      issue = Some(Admission(CaptureLimit))
      break
    }
    value.work += 1
    consumed += 1
    match advance_identity_scan_frame(value) {
      Ok(_) => ()
      Err(failure) => {
        issue = Some(failure)
        break
      }
    }
  }
  value.advancing = false
  match issue {
    Some(failure) => {
      cancel_completed_relation_identity_scan(value) |> ignore
      Err(failure)
    }
    None => Ok((value.phase is Done, consumed))
  }
}

///|
pub fn finish_completed_relation_identity_scan(
  value : CompletedRelationIdentityScan,
) -> Result[CompletedRelationExportReceipt, CompletedExportIssue] {
  if value.closed || value.advancing {
    return Err(Closed)
  }
  if !(value.phase is Done) {
    return Err(NotFinished)
  }
  let result = finish_completed_relation_export(value.stream).map(pair => pair.0)
  release_slots(value.workspace, value.workspace.live)
  value.closed = true
  result
}

///|
/// Monotone work survives failure and cancellation; it is not rolled back
/// when an unfinished export is reclaimed.
pub fn completed_relation_identity_scan_work(
  value : CompletedRelationIdentityScan,
) -> Int64 {
  value.work.to_int64()
}

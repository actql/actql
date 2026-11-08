///|
priv enum RelationIdentityPhase {
  BeginRow
  PrepareReferenceColumns
  BeginColumn
  MeasureName(SteppedValueMeasure)
  MeasureCell(SteppedValueMeasure)
  MeasureWire(IdentityWireCursor, @encode.Writer)
  EmitPayloadKey(@encode.OrderedKeyEmitCursor)
  EmitPayload(IdentityWireCursor)
  EmitLogicalKey(@encode.OrderedKeyEmitCursor)
  EmitLogical(IdentityWireCursor)
  Done
}

///|
/// Identify the exact completed Relation without retaining a row-sized JSON
/// value or draining nested values within one advance. This owns the existing
/// export and receipt machinery, not a second identity or completion format.
struct CompletedRelationIdentityScan {
  mut stream : CompletedOutputExport?
  mut preparation : CompletedOutputExportPreparation?
  workspace : RowWorkspace
  max_work : Int
  mut work : Int
  mut column : Int
  mut phase : RelationIdentityPhase
  mut advancing : Bool
  mut closed : Bool
  mut fragment_peak : Int
  mut retained_body : Array[String]?
  mut retained_body_units : Int64
  mut completed_body : String?
  mut body_receipt : CompletedRelationExportReceipt?
}

///|
priv enum IdentityWireCursor {
  CapturedWire(@admitted.WireEmitCursor)
  TextWire(@encode.StringEmitCursor)
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
  incremental_metadata? : Bool = false,
  retain_body? : Bool = false,
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
  let preparation = match
    start_completed_export(
      source,
      None,
      max_rows,
      values,
      payload_wire,
      Some(logical_wire),
      Some(schema_limits),
      Int::max(1, payload_wire.max_bytes),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let stream = if incremental_metadata {
    None
  } else {
    match drain_completed_export_preparation(preparation) {
      Ok(value) => Some(value)
      Err(issue) => return Err(issue)
    }
  }
  Ok({
    stream,
    preparation: if incremental_metadata {
      Some(preparation)
    } else {
      None
    },
    workspace,
    max_work,
    work: 0,
    column: 0,
    phase: BeginRow,
    advancing: false,
    closed: false,
    fragment_peak: 0,
    retained_body: if retain_body { Some(["{\"sort\":\"relation\",\"value\":"]) } else { None },
    retained_body_units: if retain_body { 27L } else { 0L },
    completed_body: None,
    body_receipt: None,
  })
}

///|
fn identity_scan_cell(value : CompletedRelationIdentityScan) -> Value {
  let stream = value.stream.unwrap()
  let column = stream.order.columns[value.column].1
  IndexedRows::read_cell(stream.rows, stream.row, column)
}

///|
fn identity_scan_emit(
  cell : Value,
  writer : @encode.Writer,
) -> IdentityWireCursor raise @encode.EncodeFailure {
  match cell {
    Captured(value) => CapturedWire(@admitted.start_wire_emit(value, writer))
    Text(text) if text.length() > 64 =>
      TextWire(@encode.start_string_value(writer, text))
    scalar => ScalarWire(scalar, writer)
  }
}

///|
fn advance_identity_wire(
  cursor : IdentityWireCursor,
) -> Bool raise @encode.EncodeFailure {
  match cursor {
    CapturedWire(cursor) => @admitted.advance_wire_emit(cursor)
    TextWire(cursor) => @encode.advance_string_value(cursor)
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
    TextWire(cursor) => @encode.cancel_string_value(cursor)
    ScalarWire(_, _) => ()
  }
}

///|
/// Poison only this unfinished export. The completed input remains owned by
/// its producer, including when identity or cancellation fails.
pub fn cancel_completed_relation_identity_scan(
  value : CompletedRelationIdentityScan,
) -> Bool {
  if value.advancing { return false }
  if value.retained_body is Some(parts) { parts.clear() }
  value.retained_body = None
  value.completed_body = None
  value.body_receipt = None
  value.retained_body_units = 0L
  if value.closed { return false }
  match value.phase {
    MeasureName(cursor) | MeasureCell(cursor) => clear_stepped_measure(cursor)
    MeasureWire(cursor, _) | EmitPayload(cursor) | EmitLogical(cursor) =>
      cancel_identity_wire(cursor)
    EmitPayloadKey(cursor) | EmitLogicalKey(cursor) =>
      @encode.cancel_ordered_key(cursor)
    BeginRow | PrepareReferenceColumns | BeginColumn | Done => ()
  }
  if value.preparation is Some(preparation) {
    cancel_completed_output_export_preparation(preparation) |> ignore
    value.preparation = None
  }
  if value.stream is Some(stream) {
    cancel_completed_output_export(stream)
  }
  release_slots(value.workspace, value.workspace.live)
  value.closed = true
  true
}

///|
fn advance_identity_scan_frame(
  value : CompletedRelationIdentityScan,
  observed_source : CompletedOutput,
) -> Result[Unit, CompletedExportIssue] {
  if value.preparation is Some(preparation) {
    match
      advance_completed_export_metadata_owned(
        preparation,
        1,
        Some(observed_source),
      ) {
      Err(issue) => return Err(issue)
      Ok((done, _)) =>
        if done {
          match
            finish_completed_export_metadata_owned(
              preparation,
              Some(observed_source),
            ) {
            Err(issue) => return Err(issue)
            Ok(stream) => {
              value.stream = Some(stream)
              value.preparation = None
            }
          }
        }
    }
    return Ok(())
  }
  let stream = value.stream.unwrap()
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
        @encode.begin_ordered_object(stream.writer)
        if stream.logical_writer is Some(writer) {
          @encode.begin_ordered_object(writer)
        }
        value.column = 0
        if stream.references is Some(references) {
          if !reserve_slots(references.workspace, 1) {
            return Err(Admission(CaptureLimit))
          }
          references.rows.push([])
          value.phase = PrepareReferenceColumns
        } else {
          value.phase = BeginColumn
        }
      }
      PrepareReferenceColumns => {
        let references = stream.references.unwrap()
        let row = references.rows[stream.row]
        if row.length() == IndexedRows::column_count(stream.rows) {
          value.phase = BeginColumn
        } else {
          if !reserve_slots(references.workspace, 1) {
            return Err(Admission(CaptureLimit))
          }
          row.push([])
        }
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
              let column = stream.order.columns[value.column].1
              if !IndexedRows::cell_present(stream.rows, stream.row, column) {
                if !charge_node(stream.budget, 2) {
                  return Err(Admission(CaptureLimit))
                }
                value.column += 1
                value.phase = BeginColumn
                return Ok(())
              }
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
      MeasureWire(cursor, writer) => {
        if stream.references is Some(references) &&
          cursor is CapturedWire(captured) &&
          @admitted.wire_emit_next_reference(captured) is Some(reference) {
          if !@admitted.reference_available(reference) ||
            stream.source is None ||
            references.revoked ||
            !reserve_slots(references.workspace, 1) {
            return Err(Admission(InvalidCheckedRow))
          }
          let column = stream.order.columns[value.column].1
          references.rows[stream.row][column].push(Some(reference))
        }
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
          let name = stream.order.columns[column].0
          if name.length() > 64 {
            if !reserve_slots(value.workspace, 1) {
              return Err(Admission(CaptureLimit))
            }
            value.phase = EmitPayloadKey(
              @encode.start_ordered_key(stream.writer, name),
            )
          } else {
            @encode.ordered_key(stream.writer, name)
            value.phase = EmitPayload(identity_scan_emit(cell, stream.writer))
          }
        }
      }
      EmitPayloadKey(cursor) =>
        if @encode.advance_ordered_key(cursor) {
          release_slots(value.workspace, 1)
          value.phase = EmitPayload(
            identity_scan_emit(identity_scan_cell(value), stream.writer),
          )
        }
      EmitPayload(cursor) =>
        if advance_identity_wire(cursor) {
          if stream.logical_writer is Some(writer) {
            let name = stream.order.columns[value.column].0
            if name.length() > 64 {
              if !reserve_slots(value.workspace, 1) {
                return Err(Admission(CaptureLimit))
              }
              value.phase = EmitLogicalKey(
                @encode.start_ordered_key(writer, name),
              )
            } else {
              @encode.ordered_key(writer, name)
              value.phase = EmitLogical(
                identity_scan_emit(identity_scan_cell(value), writer),
              )
            }
          } else {
            return Err(Closed)
          }
        }
      EmitLogicalKey(cursor) =>
        if @encode.advance_ordered_key(cursor) {
          release_slots(value.workspace, 1)
          guard stream.logical_writer is Some(writer) else {
            return Err(Closed)
          }
          value.phase = EmitLogical(
            identity_scan_emit(identity_scan_cell(value), writer),
          )
        }
      EmitLogical(cursor) =>
        if advance_identity_wire(cursor) {
          value.column += 1
          value.phase = BeginColumn
        }
      Done => ()
    }
    // Retention selects these SAME emitted bytes, not another traversal/hash.
    // The caller's next construction quote includes their aggregate backing
    // before this bounded advance. No unfinished body is exposed.
    let fragment = @encode.drain_hash_output(stream.writer)
    value.fragment_peak = Int::max(value.fragment_peak, fragment.length())
    if value.retained_body is Some(parts) && !fragment.is_empty() {
      value.retained_body_units += fragment.length().to_int64()
      parts.push(fragment)
    }
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
  construction_capacity? : ExecutionCapacity? = None,
) -> Result[(Bool, Int), CompletedExportIssue] {
  if value.closed || value.advancing || quantum <= 0 {
    return Err(Closed)
  }
  let source = match (value.preparation, value.stream) {
    (Some(preparation), _) => preparation.source
    (None, Some(stream)) => stream.source
    _ => None
  }
  value.advancing = true
  guard source is Some(source) && completed_output_available(source) else {
    value.advancing = false
    cancel_completed_relation_identity_scan(value) |> ignore
    return Err(Unavailable)
  }
  let mut consumed = 0
  let mut issue : CompletedExportIssue? = None
  while consumed < quantum && !(value.phase is Done) {
    if value.work >= value.max_work {
      issue = Some(Admission(CaptureLimit))
      break
    }
    if construction_capacity is Some(held) {
      guard identity_scan_next_capacity(value) is Some(next) else {
        issue = Some(Closed)
        break
      }
      if execution_capacity_retained_bytes(next) >
        execution_capacity_retained_bytes(held) ||
        execution_capacity_execution_bytes(next) >
        execution_capacity_execution_bytes(held) {
        // Yield to the same caller BEFORE construction. These quantities
        // are a continuation boundary, never Resource authority.
        break
      }
    }
    value.work += 1
    consumed += 1
    match advance_identity_scan_frame(value, source) {
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
  let result = finish_completed_relation_export(value.stream.unwrap())
  let receipt = match result {
    Ok((receipt, tail)) => {
      if value.retained_body is Some(parts) {
        parts.push(tail)
        parts.push("}")
        value.completed_body = Some(parts.join(""))
        value.body_receipt = Some(receipt)
        parts.clear()
        value.retained_body = None
      }
      receipt
    }
    Err(issue) => {
      cancel_completed_relation_identity_scan(value) |> ignore
      return Err(issue)
    }
  }
  release_slots(value.workspace, value.workspace.live)
  value.closed = true
  Ok(receipt)
}

///|
/// The same completed scan/receipt's retained logical preimage. This is DATA,
/// not a current/access grant. No row admission, encoding or hash runs here.
pub fn completed_relation_identity_scan_body(
  value : CompletedRelationIdentityScan,
  receipt : CompletedRelationExportReceipt,
) -> String? {
  if value.closed && value.phase is Done &&
    value.body_receipt is Some(original) && physical_equal(original, receipt) {
    value.completed_body
  } else { None }
}

///|
/// Monotone work survives failure and cancellation; it is not rolled back
/// when an unfinished export is reclaimed.
pub fn completed_relation_identity_scan_work(
  value : CompletedRelationIdentityScan,
) -> Int64 {
  value.work.to_int64()
}

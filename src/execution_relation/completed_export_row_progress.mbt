///|
priv enum CompletedExportRowPhase {
  Begin
  PrepareReferenceColumns
  MeasureColumn
  MeasureName(SteppedValueMeasure)
  MeasureCell(SteppedValueMeasure)
  MeasureWire(SteppedRuntimeWire, @encode.Writer)
  BeginPayload
  BeginLogical
  EmitColumn(Bool)
  EmitKey(@encode.OrderedKeyEmitCursor, Bool)
  EmitCell(SteppedRuntimeWire, Bool)
  Complete
}

///|
/// One row borrows its immutable source until admission and both existing
/// canonical writers finish. Measurement precedes emission, preserving the
/// blocking export's ordered first-failure rules and logical value charges.
priv struct CompletedExportRowProgress {
  workspace : RowWorkspace
  mut column : Int
  mut wire_bound : Int
  mut full_wire_bound : Int
  mut wire_fits_batch : Bool
  mut phase : CompletedExportRowPhase
  mut closed : Bool
}

///|
pub(all) struct CompletedOutputExportAdvance {
  batch : String?
  complete : Bool
  steps : Int
}

///|
/// Container entries for the wrapper, a possible wire handle and the two
/// continuation frames per permitted nested level, including a spare frame.
pub fn completed_output_export_workspace_slots(
  values : ValueLimits,
  wire : RowWireLimits,
) -> Int? {
  let depth = Int::max(values.max_depth, wire.max_depth)
  if values.max_depth < 0 || wire.max_depth < 0 {
    None
  } else {
    Some(Int64::min(2147483647L, 8L + 2L * depth.to_int64()).to_int())
  }
}

///|
fn close_completed_export_row(cursor : CompletedExportRowProgress) -> Unit {
  if cursor.closed {
    return
  }
  match cursor.phase {
    MeasureName(measure) | MeasureCell(measure) =>
      clear_stepped_measure(measure)
    MeasureWire(wire, writer) => {
      close_stepped_runtime_wire(wire)
      @encode.cancel_writer(writer)
    }
    EmitCell(wire, _) => close_stepped_runtime_wire(wire)
    EmitKey(key, _) => {
      @encode.cancel_ordered_key(key)
      release_slots(cursor.workspace, 1)
    }
    _ => ()
  }
  // This private workspace also retains a speculative key reservation if
  // creation failed before the successor phase was installed.
  release_slots(cursor.workspace, cursor.workspace.live)
  cursor.closed = true
}

///|
fn completed_export_progress_cell(
  stream : CompletedOutputExport,
  cursor : CompletedExportRowProgress,
) -> Value {
  IndexedRows::read_cell(
    stream.rows,
    stream.row,
    stream.order.columns[cursor.column].1,
  )
}

///|
fn completed_export_progress_writer(
  stream : CompletedOutputExport,
  logical : Bool,
) -> @encode.Writer {
  if logical {
    stream.logical_writer.unwrap()
  } else {
    stream.writer
  }
}

///|
fn begin_completed_export_cell_wire(
  stream : CompletedOutputExport,
  cursor : CompletedExportRowProgress,
  writer : @encode.Writer,
) -> Result[SteppedRuntimeWire, CompletedExportIssue] {
  start_stepped_runtime_wire(
    completed_export_progress_cell(stream, cursor),
    writer,
    cursor.workspace,
  ).map_err(issue => {
    match issue {
      Workspace => Admission(CaptureLimit)
      Encoding(issue) => Wire(Encoding(issue))
    }
  })
}

///|
fn advance_completed_export_row_frame(
  stream : CompletedOutputExport,
  cursor : CompletedExportRowProgress,
) -> Result[Unit, CompletedExportIssue] {
  try {
    match cursor.phase {
      Begin => {
        if IndexedRows::row_width(stream.rows, stream.row) !=
          IndexedRows::column_count(stream.rows) {
          return Err(Wire(InvalidLayout))
        }
        if !charge_node(stream.budget, 1) {
          return Err(Admission(CaptureLimit))
        }
        if stream.references is Some(references) {
          if !reserve_slots(references.workspace, 1) {
            return Err(Admission(CaptureLimit))
          }
          references.rows.push([])
          cursor.phase = PrepareReferenceColumns
        } else {
          cursor.phase = MeasureColumn
        }
      }
      PrepareReferenceColumns => {
        let references = stream.references.unwrap()
        let row = references.rows[stream.row]
        if row.length() == IndexedRows::column_count(stream.rows) {
          cursor.phase = MeasureColumn
        } else {
          if !reserve_slots(references.workspace, 1) {
            return Err(Admission(CaptureLimit))
          }
          row.push([])
        }
      }
      MeasureColumn =>
        if cursor.column == stream.order.columns.length() {
          cursor.column = 0
          cursor.phase = BeginPayload
        } else {
          if !reserve_slots(cursor.workspace, 1) {
            return Err(Admission(CaptureLimit))
          }
          cursor.phase = MeasureName({
            frames: [SteppedTextNext(stream.order.columns[cursor.column].0, 0)],
            workspace: cursor.workspace,
            workspace_failed: false,
          })
        }
      MeasureName(measure) | MeasureCell(measure) =>
        match advance_stepped_measure_result(measure, stream.budget) {
          SteppedMeasureContinue => ()
          SteppedMeasureLimit | SteppedMeasureWorkspaceLimit =>
            return Err(Admission(CaptureLimit))
          SteppedMeasureComplete => {
            clear_stepped_measure(measure)
            if cursor.phase is MeasureName(_) {
              let column = stream.order.columns[cursor.column].1
              if !IndexedRows::cell_present(stream.rows, stream.row, column) {
                if !charge_node(stream.budget, 2) {
                  return Err(Admission(CaptureLimit))
                }
                cursor.column += 1
                cursor.phase = MeasureColumn
              } else {
                guard start_stepped_measure_result(
                    completed_export_progress_cell(stream, cursor),
                    cursor.workspace,
                  )
                  is Some(measure) else {
                  return Err(Admission(CaptureLimit))
                }
                cursor.phase = MeasureCell(measure)
              }
            } else {
              let writer = @encode.measuring_writer(
                stream.measurement_max_bytes,
                stream.measurement_max_nodes,
                stream.measurement_max_depth,
              )
              let wire = match
                begin_completed_export_cell_wire(stream, cursor, writer) {
                Ok(wire) => wire
                Err(issue) => {
                  @encode.cancel_writer(writer)
                  return Err(issue)
                }
              }
              cursor.phase = MeasureWire(wire, writer)
            }
          }
        }
      MeasureWire(wire, writer) => {
        if stream.references is Some(references) &&
          wire.cursor is CapturedWire(captured) &&
          @admitted.wire_emit_next_reference(captured) is Some(reference) {
          if !@admitted.reference_available(reference) ||
            stream.source is None ||
            references.revoked ||
            !reserve_slots(references.workspace, 1) {
            return Err(Admission(InvalidCheckedRow))
          }
          let column = stream.order.columns[cursor.column].1
          references.rows[stream.row][column].push(Some(reference))
        }
        match advance_stepped_runtime_wire(wire) {
          Err(Workspace) => return Err(Admission(CaptureLimit))
          Err(Encoding(issue)) => return Err(Wire(Encoding(issue)))
          Ok(false) => ()
          Ok(true) => {
            let (bytes, nodes, depth) = @encode.finish_measurement_usage(writer)
            let column = cursor.column
            // Reuse this actual cell's existing wire measurement. Six bytes
            // per UTF-16 key unit bounds escaping without walking it again;
            // quotes, colon and a separator add four. Saturate at the SAME
            // batch ceiling instead of overflowing or admitting a larger row.
            // A sound measured row/frame construction bound is independent
            // of the earlier-drain hint, which may stop growing at its ceiling.
            // Int saturation is safe because no physical frame can exceed it.
            cursor.full_wire_bound = Int64::min(
              2147483647L,
              cursor.full_wire_bound.to_int64() +
              bytes.to_int64() +
              4L +
              6L * stream.order.columns[column].0.length().to_int64(),
            ).to_int()
            if stream.batch_mode == 2 && cursor.wire_fits_batch {
              let room = stream.max_batch_bytes - cursor.wire_bound
              let units = stream.order.columns[column].0.length()
              if room < 4 || bytes > room - 4 || units > (room - 4 - bytes) / 6 {
                cursor.wire_fits_batch = false
              } else {
                cursor.wire_bound += bytes + 4 + 6 * units
              }
            }
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
            let cell = completed_export_progress_cell(stream, cursor)
            if cell is Null || cell is Captured(@admitted.Null) {
              stream.column_null_rows[column] += 1
            }
            cursor.column += 1
            cursor.phase = MeasureColumn
          }
        }
      }
      BeginPayload | BeginLogical => {
        let logical = cursor.phase is BeginLogical
        @encode.begin_ordered_object(
          completed_export_progress_writer(stream, logical),
        )
        cursor.phase = EmitColumn(logical)
      }
      EmitColumn(logical) => {
        let writer = completed_export_progress_writer(stream, logical)
        if cursor.column == stream.order.columns.length() {
          @encode.end_object(writer)
          cursor.column = 0
          cursor.phase = if !logical && stream.logical_writer is Some(_) {
            BeginLogical
          } else {
            Complete
          }
        } else {
          let (name, column) = stream.order.columns[cursor.column]
          if !IndexedRows::cell_present(stream.rows, stream.row, column) {
            cursor.column += 1
          } else if name.length() > 64 {
            if !reserve_slots(cursor.workspace, 1) {
              return Err(Admission(CaptureLimit))
            }
            cursor.phase = EmitKey(
              @encode.start_ordered_key(writer, name),
              logical,
            )
          } else {
            @encode.ordered_key(writer, name)
            let wire = match
              begin_completed_export_cell_wire(stream, cursor, writer) {
              Ok(wire) => wire
              Err(issue) => return Err(issue)
            }
            cursor.phase = EmitCell(wire, logical)
          }
        }
      }
      EmitKey(key, logical) =>
        if @encode.advance_ordered_key(key) {
          release_slots(cursor.workspace, 1)
          // Clear key custody before a fallible successor allocation.
          cursor.phase = EmitColumn(logical)
          let wire = match
            begin_completed_export_cell_wire(
              stream,
              cursor,
              completed_export_progress_writer(stream, logical),
            ) {
            Ok(wire) => wire
            Err(issue) => return Err(issue)
          }
          cursor.phase = EmitCell(wire, logical)
        }
      EmitCell(wire, logical) =>
        match advance_stepped_runtime_wire(wire) {
          Err(Workspace) => return Err(Admission(CaptureLimit))
          Err(Encoding(issue)) => return Err(Wire(Encoding(issue)))
          Ok(false) => ()
          Ok(true) => {
            cursor.column += 1
            cursor.phase = EmitColumn(logical)
          }
        }
      Complete => ()
    }
    Ok(())
  } catch {
    issue => Err(Wire(Encoding(issue)))
  }
}

///|
/// A poll yields within a row, not only between rows. Provisional bytes stay
/// private until the complete row can be returned to the existing Store owner.
/// Traversal steps do not replace or double-charge logical value work.
pub fn advance_completed_output_export(
  stream : CompletedOutputExport,
  quantum : Int,
  max_workspace_slots : Int,
  batch? : Bool = false,
  before_batch_growth? : ((Int) -> Result[Bool, CompletedExportIssue])? = None,
) -> Result[CompletedOutputExportAdvance, CompletedExportIssue] {
  if stream.reading {
    return Err(Closed)
  }
  stream.poll_steps = 0
  if quantum <= 0 {
    return Err(Closed)
  }
  if max_workspace_slots < 0 {
    return Err(Admission(InvalidCaptureLimits))
  }
  stream.reading = true
  let result = (fn() -> Result[
    CompletedOutputExportAdvance,
    CompletedExportIssue,
  ] {
    guard stream.source is Some(source) else { return Err(Closed) }
    if !completed_output_available(source) {
      return Err(Unavailable)
    }
    if stream.source is None {
      return Err(Closed)
    }
    let mode = if batch { 2 } else { 1 }
    if stream.batch_mode != 0 && stream.batch_mode != mode {
      return Err(Closed)
    }
    stream.batch_mode = mode
    if stream.row == IndexedRows::row_count(stream.rows) {
      return Ok({ batch: None, complete: true, steps: 0, })
    }
    for step in 0..<quantum {
      if stream.source is None {
        return Err(Closed)
      }
      if stream.pending_row is None {
        // A batch must retain the original per-row availability fence even
        // when the next row starts within this same finite poll.
        if step > 0 && !completed_output_available(source) {
          return Err(Unavailable)
        }
        if stream.source is None {
          return Err(Closed)
        }
        let workspace = row_workspace(max_workspace_slots)
        if !reserve_slots(workspace, 1) {
          return Err(Admission(CaptureLimit))
        }
        stream.pending_row = Some({
          workspace,
          column: 0,
          wire_bound: 3,
          full_wire_bound: 3,
          wire_fits_batch: stream.max_batch_bytes >= 3,
          phase: Begin,
          closed: false,
        })
      }
      let cursor = stream.pending_row.unwrap()
      if max_workspace_slots != cursor.workspace.limit {
        return Err(Admission(InvalidCaptureLimits))
      }
      if batch && cursor.phase is BeginPayload && stream.row > 0 {
        let pending = @encode.observed_writer_usage(stream.writer).0 -
          stream.drained_bytes
        if pending > 0 &&
          (
            !cursor.wire_fits_batch ||
            cursor.wire_bound > stream.max_batch_bytes - pending
          ) {
          let part = @encode.drain_hash_output(stream.writer) catch {
            issue => return Err(Wire(Encoding(issue)))
          }
          stream.drained_bytes = @encode.observed_writer_usage(stream.writer).0
          return Ok({ batch: Some(part), complete: false, steps: step, })
        }
      }
      if cursor.phase is BeginPayload && before_batch_growth is Some(reserve) {
        let pending = @encode.observed_writer_usage(stream.writer).0 -
          stream.drained_bytes
        // Cell bytes were measured by this same traversal. The existing key
        // escape bound covers this row, never the configured future frame.
        let next = Int64::min(
          stream.max_batch_bytes.to_int64(),
          pending.to_int64() + cursor.full_wire_bound.to_int64(),
        ).to_int()
        let funded = match reserve(next) {
          Err(issue) => return Err(issue)
          Ok(value) => value
        }
        if stream.source is None ||
          !completed_output_available(source) ||
          stream.source is None {
          return Err(Unavailable)
        }
        if !funded {
          // Only a definite pre-acquisition policy refusal can defer by
          // flushing earlier complete rows. Unknown growth returns Err.
          if pending > 0 && stream.row > 0 {
            let part = @encode.drain_hash_output(stream.writer) catch {
              issue => return Err(Wire(Encoding(issue)))
            }
            stream.drained_bytes = @encode.observed_writer_usage(stream.writer).0
            return Ok({ batch: Some(part), complete: false, steps: step, })
          }
          return Err(Admission(CaptureLimit))
        }
      }
      // Record entry before a frame can fail and clear its private cursor.
      // This is traversal progress, not another logical value-admission charge.
      stream.poll_steps += 1
      match advance_completed_export_row_frame(stream, cursor) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      if stream.source is None {
        return Err(Closed)
      }
      if cursor.phase is Complete {
        close_completed_export_row(cursor)
        stream.pending_row = None
        stream.row += 1
        let bytes = @encode.observed_writer_usage(stream.writer).0
        if !batch ||
          stream.row == IndexedRows::row_count(stream.rows) ||
          bytes - stream.drained_bytes == stream.max_batch_bytes {
          let part = @encode.drain_hash_output(stream.writer) catch {
            issue => return Err(Wire(Encoding(issue)))
          }
          stream.drained_bytes = bytes
          return Ok({ batch: Some(part), complete: false, steps: step + 1, })
        }
      }
    }
    Ok({ batch: None, complete: false, steps: quantum, })
  })()
  stream.reading = false
  if result is Err(_) {
    cancel_completed_output_export(stream)
  }
  result
}

///|
/// Actual transitions entered by the last poll, including a failing frame.
/// Cancellation retains this observation; the next poll resets it.
pub fn completed_output_export_poll_steps(
  stream : CompletedOutputExport,
) -> Int {
  stream.poll_steps
}

///|
/// Constant-time completion observation; it enters no new row frame. This is
/// not a canonical receipt or permission to release the borrowed producer.
pub fn completed_output_export_rows_complete(
  stream : CompletedOutputExport,
) -> Result[Bool, CompletedExportIssue] {
  guard stream.source is Some(source) else { return Err(Closed) }
  if !completed_output_available(source) {
    return Err(Unavailable)
  }
  Ok(stream.row == IndexedRows::row_count(stream.rows))
}

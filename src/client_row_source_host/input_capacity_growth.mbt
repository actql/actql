///|
// Construction DATA/cursors on the existing RowRun, not another Resource,
// input, admission verdict or cleanup owner. Actual pages grow this same
// reservation; advertised future retention/wire ceilings do not allocate it.
priv struct RowInputProgress {
  mut nodes : Int64
  mut text : Int64
  mut rows : Int64
  mut tokens : Int64
  mut working_frames : Int
  mut preflight : @source.JsonSourcePreflight?
  mut parser : @source.JsonParse?
}

///|
fn cancel_row_input_progress(run : RowRun) -> Unit {
  if run.input_progress is Some(progress) {
    if progress.preflight is Some(cursor) {
      @source.cancel_json_source_preflight(cursor)
      progress.preflight = None
    }
    if progress.parser is Some(cursor) {
      @source.cancel_json_parse(cursor)
      progress.parser = None
    }
  }
}

///|
fn row_input_read_current(run : RowRun, read : RowSourceRead) -> Bool {
  !run.closed &&
  read.open &&
  run.attempt.state is Reading(original) &&
  physical_equal(original, read)
}

///|
// Counts are upper bounds on ACTUALLY received/borrowed page occurrences.
// Typed values stay with the same provider original until physical cleanup;
// only their checked row/presence arrays are constructed by this receiver.
fn fund_row_input_page(
  run : RowRun,
  read : RowSourceRead,
  nodes : Int64,
  text : Int64,
  rows : Int64,
  body_bytes : Int,
  geometry : @source.JsonSourceGeometry?,
) -> Result[Unit, RowHostIssue] {
  guard run.configuration is InputConfiguration(acquisition) &&
    run.input_progress is Some(progress) &&
    row_input_read_current(run, read) else {
    return Err(InvalidState)
  }
  guard @execution.checked_preparation_add_product(progress.nodes, nodes, 1L)
    is Some(next_nodes) &&
    @execution.checked_preparation_add_product(progress.text, text, 1L)
    is Some(next_text) &&
    @execution.checked_preparation_add_product(progress.rows, rows, 1L)
    is Some(next_rows) &&
    row_input_phase_capacity(
      acquisition.preparation,
      next_nodes,
      next_text,
      next_rows,
      progress.tokens,
      body_bytes,
      geometry,
    )
    is Some(capacity) else {
    return Err(Physical(InvalidLimits))
  }
  let capacity = match
    row_input_working_capacity(capacity, progress.working_frames) {
    Some(value) => value
    None => return Err(Physical(InvalidLimits))
  }
  match grow_row_input_capacity(run, acquisition, capacity) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if !row_input_read_current(run, read) {
    return Err(InvalidState)
  }
  progress.nodes = next_nodes
  progress.text = next_text
  progress.rows = next_rows
  Ok(())
}

///|
// Physical bytes are charged by the original page ticket before this entry.
// Fund UTF8 decoding/preflight, then the actual Source geometry before tree,
// indexed decode and typed admission. Transfer the SAME preserving parser.
fn prepare_row_input_page(
  run : RowRun,
  read : RowSourceRead,
  body : Bytes,
) -> Result[@source.Node, RowHostIssue] {
  if body.length() > read.page_limits.max_bytes || read.listing is Some(_) {
    return Err(Source(InvalidPage))
  }
  match fund_row_input_page(run, read, 0L, 0L, 0L, body.length(), None) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let text = @utf8.decode(body) catch { _ => return Err(Source(InvalidPage)) }
  let cursor = match
    @source.start_json_source_preflight(
      text,
      {
        max_input_bytes: read.page_limits.max_bytes,
        max_nodes: read.page_limits.max_nodes,
        max_depth: read.page_limits.max_depth,
      },
      data_keys=true,
    ) {
    Ok(value) => value
    Err(_) => return Err(Source(InvalidPage))
  }
  let progress = run.input_progress.unwrap()
  progress.preflight = Some(cursor)
  let actual = while true {
    match @source.advance_json_source_preflight(cursor, 1024) {
      Ok(JsonSourceContinue(_)) => ()
      Ok(JsonSourceReady(actual, ..)) => break actual
      _ => return Err(Source(InvalidPage))
    }
  } nobreak {
    return Err(Source(InvalidPage))
  }
  match
    fund_row_input_page(
      run,
      read,
      actual.node_upper.to_int64(),
      actual.input_bytes.to_int64(),
      actual.objects.to_int64(),
      body.length(),
      Some(actual),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let parser = match @source.take_json_source_parser(cursor) {
    Ok(value) => value
    Err(_) => return Err(Source(InvalidPage))
  }
  progress.preflight = None
  progress.parser = Some(parser)
  while true {
    match @source.advance_json_parse(parser, 1024) {
      Ok(JsonParseContinue(_)) => ()
      Ok(JsonParseComplete(parsed, ..)) => {
        progress.parser = None
        return Ok(parsed.node)
      }
      _ => return Err(Source(InvalidPage))
    }
  } nobreak {
    Err(Source(InvalidPage))
  }
}

///|
// Existing validators use one key's tuple/map at a time, then retire it before
// moving to another key. The hashing writer emits incrementally: no full
// future max_bytes wire is constructed. Cover actual rows/schema/value nodes
// plus its shared writer inventory before constructing either original cursor.
fn fund_row_input_capture(
  run : RowRun,
  acquisition : RowInputAcquisition,
  rows : @execution.CapturedRows,
) -> Result[Unit, RowHostIssue] {
  guard run.input_progress is Some(progress) else { return Err(InvalidState) }
  let usage = @execution.captured_usage(rows)
  let count = @execution.captured_row_count(rows).to_int64()
  let width = @schema.field_count(acquisition.preparation.schema).to_int64()
  progress.nodes = Int64::max(progress.nodes, usage.nodes.to_int64())
  progress.text = Int64::max(progress.text, usage.text_bytes.to_int64())
  progress.rows = Int64::max(progress.rows, count)
  guard row_input_phase_capacity(
      acquisition.preparation,
      progress.nodes,
      progress.text,
      progress.rows,
      progress.tokens,
      0,
      None,
    )
    is Some(base) &&
    @shape.collection_construction_extent({
      // Same validation control, key cursor, current tuple and Map entries;
      // score iterator, supplied-read and row-identity column permutations.
      records: 32L + count * (width + 1L),
      record_references: 64L + count * width,
      record_words: 64L + count * width,
      reference_arrays: count + 6L,
      reference_items: (count + 4L) * width,
      scalar_arrays: 3L,
      scalar_items: width * 3L,
      maps: 1L,
      map_entries: count,
    })
    is Some(validation) &&
    @execution.preparation_representation_cost({
      record_headers: validation.record_headers,
      reference_slots: validation.reference_slots,
      scalar_words: validation.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(validation_bytes) else {
    return Err(Physical(InvalidLimits))
  }
  let keys = usage.nodes.to_int64() + width + 16L
  if keys > 2147483647L {
    return Err(Physical(InvalidLimits))
  }
  guard @encode.hash_writer_live_key_inventory(
      keys.to_int(),
      Int::min(acquisition.preparation.limits.wire.max_depth, keys.to_int()),
    )
    is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers,
      reference_slots: writer.reference_slots,
      scalar_words: writer.scalar_words,
      owned_utf16_units: writer.owned_utf16_units,
      owned_wire_bytes: writer.owned_wire_bytes,
    })
    is Some(writer_bytes) &&
    @execution.checked_preparation_add_product(
      @execution.execution_capacity_execution_bytes(base),
      validation_bytes,
      1L,
    )
    is Some(execution) &&
    @execution.checked_preparation_add_product(execution, writer_bytes, 1L)
    is Some(execution) &&
    @execution.execution_capacity(
      @execution.execution_capacity_retained_bytes(base),
      execution,
    )
    is Some(capacity) else {
    return Err(Physical(InvalidLimits))
  }
  let capacity = match
    row_input_working_capacity(capacity, progress.working_frames) {
    Some(value) => value
    None => return Err(Physical(InvalidLimits))
  }
  grow_row_input_capacity(run, acquisition, capacity)
}

///|
fn row_input_capture_retained(run : RowRun) -> Int64? {
  guard run.configuration is InputConfiguration(acquisition) &&
    run.input_progress is Some(progress) &&
    row_input_phase_capacity(
      acquisition.preparation,
      progress.nodes,
      progress.text,
      progress.rows,
      progress.tokens,
      0,
      None,
    )
    is Some(capacity) else {
    return None
  }
  Some(@execution.execution_capacity_retained_bytes(capacity))
}

///|
priv enum RowInputValueFrame {
  Value(@admitted.Value)
  ArrayNext(@admitted.FrozenArray[@admitted.Value], Int)
  ObjectNext(@admitted.FrozenArray[(String, @admitted.Value)], Int)
}

///|
// One page-local geometry walk over immutable provider DATA. It reuses one
// pending buffer across cells. Local counters do not cross Resource/current
// boundaries; only an exhausted frame window asks for a larger buffer chunk.
fn count_row_input_values(
  rows : Array[Array[@admitted.CheckedValue]],
  initial_frames : Int,
  grow_frames : (Int) -> Result[Unit, RowHostIssue],
) -> Result[(Int64, Int64, Int), RowHostIssue] {
  if initial_frames < 1 {
    return Err(InvalidState)
  }
  let mut window = initial_frames
  let mut nodes = 0L
  let mut text = 0L
  let pending : Array[RowInputValueFrame] = []
  for row in rows {
    for checked in row {
      guard @execution.checked_preparation_add_product(nodes, 2L, 1L)
        is Some(next_nodes) else {
        return Err(Physical(InvalidLimits))
      }
      nodes = next_nodes
      pending.push(Value(checked.value))
      while pending.pop() is Some(frame) {
        let pushes = match frame {
          Value(@admitted.Array(values)) =>
            if @admitted.element_count(values) == 0 {
              0
            } else {
              1
            }
          Value(@admitted.Object(values)) =>
            if @admitted.element_count(values) == 0 {
              0
            } else {
              1
            }
          Value(@admitted.JsonData(_)) => 1
          Value(_) => 0
          ArrayNext(values, index) =>
            if index + 1 < @admitted.element_count(values) {
              2
            } else {
              1
            }
          ObjectNext(values, index) =>
            if index + 1 < @admitted.element_count(values) {
              2
            } else {
              1
            }
        }
        if pending.length() > window - pushes {
          if window > 1073741823 {
            return Err(Physical(InvalidLimits))
          }
          let next = window * 2
          match grow_frames(next) {
            Ok(_) => window = next
            Err(issue) => return Err(issue)
          }
        }
        let (more_nodes, more_text, next) = match frame {
          Value(value) =>
            match value {
              @admitted.Null
              | @admitted.Boolean(_)
              | @admitted.Number(_)
              | @admitted.Signed64(_) => (0L, 0L, None)
              @admitted.Text(text)
              | @admitted.Date(text)
              | @admitted.Timestamp(text) =>
                (0L, text.length().to_int64() * 3L, None)
              @admitted.Decimal(value) =>
                (0L, value.coefficient.length().to_int64() * 3L, None)
              @admitted.Reference(value) =>
                (
                  0L,
                  @admitted.reference_wire(value).length().to_int64() * 3L,
                  None,
                )
              @admitted.Vector(values) =>
                (@admitted.element_count(values).to_int64() * 2L, 0L, None)
              @admitted.Array(values) => {
                let count = @admitted.element_count(values)
                (
                  count.to_int64() * 2L,
                  0L,
                  if count == 0 {
                    None
                  } else {
                    Some(ArrayNext(values, 0))
                  },
                )
              }
              @admitted.Object(values) => {
                let count = @admitted.element_count(values)
                (
                  count.to_int64() * 3L,
                  0L,
                  if count == 0 {
                    None
                  } else {
                    Some(ObjectNext(values, 0))
                  },
                )
              }
              @admitted.JsonData(value) => (2L, 0L, Some(Value(value)))
            }
          ArrayNext(values, index) => {
            let value = @admitted.element_at(values, index).unwrap()
            if index + 1 < @admitted.element_count(values) {
              pending.push(ArrayNext(values, index + 1))
            }
            (0L, 0L, Some(Value(value)))
          }
          ObjectNext(values, index) => {
            let (name, value) = @admitted.element_at(values, index).unwrap()
            if index + 1 < @admitted.element_count(values) {
              pending.push(ObjectNext(values, index + 1))
            }
            (0L, name.length().to_int64() * 3L, Some(Value(value)))
          }
        }
        guard @execution.checked_preparation_add_product(nodes, more_nodes, 1L)
          is Some(next_nodes) &&
          @execution.checked_preparation_add_product(text, more_text, 1L)
          is Some(next_text) else {
          return Err(Physical(InvalidLimits))
        }
        nodes = next_nodes
        text = next_text
        if next is Some(frame) {
          pending.push(frame)
        }
      }
    }
  }
  Ok((nodes, text, window))
}

///|
// Same shared constructor owner for the metadata walk and existing input
// measurement stack. Doubling is actual buffer growth, not a future data cap.
fn row_input_working_capacity(
  base : @execution.ExecutionCapacity,
  frames : Int,
) -> @execution.ExecutionCapacity? {
  if frames == 0 {
    return Some(base)
  }
  let slots = frames.to_int64()
  guard @shape.collection_construction_extent({
      records: slots * 2L + 8L,
      record_references: slots * 2L + 8L,
      record_words: slots * 4L + 8L,
      reference_arrays: 2L,
      reference_items: slots * 2L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(buffer) &&
    @execution.preparation_representation_cost({
      record_headers: buffer.record_headers,
      reference_slots: buffer.reference_slots,
      scalar_words: buffer.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(bytes) &&
    @execution.checked_preparation_add_product(
      @execution.execution_capacity_execution_bytes(base),
      bytes,
      1L,
    )
    is Some(execution) else {
    return None
  }
  @execution.execution_capacity(
    @execution.execution_capacity_retained_bytes(base),
    execution,
  )
}

///|
fn fund_row_input_value_window(
  run : RowRun,
  read : RowSourceRead,
  frames : Int,
) -> Result[Unit, RowHostIssue] {
  guard run.configuration is InputConfiguration(acquisition) &&
    run.input_progress is Some(progress) &&
    row_input_read_current(run, read) else {
    return Err(InvalidState)
  }
  if frames <= progress.working_frames {
    return Ok(())
  }
  guard row_input_phase_capacity(
      acquisition.preparation,
      progress.nodes,
      progress.text,
      progress.rows,
      progress.tokens,
      0,
      None,
    )
    is Some(base) &&
    row_input_working_capacity(base, frames) is Some(capacity) else {
    return Err(Physical(InvalidLimits))
  }
  match grow_row_input_capacity(run, acquisition, capacity) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if !row_input_read_current(run, read) {
    return Err(InvalidState)
  }
  progress.working_frames = frames
  Ok(())
}

///|
fn fund_row_input_values(
  run : RowRun,
  read : RowSourceRead,
  rows : Array[Array[@admitted.CheckedValue]],
) -> Result[Unit, RowHostIssue] {
  let width = read.columns.length().to_int64()
  match
    fund_row_input_page(
      run,
      read,
      rows.length().to_int64() * (2L * width + 1L),
      0L,
      rows.length().to_int64(),
      0,
      None,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if rows.is_empty() || read.columns.is_empty() {
    return Ok(())
  }
  match fund_row_input_value_window(run, read, 16) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let progress = run.input_progress.unwrap()
  let (nodes, text, _) = match
    count_row_input_values(rows, progress.working_frames, frames => {
      fund_row_input_value_window(run, read, frames)
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Only this completed page total crosses the expensive layout/current edge.
  fund_row_input_page(run, read, nodes, text, 0L, 0, None)
}

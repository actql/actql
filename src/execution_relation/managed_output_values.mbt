///|
/// New-profile value admission without row-array canonical encoding or hashing.
/// This is provisional content evidence, not execution, retention, permission,
/// or a substitute for any required logical identity.
struct ManagedOutputValues {
  carrier_binding : @managed_carrier.Binding
  owner : @lower.BoundPrepared
  target : @pipeline.Target
  buffer : AdmittedRowBuffer
  measurement : FixedInputGuardBudget
  initial : FixedInputGuardMeasureLimits
  mut producer : FixedProducerMeasurement?
  mut managed_producer : ManagedProducerMeasurement?
  mut column_usage : Array[(Int, Int)]
  mut column_maxima : Array[Int]
  mut column_nulls : Array[Int]
  mut reference_rows : Array[Array[Array[@admitted.ReferenceValue?]]]
  mut row_measurements : ManagedRowMeasurements?
  mut finish_started : Bool
  mut finish_cursor : ManagedOutputFinishCursor?
  max_value_bytes : Int
  max_rows : Int
  mut rows : Int
  mut open : Bool
  mut reading : Bool
  mut active_uses : Int
  mut disposal_requested : Bool
  mut disposal_complete : Bool
  mut reclamation_steps : Int64
  mut issue : FixedInputGuardIssue?
}

///|
/// Separate from the old CID-bearing receipt: no missing/dummy CID can enter an
/// old completion through this type. No data buffers or source read handles
/// escape. Opaque reference authority handles remain occurrence-scoped so a
/// later checked reader never fabricates issuer evidence from wire bytes.
struct ManagedOutputValueReceipt {
  carrier_receipt : @managed_carrier.Receipt
  owner : @lower.BoundPrepared
  target : @pipeline.Target
  schema : @schema.Schema
  rows : Int
  usage : ValueUsage
  measured : (Int, Int, Int)
  fixed_measurement : (Ref[Bool], (Int, Int, Int))?
  managed_measurement : (Ref[Bool], (Int, Int, Int))?
  column_usage : Array[(Int, Int)]
  column_maxima : Array[Int]
  column_nulls : Array[Int]
  reference_rows : Array[Array[Array[@admitted.ReferenceValue]]]
  measured_depth : Int
  mut row_measurements : ManagedRowMeasurements?
}

///|
pub(all) enum ManagedOutputValueIssue {
  Admission(CaptureIssue)
  Guard(FixedInputGuardIssue)
  Closed
  MeasurementIndexLimit
  ReferenceUnavailable(Int, Int)
}

///|
pub fn prepare_managed_output_values(
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  max_rows : Int,
  values : ValueLimits,
  max_value_bytes : Int,
  measurement : FixedInputGuardMeasureLimits,
  working? : GeneratedSequence? = None,
) -> Result[ManagedOutputValues, ManagedOutputValueIssue] {
  if max_value_bytes < 0 ||
    measurement.max_work < 0 ||
    measurement.max_bytes < 0 ||
    measurement.max_nodes < 0 ||
    measurement.max_depth < 0 {
    return Err(Guard(InvalidLimits))
  }
  let preparation = match working {
    Some(generated) => {
      if !physical_equal(generated_sequence_owner(generated), owner) {
        return Err(Admission(InvalidCheckedRow))
      }
      prepare_bounded_sequence_admitted_output(
        generated, target, max_rows, values,
      )
    }
    None => prepare_admitted_output(owner, target, max_rows, values)
  }
  let output = match preparation {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  if !prepare_managed_output_scratch(output.buffer.budget, output.buffer.schema) {
    return Err(Admission(CaptureLimit))
  }
  let carrier_binding = match @managed_carrier.prepare_binding(owner, target) {
    Ok(value) => value
    Err(_) => return Err(Admission(InvalidCheckedRow))
  }
  if @managed_carrier.binding_kind(carrier_binding) != @carrier.RelationKind {
    return Err(Admission(InvalidCheckedRow))
  }
  Ok({
    carrier_binding,
    owner,
    target,
    buffer: output.buffer,
    measurement: {
      work: measurement.max_work,
      bytes: measurement.max_bytes,
      nodes: measurement.max_nodes,
      depth: measurement.max_depth,
    },
    initial: measurement,
    producer: None,
    managed_producer: None,
    column_usage: Array::make(@schema.field_count(output.buffer.schema), (0, 0)),
    column_maxima: Array::make(@schema.field_count(output.buffer.schema), 0),
    column_nulls: Array::make(@schema.field_count(output.buffer.schema), 0),
    reference_rows: [],
    row_measurements: None,
    finish_started: false,
    finish_cursor: None,
    max_value_bytes,
    max_rows,
    rows: 0,
    open: true,
    reading: false,
    active_uses: 0,
    disposal_requested: false,
    disposal_complete: false,
    reclamation_steps: 0L,
    issue: None,
  })
}

///|
pub fn cancel_managed_output_values(value : ManagedOutputValues) -> Bool {
  if !value.open {
    return false
  }
  request_managed_output_values_disposal(value)
  true
}

///|
/// Revoke the original admission buffer without performing cleanup work.
/// The existing reclamation cursor owns all subsequent bounded retirement.
pub fn request_managed_output_values_disposal(
  value : ManagedOutputValues,
) -> Unit {
  if !value.disposal_requested {
    value.buffer.reclaiming = true
  }
  value.disposal_requested = true
  value.open = false
  value.buffer.open = false
}

///|
/// Retire only admission-owned scratch. A finished receipt keeps its copied
/// facts and transferred index; it remains available under its separate owner.
/// This is safe after cancellation, failed finish, or successful completion.
pub fn dispose_managed_output_values_scratch(
  value : ManagedOutputValues,
) -> Unit {
  request_managed_output_values_disposal(value)
  advance_managed_output_values_reclamation(value, 64) |> ignore
}

///|
/// Retire at most quantum private entries. Revocation and the release witness
/// are separate: a caller must retain this owner until reclamation completes.
/// This bounds reference retirement, not collector or allocator latency.
pub fn advance_managed_output_values_reclamation(
  value : ManagedOutputValues,
  quantum : Int,
) -> Bool {
  if value.disposal_complete {
    return true
  }
  if !value.disposal_requested || quantum <= 0 {
    return false
  }
  // Revocation is immediate; destructive cleanup waits for stack ownership
  // to unwind, including callbacks within measurement and representation IO.
  if value.active_uses != 0 || value.buffer.reading {
    return false
  }
  // A reserved view/verification port also uses reading. Once every active
  // frame has returned, disposal ends that reservation as well.
  value.reading = false
  for _ in 0..<quantum {
    if value.buffer.reclaiming {
      advance_admitted_buffer_reclamation(value.buffer, 1) |> ignore
    } else if value.row_measurements is Some(index) {
      discard_managed_row_measurements(index)
      value.row_measurements = None
    } else if value.finish_cursor is Some(cursor) {
      // Partial receipt copies remain admission-owned until issuance. Scrub
      // each container root before popping it, including Native backing slots.
      if cursor.references.last() is Some(row) {
        if !row.is_empty() {
          row[row.length() - 1] = []
          row.pop() |> ignore
        } else {
          cursor.references[cursor.references.length() - 1] = []
          cursor.references.pop() |> ignore
        }
      } else if !cursor.column_usage.is_empty() {
        cursor.column_usage.pop() |> ignore
      } else if !cursor.column_maxima.is_empty() {
        cursor.column_maxima.pop() |> ignore
      } else if !cursor.column_nulls.is_empty() {
        cursor.column_nulls.pop() |> ignore
      } else {
        value.finish_cursor = None
      }
    } else if value.reference_rows.last() is Some(row) {
      if row.last() is Some(references) {
        if references.is_empty() {
          row[row.length() - 1] = []
          row.pop() |> ignore
        } else {
          // Native/Wasm backing storage can retain popped entries. Scrub
          // authority handles without fabricating a replacement reference.
          references[references.length() - 1] = None
          references.pop() |> ignore
        }
      } else {
        value.reference_rows[value.reference_rows.length() - 1] = []
        value.reference_rows.pop() |> ignore
      }
    } else if !value.column_usage.is_empty() {
      value.column_usage.pop() |> ignore
    } else if !value.column_maxima.is_empty() {
      value.column_maxima.pop() |> ignore
    } else if !value.column_nulls.is_empty() {
      value.column_nulls.pop() |> ignore
    } else {
      break
    }
    value.reclamation_steps += 1L
  }
  if value.buffer.reclaiming ||
    value.row_measurements is Some(_) ||
    value.finish_cursor is Some(_) ||
    !value.reference_rows.is_empty() ||
    !value.column_usage.is_empty() ||
    !value.column_maxima.is_empty() ||
    !value.column_nulls.is_empty() {
    return false
  }
  value.reference_rows = []
  value.column_usage = []
  value.column_maxima = []
  value.column_nulls = []
  value.producer = None
  value.managed_producer = None
  value.disposal_complete = true
  true
}

///|
/// Observe only entries retired by the original bounded reclamation cursor.
/// A changed count permits another cleanup slice, never an assumption of stop.
pub fn managed_output_values_reclamation_steps(
  value : ManagedOutputValues,
) -> Int64 {
  value.reclamation_steps
}

///|
/// Observe real released roots without driving cleanup. Active admission may
/// still hold a callback's temporary values until that frame has returned.
pub fn managed_output_values_scratch_released(
  value : ManagedOutputValues,
) -> Bool {
  !value.open &&
  value.active_uses == 0 &&
  !value.reading &&
  !value.buffer.reading &&
  value.buffer.rows.capacity() == 0 &&
  value.buffer.presence_rows.capacity() == 0 &&
  value.reference_rows.capacity() == 0 &&
  value.column_usage.capacity() == 0 &&
  value.column_maxima.capacity() == 0 &&
  value.column_nulls.capacity() == 0 &&
  value.row_measurements is None &&
  value.finish_cursor is None &&
  value.producer is None &&
  value.managed_producer is None
}

///|
fn[A] with_managed_output_scratch_use(
  value : ManagedOutputValues,
  action : () -> A,
) -> A {
  value.active_uses += 1
  let result = action()
  value.active_uses -= 1
  if value.disposal_requested {
    dispose_managed_output_values_scratch(value)
  }
  result
}

///|
pub fn managed_output_values_schema(
  value : ManagedOutputValues,
) -> @schema.Schema {
  value.buffer.schema
}

///|
/// Initial value validation remains mandatory. Measurements are per top-level
/// value, not row-array JSON bytes; their measuring writer has no text/hash sink.
pub fn append_managed_output_values(
  stream : ManagedOutputValues,
  width : Int,
  read : (Int) -> @admitted.CheckedValue?,
) -> Result[Unit, ManagedOutputValueIssue] {
  if stream.active_uses != 0 {
    return Err(Closed)
  }
  with_managed_output_scratch_use(stream, fn() {
    append_managed_output_values_active(stream, width, read)
  })
}

///|
fn append_managed_output_values_active(
  stream : ManagedOutputValues,
  width : Int,
  read : (Int) -> @admitted.CheckedValue?,
) -> Result[Unit, ManagedOutputValueIssue] {
  if !stream.open || stream.reading || stream.finish_started {
    return Err(Closed)
  }
  if stream.rows >= stream.max_rows {
    cancel_managed_output_values(stream) |> ignore
    return Err(Admission(CaptureLimit))
  }
  match managed_output_row_start(stream, width) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  stream.reading = true
  let result = append_admitted_buffer_cells(stream.buffer, width, read)
  stream.reading = false
  match result {
    Err(ClosedCapture) => {
      cancel_managed_output_values(stream) |> ignore
      return Err(Closed)
    }
    Err(issue) => {
      cancel_managed_output_values(stream) |> ignore
      return Err(
        Admission(
          match issue {
            ForeignCheckedValue(_, column) =>
              ForeignCheckedValue(stream.rows, column)
            _ => issue
          },
        ),
      )
    }
    Ok(_) => ()
  }
  managed_output_row_finish(stream)
}

///|
/// Finite preservation rule for checked Local execution. Only a freshly
/// admitted table under the exact output owner, target and schema may move into
/// the managed result; numeric/row or foreign representations fall back to
/// another candidate instead of manufacturing checked cells.
pub fn append_completed_projection_managed_values(
  stream : ManagedOutputValues,
  output : CompletedOutput,
  row : Int,
) -> Result[Unit, ManagedOutputValueIssue] {
  if stream.active_uses != 0 {
    return Err(Closed)
  }
  with_managed_output_scratch_use(stream, fn() {
    append_completed_projection_managed_values_active(stream, output, row)
  })
}

///|
fn append_completed_projection_managed_values_active(
  stream : ManagedOutputValues,
  output : CompletedOutput,
  row : Int,
) -> Result[Unit, ManagedOutputValueIssue] {
  if !stream.open ||
    stream.reading ||
    stream.finish_started ||
    !completed_output_available(output) {
    return Err(Closed)
  }
  if output.table is Some(PresenceTable(table)) {
    guard table.rows.get(row) is Some(values) &&
      physical_equal(table.owner, stream.owner) &&
      output.target == stream.target else {
      return Err(Admission(InvalidCheckedRow))
    }
    match managed_output_row_start(stream, values.cells.length()) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    match append_admitted_buffer_presence(stream.buffer, values) {
      Err(issue) => {
        cancel_managed_output_values(stream) |> ignore
        return Err(Admission(issue))
      }
      Ok(_) => return managed_output_row_finish(stream)
    }
  }
  guard output.table is Some(AdmittedTable(table)) &&
    table.rows.get(row) is Some(values) &&
    physical_equal(table.owner, stream.owner) &&
    output.target == stream.target &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(stream.owner),
      stream.target,
    )
    is Some(schema) else {
    return Err(Admission(InvalidCheckedRow))
  }
  match managed_output_row_start(stream, values.length()) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match append_admitted_buffer_values(stream.buffer, schema, values) {
    Err(ClosedCapture) => {
      cancel_managed_output_values(stream) |> ignore
      Err(Closed)
    }
    Err(issue) => {
      cancel_managed_output_values(stream) |> ignore
      Err(Admission(issue))
    }
    Ok(_) => managed_output_row_finish(stream)
  }
}

///|
/// Finite Local fallback for an owned checked layout that is not already an
/// admitted-value table. The registered bridge emits and re-admits one bounded
/// row using the existing canonical value encoder and schema admission. This
/// establishes value evidence only; it does not establish a logical CID.
pub fn append_completed_projection_managed_wire(
  stream : ManagedOutputValues,
  output : CompletedOutput,
  row : Int,
  wire : RowWireLimits,
  decode : RetainedRowDecodeLimits,
) -> Result[Unit, ManagedOutputValueIssue] {
  if stream.active_uses != 0 {
    return Err(Closed)
  }
  with_managed_output_scratch_use(stream, fn() {
    append_completed_projection_managed_wire_active(
      stream, output, row, wire, decode,
    )
  })
}

///|
fn append_completed_projection_managed_wire_active(
  stream : ManagedOutputValues,
  output : CompletedOutput,
  row : Int,
  wire : RowWireLimits,
  decode : RetainedRowDecodeLimits,
) -> Result[Unit, ManagedOutputValueIssue] {
  if !stream.open ||
    stream.reading ||
    stream.finish_started ||
    !completed_output_matches_port(output, stream.owner, stream.target) ||
    completed_column_count(output) > wire.max_columns {
    return Err(Admission(InvalidCheckedRow))
  }
  let text = match
    completed_output_row_wire(
      output,
      row,
      wire.max_bytes,
      wire.max_nodes,
      wire.max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(Admission(InvalidCheckedRow))
  }
  let values = match decode_retained_row(stream.buffer.schema, text, decode) {
    Ok(value) => value
    Err(_) => return Err(Admission(InvalidCheckedRow))
  }
  append_managed_output_values_active(stream, values.length(), column => {
    values.get(column)
  })
}

///|
fn managed_output_row_start(
  stream : ManagedOutputValues,
  width : Int,
) -> Result[Unit, ManagedOutputValueIssue] {
  if !stream.open || stream.reading || stream.finish_started {
    return Err(Closed)
  }
  if stream.rows >= stream.max_rows {
    cancel_managed_output_values(stream) |> ignore
    return Err(Admission(CaptureLimit))
  }
  if stream.row_measurements is Some(index) &&
    width > index.max_cells - index.count {
    cancel_managed_output_values(stream) |> ignore
    return Err(MeasurementIndexLimit)
  }
  Ok(())
}

///|
fn managed_output_row_finish(
  stream : ManagedOutputValues,
) -> Result[Unit, ManagedOutputValueIssue] {
  stream.reading = true
  let result = finish_managed_output_row_active(stream)
  stream.reading = false
  result
}

///|
fn finish_managed_output_row_active(
  stream : ManagedOutputValues,
) -> Result[Unit, ManagedOutputValueIssue] {
  if !stream.open {
    return Err(Closed)
  }
  let presence = stream.buffer.presence_rows.get(0)
  if stream.issue is None {
    let measured = match presence {
      Some(row) =>
        measure_input_values(
          SinglePresenceGuardRow::{ value: row, },
          stream.max_value_bytes,
          Output,
          stream.measurement,
          column_usage=stream.column_usage,
          column_maxima=stream.column_maxima,
          column_nulls=stream.column_nulls,
          row_measurements?=stream.row_measurements,
        )
      None =>
        measure_input_values(
          SingleAdmittedGuardRow::{ values: stream.buffer.rows[0], },
          stream.max_value_bytes,
          Output,
          stream.measurement,
          column_usage=stream.column_usage,
          column_maxima=stream.column_maxima,
          column_nulls=stream.column_nulls,
          row_measurements?=stream.row_measurements,
        )
    }
    match measured {
      Ok(_) => ()
      Err(issue) =>
        stream.issue = Some(
          match issue {
            Measurement(phase, _, column, detail) =>
              Measurement(phase, stream.rows, column, detail)
            ValueBytes(phase, _, column) =>
              ValueBytes(phase, stream.rows, column)
            _ => issue
          },
        )
    }
  }
  if stream.buffer.budget.row_scratch_start is None {
    let references : Array[Array[@admitted.ReferenceValue]] = []
    for column in 0..<@schema.field_count(stream.buffer.schema) {
      let value = match presence {
        Some(row) => row.cells[column]
        None => Some(stream.buffer.rows[0][column])
      }
      guard value is Some(value) else {
        references.push([])
        continue
      }
      match
        collect_managed_references(value, stream.buffer.budget.limits.max_nodes) {
        Some(found) => references.push(found)
        None => {
          cancel_managed_output_values(stream) |> ignore
          return Err(ReferenceUnavailable(stream.rows, column))
        }
      }
    }
    // Reference availability is a Host callback. Disposal may have retired
    // admission while the active frame still held the row and reference roots.
    if !stream.open {
      return Err(Closed)
    }
    stream.reference_rows.push(
      references.map(found => found.map(reference => Some(reference))),
    )
  }
  // Preserve the original post-measurement/current frame fence even when the
  // complete schema proof establishes that no reference callbacks can occur.
  if !stream.open {
    return Err(Closed)
  }
  // Admission keeps running after a deferred measurement failure, as in the old
  // streamed output path. No successful receipt may conceal that failure.
  stream.buffer.rows.clear()
  stream.buffer.presence_rows.clear()
  stream.rows += 1
  let budget = stream.buffer.budget
  if budget.row_scratch_start is Some(_) {
    // This changes only the next row's physical extent origin. All semantic
    // counters and the TWO-largest-rows reservation remain cumulative/live.
    budget.row_scratch_start = Some((budget.nodes, budget.text))
  }
  Ok(())
}

///|
pub fn finish_managed_output_values(
  stream : ManagedOutputValues,
) -> Result[ManagedOutputValueReceipt, ManagedOutputValueIssue] {
  if stream.active_uses != 0 || stream.finish_started {
    return Err(Closed)
  }
  with_managed_output_scratch_use(stream, fn() {
    finish_managed_output_values_scoped(stream)
  })
}

///|
fn finish_managed_output_values_scoped(
  stream : ManagedOutputValues,
) -> Result[ManagedOutputValueReceipt, ManagedOutputValueIssue] {
  if !stream.open || stream.reading || stream.finish_started {
    return Err(Closed)
  }
  stream.reading = true
  let result = finish_managed_output_values_active(stream)
  // A finish attempt remains terminal even when a callback rejects its input.
  stream.open = false
  stream.buffer.open = false
  stream.reading = false
  result
}

///|
fn finish_managed_output_values_active(
  stream : ManagedOutputValues,
) -> Result[ManagedOutputValueReceipt, ManagedOutputValueIssue] {
  while true {
    let poll = match advance_managed_output_finish_active(stream, 64) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if poll.receipt is Some(receipt) {
      return Ok(receipt)
    }
  }
  Err(Closed)
}

///|
fn issue_managed_output_value_receipt(
  stream : ManagedOutputValues,
  cursor : ManagedOutputFinishCursor,
) -> Result[ManagedOutputValueReceipt, ManagedOutputValueIssue] {
  // Keep the stream open while invoking availability callbacks; reading
  // prevents reentry, and disposal can still revoke this active finish.
  if !stream.open {
    return Err(Closed)
  }
  stream.open = false
  stream.buffer.open = false
  if stream.issue is Some(issue) {
    return Err(Guard(issue))
  }
  if stream.row_measurements is Some(index) {
    let width = @schema.field_count(stream.buffer.schema)
    if (width == 0 && index.count != 0) ||
      (
        width > 0 &&
        (index.count / width != stream.rows || index.count % width != 0)
      ) {
      return Err(MeasurementIndexLimit)
    }
  }
  let budget = stream.buffer.budget
  let carrier_receipt = match
    @managed_carrier.complete_receipt(
      stream.carrier_binding,
      @managed_carrier.RelationMeasure(
        rows=stream.rows,
        columns=@schema.field_count(stream.buffer.schema),
      ),
    ) {
    Ok(value) => value
    Err(_) => return Err(Guard(InvalidLayout))
  }
  let receipt : ManagedOutputValueReceipt = {
    carrier_receipt,
    owner: stream.owner,
    target: stream.target,
    schema: stream.buffer.schema,
    rows: stream.rows,
    usage: { nodes: budget.nodes, text_bytes: budget.text, work: budget.work, },
    measured: (
      stream.initial.max_work - stream.measurement.work,
      stream.initial.max_bytes - stream.measurement.bytes,
      stream.initial.max_nodes - stream.measurement.nodes,
    ),
    fixed_measurement: cursor.fixed_measurement,
    managed_measurement: cursor.managed_measurement,
    column_usage: cursor.column_usage,
    column_maxima: cursor.column_maxima,
    column_nulls: cursor.column_nulls,
    reference_rows: cursor.references,
    measured_depth: stream.measurement.depth,
    row_measurements: stream.row_measurements,
  }
  // The receipt now owns the index. Later admission-scratch disposal must not
  // revoke or clear the separately retained successful output.
  stream.row_measurements = None
  stream.finish_cursor = None
  Ok(receipt)
}

///|
/// Preserve only opaque authority handles while the ordinary row buffer is
/// still available. Traversal is bounded by the already-admitted value limit.
fn collect_managed_references(
  value : @admitted.Value,
  max_nodes : Int,
) -> Array[@admitted.ReferenceValue]? {
  let pending = [value]
  let references = []
  let mut remaining = max_nodes
  while pending.pop() is Some(current) {
    if remaining == 0 {
      return None
    }
    remaining -= 1
    match current {
      @admitted.Reference(reference) => {
        if !@admitted.reference_available(reference) {
          return None
        }
        references.push(reference)
      }
      @admitted.Array(values) =>
        for index = @admitted.element_count(values) - 1
            index >= 0
            index = index - 1 {
          pending.push(@admitted.element_at(values, index).unwrap())
        }
      @admitted.Object(values) =>
        for index = @admitted.element_count(values) - 1
            index >= 0
            index = index - 1 {
          pending.push(@admitted.element_at(values, index).unwrap().1)
        }
      @admitted.Null
      | @admitted.Boolean(_)
      | @admitted.Number(_)
      | @admitted.Text(_)
      | @admitted.Date(_)
      | @admitted.Timestamp(_)
      | @admitted.Decimal(_)
      | @admitted.Signed64(_)
      | @admitted.Vector(_) => ()
      @admitted.JsonData(_) => ()
    }
  }
  Some(references)
}

///|
/// Transfer one fully measured fixed-input session into output admission. The
/// output consumes the same remaining ledger, not a fresh allowance. No source
/// handles escape in the resulting receipt; this is still not completion proof.
pub fn prepare_fixed_managed_output_values(
  producer : FixedProducerMeasurement,
  values : ValueLimits,
) -> Result[ManagedOutputValues, ManagedOutputValueIssue] {
  if !producer.open ||
    producer.scanning_input ||
    producer.next_input != producer.inputs.length() {
    return Err(Guard(ForeignInput))
  }
  for input in producer.inputs {
    if !producer_read_available(input) {
      return Err(Guard(ForeignInput))
    }
  }
  let stream = match
    prepare_managed_output_values(
      producer_read_receiver(producer.inputs[0]),
      producer.target,
      producer.max_rows,
      values,
      producer.max_value_bytes,
      {
        max_work: producer.budget.work,
        max_bytes: producer.budget.bytes,
        max_nodes: producer.budget.nodes,
        max_depth: producer.budget.depth,
      },
    ) {
    Ok(stream) => stream
    Err(issue) => return Err(issue)
  }
  producer.open = false
  Ok({ ..stream, measurement: producer.budget, producer: Some(producer), })
}

///|
pub fn managed_output_value_fixed_measurement_matches(
  receipt : ManagedOutputValueReceipt,
  producer : FixedProducerMeasurement,
) -> Bool {
  guard receipt.fixed_measurement is Some((identity, _)) &&
    physical_equal(identity, producer.identity) &&
    identity.val &&
    !producer.open else {
    return false
  }
  for input in producer.inputs {
    if !producer_read_available(input) {
      return false
    }
  }
  true
}

///|
/// Total input plus output measurement, present only for a transferred session.
pub fn managed_output_value_fixed_measurement_usage(
  receipt : ManagedOutputValueReceipt,
) -> (Int, Int, Int)? {
  receipt.fixed_measurement.map(pair => pair.1)
}

///|
pub fn managed_output_value_receipt_matches(
  receipt : ManagedOutputValueReceipt,
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
) -> Bool {
  physical_equal(receipt.owner, owner) && receipt.target == target
}

///|
pub fn managed_output_value_row_count(
  receipt : ManagedOutputValueReceipt,
) -> Int {
  receipt.rows
}

///|
pub fn managed_output_value_schema(
  receipt : ManagedOutputValueReceipt,
) -> @schema.Schema {
  receipt.schema
}

///|
pub fn managed_output_value_usage(
  receipt : ManagedOutputValueReceipt,
) -> ValueUsage {
  receipt.usage
}

///|
pub fn managed_output_value_measurement(
  receipt : ManagedOutputValueReceipt,
) -> (Int, Int, Int) {
  receipt.measured
}

///|
/// Only local finite reclamation is runnable; a live reader remains a blocker.
/// Observation grants no release and does not advance the original cursor.
pub fn managed_output_values_reclamation_runnable(
  value : ManagedOutputValues,
) -> Bool {
  value.disposal_requested &&
  !value.disposal_complete &&
  value.active_uses == 0 &&
  !value.buffer.reading
}

///|
// JSON object punctuation plus a conservative escape bound for actual field
// names. Cell sizes come from the original successful measurement, not policy.
fn measured_row_wire_add(
  total : Int,
  name : String,
  cell : Int,
  maximum : Int,
) -> Int? {
  if total < 0 || cell < 0 || maximum < total {
    return None
  }
  let bytes = total.to_int64() +
    4L +
    name.length().to_int64() * 6L +
    cell.to_int64()
  if bytes > maximum.to_int64() {
    None
  } else {
    Some(bytes.to_int())
  }
}

///|
/// Bound one physical batch from the SAME admitted values and optional checked
/// Result projection. Uses cached column maxima, never rescans rows or issues
/// permission. Projection duplicates and renamed fields are counted separately.
pub fn managed_output_value_row_wire_bound(
  receipt : ManagedOutputValueReceipt,
  result : ManagedResultOccurrence?,
  max_columns : Int,
  max_bytes : Int,
) -> Int? {
  if max_columns < 0 ||
    max_bytes < 3 ||
    receipt.column_maxima.length() != @schema.field_count(receipt.schema) {
    return None
  }
  let schema = match result {
    None => receipt.schema
    Some(occurrence) => {
      if !physical_equal(occurrence.owner, receipt.owner) ||
        @results.port_target(occurrence.port) != receipt.target {
        return None
      }
      @results.port_schema(occurrence.port)
    }
  }
  if @schema.field_count(schema) > max_columns {
    return None
  }
  if receipt.rows == 0 {
    return Some(3)
  }
  let mut cell = 0
  for maximum in receipt.column_maxima {
    if maximum < 0 {
      return None
    }
    cell = Int::max(cell, maximum)
  }
  let mut total = 3
  for column in 0..<@schema.field_count(schema) {
    guard @schema.field_reference_name_at(schema, column) is Some(name) &&
      measured_row_wire_add(total, name, cell, max_bytes) is Some(next) else {
      return None
    }
    total = next
  }
  Some(total)
}

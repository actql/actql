///|
/// Bounded decoding of an exact retained producer. Returned rows are provisional
/// import material, not a completed input or permission to execute a consumer.
struct RetainedProducerScan {
  input : ProducerRead
  wire_columns : Array[Int]
  stream : AdmittedOutputStream
  mut open : Bool
  mut measurement : FixedProducerMeasurement?
  mut guard_issue : FixedInputGuardIssue?
  mut join_validation : FixedJoinStream?
}

///|
/// Full ordered content verification for one exact receiving read. This does
/// not discharge the consumer's guard/demand budgets or prove a DB import.
struct VerifiedProducerScan {
  input : ProducerRead
  receipt : AdmittedOutputStreamReceipt
}

///|
pub fn prepare_retained_producer_scan(
  input : ProducerRead,
  max_rows : Int,
  values : ValueLimits,
  wire : RowWireLimits,
  max_batch_bytes : Int,
) -> Result[RetainedProducerScan, CompletedImportIssue] {
  if !producer_read_available(input) {
    return Err(Unavailable)
  }
  guard input.bound.output.representation is Some(material) else {
    return Err(NotRetainedRepresentation)
  }
  let receipt = material.receipt
  let wire_columns = []
  let control = ControlBudget::{
    remaining: wire.max_order_work,
    max_frames: 0,
  }
  for column in input.columns {
    let name = completed_column_name(input.bound.output, column).unwrap()
    let mut found = None
    for index in 0..<@schema.field_count(receipt.schema) {
      let candidate = @schema.reference_name(
        @schema.field_at(receipt.schema, index).unwrap().name,
      )
      if !spend_control(control, 1) ||
        !spend_control_text(control, name) ||
        !spend_control_text(control, candidate) {
        return Err(Admission(CaptureLimit))
      }
      if name == candidate {
        found = Some(index)
        break
      }
    }
    guard found is Some(index) else { return Err(IdentityMismatch) }
    wire_columns.push(index)
  }
  if max_rows < receipt.rows {
    return Err(Admission(CaptureLimit))
  }
  let stream = match
    prepare_admitted_stream(
      receipt.owner,
      receipt.target,
      max_rows,
      values,
      wire,
      max_batch_bytes,
      false,
    ) {
    Ok(stream) => stream
    Err(issue) => return Err(Encoding(issue))
  }
  Ok({
    input,
    wire_columns,
    stream,
    open: true,
    measurement: None,
    guard_issue: None,
    join_validation: None,
  })
}

///|
pub fn cancel_retained_producer_scan(scan : RetainedProducerScan) -> Bool {
  if !scan.open {
    return false
  }
  scan.open = false
  if scan.join_validation is Some(value) {
    cancel_fixed_join_stream(value)
  }
  if scan.measurement is Some(measurement) {
    measurement.open = false
  }
  cancel_admitted_output_stream(scan.stream) |> ignore
  true
}

///|
/// Decode the complete stored row before projecting the exact receiving port.
/// Even omitted fields contribute to canonical source identity verification.
pub fn append_retained_producer_scan_wire(
  scan : RetainedProducerScan,
  text : String,
  limits : RetainedRowDecodeLimits,
) -> Result[Array[@admitted.CheckedValue], CompletedImportIssue] {
  if !scan.open {
    return Err(Closed)
  }
  if !producer_read_available(scan.input) {
    cancel_retained_producer_scan(scan) |> ignore
    return Err(Unavailable)
  }
  let values = match
    decode_retained_row(scan.stream.buffer.schema, text, limits) {
    Ok(values) => values
    Err(issue) => {
      cancel_retained_producer_scan(scan) |> ignore
      return Err(WireRow(issue))
    }
  }
  append_retained_producer_scan_values(scan, values)
}

///|
/// Admit one bounded row supplied by a typed representation reader. Values must
/// belong to the exact stored schema, including fields omitted by the consumer.
/// Neither the typed entry nor successful append grants readiness: ordered
/// identity, measurement and join obligations are still finished below.
pub fn append_retained_producer_scan_values(
  scan : RetainedProducerScan,
  values : Array[@admitted.CheckedValue],
) -> Result[Array[@admitted.CheckedValue], CompletedImportIssue] {
  if !scan.open {
    return Err(Closed)
  }
  if !producer_read_available(scan.input) {
    cancel_retained_producer_scan(scan) |> ignore
    return Err(Unavailable)
  }
  match
    append_admitted_output_stream(scan.stream, values.length(), column => {
      values.get(column)
    }) {
    Err(issue) => {
      cancel_retained_producer_scan(scan) |> ignore
      return Err(Encoding(issue))
    }
    Ok(_) => ()
  }
  let projected = scan.wire_columns.map(column => values[column])
  measure_retained_producer_scan_row(scan, projected)
  if scan.join_validation is Some(value) {
    match
      collect_fixed_join_keys(value, producer_read_input_index(scan.input), column => {
        capture(projected[column].value)
      }) {
      Ok(_) => ()
      Err(issue) => {
        cancel_retained_producer_scan(scan) |> ignore
        return Err(JoinValidation(issue))
      }
    }
  }
  Ok(projected)
}

///|
pub fn finish_retained_producer_scan(
  scan : RetainedProducerScan,
) -> Result[VerifiedProducerScan, CompletedImportIssue] {
  if !scan.open {
    return Err(Closed)
  }
  if !producer_read_available(scan.input) {
    cancel_retained_producer_scan(scan) |> ignore
    return Err(Unavailable)
  }
  let (receipt, _) = match finish_admitted_output_stream(scan.stream) {
    Ok(value) => value
    Err(issue) => {
      cancel_retained_producer_scan(scan) |> ignore
      return Err(Encoding(issue))
    }
  }
  scan.open = false
  let expected = scan.input.bound.output.representation.unwrap().receipt
  if receipt.cid != expected.cid ||
    receipt.rows != expected.rows ||
    receipt.bytes != expected.bytes ||
    receipt.nodes != expected.nodes ||
    !physical_equal(receipt.owner, expected.owner) ||
    receipt.target != expected.target ||
    !physical_equal(receipt.schema, expected.schema) {
    if scan.measurement is Some(measurement) {
      measurement.open = false
    }
    if scan.join_validation is Some(value) {
      cancel_fixed_join_stream(value)
    }
    return Err(IdentityMismatch)
  }
  match finish_retained_producer_scan_measurement(scan) {
    Err(issue) => {
      if scan.join_validation is Some(value) {
        cancel_fixed_join_stream(value)
      }
      return Err(InputGuard(issue))
    }
    Ok(_) => ()
  }
  if scan.join_validation is Some(value) {
    value.verified[producer_read_input_index(scan.input)] = true
  }
  Ok({ input: scan.input, receipt, })
}

///|
pub fn verified_producer_scan_matches(
  scan : VerifiedProducerScan,
  input : ProducerRead,
) -> Bool {
  physical_equal(scan.input, input) &&
  scan.receipt.rows == producer_read_row_count(input) &&
  producer_read_available(input)
}

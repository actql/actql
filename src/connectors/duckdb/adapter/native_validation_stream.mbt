///|
/// Receipt-local accounting only. No rows, cursors or physical batches survive
/// chunk acceptance. Deferred issues preserve admission-before-guard ordering.
priv struct NativeValidationStream {
  wire : @execution.RowWireLimits
  demand_limits : @execution.FixedInputGuardMeasureLimits
  max_chunk_rows : Int
  demand : ComparisonDemand
  demand_budget : NativeValueBudget
  mut rows : Int
  mut guard_issue : NativeReceivingIssue?
  mut demand_issue : NativeDemandIssue?
  mut digest_issue : @execution.RowWireIssue?
  mut writer : @encode.Writer?
  mut order : @execution.RowWireOrder?
  mut digest : ReceiptDigest?
}

///|
/// Live physical retention diagnostic, not a receipt or execution proof.
pub fn native_validation_retained_rows(value : NativeReceiving) -> Int {
  let mut rows = 0
  for batch in value.validation_batches {
    rows += batch.rows
  }
  rows
}

///|
/// Select bounded validation before metadata or receipt work begins. Final
/// demand/identity callers must use these exact physical allowances; they may
/// not reset the budget after the source values have been discarded.
pub fn stream_native_validation(
  value : NativeReceiving,
  wire : @execution.RowWireLimits,
  demand : @execution.FixedInputGuardMeasureLimits,
  max_chunk_rows : Int,
) -> Result[Unit, NativeReceivingIssue] {
  if !(value.phase is Metadata) || value.validation_stream is Some(_) {
    return Err(InvalidState)
  }
  if wire.max_bytes < 0 ||
    wire.max_nodes < 1 ||
    wire.max_depth < 0 ||
    wire.max_columns < 0 ||
    wire.max_order_work < 0 ||
    max_chunk_rows < 0 ||
    demand.max_work < 0 ||
    demand.max_bytes < 0 ||
    demand.max_nodes < 0 ||
    demand.max_depth < 0 {
    return Err(InvalidLimits)
  }
  value.validation_stream = Some({
    wire,
    demand_limits: demand,
    max_chunk_rows,
    demand: { rows: 0, field_bytes: 0L, rhs_bytes: None, null_rows: 0, },
    demand_budget: {
      guards: value.measurement.guards,
      work: demand.max_work,
      bytes: demand.max_bytes,
      nodes: demand.max_nodes,
      depth: demand.max_depth,
    },
    rows: 0,
    guard_issue: None,
    demand_issue: None,
    digest_issue: None,
    writer: None,
    order: None,
    digest: None,
  })
  Ok(())
}

///|
fn start_validation_digest(
  stream : NativeValidationStream,
  result : PhysicalResult,
) -> Unit {
  let width = @schema.field_count(result.schema)
  if width > stream.wire.max_columns || width > stream.wire.max_order_work {
    stream.digest_issue = Some(OrderLimit)
    return
  }
  let names = Array::makei(width, column => {
    @schema.reference_name(
      @schema.field_at(result.schema, column).unwrap().name,
    )
  })
  match
    @execution.prepare_row_wire_order(
      names,
      stream.wire.max_columns,
      stream.wire.max_order_work - width,
    ) {
    Err(issue) => stream.digest_issue = Some(issue)
    Ok(order) => {
      stream.order = Some(order)
      try {
        let writer = @encode.hashing_writer(
          stream.wire.max_bytes,
          stream.wire.max_nodes,
          stream.wire.max_depth,
        )
        @encode.begin_array(writer)
        stream.writer = Some(writer)
      } catch {
        issue => stream.digest_issue = Some(Encoding(issue))
      }
    }
  }
}

///|
fn consume_validation_batch(
  value : NativeReceiving,
  stream : NativeValidationStream,
  batch : PhysicalBatch,
) -> Unit {
  for row in 0..<batch.rows {
    if stream.guard_issue is None {
      if value.measurement.work == 0 {
        stream.guard_issue = Some(
          Guard(ValidationScan, stream.rows, -1, MeasurementWork),
        )
      } else {
        value.measurement.work -= 1
        match measure_native_record(value.measurement, batch, row) {
          Ok(_) => ()
          Err(issue) =>
            stream.guard_issue = Some(
              Guard(ValidationScan, stream.rows, -1, issue),
            )
        }
      }
    }
    if stream.demand_issue is None {
      match physical_batch_cell(batch, row, value.scan.predicate_column) {
        None => stream.demand_issue = Some(InvalidLayout)
        Some(cell) =>
          match
            accumulate_comparison_demand(
              stream.demand,
              stream.demand_budget,
              Admitted(cell.value),
              value.scan.query.parameter.value,
            ) {
            Ok(_) => ()
            Err(issue) => stream.demand_issue = Some(issue)
          }
      }
    }
    if stream.digest_issue is None &&
      stream.writer is Some(writer) &&
      stream.order is Some(order) {
      try {
        @encode.begin_object(writer)
        for index in 0..<batch.owner.mappings.length() {
          let (name, column) = @execution.row_wire_order_column(order, index).unwrap()
          @encode.key(writer, name)
          @admitted.emit_wire_value(
            physical_batch_cell(batch, row, column).unwrap().value,
            writer,
          )
        }
        @encode.end_object(writer)
      } catch {
        issue => {
          stream.digest_issue = Some(Encoding(issue))
          stream.writer = None
        }
      }
    }
    stream.rows += 1
  }
}

///|
fn finish_validation_digest(
  stream : NativeValidationStream,
  result : PhysicalResult,
) -> Unit {
  if stream.digest_issue is Some(_) {
    return
  }
  guard stream.writer is Some(writer) && stream.order is Some(order) else {
    return
  }
  stream.writer = None
  try {
    @encode.end_array(writer)
    let (hash, bytes, nodes) = @encode.finish_hash_usage(writer)
    stream.digest = Some({
      order,
      columns: @schema.field_count(result.schema),
      cid: "sha256:" + hash,
      bytes,
      nodes,
      rows: result.rows,
      work: @schema.field_count(result.schema) +
      @execution.row_wire_order_work(order),
    })
  } catch {
    issue => stream.digest_issue = Some(Encoding(issue))
  }
}

///|
fn validation_stream_digest(
  stream : NativeValidationStream,
  limits : @execution.RowWireLimits,
) -> Result[ReceiptDigest, @execution.RowWireIssue] {
  if limits.max_bytes != stream.wire.max_bytes ||
    limits.max_nodes != stream.wire.max_nodes ||
    limits.max_depth != stream.wire.max_depth ||
    limits.max_columns != stream.wire.max_columns ||
    limits.max_order_work != stream.wire.max_order_work {
    return Err(OrderLimit)
  }
  if stream.digest_issue is Some(issue) {
    return Err(issue)
  }
  match stream.digest {
    Some(digest) => Ok(digest)
    None => Err(OrderLimit)
  }
}

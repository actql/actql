///|
/// Independent traversal for the comparator, sharing physical admission and
/// canonical value semantics. This token never issues product completion.
struct ObligationStream {
  physical : @duckdb.PhysicalResult
  order : @execution.RowWireOrder
  width : Int
  writer : @encode.Writer
  transport : @duckdb.TransportColumnLimits
  guard_budget : GuardBudget
  records : Bool
  retain : Bool
  identity : Bool
  initial_work : Int
  initial_bytes : Int
  initial_nodes : Int
  mut max_value_bytes : Int
  mut value_depth : Int
  mut open : Bool
  mut finished : Bool
  comparisons : Array[(Int, ComparisonSlot)]
  mut record_guard_issue : ObligationFailure?
}

///|
/// Successful scalar measurement only. Independent orchestration must bind
/// this to its exact immutable table; it is not a product admission token.
struct GuardSummary {
  work : Int
  bytes : Int
  nodes : Int
  depth : Int
  max_value_bytes : Int
  records : Bool
}

///|
#export_name("obligationReuseMeasurement")
pub fn obligation_reuse_measurement(
  summary : GuardSummary,
  budget : GuardBudget,
) -> Bool {
  // If a different ceiling might fail, replay the original measurement to
  // retain its first-failure order rather than approximating an error position.
  if budget.borrowed ||
    summary.records ||
    summary.work > budget.work ||
    summary.bytes > budget.bytes ||
    summary.nodes > budget.nodes ||
    summary.depth > budget.depth ||
    summary.max_value_bytes > budget.ceiling {
    return false
  }
  budget.work -= summary.work
  budget.bytes -= summary.bytes
  budget.nodes -= summary.nodes
  true
}

///|
struct GuardBudget {
  mut borrowed : Bool
  mut work : Int
  mut bytes : Int
  mut nodes : Int
  depth : Int
  ceiling : Int
}

///|
suberror ObligationFailure {
  InvalidConfiguration
  Closed
  InvalidLayout
  Physical(@duckdb.PhysicalResultIssue)
  Encoding(Error)
  GuardLimit
  Demand(@duckdb.NativeDemandIssue)
}

///|
#export_name("obligationBudget")
pub fn obligation_budget(
  work : Int,
  bytes : Int,
  nodes : Int,
  depth : Int,
  ceiling : Int,
) -> GuardBudget raise ObligationFailure {
  if work < 0 || bytes < 0 || nodes < 0 || depth < 0 || ceiling < 0 {
    raise InvalidConfiguration
  }
  { work, bytes, nodes, depth, ceiling, borrowed: false, }
}

///|
#export_name("obligationBegin")
pub fn obligation_begin(
  names : Array[String],
  kinds : Array[Int],
  nullable : Array[Bool],
  physical : @duckdb.PhysicalResultLimits,
  wire : @execution.RowWireLimits,
  transport : @duckdb.TransportColumnLimits,
  budget : GuardBudget,
  records : Bool,
  retain : Bool,
  identity : Bool,
  max_batch_bytes : Int,
) -> ObligationStream raise ObligationFailure {
  if budget.borrowed ||
    names.length() != kinds.length() ||
    names.length() != nullable.length() ||
    names.length() > wire.max_columns ||
    max_batch_bytes <= 0 ||
    (retain && !identity) {
    raise InvalidConfiguration
  }
  let fields = []
  let native = []
  for index, name in names {
    let (kind, physical) = match kinds[index] {
      0 => (@contract.NumberType, @duckdb.Float64)
      1 => (@contract.StringType, @duckdb.Varchar)
      2 => (@contract.BooleanType, @duckdb.Boolean)
      _ => raise InvalidConfiguration
    }
    fields.push(
      (
        @schema.Unqualified(name),
        @contract.primitive(kind, nullable=nullable[index]),
      ),
    )
    native.push((name, physical))
  }
  let schema = match
    @schema.from_fields(
      fields,
      max_fields=wire.max_columns,
      max_name_bytes=wire.max_order_work,
    ) {
    Ok(value) => value
    Err(_) => raise InvalidConfiguration
  }
  let physical = match
    @duckdb.prepare_physical_result(
      schema,
      native,
      physical,
      wire.max_order_work,
    ) {
    Ok(value) => value
    Err(issue) => raise Physical(issue)
  }
  let order = match
    @execution.prepare_row_wire_order(
      Array::makei(@schema.field_count(schema), index => {
        @schema.reference_name(@schema.field_at(schema, index).unwrap().name)
      }),
      wire.max_columns,
      wire.max_order_work,
    ) {
    Ok(value) => value
    Err(_) => raise InvalidConfiguration
  }
  try {
    let writer = if !identity {
      @encode.measuring_writer(wire.max_bytes, wire.max_nodes, wire.max_depth)
    } else if retain {
      @encode.buffered_hashing_writer(
        wire.max_bytes,
        wire.max_nodes,
        wire.max_depth,
        max_batch_bytes,
      )
    } else {
      @encode.hashing_writer(wire.max_bytes, wire.max_nodes, wire.max_depth)
    }
    @encode.begin_array(writer)
    budget.borrowed = true
    {
      physical,
      order,
      width: names.length(),
      writer,
      transport,
      guard_budget: budget,
      records,
      retain,
      identity,
      initial_work: budget.work,
      initial_bytes: budget.bytes,
      initial_nodes: budget.nodes,
      max_value_bytes: 0,
      value_depth: 0,
      open: true,
      finished: false,
      comparisons: [],
      record_guard_issue: None,
    }
  } catch {
    issue => raise Encoding(issue)
  }
}

///|
fn measure_row(
  stream : ObligationStream,
  batch : @duckdb.PhysicalBatch,
  row : Int,
) -> Unit raise ObligationFailure {
  let budget = stream.guard_budget
  if budget.work <= 0 {
    raise GuardLimit
  }
  budget.work -= 1
  try {
    if stream.records {
      let writer = @encode.measuring_writer(
        budget.bytes,
        budget.nodes,
        budget.depth,
      )
      @encode.begin_object(writer)
      for index in 0..<stream.width {
        if budget.work <= 0 {
          raise GuardLimit
        }
        budget.work -= 1
        let (name, column) = @execution.row_wire_order_column(
          stream.order,
          index,
        ).unwrap()
        @encode.key(writer, name)
        @admitted.emit_wire_value(
          @duckdb.physical_batch_cell(batch, row, column).unwrap().value,
          writer,
        )
      }
      @encode.end_object(writer)
      let (bytes, nodes, depth) = @encode.finish_measurement_usage(writer)
      stream.max_value_bytes = Int::max(stream.max_value_bytes, bytes)
      stream.value_depth = Int::max(stream.value_depth, depth)
      budget.bytes -= bytes
      budget.nodes -= nodes
      if bytes > budget.ceiling {
        raise GuardLimit
      }
    } else {
      for column in 0..<stream.width {
        if budget.work <= 0 {
          raise GuardLimit
        }
        budget.work -= 1
        let writer = @encode.measuring_writer(
          budget.bytes,
          budget.nodes,
          budget.depth,
        )
        @admitted.emit_wire_value(
          @duckdb.physical_batch_cell(batch, row, column).unwrap().value,
          writer,
        )
        let (bytes, nodes, depth) = @encode.finish_measurement_usage(writer)
        stream.max_value_bytes = Int::max(stream.max_value_bytes, bytes)
        stream.value_depth = Int::max(stream.value_depth, depth)
        budget.bytes -= bytes
        budget.nodes -= nodes
        if bytes > budget.ceiling {
          raise GuardLimit
        }
      }
    }
  } catch {
    error => raise Encoding(error)
  }
}

///|
#export_name("obligationAppend")
pub fn obligation_append(
  stream : ObligationStream,
  rows : Int,
  text : String,
) -> String raise ObligationFailure {
  if !stream.open {
    raise Closed
  }
  // A failed parse, admission, guard or encoding leaves the stream poisoned.
  stream.open = false
  let columns = match @duckdb.decode_transport_columns(text, stream.transport) {
    Ok(value) => value
    Err(_) => raise InvalidLayout
  }
  let batch = match
    @duckdb.admit_physical_chunk(stream.physical, rows, columns) {
    Ok(value) => value
    Err(issue) => raise Physical(issue)
  }
  try {
    for row in 0..<rows {
      if stream.records {
        // Acquisition admits the complete selected scan before reporting its
        // record guard. Keep decoding later batches under physical limits so
        // an excluded invalid value is not hidden by an earlier guard failure.
        if stream.record_guard_issue is None {
          measure_row(stream, batch, row) catch {
            issue => stream.record_guard_issue = Some(issue)
          }
        }
      } else {
        measure_row(stream, batch, row)
      }
      for (column, comparison) in stream.comparisons {
        if comparison.issue is None {
          match
            @duckdb.append_comparison_measurement(
              comparison.measurement,
              @duckdb.physical_batch_cell(batch, row, column).unwrap().value,
            ) {
            Ok(_) => ()
            Err(issue) => comparison.issue = Some(issue)
          }
        }
      }
      if !stream.identity {
        continue
      }
      @encode.begin_object(stream.writer)
      for index in 0..<stream.width {
        let (name, column) = @execution.row_wire_order_column(
          stream.order,
          index,
        ).unwrap()
        @encode.key(stream.writer, name)
        @admitted.emit_wire_value(
          @duckdb.physical_batch_cell(batch, row, column).unwrap().value,
          stream.writer,
        )
      }
      @encode.end_object(stream.writer)
    }
    let text = if stream.retain {
      @encode.drain_hash_output(stream.writer)
    } else {
      ""
    }
    stream.open = true
    text
  } catch {
    error => raise Encoding(error)
  }
}

///|
#export_name("obligationFinish")
pub fn obligation_finish(
  stream : ObligationStream,
) -> (String, String?, Int, Int, Int, GuardSummary) raise ObligationFailure {
  if !stream.open {
    raise Closed
  }
  stream.open = false
  if stream.record_guard_issue is Some(issue) {
    raise issue
  }
  try {
    @encode.end_array(stream.writer)
    let tail = if stream.retain {
      @encode.drain_hash_output(stream.writer)
    } else {
      ""
    }
    let (cid, bytes, nodes) = if stream.identity {
      let (hash, bytes, nodes) = @encode.finish_hash_usage(stream.writer)
      (Some("sha256:" + hash), bytes, nodes)
    } else {
      @encode.finish_measurement_usage(stream.writer) |> ignore
      (None, 0, 0)
    }
    let (rows, _, _, _) = @duckdb.physical_result_usage(stream.physical)
    stream.guard_budget.borrowed = false
    stream.finished = true
    (
      tail,
      cid,
      bytes,
      nodes,
      rows,
      {
        work: stream.initial_work - stream.guard_budget.work,
        bytes: stream.initial_bytes - stream.guard_budget.bytes,
        nodes: stream.initial_nodes - stream.guard_budget.nodes,
        depth: stream.value_depth,
        max_value_bytes: stream.max_value_bytes,
        records: stream.records,
      },
    )
  } catch {
    issue => raise Encoding(issue)
  }
}

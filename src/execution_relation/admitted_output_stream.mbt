///|
/// Provisional output admission and canonical encoding with one row of scratch.
/// The caller owns storage of drained text. No received row remains here after
/// append returns, and successful value admission is not Compute completion.
struct AdmittedOutputStream {
  owner : @lower.BoundPrepared
  target : @pipeline.Target
  buffer : AdmittedRowBuffer
  order : RowWireOrder
  writer : @encode.Writer
  max_rows : Int
  mut rows : Int
  mut open : Bool
  mut reading : Bool
  mut measurement : FixedProducerMeasurement?
}

///|
/// Exact completed content admission, not execution or physical-retention proof.
/// No row references, callbacks, paths or connector payloads are retained.
struct AdmittedOutputStreamReceipt {
  owner : @lower.BoundPrepared
  target : @pipeline.Target
  schema : @schema.Schema
  rows : Int
  cid : String
  bytes : Int
  nodes : Int
  depth : Int
  usage : ValueUsage
  measurement_identity : Ref[Bool]?
}

///|
pub(all) enum OutputStreamIssue {
  Admission(CaptureIssue)
  Wire(RowWireIssue)
  Closed
}

///|
pub fn prepare_admitted_output_stream(
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  max_rows : Int,
  values : ValueLimits,
  wire : RowWireLimits,
  max_batch_bytes : Int,
) -> Result[AdmittedOutputStream, OutputStreamIssue] {
  if !row_wire_valid_limits(wire) || max_batch_bytes < 0 {
    return Err(Wire(InvalidLimits))
  }
  let output = match prepare_admitted_output(owner, target, max_rows, values) {
    Ok(output) => output
    Err(issue) => return Err(Admission(issue))
  }
  let width = @schema.field_count(output.buffer.schema)
  if width > wire.max_columns || width > wire.max_order_work {
    return Err(Wire(OrderLimit))
  }
  let names = Array::makei(width, column => {
    @schema.reference_name(
      @schema.field_at(output.buffer.schema, column).unwrap().name,
    )
  })
  let order = match
    prepare_row_wire_order(names, wire.max_columns, wire.max_order_work) {
    Ok(order) => order
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
    Ok({
      owner,
      target,
      buffer: output.buffer,
      order,
      writer,
      max_rows,
      rows: 0,
      open: true,
      reading: false,
      measurement: None,
    })
  } catch {
    issue => Err(Wire(Encoding(issue)))
  }
}

///|
pub fn cancel_admitted_output_stream(stream : AdmittedOutputStream) -> Bool {
  if !stream.open {
    return false
  }
  stream.open = false
  stream.measurement = None
  cancel_admitted_buffer(stream.buffer) |> ignore
  true
}

///|
/// Append one row, returning only its provisional canonical storage batch. The
/// initial '[' and subsequent commas are emitted exactly once in stream order.
/// Physical batch limits do not reset value, row or canonical encoding budgets.
pub fn append_admitted_output_stream(
  stream : AdmittedOutputStream,
  width : Int,
  read : (Int) -> @admitted.CheckedValue?,
) -> Result[String, OutputStreamIssue] {
  if !stream.open || stream.reading {
    return Err(Closed)
  }
  if stream.rows >= stream.max_rows {
    cancel_admitted_output_stream(stream) |> ignore
    return Err(Admission(CaptureLimit))
  }
  stream.reading = true
  let result = append_output_stream_row(stream, width, read)
  stream.reading = false
  stream.buffer.rows.clear()
  match result {
    Ok(text) => {
      stream.rows += 1
      Ok(text)
    }
    Err(issue) => {
      cancel_admitted_output_stream(stream) |> ignore
      Err(issue)
    }
  }
}

///|
fn append_output_stream_row(
  stream : AdmittedOutputStream,
  width : Int,
  read : (Int) -> @admitted.CheckedValue?,
) -> Result[String, OutputStreamIssue] {
  match append_admitted_buffer_cells(stream.buffer, width, read) {
    Err(ForeignCheckedValue(_, column)) =>
      return Err(Admission(ForeignCheckedValue(stream.rows, column)))
    Err(issue) => return Err(Admission(issue))
    Ok(_) => ()
  }
  if !stream.open {
    return Err(Closed)
  }
  let row = stream.buffer.rows[0]
  if stream.measurement is Some(measurement) {
    measure_fixed_producer_stream_row(measurement, row)
  }
  try {
    @encode.begin_object(stream.writer)
    for (name, column) in stream.order.columns {
      @encode.key(stream.writer, name)
      @admitted.emit_wire_value(row[column], stream.writer)
    }
    @encode.end_object(stream.writer)
    Ok(@encode.drain_hash_output(stream.writer))
  } catch {
    issue => Err(Wire(Encoding(issue)))
  }
}

///|
/// Return the final storage batch and admitted identity only after full stream
/// completion. Storage must separately accept all batches before publication.
pub fn finish_admitted_output_stream(
  stream : AdmittedOutputStream,
) -> Result[(AdmittedOutputStreamReceipt, String), OutputStreamIssue] {
  if !stream.open || stream.reading {
    return Err(Closed)
  }
  stream.open = false
  stream.buffer.open = false
  let measurement_identity = stream.measurement.map(value => value.identity)
  stream.measurement = None
  try {
    @encode.end_array(stream.writer)
    let tail = @encode.drain_hash_output(stream.writer)
    let (hash, bytes, nodes, depth) = @encode.finish_hash_metrics(stream.writer)
    let budget = stream.buffer.budget
    Ok(
      (
        {
          owner: stream.owner,
          target: stream.target,
          schema: stream.buffer.schema,
          rows: stream.rows,
          cid: "sha256:" + hash,
          bytes,
          nodes,
          depth,
          usage: {
            nodes: budget.nodes,
            text_bytes: budget.text,
            work: budget.work,
          },
          measurement_identity,
        },
        tail,
      ),
    )
  } catch {
    issue => Err(Wire(Encoding(issue)))
  }
}

///|
pub fn output_stream_owner(
  value : AdmittedOutputStreamReceipt,
) -> @lower.BoundPrepared {
  value.owner
}

///|
pub fn output_stream_target(
  value : AdmittedOutputStreamReceipt,
) -> @pipeline.Target {
  value.target
}

///|
pub fn output_stream_schema(
  value : AdmittedOutputStreamReceipt,
) -> @schema.Schema {
  value.schema
}

///|
pub fn output_stream_identity(
  value : AdmittedOutputStreamReceipt,
) -> (String, Int, Int, Int) {
  (value.cid, value.bytes, value.nodes, value.rows)
}

///|
pub fn output_stream_value_usage(
  value : AdmittedOutputStreamReceipt,
) -> ValueUsage {
  value.usage
}

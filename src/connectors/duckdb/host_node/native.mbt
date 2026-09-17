///|
/// JS transport facade. No test setup, fixed catalog or semantic derivation.
struct NativeNodeRun {
  host : @acquisition_host.NativeHostRun
  limits : @acquisition_host.NativeHostLimits
  physical : NativePhysical?
  mut streaming_output : Bool
  stream_owner : Ref[Bool]
}

///|
pub(all) suberror NodeHostFailure {
  Host(@acquisition_host.NativeHostIssue)
  Broad(@acquisition_host.BroadHostIssue)
  Compute(@duckdb_compute.DuckDBComputeIssue)
  Strategy(@strategy.RunIssue)
  Physical(@resources.LedgerIssue)
  CapturedSource(@query.CapturedSourceIssue)
  ComputeParameter(@duckdb.ValueIssue)
  Transport(@duckdb.TransportColumnIssue)
  Descriptor(@duckdb.ValueIssue)
  InvalidFields
  InvalidCommand
  Encoding(@encode.EncodeFailure)
  Completion(@execution.TrustedOutputIssue)
  ManagedValues(@duckdb.ManagedPhysicalOutputIssue)
  ManagedRetention(@execution.ManagedOutputRetentionIssue)
  ManagedView(@execution.ManagedViewOutputIssue)
  ManagedComputed(@duckdb.ManagedComputedPhysicalIssue)
}

///|
#export_name("nativeHostOpen")
pub fn native_host_open(
  setup : @acquisition_host.NativeHostConfiguration,
  nonce : String,
  verify : (@duckdb_query.DuckDBNativeAttempt) -> Bool,
) -> NativeNodeRun raise NodeHostFailure {
  match @acquisition_host.start_configured_native_host(setup, nonce, verify) {
    Ok(host) =>
      {
        host,
        limits: @acquisition_host.configured_native_host_limits(setup),
        physical: None,
        streaming_output: false,
        stream_owner: Ref(true),
      }
    Err(issue) => raise Host(issue)
  }
}

///|
#export_name("nativeHostAttempt")
pub fn native_host_attempt(
  run : NativeNodeRun,
) -> @duckdb_query.DuckDBNativeAttempt {
  @acquisition_host.native_host_attempt(run.host)
}

///|
#export_name("nativeHostSql")
pub fn native_host_sql(
  run : NativeNodeRun,
  kind : Int,
) -> String raise NodeHostFailure {
  let scan = @acquisition_host.native_host_scan(run.host)
  match kind {
    0 => @duckdb.native_scan_metadata_sql(scan)
    1 => @duckdb.native_scan_sql(scan)
    2 => @duckdb.native_query_sql(@duckdb.native_scan_query(scan))
    _ => raise InvalidCommand
  }
}

///|
#export_name("nativeHostParameter")
pub fn native_host_parameter(
  run : NativeNodeRun,
  index : Int,
) -> String raise NodeHostFailure {
  let scan = @acquisition_host.native_host_scan(run.host)
  let parameter = if index == 2 {
    @duckdb.native_query_parameter(@duckdb.native_scan_query(scan))
  } else {
    match @duckdb.native_scan_metadata_parameter(scan, index) {
      Some(value) => value
      None => raise InvalidCommand
    }
  }
  try {
    let limits = run.limits.transport
    let writer = @encode.writer(limits.max_bytes, limits.max_nodes, 4)
    @duckdb.emit_physical_parameter(parameter, writer)
    @encode.finish(writer)
  } catch {
    issue => raise Encoding(issue)
  }
}

///|
fn chunk_columns(
  limits : @duckdb.TransportColumnLimits,
  text : String,
) -> Array[@decode.Cursor] raise NodeHostFailure {
  match @duckdb.decode_transport_columns(text, limits) {
    Ok(value) => value
    Err(issue) => raise Transport(issue)
  }
}

///|
fn transport_fields(
  limits : @duckdb.TransportColumnLimits,
  text : String,
) -> Array[(String, @duckdb.PhysicalType)] raise NodeHostFailure {
  let records = match
    @duckdb.decode_transport_columns(text, { ..limits, max_rows: 4, }) {
    Ok(value) => value
    Err(issue) => raise Transport(issue)
  }
  let output = []
  for record in records {
    if @decode.array_length(record) != Some(4) {
      raise InvalidFields
    }
    let name = match @decode.text(@decode.element_at(record, 0).unwrap()) {
      Ok(value) => value
      Err(_) => raise InvalidFields
    }
    let id = match @decode.text(@decode.element_at(record, 1).unwrap()) {
      Ok(value) => value
      Err(_) => raise InvalidFields
    }
    let span = @decode.cursor_span(record)
    let members : Array[@source.Field] = [
      { key: "id", key_span: span, value: { value: String(id), span, }, },
    ]
    for (index, key) in [(2, "precision"), (3, "scale")] {
      let cell = @decode.element_at(record, index).unwrap()
      if @decode.is_null(cell) {
        continue
      }
      let digits = match @decode.text(cell) {
        Ok(value) => value
        Err(_) => raise InvalidFields
      }
      if digits.length() == 0 || digits.length() > 2 {
        raise InvalidFields
      }
      let mut number = 0
      for c in digits.iter() {
        if c < '0' || c > '9' {
          raise InvalidFields
        }
        number = number * 10 + c.to_int() - 48
      }
      members.push({
        key,
        key_span: span,
        value: { value: Number(number.to_double()), span, },
      })
    }
    let descriptor = match
      @decode.admit({ value: Object(members), span, }, {
        max_nodes: 8,
        max_depth: 2,
        max_string_bytes: limits.max_text_bytes,
        max_total_string_bytes: limits.max_text_bytes,
      }) {
      Ok(value) => value
      Err(_) => raise InvalidFields
    }
    let physical = match @duckdb.decode_physical_type(descriptor) {
      Ok(value) => value
      Err(issue) => raise Descriptor(issue)
    }
    output.push((name, physical))
  }
  output
}

///|
#export_name("nativeHostMetadata")
pub fn native_host_metadata(
  run : NativeNodeRun,
  rows : Int,
  fields : String,
  data : String,
) -> Unit raise NodeHostFailure {
  match
    @acquisition_host.native_host_metadata(
      run.host,
      rows,
      transport_fields(run.limits.transport, fields),
      chunk_columns(run.limits.transport, data),
    ) {
    Ok(_) => ()
    Err(issue) => raise Host(issue)
  }
}

///|
#export_name("nativeHostBegin")
pub fn native_host_begin(
  run : NativeNodeRun,
  native : Bool,
  fields : String,
) -> Unit raise NodeHostFailure {
  match
    @acquisition_host.begin_native_host_receipt(
      run.host,
      if native {
        @duckdb.NativeResult
      } else {
        @duckdb.ValidationScan
      },
      transport_fields(run.limits.transport, fields),
    ) {
    Ok(_) => ()
    Err(issue) => raise Host(issue)
  }
}

///|
#export_name("nativeHostAccept")
pub fn native_host_accept(
  run : NativeNodeRun,
  rows : Int,
  data : String,
) -> Unit raise NodeHostFailure {
  match
    @acquisition_host.accept_native_host_chunk(
      run.host,
      rows,
      chunk_columns(run.limits.transport, data),
    ) {
    Ok(_) => ()
    Err(issue) => raise Host(issue)
  }
}

///|
#export_name("nativeHostFinish")
pub fn native_host_finish(run : NativeNodeRun) -> Unit raise NodeHostFailure {
  match @acquisition_host.finish_native_host_receipt(run.host) {
    Ok(_) => ()
    Err(issue) => raise Host(issue)
  }
}

///|
#export_name("nativeHostComplete")
pub fn native_host_complete(
  run : NativeNodeRun,
) -> @duckdb_query.DuckDBNativeObservation raise NodeHostFailure {
  if run.physical is Some(p) {
    if p.closed || !p.settled || p.holding is Some(_) {
      raise Physical(InvalidCharge)
    }
    let retention = if run.streaming_output {
      guard p.sealed_file_bytes is Some(bytes) else {
        raise Physical(InvalidCharge)
      }
      p.retention - p.file_capacity + bytes
    } else {
      p.retention
    }
    p.holding = Some(
      match @resources.retain_allocation(p.ledger, p.reservation, retention) {
        Ok(value) => value
        Err(issue) => raise Physical(issue)
      },
    )
  }
  match
    @acquisition_host.complete_native_host(run.host, run.limits.completion) {
    Ok(value) => {
      if run.physical is Some(p) {
        // Construct the retained root while post-DB checking capacity is still
        // reserved. DAG adoption subsequently transfers this exact handle.
        p.source = Some(native_host_captured_source(run, value))
        p.observation = Some(value)
        match @resources.settle_reservation(p.ledger, p.reservation) {
          Ok(_) => p.completed = true
          Err(issue) => raise Physical(issue)
        }
      }
      value
    }
    Err(issue) => raise Host(issue)
  }
}

///|
#export_name("nativeHostOutput")
pub fn native_host_output(
  run : NativeNodeRun,
  observation : @duckdb_query.DuckDBNativeObservation,
) -> @execution.CompletedOutput raise NodeHostFailure {
  // Accounted acquisitions hand off through their one owned DAG root, not an
  // untracked parallel export which could outlive that allocation's port.
  if run.physical is Some(_) {
    raise Physical(InvalidCharge)
  }
  let limits = run.limits
  if run.streaming_output {
    return match
      @acquisition_host.native_host_retained_output(
        run.host,
        observation,
        limits.output_entries,
        limits.output_name_bytes,
      ) {
      Ok(output) => output
      Err(issue) => raise Host(issue)
    }
  }
  let retained = match
    @acquisition_host.native_host_output(
      run.host,
      observation,
      limits.output_rows,
      limits.retention,
    ) {
    Ok(value) => value
    Err(issue) => raise Host(issue)
  }
  match
    @duckdb_query.complete_duckdb_native_output(
      retained,
      limits.output_entries,
      limits.output_name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => raise Completion(issue)
  }
}

///|
#export_name("nativeHostDocument")
pub fn native_host_document(
  observation : @duckdb_query.DuckDBNativeObservation,
) -> String {
  @encode.document_text(
    @duckdb_query.duckdb_native_observation_document(observation),
  )
}

///|
#export_name("nativeHostReceiptDocument")
pub fn native_host_receipt_document(
  observation : @duckdb_query.DuckDBNativeObservation,
  index : Int,
) -> String raise NodeHostFailure {
  guard @duckdb_query.duckdb_native_observation_receipt_at(observation, index)
    is Some((document, _)) else {
    raise InvalidCommand
  }
  @encode.document_text(document)
}

///|
#export_name("nativeHostRecordDocument")
pub fn native_host_record_document(
  observation : @duckdb_query.DuckDBNativeObservation,
  index : Int,
) -> String raise NodeHostFailure {
  guard @duckdb_query.duckdb_native_observation_record_at(observation, index)
    is Some((document, _)) else {
    raise InvalidCommand
  }
  @encode.document_text(document)
}

///|
/// Logical value-measurement usage for the captured validation and native
/// receipts. These values are charges, not observed CPU or transport work.
#export_name("nativeHostMeasurementUsage")
pub fn native_host_measurement_usage(
  observation : @duckdb_query.DuckDBNativeObservation,
) -> Array[Int] {
  let (work, bytes, nodes) = @duckdb_query.duckdb_native_observation_measurement_usage(
    observation,
  )
  [work, bytes, nodes]
}

///|
/// Exact comparison demand for the captured validation occurrence.
#export_name("nativeHostComparisonUsage")
pub fn native_host_comparison_usage(
  observation : @duckdb_query.DuckDBNativeObservation,
) -> Array[String] {
  let usage = @duckdb_query.duckdb_native_observation_demand_usage(observation)
  [
    usage.rows.to_string(),
    usage.field_bytes.to_string(),
    usage.rhs_bytes.unwrap_or(-1).to_string(),
    usage.true_rows.to_string(),
    usage.false_rows.to_string(),
    usage.null_rows.to_string(),
    usage.predicate_bytes.to_string(),
    usage.physical_work.to_string(),
    usage.physical_bytes.to_string(),
    usage.physical_nodes.to_string(),
  ]
}

///|
#export_name("nativeHostCapturedSource")
pub fn native_host_captured_source(
  run : NativeNodeRun,
  observation : @duckdb_query.DuckDBNativeObservation,
) -> @query.CapturedInputSource raise NodeHostFailure {
  if run.physical is Some(p) && (p.completed || p.closed) {
    raise Physical(InvalidCharge)
  }
  let limits = run.limits
  if run.streaming_output {
    return match
      @acquisition_host.native_host_retained_source(
        run.host,
        observation,
        limits.output_entries,
        limits.output_name_bytes,
      ) {
      Ok(source) => source
      Err(issue) => raise CapturedSource(issue)
    }
  }
  let retained = match
    @acquisition_host.native_host_output(
      run.host,
      observation,
      limits.output_rows,
      limits.retention,
    ) {
    Ok(value) => value
    Err(issue) => raise Host(issue)
  }
  match
    @duckdb_query.native_captured_source(
      retained,
      limits.output_entries,
      limits.output_name_bytes,
    ) {
    Ok(source) => source
    Err(issue) => raise CapturedSource(issue)
  }
}

///|
#export_name("nativeHostAbort")
pub fn native_host_abort(run : NativeNodeRun) -> Unit {
  @acquisition_host.abort_native_host(run.host)
}

///|
#export_name("nativeHostClose")
pub fn native_host_close(run : NativeNodeRun) -> Unit {
  run.stream_owner.val = false
  @acquisition_host.close_native_host(run.host)
  close_native_physical(run)
}

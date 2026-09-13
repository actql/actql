///|
/// JS transport facade. No test setup, fixed catalog or semantic derivation.
struct NativeNodeRun {
  host : @host.NativeHostRun
  limits : @host.NativeHostLimits
}

///|
pub(all) suberror NativeNodeFailure {
  Host(@host.NativeHostIssue)
  Transport(@duckdb.TransportColumnIssue)
  Descriptor(@duckdb.ValueIssue)
  InvalidFields
  InvalidCommand
  Encoding(@encode.EncodeFailure)
  Completion(@execution.TrustedOutputIssue)
}

///|
#export_name("nativeHostOpen")
pub fn native_host_open(
  setup : @host.NativeHostConfiguration,
  nonce : String,
  verify : (@planning.DuckDBNativeAttempt) -> Bool,
) -> NativeNodeRun raise NativeNodeFailure {
  match @host.start_configured_native_host(setup, nonce, verify) {
    Ok(host) => { host, limits: @host.configured_native_host_limits(setup), }
    Err(issue) => raise Host(issue)
  }
}

///|
#export_name("nativeHostAttempt")
pub fn native_host_attempt(
  run : NativeNodeRun,
) -> @planning.DuckDBNativeAttempt {
  @host.native_host_attempt(run.host)
}

///|
#export_name("nativeHostSql")
pub fn native_host_sql(
  run : NativeNodeRun,
  kind : Int,
) -> String raise NativeNodeFailure {
  let scan = @host.native_host_scan(run.host)
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
) -> String raise NativeNodeFailure {
  let scan = @host.native_host_scan(run.host)
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
  run : NativeNodeRun,
  text : String,
) -> Array[@decode.Cursor] raise NativeNodeFailure {
  match @duckdb.decode_transport_columns(text, run.limits.transport) {
    Ok(value) => value
    Err(issue) => raise Transport(issue)
  }
}

///|
fn transport_fields(
  run : NativeNodeRun,
  text : String,
) -> Array[(String, @duckdb.PhysicalType)] raise NativeNodeFailure {
  let records = match
    @duckdb.decode_transport_columns(text, {
      ..run.limits.transport,
      max_rows: 4,
    }) {
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
        max_string_bytes: run.limits.transport.max_text_bytes,
        max_total_string_bytes: run.limits.transport.max_text_bytes,
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
) -> Unit raise NativeNodeFailure {
  match
    @host.native_host_metadata(
      run.host,
      rows,
      transport_fields(run, fields),
      chunk_columns(run, data),
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
) -> Unit raise NativeNodeFailure {
  match
    @host.begin_native_host_receipt(
      run.host,
      if native {
        @duckdb.NativeResult
      } else {
        @duckdb.ValidationScan
      },
      transport_fields(run, fields),
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
) -> Unit raise NativeNodeFailure {
  match
    @host.accept_native_host_chunk(run.host, rows, chunk_columns(run, data)) {
    Ok(_) => ()
    Err(issue) => raise Host(issue)
  }
}

///|
#export_name("nativeHostFinish")
pub fn native_host_finish(run : NativeNodeRun) -> Unit raise NativeNodeFailure {
  match @host.finish_native_host_receipt(run.host) {
    Ok(_) => ()
    Err(issue) => raise Host(issue)
  }
}

///|
#export_name("nativeHostComplete")
pub fn native_host_complete(
  run : NativeNodeRun,
) -> @planning.DuckDBNativeObservation raise NativeNodeFailure {
  match @host.complete_native_host(run.host, run.limits.completion) {
    Ok(value) => value
    Err(issue) => raise Host(issue)
  }
}

///|
#export_name("nativeHostOutput")
pub fn native_host_output(
  run : NativeNodeRun,
  observation : @planning.DuckDBNativeObservation,
) -> @execution.CompletedOutput raise NativeNodeFailure {
  let limits = run.limits
  let retained = match
    @host.native_host_output(
      run.host,
      observation,
      limits.output_rows,
      limits.retention,
    ) {
    Ok(value) => value
    Err(issue) => raise Host(issue)
  }
  match
    @planning.complete_duckdb_native_output(
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
  observation : @planning.DuckDBNativeObservation,
) -> String {
  @encode.document_text(
    @planning.duckdb_native_observation_document(observation),
  )
}

///|
#export_name("nativeHostAbort")
pub fn native_host_abort(run : NativeNodeRun) -> Unit {
  @host.abort_native_host(run.host)
}

///|
#export_name("nativeHostClose")
pub fn native_host_close(run : NativeNodeRun) -> Unit {
  @host.close_native_host(run.host)
}

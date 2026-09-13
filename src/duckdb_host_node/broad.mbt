///|
struct BroadNodeRun {
  host : @host.BroadHostRun
  limits : @host.BroadHostLimits
}

///|
#export_name("broadHostOpen")
pub fn broad_host_open(
  setup : @host.BroadHostConfiguration,
  nonce : String,
  verify : (@planning.DuckDBBroadAttempt) -> Bool,
) -> BroadNodeRun raise NodeHostFailure {
  match @host.start_configured_broad_host(setup, nonce, verify) {
    Ok(host) => { host, limits: @host.configured_broad_host_limits(setup), }
    Err(issue) => raise Broad(issue)
  }
}

///|
#export_name("broadHostAttempt")
pub fn broad_host_attempt(run : BroadNodeRun) -> @planning.DuckDBBroadAttempt {
  @host.broad_host_attempt(run.host)
}

///|
#export_name("broadHostSql")
pub fn broad_host_sql(run : BroadNodeRun, metadata : Bool) -> String {
  let scan = @host.broad_host_scan(run.host)
  if metadata {
    @duckdb.broad_scan_metadata_sql(scan)
  } else {
    @duckdb.broad_scan_sql(scan)
  }
}

///|
#export_name("broadHostParameter")
pub fn broad_host_parameter(
  run : BroadNodeRun,
  index : Int,
) -> String raise NodeHostFailure {
  let parameter = match
    @duckdb.broad_scan_metadata_parameter(
      @host.broad_host_scan(run.host),
      index,
    ) {
    Some(value) => value
    None => raise InvalidCommand
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
#export_name("broadHostMetadata")
pub fn broad_host_metadata(
  run : BroadNodeRun,
  rows : Int,
  fields : String,
  data : String,
) -> Unit raise NodeHostFailure {
  match
    @host.broad_host_metadata(
      run.host,
      rows,
      transport_fields(run.limits.transport, fields),
      chunk_columns(run.limits.transport, data),
    ) {
    Ok(_) => ()
    Err(issue) => raise Broad(issue)
  }
}

///|
#export_name("broadHostBegin")
pub fn broad_host_begin(
  run : BroadNodeRun,
  fields : String,
) -> Unit raise NodeHostFailure {
  match
    @host.begin_broad_host_receipt(
      run.host,
      transport_fields(run.limits.transport, fields),
    ) {
    Ok(_) => ()
    Err(issue) => raise Broad(issue)
  }
}

///|
#export_name("broadHostAccept")
pub fn broad_host_accept(
  run : BroadNodeRun,
  rows : Int,
  data : String,
) -> Unit raise NodeHostFailure {
  match
    @host.accept_broad_host_chunk(
      run.host,
      rows,
      chunk_columns(run.limits.transport, data),
    ) {
    Ok(_) => ()
    Err(issue) => raise Broad(issue)
  }
}

///|
#export_name("broadHostFinish")
pub fn broad_host_finish(run : BroadNodeRun) -> Unit raise NodeHostFailure {
  match @host.finish_broad_host_receipt(run.host) {
    Ok(_) => ()
    Err(issue) => raise Broad(issue)
  }
}

///|
#export_name("broadHostComplete")
pub fn broad_host_complete(
  run : BroadNodeRun,
) -> @planning.DuckDBBroadObservation raise NodeHostFailure {
  match @host.complete_broad_host(run.host) {
    Ok(value) => value
    Err(issue) => raise Broad(issue)
  }
}

///|
#export_name("broadHostBind")
pub fn broad_host_bind(
  run : BroadNodeRun,
  observation : @planning.DuckDBBroadObservation,
  receiver : @lower.BoundPrepared,
  input_index : Int,
) -> @execution.BoundProducerInput raise NodeHostFailure {
  match
    @host.bind_broad_host_input(run.host, observation, receiver, input_index) {
    Ok(value) => value
    Err(issue) => raise Broad(issue)
  }
}

///|
#export_name("broadHostDocument")
pub fn broad_host_document(
  observation : @planning.DuckDBBroadObservation,
) -> String {
  @encode.document_text(
    @planning.duckdb_broad_observation_document(observation),
  )
}

///|
#export_name("broadHostAbort")
pub fn broad_host_abort(run : BroadNodeRun) -> Unit {
  @host.abort_broad_host(run.host)
}

///|
#export_name("broadHostClose")
pub fn broad_host_close(run : BroadNodeRun) -> Unit {
  @host.close_broad_host(run.host)
}

///|
struct BroadNodeRun {
  host : @acquisition_host.BroadHostRun
  limits : @acquisition_host.BroadHostLimits
  physical : BroadPhysical?
}

///|
#export_name("broadHostSourceCapture")
pub fn broad_host_source_capture(
  run : BroadNodeRun,
  observation : @duckdb_query.DuckDBBroadObservation,
) -> @acquisition_host.BroadHostSourceCapture raise NodeHostFailure {
  if run.physical is Some(p) {
    if p.closed {
      raise Physical(InvalidCharge)
    }
    if p.observation is Some(expected) {
      guard physical_equal(expected, observation) && p.capture is Some(capture) else {
        raise Physical(InvalidCharge)
      }
      return capture
    }
  }
  match @acquisition_host.capture_broad_host_source(run.host, observation) {
    Ok(value) => value
    Err(issue) => raise CapturedSource(issue)
  }
}

///|
#export_name("broadHostSourceCaptureSource")
pub fn broad_host_source_capture_source(
  capture : @acquisition_host.BroadHostSourceCapture,
) -> @query.CapturedInputSource raise NodeHostFailure {
  match @acquisition_host.broad_host_source_capture_source(capture) {
    Ok(value) => value
    Err(issue) => raise CapturedSource(issue)
  }
}

///|
#export_name("broadHostSourceCaptureIdentityMatches")
pub fn broad_host_source_capture_identity_matches(
  capture : @acquisition_host.BroadHostSourceCapture,
  identity : @query.CapturedSourceRelationIdentity,
) -> Bool {
  @acquisition_host.broad_host_source_capture_identity_matches(
    capture, identity,
  )
}

///|
#export_name("broadHostSourceCaptureSourceRef")
pub fn broad_host_source_capture_source_ref(
  capture : @acquisition_host.BroadHostSourceCapture,
) -> String? {
  @acquisition_host.broad_host_source_capture_source_ref(capture)
}

///|
#export_name("broadHostIssueSourceEvidence")
pub fn broad_host_issue_source_evidence(
  capture : @acquisition_host.BroadHostSourceCapture,
  context : @acquisition_host.NativeSourceEvidenceContext,
  identity : @query.CapturedSourceRelationIdentity,
  logical_input : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  effective_data_policy_cid : String,
  observed_at : String,
) -> String raise NodeHostFailure {
  match
    @acquisition_host.issue_broad_host_source_evidence(
      capture, context, identity, logical_input, authority_scope_cid, effective_data_policy_cid,
      observed_at,
    ) {
    Ok(value) => @publication.run_evidence_value_json(value)
    Err(issue) => raise SourceEvidence(issue)
  }
}

///|
#export_name("broadHostOpen")
pub fn broad_host_open(
  setup : @acquisition_host.BroadHostConfiguration,
  nonce : String,
  verify : (@duckdb_query.DuckDBBroadAttempt) -> Bool,
) -> BroadNodeRun raise NodeHostFailure {
  match @acquisition_host.start_configured_broad_host(setup, nonce, verify) {
    Ok(host) =>
      {
        host,
        limits: @acquisition_host.configured_broad_host_limits(setup),
        physical: None,
      }
    Err(issue) => raise Broad(issue)
  }
}

///|
#export_name("broadHostAttempt")
pub fn broad_host_attempt(
  run : BroadNodeRun,
) -> @duckdb_query.DuckDBBroadAttempt {
  @acquisition_host.broad_host_attempt(run.host)
}

///|
#export_name("broadHostSql")
pub fn broad_host_sql(run : BroadNodeRun, metadata : Bool) -> String {
  let scan = @acquisition_host.broad_host_scan(run.host)
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
      @acquisition_host.broad_host_scan(run.host),
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
    @acquisition_host.broad_host_metadata(
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
    @acquisition_host.begin_broad_host_receipt(
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
    @acquisition_host.accept_broad_host_chunk(
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
  match @acquisition_host.finish_broad_host_receipt(run.host) {
    Ok(_) => ()
    Err(issue) => raise Broad(issue)
  }
}

///|
#export_name("broadHostComplete")
pub fn broad_host_complete(
  run : BroadNodeRun,
) -> @duckdb_query.DuckDBBroadObservation raise NodeHostFailure {
  match @acquisition_host.complete_broad_host(run.host) {
    Ok(value) => value
    Err(issue) => raise Broad(issue)
  }
}

///|
#export_name("broadHostBind")
pub fn broad_host_bind(
  run : BroadNodeRun,
  observation : @duckdb_query.DuckDBBroadObservation,
  receiver : @lower.BoundPrepared,
  input_index : Int,
) -> @execution.BoundProducerInput raise NodeHostFailure {
  // Accounted acquisitions enter through their retained DAG slot. A parallel
  // bound export must not outlive that allocation's original cleanup owner.
  if run.physical is Some(_) {
    raise Physical(InvalidCharge)
  }
  match
    @acquisition_host.bind_broad_host_input(
      run.host,
      observation,
      receiver,
      input_index,
    ) {
    Ok(value) => value
    Err(issue) => raise Broad(issue)
  }
}

///|
#export_name("broadHostDocument")
pub fn broad_host_document(
  observation : @duckdb_query.DuckDBBroadObservation,
) -> String {
  @encode.document_text(
    @duckdb_query.duckdb_broad_observation_document(observation),
  )
}

///|
#export_name("broadHostAbort")
pub fn broad_host_abort(run : BroadNodeRun) -> Unit {
  @acquisition_host.abort_broad_host(run.host)
}

///|
#export_name("broadHostClose")
pub fn broad_host_close(run : BroadNodeRun) -> Unit {
  @acquisition_host.close_broad_host(run.host)
  close_broad_physical(run)
}

///|
/// Connector-owned acquisition handle for the separate Client/Local
/// composition. The transport bridge never imports Local execution.
#export_name("broadHostAcquisition")
pub fn broad_host_acquisition(
  run : BroadNodeRun,
) -> @acquisition_host.BroadHostRun {
  run.host
}

///|
/// The only completion-policy input needed by the Local composition.
#export_name("broadHostMaxNameBytes")
pub fn broad_host_max_name_bytes(run : BroadNodeRun) -> Int {
  run.limits.completion.records.max_bytes
}

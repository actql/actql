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
  SourceEvidence(@acquisition_host.NativeSourceEvidenceIssue)
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
  Frame(@publication.DurableResultRowFrameIssue)
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
  match @duckdb.decode_physical_fields(text, limits) {
    Ok(value) => value
    Err(Transport(issue)) => raise Transport(issue)
    Err(InvalidFields) => raise InvalidFields
    Err(Descriptor(issue)) => raise Descriptor(issue)
  }
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
        let capture = native_host_source_capture(run, value)
        p.capture = Some(capture)
        p.source = Some(native_host_source_capture_source(capture))
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
  if run.physical is Some(p) {
    if p.closed {
      raise Physical(InvalidCharge)
    }
    if p.completed {
      guard p.source is Some(source) &&
        p.observation is Some(expected) &&
        physical_equal(expected, observation) else {
        raise Physical(InvalidCharge)
      }
      return source
    }
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
#export_name("nativeHostSourceCapture")
pub fn native_host_source_capture(
  run : NativeNodeRun,
  observation : @duckdb_query.DuckDBNativeObservation,
) -> @acquisition_host.NativeHostSourceCapture raise NodeHostFailure {
  if run.physical is Some(p) {
    if p.closed {
      raise Physical(InvalidCharge)
    }
    if p.completed {
      guard p.capture is Some(capture) &&
        p.observation is Some(expected) &&
        physical_equal(expected, observation) else {
        raise Physical(InvalidCharge)
      }
      return capture
    }
  }
  let limits = run.limits
  match
    @acquisition_host.capture_native_host_source(
      run.host,
      observation,
      run.streaming_output,
      limits.output_rows,
      limits.retention,
      limits.output_entries,
      limits.output_name_bytes,
    ) {
    Ok(capture) => capture
    Err(issue) => raise CapturedSource(issue)
  }
}

///|
#export_name("nativeHostSourceCaptureSource")
pub fn native_host_source_capture_source(
  capture : @acquisition_host.NativeHostSourceCapture,
) -> @query.CapturedInputSource raise NodeHostFailure {
  match @acquisition_host.native_host_source_capture_source(capture) {
    Ok(source) => source
    Err(issue) => raise CapturedSource(issue)
  }
}

///|
#export_name("nativeHostSourceCaptureIdentityMatches")
pub fn native_host_source_capture_identity_matches(
  capture : @acquisition_host.NativeHostSourceCapture,
  identity : @query.CapturedSourceRelationIdentity,
) -> Bool {
  @acquisition_host.native_host_source_capture_identity_matches(
    capture, identity,
  )
}

///|
#export_name("nativeHostClose")
pub fn native_host_close(run : NativeNodeRun) -> Unit {
  run.stream_owner.val = false
  @acquisition_host.close_native_host(run.host)
  close_native_physical(run)
}

///|
#export_name("nativeHostIssueSourceEvidence")
pub fn native_host_issue_source_evidence(
  capture : @acquisition_host.NativeHostSourceCapture,
  context : @acquisition_host.NativeSourceEvidenceContext,
  identity : @query.CapturedSourceRelationIdentity,
  logical_input : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  effective_data_policy_cid : String,
  observed_at : String,
) -> String raise NodeHostFailure {
  match
    @acquisition_host.issue_native_host_source_evidence(
      capture, context, identity, logical_input, authority_scope_cid, effective_data_policy_cid,
      observed_at,
    ) {
    Ok(value) => @publication.run_evidence_value_json(value)
    Err(issue) => raise SourceEvidence(issue)
  }
}

///|
#export_name("nativeHostSourceCaptureSourceRef")
pub fn native_host_source_capture_source_ref(
  capture : @acquisition_host.NativeHostSourceCapture,
) -> String? {
  @acquisition_host.native_host_source_capture_source_ref(capture)
}

///|
// Both ordinary publication and original Effect capture use the same installed
// Source/Run ceilings. No separate Effect profile increases export capacity.
fn local_result_output_limits(
  run : LocalRunInstallation,
  configuration : @source_owner.ResidentSourceComputeConfiguration,
) -> @run_host.PublicationOutputExportLimits {
  let native = configuration.dispatch.native
  let transport = configuration.dispatch.transport
  let wire : @execution.RowWireLimits = {
    max_columns: transport.max_columns,
    max_order_work: native.metadata_work,
    max_bytes: run.result_payload_bytes.to_int(),
    max_nodes: native.values.max_nodes,
    max_depth: native.values.max_depth,
  }
  {
    max_result_fields: transport.max_columns,
    max_result_mapping_work: native.metadata_work,
    max_result_order_work: native.metadata_work,
    max_result_workspace_entries: native.metadata_work,
    max_rows: transport.max_rows,
    values: configuration.dispatch.local_execution.rows.output_values,
    payload_wire: wire,
    logical_wire: wire,
    schema: {
      max_fields: transport.max_columns,
      max_bytes: 65536,
      max_nodes: 8192,
      max_depth: 64,
    },
    max_batch_bytes: run.result_payload_bytes.to_int().min(16384),
  }
}

///|
// Preserve the original typed refusal without discarding the Work's custody.
priv enum LocalEffectOriginalCaptureIssue {
  Submission(@local_host.NativeClientSubmittedEffectMaterialsIssue)
  Capture(@local_host.NativeClientEffectCaptureIssue)
}

///|
// The forthcoming trusted Local review assembly borrows this original Work.
// On success it retains the returned capture and Work separately; on failure
// the Work remains responsible for physical cleanup and any retry handle.
// The public Effect ingress still refuses until its authority supplier exists.
fn local_capture_effect_original(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  reference : @local_host.NativeClientSubmissionReference,
  request : @run_host.ClientRequestIdentity,
  work : @local_host.NativeClientEffectSourceWork,
  run : LocalRunInstallation,
  configuration : @source_owner.ResidentSourceComputeConfiguration,
) -> Result[
  @source_owner.ResidentLocalEffectCaptureContext,
  LocalEffectOriginalCaptureIssue,
] {
  match
    host.check_submitted_effect_capture_work(
      crypto,
      settings.principal,
      settings.connection,
      reference,
      request,
      work,
      @env.now().to_double(),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Submission(issue))
  }
  work
  .prepare_original_capture_context(
    run.retention,
    local_result_output_limits(run, configuration),
    65536,
    8192,
    64,
  )
  .map_err(issue => Capture(issue))
}

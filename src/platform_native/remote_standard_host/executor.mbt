///|
/// Limits for deriving one remote retained representation from an exact
/// standard Local or DuckDB task output. They bound both the semantic export
/// and its compact physical manifest.
pub(all) struct NativeRemoteStandardTaskLimits {
  output_export : @publication_host.PublicationOutputExportLimits
  max_manifest_bytes : Int
  max_retained_bytes : Int64
}

///|
/// Product integration failures detected before an executor can be installed.
pub(all) enum NativeRemoteStandardHostIssue {
  InvalidConfiguration
  Runtime(@runtime.NativeRemoteRuntimeIssue)
}

///|
/// One exact standard-Host task prepared for installation in a native Site
/// component. The runtime executor stays opaque so application composition
/// cannot replace the checked Local or DuckDB completion boundary.
struct NativeRemoteStandardTaskExecutor {
  executor : @runtime.NativeRemoteTaskExecutor
}

///|
/// One exact standard Run opened from the dispatch-bound input owner. The
/// resolver must retain the input until `finish_input` is called after the
/// synchronous Connector has stopped reading it. A raw preconfigured Run
/// cannot cross the remote task installation boundary.
struct NativeRemoteStandardBoundRun {
  request_cid : String
  input_binding_cid : String
  run : @native_host.NativeStandardStrategyRun
  finish_input_owner : () -> Bool
  mut input_finished : Bool
}

///|
/// A resolver failure that retains any input cleanup owner acquired before a
/// standard Run could be bound. The common runtime, rather than the resolver,
/// decides when the dispatch may settle from this physical cleanup report.
struct NativeRemoteStandardInputFailure {
  code : String
  cleanup : () -> Bool
  mut cleanup_complete : Bool
}

///|
/// Stable diagnostic category for an input resolver failure. It is not a
/// substitute for retrying the attached physical cleanup owner.
pub fn native_remote_standard_input_failure_code(
  failure : NativeRemoteStandardInputFailure,
) -> String {
  failure.code
}

///|
/// Retry the exact physical owner retained by an input resolver failure.
pub fn retry_native_remote_standard_input_failure_cleanup(
  failure : NativeRemoteStandardInputFailure,
) -> Bool {
  if failure.cleanup_complete {
    return true
  }
  if (failure.cleanup)() {
    failure.cleanup_complete = true
    true
  } else {
    false
  }
}

///|
/// Reports the current physical cleanup responsibility retained by this
/// failure. Environment adapters may observe this state but do not derive it.
pub fn native_remote_standard_input_failure_cleanup_pending(
  failure : NativeRemoteStandardInputFailure,
) -> Bool {
  !failure.cleanup_complete
}

///|
pub fn prepare_native_remote_standard_input_failure(
  code : String,
  cleanup : () -> Bool,
) -> Result[NativeRemoteStandardInputFailure, NativeRemoteStandardHostIssue] {
  if code.is_empty() || code.length() > 128 {
    return Err(InvalidConfiguration)
  }
  Ok({ code, cleanup, cleanup_complete: false, })
}

///|
pub fn reject_native_remote_standard_input(
  code : String,
) -> Result[NativeRemoteStandardInputFailure, NativeRemoteStandardHostIssue] {
  prepare_native_remote_standard_input_failure(code, () => true)
}

///|
pub fn bind_native_remote_standard_run(
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  run : @native_host.NativeStandardStrategyRun,
  finish_input_owner : () -> Bool,
) -> Result[NativeRemoteStandardBoundRun, NativeRemoteStandardHostIssue] {
  let binding_cid = @remote.remote_input_binding_cid(binding)
  if !@remote.remote_input_binding_matches_dispatch(binding, request) {
    return Err(InvalidConfiguration)
  }
  Ok({
    request_cid: @remote.dispatch_request_identity(request),
    input_binding_cid: binding_cid,
    run,
    finish_input_owner,
    input_finished: false,
  })
}

///|
fn NativeRemoteStandardBoundRun::finish_input(
  self : NativeRemoteStandardBoundRun,
) -> Bool {
  if self.input_finished {
    return true
  }
  if (self.finish_input_owner)() {
    self.input_finished = true
    true
  } else {
    false
  }
}

///|
fn NativeRemoteStandardBoundRun::release(
  self : NativeRemoteStandardBoundRun,
) -> Bool {
  match @native_host.close_native_standard_strategy_run(self.run) {
    Ok(true) => self.finish_input()
    Ok(false) | Err(_) => false
  }
}

///|
priv struct NativeRemoteStandardOutputOwner {
  output_export : @publication_host.PublicationOutputExport
  bound : NativeRemoteStandardBoundRun
  mut export_cancelled : Bool
  mut released : Bool
}

///|
priv struct NativeRemoteStandardReaderState {
  replay : @publication_host.PublicationOutputReplay
  mut pending : Bytes?
  mut offset : Int
  mut replay_finished : Bool
  mut eof_reported : Bool
  mut closed : Bool
}

///|
fn remote_standard_failure(
  bound : NativeRemoteStandardBoundRun,
  code : String,
) -> @runtime.NativeRemotePhysicalExecution {
  if bound.release() {
    @runtime.prepare_native_remote_failure(code, false, false, true, () => true).unwrap()
  } else {
    @runtime.prepare_native_remote_failure(code, false, true, false, () => {
      bound.release()
    }).unwrap()
  }
}

///|
fn remote_standard_rejection(
  failure : NativeRemoteStandardInputFailure,
) -> @runtime.NativeRemotePhysicalExecution {
  if retry_native_remote_standard_input_failure_cleanup(failure) {
    @runtime.prepare_native_remote_failure(failure.code, false, false, true, () => {
      true
    }).unwrap()
  } else {
    @runtime.prepare_native_remote_failure(failure.code, false, true, false, () => {
      retry_native_remote_standard_input_failure_cleanup(failure)
    }).unwrap()
  }
}

///|
fn remote_standard_material_generation(
  request : @remote.DispatchRequest,
  physical_content_cid : String,
  task : Int,
) -> String? {
  let writer = @encode.writer(1024, 12, 2) catch { _ => return None }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, @remote.dispatch_request_identity(request))
    @encode.key(writer, "physical_content_cid")
    @encode.string_value(writer, physical_content_cid)
    @encode.key(writer, "task")
    @encode.number_value(writer, task.to_double())
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-remote-output-generation/0.1")
    @encode.end_object(writer)
    let body = @encode.finish(writer)
    match @sha.text_hex(body) {
      Ok(hex) => Some("sha256:" + hex)
      Err(_) => None
    }
  } catch {
    _ => None
  }
}

///|
fn NativeRemoteStandardOutputOwner::release(
  self : NativeRemoteStandardOutputOwner,
) -> Bool {
  if self.released {
    return true
  }
  if !self.export_cancelled {
    self.output_export.cancel()
    self.export_cancelled = true
  }
  if self.bound.release() {
    self.released = true
    true
  } else {
    false
  }
}

///|
fn native_remote_standard_reader_next(
  state : NativeRemoteStandardReaderState,
  max_bytes : Int,
) -> Result[@runtime.NativeRemoteOutputChunk, String] {
  if state.closed || max_bytes < 1 {
    return Err("invalid-reader-state")
  }
  while true {
    match state.pending {
      Some(bytes) if state.offset < bytes.length() => {
        let count = Int::min(max_bytes, bytes.length() - state.offset)
        let output = Bytes::from_array(
          Array::makei(count, index => bytes[state.offset + index]),
        )
        state.offset += count
        return Ok({ bytes: output, eof: false, })
      }
      _ => {
        state.pending = None
        state.offset = 0
      }
    }
    if state.replay_finished {
      state.eof_reported = true
      return Ok({ bytes: Bytes::new(0), eof: true, })
    }
    match state.replay.next() {
      Err(_) => return Err("output-replay-read")
      Ok(Some(text)) => state.pending = Some(@utf8.encode(text))
      Ok(None) =>
        match state.replay.finish() {
          Err(_) => return Err("output-replay-finish")
          Ok(tail) => {
            state.replay_finished = true
            state.pending = Some(@utf8.encode(tail))
          }
        }
    }
  } nobreak {
    Err("output-replay-state")
  }
}

///|
fn NativeRemoteStandardOutputOwner::open_reader(
  self : NativeRemoteStandardOutputOwner,
) -> Result[@runtime.NativeRemotePhysicalReader, String] {
  if self.released || self.export_cancelled {
    return Err("output-released")
  }
  let replay = match self.output_export.replay() {
    Ok(value) => value
    Err(_) => return Err("output-replay-open")
  }
  let state : NativeRemoteStandardReaderState = {
    replay,
    pending: None,
    offset: 0,
    replay_finished: false,
    eof_reported: false,
    closed: false,
  }
  Ok(
    @runtime.prepare_native_remote_physical_reader(
      max_bytes => native_remote_standard_reader_next(state, max_bytes),
      () => {
        if state.closed {
          Ok(())
        } else if !state.eof_reported {
          Err("output-reader-incomplete")
        } else {
          state.closed = true
          Ok(())
        }
      },
      () => {
        if !state.closed && !state.replay_finished {
          state.replay.cancel()
        }
        state.closed = true
        Ok(())
      },
    ),
  )
}

///|
fn execute_native_remote_standard_task(
  expected_task : Int,
  resolve_run : (@remote.DispatchRequest, @remote.RemoteInputBinding) -> Result[
    NativeRemoteStandardBoundRun,
    NativeRemoteStandardInputFailure,
  ],
  limits : NativeRemoteStandardTaskLimits,
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  budget : @remote.RemoteDispatchBudget,
) -> @runtime.NativeRemotePhysicalExecution {
  let bound = match resolve_run(request, binding) {
    Ok(value) => value
    Err(failure) => return remote_standard_rejection(failure)
  }
  if bound.request_cid != @remote.dispatch_request_identity(request) ||
    bound.input_binding_cid != @remote.remote_input_binding_cid(binding) {
    ignore(bound.release())
    return remote_standard_rejection(
      reject_native_remote_standard_input("foreign-input-binding").unwrap(),
    )
  }
  let run = bound.run
  let completion = match
    @native_host.execute_next_native_standard_strategy_task(run) {
    Ok(Some(value)) => value
    Ok(None) => return remote_standard_failure(bound, "missing-standard-task")
    Err(_) => return remote_standard_failure(bound, "standard-task-failed")
  }
  if completion.task != expected_task {
    return remote_standard_failure(bound, "foreign-standard-task")
  }
  if !bound.finish_input() {
    return remote_standard_failure(bound, "standard-input-cleanup")
  }
  let output_export = match
    @publication_host.prepare_publication_output_export(
      completion.output,
      limits.output_export,
    ) {
    Ok(value) => value
    Err(_) => return remote_standard_failure(bound, "output-export-prepare")
  }
  while true {
    match output_export.next() {
      Ok(Some(_)) => continue
      Ok(None) => break
      Err(_) => {
        output_export.cancel()
        return remote_standard_failure(bound, "output-export-read")
      }
    }
  }
  match output_export.finish() {
    Ok(_) => ()
    Err(_) => {
      output_export.cancel()
      return remote_standard_failure(bound, "output-export-finish")
    }
  }
  let content_cid = match output_export.content_cid() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_failure(bound, "output-content-identity")
    }
  }
  let content_bytes = match output_export.content_bytes() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_failure(bound, "output-content-size")
    }
  }
  let row_count = match output_export.row_count() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_failure(bound, "output-row-count")
    }
  }
  let result_schema_cid = match output_export.result_schema_cid() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_failure(bound, "output-schema-identity")
    }
  }
  let logical_view_cid = match output_export.logical_relation_cid() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_failure(bound, "output-view-identity")
    }
  }
  let codec_cid = match output_export.codec_contract_cid() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_failure(bound, "output-codec-identity")
    }
  }
  let measured = match output_export.measurement() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_failure(bound, "output-measurement")
    }
  }
  let measurement = match
    @remote.prepare_remote_managed_output_measurement(
      measured.row_count,
      measured.admission_nodes,
      measured.admission_text_bytes,
      measured.admission_work,
      measured.column_rows,
      measured.column_bytes,
      measured.column_nodes,
      measured.column_max_value_bytes,
      measured.column_null_rows,
      measured.column_admitted_depths,
    ) {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_failure(bound, "output-measurement-admission")
    }
  }
  let retained_bytes = content_bytes.to_int64()
  let (admitted_retained, _) = @remote.remote_dispatch_budget_capacity(budget)
  if retained_bytes > limits.max_retained_bytes ||
    retained_bytes > admitted_retained {
    output_export.cancel()
    return remote_standard_failure(bound, "output-capacity")
  }
  let manifest = match
    @manifest.admit(
      "actql-managed-physical-manifest/0.1",
      result_schema_cid,
      logical_view_cid,
      codec_cid,
      row_count,
      [content_cid],
      [retained_bytes],
      [row_count],
      1,
      limits.max_manifest_bytes,
      limits.max_retained_bytes,
    ) {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_failure(bound, "output-manifest")
    }
  }
  let material_generation = match
    remote_standard_material_generation(request, content_cid, expected_task) {
    Some(value) => value
    None => {
      output_export.cancel()
      return remote_standard_failure(bound, "output-generation")
    }
  }
  let owner : NativeRemoteStandardOutputOwner = {
    output_export,
    bound,
    export_cancelled: false,
    released: false,
  }
  match
    @runtime.prepare_native_remote_output(
      {
        material_generation,
        managed_profile_cid: @execution.managed_execution_profile_cid(
          @execution.selected_managed_execution_profile(),
        ),
        result_schema_cid,
        logical_view_cid,
        representation_codec_cid: codec_cid,
        physical_manifest_cid: @manifest.manifest_cid(manifest),
        row_count,
        retained_bytes,
        measurement,
      },
      () => owner.open_reader(),
      () => owner.release(),
    ) {
    Ok(value) => value
    Err(_) => {
      ignore(owner.release())
      remote_standard_failure(bound, "output-runtime-admission")
    }
  }
}

///|
/// Install one exact checked task from the native standard Local/DuckDB Host
/// into the common remote runtime registry. The physical implementation cannot
/// supply output identity, measurement, manifest, or lifecycle authority;
/// those are derived here from the admitted common output and runtime owner.
/// A fresh exact Run is opened only after the input binding matches, so a
/// foreign dispatch cannot consume or close a preconfigured Run owner.
pub fn install_native_remote_standard_task_executor(
  run_definition_cid : String,
  task_key : String,
  expected_task : Int,
  resolve_run : (@remote.DispatchRequest, @remote.RemoteInputBinding) -> Result[
    NativeRemoteStandardBoundRun,
    NativeRemoteStandardInputFailure,
  ],
  limits : NativeRemoteStandardTaskLimits,
) -> Result[NativeRemoteStandardTaskExecutor, NativeRemoteStandardHostIssue] {
  if expected_task < 0 ||
    limits.max_manifest_bytes < 1 ||
    limits.max_retained_bytes < 0L {
    return Err(InvalidConfiguration)
  }
  @runtime.install_native_remote_task_executor(run_definition_cid, task_key, (
    request,
    binding,
    budget,
  ) => {
    execute_native_remote_standard_task(
      expected_task, resolve_run, limits, request, binding, budget,
    )
  })
  .map(executor => { executor, })
  .map_err(issue => Runtime(issue))
}

///|
/// Open the standard native Remote Site runtime from one verified active
/// component and an exact registry of checked Local or DuckDB tasks. This is
/// the product composition boundary used by a statically linked Site
/// component; callers cannot install an unrelated physical executor through
/// this API.
pub fn open_native_remote_standard_site_runtime(
  site : @site.ExecutionSite,
  active_runtime : @bundle.NativeActiveRuntimeBinding,
  operation_capability_cid : String,
  issuer_capability_cid : String,
  tasks : Array[NativeRemoteStandardTaskExecutor],
  journal : @journal.Journal,
  bundles : @bundle.NativeRuntimeBundleStore,
  budgets : Array[@remote.RemoteDispatchBudget],
) -> Result[@runtime.NativeRemoteRuntime, NativeRemoteStandardHostIssue] {
  if tasks.is_empty() || budgets.is_empty() {
    return Err(InvalidConfiguration)
  }
  let executors = tasks.map(task => task.executor)
  let registration = match
    @runtime.install_native_remote_runtime_registry_registration(
      site, active_runtime, operation_capability_cid, issuer_capability_cid, executors,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Runtime(issue))
  }
  @runtime.open_native_remote_runtime(journal, bundles, [registration], budgets).map_err(issue => {
      Runtime(issue)
    },
  )
}

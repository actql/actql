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
priv struct NativeRemoteStandardOutputOwner {
  output_export : @publication_host.PublicationOutputExport
  run : @native_host.NativeStandardStrategyRun
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
  run : @native_host.NativeStandardStrategyRun,
  code : String,
) -> @runtime.NativeRemotePhysicalExecution {
  match @native_host.close_native_standard_strategy_run(run) {
    Ok(true) =>
      @runtime.prepare_native_remote_failure(code, false, false, true, () => {
        true
      }).unwrap()
    Ok(false) | Err(_) =>
      @runtime.prepare_native_remote_failure(code, false, true, false, () => {
        @native_host.close_native_standard_strategy_run(run) is Ok(true)
      }).unwrap()
  }
}

///|
fn remote_standard_rejection(
  code : String,
) -> @runtime.NativeRemotePhysicalExecution {
  @runtime.prepare_native_remote_failure(code, false, false, true, () => true).unwrap()
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
  match @native_host.close_native_standard_strategy_run(self.run) {
    Ok(true) => {
      self.released = true
      true
    }
    Ok(false) | Err(_) => false
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
  expected_binding_cid : String,
  expected_task : Int,
  open_run : () -> Result[@native_host.NativeStandardStrategyRun, String],
  limits : NativeRemoteStandardTaskLimits,
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  budget : @remote.RemoteDispatchBudget,
) -> @runtime.NativeRemotePhysicalExecution {
  if @remote.remote_input_binding_cid(binding) != expected_binding_cid {
    return remote_standard_rejection("foreign-input-binding")
  }
  let run = match open_run() {
    Ok(value) => value
    Err(_) => return remote_standard_rejection("standard-run-open")
  }
  let completion = match
    @native_host.execute_next_native_standard_strategy_task(run) {
    Ok(Some(value)) => value
    Ok(None) => return remote_standard_failure(run, "missing-standard-task")
    Err(_) => return remote_standard_failure(run, "standard-task-failed")
  }
  if completion.task != expected_task {
    return remote_standard_failure(run, "foreign-standard-task")
  }
  let output_export = match
    @publication_host.prepare_publication_output_export(
      completion.output,
      limits.output_export,
    ) {
    Ok(value) => value
    Err(_) => return remote_standard_failure(run, "output-export-prepare")
  }
  while true {
    match output_export.next() {
      Ok(Some(_)) => continue
      Ok(None) => break
      Err(_) => {
        output_export.cancel()
        return remote_standard_failure(run, "output-export-read")
      }
    }
  }
  match output_export.finish() {
    Ok(_) => ()
    Err(_) => {
      output_export.cancel()
      return remote_standard_failure(run, "output-export-finish")
    }
  }
  let content_cid = match output_export.content_cid() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_failure(run, "output-content-identity")
    }
  }
  let content_bytes = match output_export.content_bytes() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_failure(run, "output-content-size")
    }
  }
  let row_count = match output_export.row_count() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_failure(run, "output-row-count")
    }
  }
  let result_schema_cid = match output_export.result_schema_cid() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_failure(run, "output-schema-identity")
    }
  }
  let logical_view_cid = match output_export.logical_relation_cid() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_failure(run, "output-view-identity")
    }
  }
  let codec_cid = match output_export.codec_contract_cid() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_failure(run, "output-codec-identity")
    }
  }
  let measured = match output_export.measurement() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_failure(run, "output-measurement")
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
      return remote_standard_failure(run, "output-measurement-admission")
    }
  }
  let retained_bytes = content_bytes.to_int64()
  let (admitted_retained, _) = @remote.remote_dispatch_budget_capacity(budget)
  if retained_bytes > limits.max_retained_bytes ||
    retained_bytes > admitted_retained {
    output_export.cancel()
    return remote_standard_failure(run, "output-capacity")
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
      return remote_standard_failure(run, "output-manifest")
    }
  }
  let material_generation = match
    remote_standard_material_generation(request, content_cid, expected_task) {
    Some(value) => value
    None => {
      output_export.cancel()
      return remote_standard_failure(run, "output-generation")
    }
  }
  let owner : NativeRemoteStandardOutputOwner = {
    output_export,
    run,
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
      remote_standard_failure(run, "output-runtime-admission")
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
  expected_input_binding_cid : String,
  expected_task : Int,
  open_run : () -> Result[@native_host.NativeStandardStrategyRun, String],
  limits : NativeRemoteStandardTaskLimits,
) -> Result[NativeRemoteStandardTaskExecutor, NativeRemoteStandardHostIssue] {
  if expected_input_binding_cid.is_empty() ||
    expected_task < 0 ||
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
      expected_input_binding_cid, expected_task, open_run, limits, request, binding,
      budget,
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

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
  owner : NativeRemoteStandardRunOwner
}

///|
/// One fresh standard Run and its exact input owner. The factory that creates
/// this value is fixed before remote runtime admission; a dispatch cannot
/// replace either the Run or its cleanup responsibility.
struct NativeRemoteStandardRunOwner {
  run : NativeRemoteStandardRun
  finish_output_owner : () -> Bool
  finish_input_owner : () -> Bool
  mut run_finished : Bool
  mut output_finished : Bool
  mut input_finished : Bool
  source_observation : ((@remote.DispatchRequest) -> Result[
    @remote.RemoteSourceObservation,
    @remote.DispatchIssue,
  ])?
}

///|
/// A captured acquisition is already a completed checked task. It shares
/// the standard runtime owner without inventing a Compute execution.
priv enum NativeRemoteStandardRun {
  Compute(@native_host.NativeStandardStrategyRun)
  Acquired(@strategy.CapturedDAG, Int, Int)
}

///|
/// A fresh standard strategy Run and its captured output owner before a
/// physical input scope has been attached. Store and direct input factories
/// use this opaque value so application composition cannot lose Captured DAG
/// cleanup when it hands the Run to the remote runtime.
struct NativeRemoteStandardComputeOwner {
  run : @native_host.NativeStandardStrategyRun
  finish_output_owner : () -> Bool
}

///|
/// Exact non-streaming input factory installed by one verified runtime
/// component. It admits only the input binding fixed at registration and
/// opens a fresh occurrence owner after that binding has been checked.
struct NativeRemoteStandardBoundRunFactory {
  input_binding_cid : String
  open : () -> Result[
    NativeRemoteStandardRunOwner,
    NativeRemoteStandardInputFailure,
  ]
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
fn bind_native_remote_standard_run(
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  owner : NativeRemoteStandardRunOwner,
) -> Result[NativeRemoteStandardBoundRun, NativeRemoteStandardHostIssue] {
  let binding_cid = @remote.remote_input_binding_cid(binding)
  if !@remote.remote_input_binding_matches_dispatch(binding, request) {
    return Err(InvalidConfiguration)
  }
  Ok({
    request_cid: @remote.dispatch_request_identity(request),
    input_binding_cid: binding_cid,
    owner,
  })
}

///|
/// Prepares one occurrence-owned standard Run. This does not bind the Run to
/// a dispatch or make it executable; only a registered exact factory can do
/// that after common runtime admission.
pub fn prepare_native_remote_standard_run_owner(
  run : @native_host.NativeStandardStrategyRun,
  finish_input_owner : () -> Bool,
) -> NativeRemoteStandardRunOwner {
  prepare_native_remote_standard_captured_run_owner(
    run,
    () => true,
    finish_input_owner,
  )
}

///|
/// Prepares one occurrence owner whose captured output lifetime remains
/// independent from its input lifetime. The output owner is released only
/// after the standard Run has stopped and remains retryable without rerunning
/// either physical cleanup step.
pub fn prepare_native_remote_standard_captured_run_owner(
  run : @native_host.NativeStandardStrategyRun,
  finish_output_owner : () -> Bool,
  finish_input_owner : () -> Bool,
) -> NativeRemoteStandardRunOwner {
  {
    run: Compute(run),
    finish_output_owner,
    finish_input_owner,
    run_finished: false,
    output_finished: false,
    input_finished: false,
    source_observation: None,
  }
}

///|
/// Retain one acquired Source Result under its existing captured DAG owner.
/// Its live input remains available until the last publication reader has
/// finished and the remote runtime authorizes release. This function opens
/// no database and does not execute or combine checked tasks.
pub fn prepare_native_remote_standard_acquired_run_owner(
  run : @strategy.CapturedDAG,
  result : Int,
  finish_input_owner : () -> Bool,
  source_observation? : ((@remote.DispatchRequest) -> Result[
    @remote.RemoteSourceObservation,
    @remote.DispatchIssue,
  ])? = None,
) -> Result[NativeRemoteStandardRunOwner, NativeRemoteStandardHostIssue] {
  let graph = @strategy.captured_dag_graph(run)
  guard @strategy.graph_result_task(graph, result) is Some(task) &&
    task < @strategy.captured_compute_first_task(run) else {
    return Err(InvalidConfiguration)
  }
  Ok({
    run: Acquired(run, result, task),
    finish_output_owner: () => true,
    finish_input_owner,
    run_finished: false,
    output_finished: false,
    input_finished: false,
    source_observation,
  })
}

///|
pub fn prepare_native_remote_standard_compute_owner(
  run : @native_host.NativeStandardStrategyRun,
  finish_output_owner : () -> Bool,
) -> NativeRemoteStandardComputeOwner {
  { run, finish_output_owner, }
}

///|
fn NativeRemoteStandardRunOwner::finish_input(
  self : NativeRemoteStandardRunOwner,
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
fn NativeRemoteStandardRunOwner::release(
  self : NativeRemoteStandardRunOwner,
) -> Bool {
  if !self.run_finished {
    match self.run {
      Compute(run) =>
        match @native_host.close_native_standard_strategy_run(run) {
          Ok(true) => self.run_finished = true
          Ok(false) | Err(_) => return false
        }
      Acquired(run, _, _) => {
        @strategy.stop_captured_dag(run)
        self.run_finished = true
      }
    }
  }
  if !self.output_finished {
    if !(self.finish_output_owner)() {
      return false
    }
    self.output_finished = true
  }
  self.finish_input()
}

///|
/// Registers one exact non-streaming input factory. Registration performs no
/// physical work and cannot authorize a foreign input binding.
pub fn register_native_remote_standard_bound_run_factory(
  binding : @remote.RemoteInputBinding,
  open : () -> Result[
    NativeRemoteStandardRunOwner,
    NativeRemoteStandardInputFailure,
  ],
) -> NativeRemoteStandardBoundRunFactory {
  { input_binding_cid: @remote.remote_input_binding_cid(binding), open, }
}

///|
/// Resolves one occurrence after both the dispatch binding and the factory's
/// exact registered binding have been checked.
fn NativeRemoteStandardBoundRunFactory::resolve(
  self : NativeRemoteStandardBoundRunFactory,
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
) -> Result[NativeRemoteStandardBoundRun, NativeRemoteStandardInputFailure] {
  if !@remote.remote_input_binding_matches_dispatch(binding, request) ||
    @remote.remote_input_binding_cid(binding) != self.input_binding_cid {
    return Err(
      reject_native_remote_standard_input("foreign-input-binding").unwrap(),
    )
  }
  let owner = match (self.open)() {
    Ok(value) => value
    Err(failure) => return Err(failure)
  }
  match bind_native_remote_standard_run(request, binding, owner) {
    Ok(value) => Ok(value)
    Err(_) =>
      Err(
        prepare_native_remote_standard_input_failure("standard-input-binding", () => {
          owner.release()
        }).unwrap(),
      )
  }
}

///|
fn NativeRemoteStandardBoundRun::finish_input(
  self : NativeRemoteStandardBoundRun,
) -> Bool {
  self.owner.finish_input()
}

///|
fn NativeRemoteStandardBoundRun::release(
  self : NativeRemoteStandardBoundRun,
) -> Bool {
  self.owner.release()
}

///|
priv struct NativeRemoteStandardOutputOwner {
  output_export : @publication_host.PublicationOutputExport
  release_run : () -> Bool
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
/// Bounded replay preserving the physical manifest chunks established by the
/// first traversal. One row is held for lookahead so only the final row chunk
/// receives the canonical array tail.
priv struct NativeRemoteStandardManifestReaderState {
  replay : @publication_host.PublicationOutputReplay
  mut pending : String?
  mut next_index : Int
  mut replay_finished : Bool
  mut closed : Bool
}

///|
fn remote_standard_release_failure(
  release_run : () -> Bool,
  code : String,
) -> @runtime.NativeRemotePhysicalExecution {
  if release_run() {
    @runtime.prepare_native_remote_failure(code, false, false, true, () => true).unwrap()
  } else {
    @runtime.prepare_native_remote_failure(code, false, true, false, () => {
      release_run()
    }).unwrap()
  }
}

///|
fn remote_standard_failure(
  bound : NativeRemoteStandardBoundRun,
  code : String,
) -> @runtime.NativeRemotePhysicalExecution {
  remote_standard_release_failure(() => bound.release(), code)
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
  if (self.release_run)() {
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
fn native_remote_standard_manifest_reader_next(
  state : NativeRemoteStandardManifestReaderState,
  index : Int,
) -> Result[Bytes, String] {
  if state.closed || state.replay_finished || index != state.next_index {
    return Err("invalid-manifest-reader-state")
  }
  if state.pending is None {
    match state.replay.next() {
      Err(_) => return Err("output-replay-read")
      Ok(Some(text)) => state.pending = Some(text)
      Ok(None) =>
        match state.replay.finish() {
          Err(_) => return Err("output-replay-finish")
          Ok(tail) => {
            state.replay_finished = true
            state.next_index += 1
            return Ok(@utf8.encode(tail))
          }
        }
    }
  }
  guard state.pending is Some(current) else {
    return Err("output-replay-state")
  }
  match state.replay.next() {
    Err(_) => Err("output-replay-read")
    Ok(Some(next)) => {
      state.pending = Some(next)
      state.next_index += 1
      Ok(@utf8.encode(current))
    }
    Ok(None) =>
      match state.replay.finish() {
        Err(_) => Err("output-replay-finish")
        Ok(tail) => {
          state.pending = None
          state.replay_finished = true
          state.next_index += 1
          Ok(@utf8.encode(current + tail))
        }
      }
  }
}

///|
fn NativeRemoteStandardOutputOwner::open_manifest_reader(
  self : NativeRemoteStandardOutputOwner,
) -> Result[@runtime.NativeRemotePhysicalManifestReader, String] {
  if self.released || self.export_cancelled {
    return Err("output-released")
  }
  let replay = match self.output_export.replay() {
    Ok(value) => value
    Err(_) => return Err("output-replay-open")
  }
  let state : NativeRemoteStandardManifestReaderState = {
    replay,
    pending: None,
    next_index: 0,
    replay_finished: false,
    closed: false,
  }
  Ok(
    @runtime.prepare_native_remote_physical_manifest_reader(
      index => native_remote_standard_manifest_reader_next(state, index),
      () => {
        if state.closed {
          Ok(())
        } else if !state.replay_finished || state.pending is Some(_) {
          Err("output-manifest-reader-incomplete")
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
  let output_export = match bound.owner.run {
    Compute(run) => {
      let completion = match
        @native_host.execute_next_native_standard_strategy_task(run) {
        Ok(Some(value)) => value
        Ok(None) =>
          return remote_standard_failure(bound, "missing-standard-task")
        Err(_) => return remote_standard_failure(bound, "standard-task-failed")
      }
      if completion.task != expected_task {
        return remote_standard_failure(bound, "foreign-standard-task")
      }
      if !bound.finish_input() {
        return remote_standard_failure(bound, "standard-input-cleanup")
      }
      match
        @publication_host.prepare_publication_output_export(
          completion.output,
          limits.output_export,
        ) {
        Ok(value) => value
        Err(_) => return remote_standard_failure(bound, "output-export-prepare")
      }
    }
    Acquired(run, result, task) => {
      if task != expected_task {
        return remote_standard_failure(bound, "foreign-standard-task")
      }
      match
        @publication_host.prepare_captured_result_publication_export(
          run,
          result,
          limits.output_export,
        ) {
        Ok(value) => value
        Err(_) => return remote_standard_failure(bound, "source-export-prepare")
      }
    }
  }
  let observation = match bound.owner.source_observation {
    None => None
    Some(issue) =>
      match issue(request) {
        Ok(value) => Some(value)
        Err(_) => {
          output_export.cancel()
          return remote_standard_failure(bound, "source-observation-rejected")
        }
      }
  }
  let physical = prepare_native_remote_standard_output_from_export(
    request,
    expected_task,
    output_export,
    () => bound.release(),
    limits,
    budget,
  )
  match observation {
    Some(value) =>
      @runtime.attach_native_remote_source_observation(
        physical, request, expected_task, value,
      )
    None => physical
  }
}

///|
/// Package an admitted output export for the native Site runtime. Its caller
/// must bind the export to the exact checked task before entering this API.
/// The output owner retains its Compute and bridge cleanup callback until the
/// runtime has finished every reader and manifest observation. This shared
/// path derives manifest, measurement, generation and replay identities for
/// standard tasks and source-free Local Values alike.
pub fn prepare_native_remote_standard_output_from_export(
  request : @remote.DispatchRequest,
  expected_task : Int,
  output_export : @publication_host.PublicationOutputExport,
  release_run : () -> Bool,
  limits : NativeRemoteStandardTaskLimits,
  budget : @remote.RemoteDispatchBudget,
) -> @runtime.NativeRemotePhysicalExecution {
  if expected_task < 0 ||
    limits.max_manifest_bytes < 1 ||
    limits.max_retained_bytes < 0L ||
    limits.output_export.max_batch_bytes < 1 ||
    limits.output_export.max_batch_bytes > 1048575 {
    output_export.cancel()
    return remote_standard_release_failure(release_run, "output-configuration")
  }
  let chunk_cids : Array[String] = []
  let chunk_byte_lengths : Array[Int64] = []
  let chunk_row_counts : Array[Int] = []
  let mut pending_chunk : String? = None
  while true {
    match output_export.next() {
      Ok(Some(text)) => {
        match pending_chunk {
          Some(previous) => {
            let bytes = @utf8.encode(previous)
            chunk_cids.push("sha256:" + @sha.hex(bytes))
            chunk_byte_lengths.push(bytes.length().to_int64())
            chunk_row_counts.push(1)
          }
          None => ()
        }
        pending_chunk = Some(text)
        continue
      }
      Ok(None) => break
      Err(_) => {
        output_export.cancel()
        return remote_standard_release_failure(
          release_run, "output-export-read",
        )
      }
    }
  }
  let tail = match output_export.finish() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_release_failure(
        release_run, "output-export-finish",
      )
    }
  }
  let final_chunk = match pending_chunk {
    Some(previous) => (previous + tail, 1)
    None => (tail, 0)
  }
  let final_bytes = @utf8.encode(final_chunk.0)
  chunk_cids.push("sha256:" + @sha.hex(final_bytes))
  chunk_byte_lengths.push(final_bytes.length().to_int64())
  chunk_row_counts.push(final_chunk.1)
  let content_cid = match output_export.content_cid() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_release_failure(
        release_run, "output-content-identity",
      )
    }
  }
  let content_bytes = match output_export.content_bytes() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_release_failure(release_run, "output-content-size")
    }
  }
  let mut physical_bytes = 0L
  for length in chunk_byte_lengths {
    if length < 0L || length > 1048576L {
      output_export.cancel()
      return remote_standard_release_failure(
        release_run, "output-manifest-chunk",
      )
    }
    physical_bytes += length
  }
  if physical_bytes != content_bytes.to_int64() {
    output_export.cancel()
    return remote_standard_release_failure(release_run, "output-manifest-size")
  }
  let row_count = match output_export.row_count() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_release_failure(release_run, "output-row-count")
    }
  }
  let result_schema_cid = match output_export.result_schema_cid() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_release_failure(
        release_run, "output-schema-identity",
      )
    }
  }
  let logical_view_cid = match output_export.logical_relation_cid() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_release_failure(
        release_run, "output-view-identity",
      )
    }
  }
  let codec_cid = match output_export.codec_contract_cid() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_release_failure(
        release_run, "output-codec-identity",
      )
    }
  }
  let measured = match output_export.measurement() {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_release_failure(release_run, "output-measurement")
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
      return remote_standard_release_failure(
        release_run, "output-measurement-admission",
      )
    }
  }
  let retained_bytes = content_bytes.to_int64()
  let (admitted_retained, _) = @remote.remote_dispatch_budget_capacity(budget)
  if retained_bytes > limits.max_retained_bytes ||
    retained_bytes > admitted_retained {
    output_export.cancel()
    return remote_standard_release_failure(release_run, "output-capacity")
  }
  let manifest = match
    @manifest.admit(
      "actql-managed-physical-manifest/0.1",
      result_schema_cid,
      logical_view_cid,
      codec_cid,
      row_count,
      chunk_cids,
      chunk_byte_lengths,
      chunk_row_counts,
      Int::max(row_count, 1),
      limits.max_manifest_bytes,
      limits.max_retained_bytes,
    ) {
    Ok(value) => value
    Err(_) => {
      output_export.cancel()
      return remote_standard_release_failure(release_run, "output-manifest")
    }
  }
  let material_generation = match
    remote_standard_material_generation(request, content_cid, expected_task) {
    Some(value) => value
    None => {
      output_export.cancel()
      return remote_standard_release_failure(release_run, "output-generation")
    }
  }
  let owner : NativeRemoteStandardOutputOwner = {
    output_export,
    release_run,
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
        physical_manifest: manifest,
        row_count,
        retained_bytes,
        measurement,
      },
      () => owner.open_reader(),
      () => owner.open_manifest_reader(),
      () => owner.release(),
    ) {
    Ok(value) => value
    Err(_) =>
      if owner.release() {
        @runtime.prepare_native_remote_failure(
          "output-runtime-admission",
          false,
          false,
          true,
          () => true,
        ).unwrap()
      } else {
        @runtime.prepare_native_remote_failure(
          "output-runtime-admission",
          false,
          true,
          false,
          () => owner.release(),
        ).unwrap()
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
fn install_native_remote_standard_task_executor(
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
    limits.max_retained_bytes < 0L ||
    limits.output_export.max_batch_bytes < 1 ||
    limits.output_export.max_batch_bytes > 1048575 {
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
/// Installs one exact non-streaming input factory into the remote runtime.
/// Application composition cannot inspect the dispatch or substitute a
/// different input binding after registration.
pub fn install_native_remote_standard_bound_task_executor(
  run_definition_cid : String,
  task_key : String,
  expected_task : Int,
  factory : NativeRemoteStandardBoundRunFactory,
  limits : NativeRemoteStandardTaskLimits,
) -> Result[NativeRemoteStandardTaskExecutor, NativeRemoteStandardHostIssue] {
  install_native_remote_standard_task_executor(
    run_definition_cid,
    task_key,
    expected_task,
    (request, binding) => factory.resolve(request, binding),
    limits,
  )
}

///|
/// Installs one exact durable-Store task factory into the remote runtime.
/// Application composition supplies only the checked task identity and output
/// limits; it cannot replace input verification or physical ownership.
pub fn install_native_remote_standard_store_task_executor(
  run_definition_cid : String,
  task_key : String,
  expected_task : Int,
  factory : NativeRemoteStandardStoreRunFactory,
  limits : NativeRemoteStandardTaskLimits,
) -> Result[NativeRemoteStandardTaskExecutor, NativeRemoteStandardHostIssue] {
  install_native_remote_standard_task_executor(
    run_definition_cid,
    task_key,
    expected_task,
    (request, binding) => factory.resolve(request, binding),
    limits,
  )
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

///|
/// Restoration is not execution. Pending carries the existing physical
/// cleanup callback, but does not change the original dispatch's outcome.
pub(all) enum NativeRemoteOutputRestoration {
  NativeRestoredOutput(@runtime.NativeRemotePhysicalExecution)
  NativeOutputRestorationPending(String, () -> Bool)
}

///|
fn restored_output_refused(
  code : String,
  release : () -> Bool,
) -> NativeRemoteOutputRestoration {
  // The original operation is already settled. Input restoration failure is
  // not an unknown execution or permission to execute the task again.
  NativeOutputRestorationPending(code, release)
}

///|
/// Keep the original exact cleanup obligation even when opening its root is
/// temporarily unavailable. A recovered handle is cached for unlink/sync retry.
fn retry_restored_standard_cleanup(
  root_path : String,
  custody : @journal.NativeOutputFileCustody,
  max_bytes : Int64,
  release_input : () -> Bool,
) -> () -> Bool {
  let cleanup : Ref[(() -> Bool)?] = Ref(None)
  () => {
    if cleanup.val is None {
      let file = match
        @retained_file.restore_native_retained_task_file_cleanup(
          root_path,
          @journal.native_output_file_custody_occurrence(custody),
          @journal.native_output_file_custody_generation(custody),
          @journal.native_output_file_custody_content_cid(custody),
          max_bytes,
        ) {
        Ok(value) => value
        Err(_) => return false
      }
      cleanup.val = Some(
        retain_standard_output_cleanup(Some(file), release_input),
      )
    }
    cleanup.val.unwrap()()
  }
}

///|
fn verify_restored_standard_stream(
  file : @retained_file.NativeRetainedTaskFile,
  current : () -> Bool,
) -> Result[Unit, String] {
  if !current() {
    return Err("output-restore-current")
  }
  let reader = match file.open_reader() {
    Ok(value) => value
    Err(_) => return Err("output-restore-content")
  }
  while true {
    if !current() {
      ignore(reader.close())
      return Err("output-restore-current")
    }
    match reader.next(65536) {
      Ok(chunk) if chunk.eof => {
        if !current() {
          ignore(reader.close())
          return Err("output-restore-current")
        }
        if reader.finish() is Ok(_) {
          return Ok(())
        }
        ignore(reader.close())
        return Err("output-restore-content")
      }
      Ok(_) => ()
      Err(_) => {
        ignore(reader.close())
        return Err("output-restore-content")
      }
    }
  } nobreak {
    Err("output-restore-content")
  }
}

///|
/// Reopen exact saved output after the former holder stopped. The trusted
/// current port must inspect the live Site generation/authority and exclusive
/// slot, not saved snapshot fields. This restores file handles only, not a Site holding,
/// runtime owner, capacity reservation, borrow or execution permission.
/// Rejected physical restoration returns the original cleanup callback.
pub fn restore_native_remote_standard_output(
  recovered : @journal.RecoveredSiteDispatch,
  root_path : String,
  max_bytes : Int64,
  current : () -> Bool,
  cleanup_current? : (() -> Bool)? = None,
  release_input? : () -> Bool = () => true,
) -> NativeRemoteOutputRestoration {
  let initially_current = current()
  let record = @journal.recovered_site_dispatch_record(recovered)
  guard @journal.recovered_site_dispatch_file_custody(recovered)
    is Some(custody) &&
    @journal.recovered_site_dispatch_evidence(recovered) is Some(evidence) &&
    @journal.recovered_site_dispatch_subject(recovered) is Some(subject) &&
    @journal.recovered_site_dispatch_measurement(recovered) is Some(measurement) else {
    return restored_output_refused("output-restore-evidence", () => false)
  }
  if @remote.restore_remote_runtime_completed_custody(
      record, evidence, subject, measurement,
    )
    is Err(_) {
    return restored_output_refused("output-restore-state", () => false)
  }
  let cleanup_authorized = cleanup_current.unwrap_or(current)
  let retry_cleanup = retry_restored_standard_cleanup(
    root_path, custody, max_bytes, release_input,
  )
  let cleanup = () => cleanup_authorized() && retry_cleanup()
  let occurrence = @journal.native_output_file_custody_occurrence(custody)
  let generation = @journal.native_output_file_custody_generation(custody)
  let content_cid = @journal.native_output_file_custody_content_cid(custody)
  if !initially_current || !current() {
    return restored_output_refused("output-restore-current", cleanup)
  }
  let file = match
    @retained_file.restore_native_retained_task_file(
      root_path, occurrence, generation, content_cid, max_bytes,
    ) {
    Ok(value) => value
    Err(_) => return restored_output_refused("output-restore-physical", cleanup)
  }
  let release = retain_standard_output_cleanup(Some(file), release_input)
  if verify_restored_standard_stream(file, current) is Err(code) {
    return restored_output_refused(code, release)
  }
  if !current() {
    return restored_output_refused("output-restore-current", release)
  }
  let manifest = @journal.native_output_file_custody_manifest(custody)
  let fields = @remote.remote_managed_output_subject_projection(subject)
  let facts : @runtime.NativeRemoteOutputFacts = {
    material_generation: @journal.native_output_file_custody_material_generation(
      custody,
    ),
    managed_profile_cid: fields[3],
    result_schema_cid: fields[4],
    logical_view_cid: fields[5],
    representation_codec_cid: fields[6],
    physical_manifest: manifest,
    row_count: manifest.row_count,
    retained_bytes: generation.size,
    measurement,
  }
  let execution = match
    @runtime.prepare_native_remote_output(
      facts,
      () => open_retained_standard_reader(file),
      () => {
        open_retained_standard_manifest_reader(
          file,
          manifest.chunks.map(chunk => chunk.byte_length),
        )
      },
      release,
      file_custody=Some(custody),
    ) {
    Ok(value) => value
    Err(_) => return restored_output_refused("output-restore-facts", release)
  }
  let attached = match
    @journal.recovered_site_dispatch_source_observation(recovered) {
    None => execution
    Some(source) =>
      @runtime.attach_native_remote_source_observation(
        execution,
        @remote.dispatch_record_request(record),
        @remote.remote_source_observation_projection(source).0,
        source,
      )
  }
  match attached {
    @runtime.NativeRemoteOutputReady(_) => NativeRestoredOutput(attached)
    @runtime.NativeRemoteExecutionFailed(_) =>
      restored_output_refused("output-restore-source", release)
  }
}

///|
/// Join the physical restoration port to the existing Runtime, which owns
/// capacity and formal release. Pending requires retaining this same Runtime.
pub fn restore_native_remote_standard_runtime_output(
  runtime : @runtime.NativeRemoteRuntime,
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  root_path : String,
  max_bytes : Int64,
  current : () -> Bool,
  cleanup_current? : (() -> Bool)? = None,
  release_input? : () -> Bool = () => true,
) -> @runtime.NativeCompletedRuntimeRestoration {
  let custody_current = cleanup_current.unwrap_or(current)
  let cleanup : @runtime.NativeCompletedCleanupRestoration = {
    current: custody_current,
    restore: recovered => {
      guard @journal.recovered_site_dispatch_file_custody(recovered)
        is Some(custody) else {
        return () => false
      }
      retry_restored_standard_cleanup(
        root_path, custody, max_bytes, release_input,
      )
    },
  }
  runtime.restore_completed(
    request,
    binding,
    current,
    recovered => {
      match
        restore_native_remote_standard_output(
          recovered,
          root_path,
          max_bytes,
          current,
          cleanup_current=Some(custody_current),
          release_input~,
        ) {
        NativeRestoredOutput(@runtime.NativeRemoteOutputReady(output)) =>
          @runtime.RestoredCompletedOutput(output)
        NativeRestoredOutput(@runtime.NativeRemoteExecutionFailed(_)) =>
          @runtime.CompletedOutputUnavailable("output-restore-facts", () => {
            false
          })
        NativeOutputRestorationPending(code, cleanup) =>
          @runtime.CompletedOutputUnavailable(code, cleanup)
      }
    },
    cleanup=Some(cleanup),
  )
}

///|
/// Recover the existing sealed-output cleanup without reopening payload use.
/// Both this file and the original input owner must confirm physical cleanup.
pub fn prepare_native_remote_standard_saved_output_cleanup(
  recovered : @journal.RecoveredSiteDispatch,
  root_path : String,
  max_bytes : Int64,
  release_input : () -> Bool,
  cleanup_current : () -> Bool,
) -> (() -> Bool)? {
  @journal.recovered_site_dispatch_file_custody(recovered).map(custody => {
    let cleanup = retry_restored_standard_cleanup(
      root_path, custody, max_bytes, release_input,
    )
    () => cleanup_current() && cleanup()
  })
}

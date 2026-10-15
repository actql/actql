///|
/// Immutable transport of the existing Runtime Owner's result. This is not a
/// new installation, resource, current-policy or cleanup authority.
pub(all) enum NativeLocalPackagedRuntimeOperation {
  CapturePackagedRuntime
  ObservePackagedRuntime
  ClosePackagedRuntime
} derive(Eq)

///|
struct NativeLocalPackagedRuntimeReply {
  operation : NativeLocalPackagedRuntimeOperation
  original_read : (@arena.InstalledArenaHost, @arena.InstalledArenaOriginalRead)?
  runtime : NativeLocalPackagedRuntime?
  issue : NativeLocalPackagedRuntimeIssue?
}

///|
/// Only the original scoped constructor is selected. Missing supply remains
/// a typed refusal before Root acquisition; the legacy entry is never used.
pub fn capture_native_local_packaged_runtime_reply(
  original_read : (@arena.InstalledArenaHost, @arena.InstalledArenaOriginalRead)?,
  root_path : String,
  source_sha : String,
  platform : String,
  manifest_sha256 : String,
  diagnostic_ceiling : Int,
) -> NativeLocalPackagedRuntimeReply {
  let (runtime, issue) = match
    open_native_local_packaged_runtime_in_original_read(
      original_read, root_path, source_sha, platform, manifest_sha256, diagnostic_ceiling,
    ) {
    Ok(value) => (Some(value), None)
    Err(Refused(issue)) => (None, Some(issue))
    Err(Pending(value, issue)) => (Some(value), Some(issue))
  }
  { operation: CapturePackagedRuntime, original_read, runtime, issue, }
}

///|
fn local_packaged_runtime_unit_reply(
  operation : NativeLocalPackagedRuntimeOperation,
  runtime : NativeLocalPackagedRuntime,
  result : Result[Unit, NativeLocalPackagedRuntimeIssue],
) -> NativeLocalPackagedRuntimeReply {
  {
    operation,
    original_read: runtime.original_read,
    runtime: Some(runtime),
    issue: match result {
      Ok(_) => None
      Err(issue) => Some(issue)
    },
  }
}

///|
pub fn current_native_local_packaged_runtime_reply(
  runtime : NativeLocalPackagedRuntime,
) -> NativeLocalPackagedRuntimeReply {
  let result = if runtime.original_read is None {
    Err(OriginalReadUnavailable)
  } else {
    runtime.check_current()
  }
  local_packaged_runtime_unit_reply(ObservePackagedRuntime, runtime, result)
}

///|
/// Inner Root/Reader cleanup only. The reply retains the same Runtime and
/// parent carrier; only their caller may drop aliases before outer retirement.
pub fn close_native_local_packaged_runtime_reply(
  runtime : NativeLocalPackagedRuntime,
) -> NativeLocalPackagedRuntimeReply {
  let result = if runtime.original_read is None {
    Err(OriginalReadUnavailable)
  } else {
    runtime.close()
  }
  local_packaged_runtime_unit_reply(ClosePackagedRuntime, runtime, result)
}

///|
pub fn NativeLocalPackagedRuntimeReply::original_host(
  self : NativeLocalPackagedRuntimeReply,
) -> @arena.InstalledArenaHost? {
  self.original_read.map(value => value.0)
}

///|
pub fn NativeLocalPackagedRuntimeReply::original_read(
  self : NativeLocalPackagedRuntimeReply,
) -> @arena.InstalledArenaOriginalRead? {
  self.original_read.map(value => value.1)
}

///|
pub fn NativeLocalPackagedRuntimeReply::original_runtime(
  self : NativeLocalPackagedRuntimeReply,
) -> NativeLocalPackagedRuntime? {
  self.runtime
}

///|
pub fn NativeLocalPackagedRuntimeReply::operation_tag(
  self : NativeLocalPackagedRuntimeReply,
) -> Int {
  match self.operation {
    CapturePackagedRuntime => 1
    ObservePackagedRuntime => 2
    ClosePackagedRuntime => 3
  }
}

///|
/// Preserve the existing imported Unknown distinctly from known refusal and
/// cleanup pending. These tags describe results, not permission or final ACK.
pub fn NativeLocalPackagedRuntimeReply::issue_family(
  self : NativeLocalPackagedRuntimeReply,
) -> Int {
  match self.issue {
    None => 0
    Some(InvalidInput) => 1
    Some(InvalidManifest) => 2
    Some(Changed) => 3
    Some(Limit) => 4
    Some(Physical(_)) => 5
    Some(OriginalReadUnavailable) => 6
    Some(OriginalRead(@arena.Child(@resources.Unknown))) => 7
    Some(OriginalRead(_)) => 8
    Some(CleanupPending) => 9
  }
}

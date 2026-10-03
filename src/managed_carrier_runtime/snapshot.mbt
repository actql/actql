///|
/// Stable common failures. A family's diagnostic is not a public error code
/// and cannot grant producer authority or replace the checked port.
pub(all) enum SnapshotIssue {
  SnapshotUnavailable
  SnapshotAlreadyClaimed
  SnapshotForeignGeneration
  SnapshotByteLimit
  SnapshotFamilyFailure(String)
} derive(Eq, Debug)

///|
/// Cumulative values for this save or reload stage, not per-resume deltas.
/// A terminal issue keeps the work report: callers charge its delta before
/// propagating the failure. It never authorizes another Compute invocation.
pub(all) struct SnapshotAdvance {
  complete : Bool
  progress : Int64
  work : Int64
  issue : SnapshotIssue?
}

///|
pub(all) struct SnapshotContent {
  cid : String
  bytes : Int
}

///|
/// Family-owned operation callbacks, not another material, accounting, or
/// storage owner. The installed Host moves bounded bytes through its existing
/// Store and returns them to the family validator before task completion.
/// Cleanup returns true only when all private operation custody has ended;
/// false and errors preserve the same handle for retry.
pub struct SnapshotIO {
  source_reference : CompletionReference
  maximum_bytes : Int
  maximum_frame_bytes : Int
  workspace_bytes : Int64
  advance_save : (Int) -> Result[SnapshotAdvance, SnapshotIssue]
  take_output : () -> Result[String, SnapshotIssue]
  content : () -> Result[SnapshotContent, SnapshotIssue]
  release_source : (String) -> Result[Unit, SnapshotIssue]
  begin_reload : (String, () -> Bool) -> Result[Unit, SnapshotIssue]
  advance_reload : (Int) -> Result[SnapshotAdvance, SnapshotIssue]
  take_material : () -> Result[Material, SnapshotIssue]
  cleanup : () -> Result[Bool, SnapshotIssue]
}

///|
/// Bound before operation creation. A foreign factory is rejected without
/// invoking callbacks or acquiring serialization/storage resources.
pub struct SnapshotFactory {
  source_reference : CompletionReference
  create : () -> Result[SnapshotIO, SnapshotIssue]
}

///|
pub fn prepare_snapshot_factory(
  source_reference : CompletionReference,
  create : () -> Result[SnapshotIO, SnapshotIssue],
) -> Result[SnapshotFactory, SnapshotIssue] {
  if !completion_reference_available(source_reference) {
    return Err(SnapshotUnavailable)
  }
  Ok({ source_reference, create, })
}

///|
/// Trusted family assembly. The reference is still compared with the exact
/// material generation when this operation is claimed; equal CIDs do not match.
pub fn prepare_snapshot_io(
  source_reference : CompletionReference,
  maximum_bytes : Int,
  maximum_frame_bytes : Int,
  workspace_bytes : Int64,
  advance_save : (Int) -> Result[SnapshotAdvance, SnapshotIssue],
  take_output : () -> Result[String, SnapshotIssue],
  content : () -> Result[SnapshotContent, SnapshotIssue],
  release_source : (String) -> Result[Unit, SnapshotIssue],
  begin_reload : (String, () -> Bool) -> Result[Unit, SnapshotIssue],
  advance_reload : (Int) -> Result[SnapshotAdvance, SnapshotIssue],
  take_material : () -> Result[Material, SnapshotIssue],
  cleanup : () -> Result[Bool, SnapshotIssue],
) -> Result[SnapshotIO, SnapshotIssue] {
  if !completion_reference_available(source_reference) ||
    maximum_bytes < 0 ||
    maximum_frame_bytes < 1 ||
    maximum_frame_bytes > 16777216 ||
    workspace_bytes < 0L {
    return Err(SnapshotUnavailable)
  }
  Ok({
    source_reference,
    maximum_bytes,
    maximum_frame_bytes,
    workspace_bytes,
    advance_save,
    take_output,
    content,
    release_source,
    begin_reload,
    advance_reload,
    take_material,
    cleanup,
  })
}

///|
/// Claim once before any physical I/O. A failure keeps the original material's
/// custody; it is not permission to start another save/allocation for it.
pub fn material_prepare_snapshot(
  value : Material,
) -> Result[SnapshotIO?, SnapshotIssue] {
  if !material_available(value) {
    return Err(SnapshotUnavailable)
  }
  guard value.snapshot_factory is Some(factory) else { return Ok(None) }
  if !completion_reference_same(value.reference, factory.source_reference) {
    return Err(SnapshotForeignGeneration)
  }
  if value.snapshot_claimed.val {
    return Err(SnapshotAlreadyClaimed)
  }
  value.snapshot_claimed.val = true
  match (factory.create)() {
    Err(issue) => Err(issue)
    Ok(operation) => {
      // Capture custody before validation. Even a defective trusted family
      // factory cannot make a returned cleanup handle disappear on rejection.
      value.snapshot_operation.val = Some(operation)
      if completion_reference_same(value.reference, operation.source_reference) &&
        completion_reference_available(operation.source_reference) {
        Ok(Some(operation))
      } else {
        Err(SnapshotForeignGeneration)
      }
    }
  }
}

///|
/// A revoked source reference does not prove that its in-flight snapshot
/// operation has released temporary storage or the private restored generation.
pub fn material_cleanup_pending(value : Material) -> Bool {
  material_available(value) ||
  (value.snapshot_operation.val is Some(_) && !value.snapshot_cleaned.val)
}

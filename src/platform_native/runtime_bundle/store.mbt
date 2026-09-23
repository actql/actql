///|
pub(all) enum NativeRuntimeBundleStoreIssue {
  UnsupportedTarget
  Closed
  InvalidConfiguration
  AdmissionRejected
  MissingBundle
  ExistingBundle
  BundleLimit
  CapacityExceeded
  HoldCollision
  StateCollision
  ComponentMismatch
  RecoveryRequired
  CleanupPending
  Bundle(@bundle.RemoteBundleIssue)
  Signature(@signature.NativeSignatureIssue)
  Filesystem(@filesystem.NativeFilesystemIssue)
  Database(@sqlite.NativeSqliteIssue)
}

///|
pub(all) struct NativeRuntimeBundleInstallSnapshot {
  install_id : String
  runtime_bundle_cid : String
  artifact_name : String
  staging_name : String
  reserved_bytes : Int64
} derive(Eq, Debug)

///|
pub(all) struct NativeRuntimeBundleSnapshot {
  runtime_bundle_cid : String
  manifest_json : String
  artifact_name : String
  generation : @filesystem.NativeFileGeneration
  state : Array[String]
  reclaim_pending : Bool
}

///|
/// Exact active component admitted by the durable bundle Store. The fields
/// remain private so a runtime registration cannot be assembled from an
/// arbitrary bundle CID or Connector revision.
pub struct NativeActiveRuntimeBinding {
  runtime_bundle_cid : String
  component_cid : String
  target_triple : String
  connector_registration : String
  connector_revision : String
  strategy_revision : String
  process_hold_id : String
}

///|
/// One signed component inside the Store-owned physical bundle allocation.
/// The offset is derived from the admitted component order and exact lengths,
/// never from a caller-provided path or unsigned sidecar metadata.
pub struct NativeRuntimeBundleComponentSource {
  runtime_bundle_cid : String
  role : String
  component_cid : String
  component_bytes : Int64
  artifact_name : String
  generation : @filesystem.NativeFileGeneration
  offset : Int64
}

///|
#warnings("-unused_value")
fn native_bundle_component_source(
  runtime_bundle_cid : String,
  role : String,
  component_cid : String,
  component_bytes : Int64,
  artifact_name : String,
  generation : @filesystem.NativeFileGeneration,
  offset : Int64,
) -> NativeRuntimeBundleComponentSource {
  {
    runtime_bundle_cid,
    role,
    component_cid,
    component_bytes,
    artifact_name,
    generation,
    offset,
  }
}

///|
pub fn native_bundle_component_source_projection(
  value : NativeRuntimeBundleComponentSource,
) -> (
  String,
  String,
  String,
  Int64,
  String,
  @filesystem.NativeFileGeneration,
  Int64,
) {
  (
    value.runtime_bundle_cid,
    value.role,
    value.component_cid,
    value.component_bytes,
    value.artifact_name,
    value.generation,
    value.offset,
  )
}

///|
#warnings("-unused_value")
fn native_active_runtime_binding(
  runtime_bundle_cid : String,
  component_cid : String,
  target_triple : String,
  connector_registration : String,
  connector_revision : String,
  strategy_revision : String,
  process_hold_id : String,
) -> NativeActiveRuntimeBinding {
  {
    runtime_bundle_cid,
    component_cid,
    target_triple,
    connector_registration,
    connector_revision,
    strategy_revision,
    process_hold_id,
  }
}

///|
pub fn native_active_runtime_bundle_cid(
  binding : NativeActiveRuntimeBinding,
) -> String {
  binding.runtime_bundle_cid
}

///|
pub fn native_active_runtime_component_cid(
  binding : NativeActiveRuntimeBinding,
) -> String {
  binding.component_cid
}

///|
pub fn native_active_runtime_target_triple(
  binding : NativeActiveRuntimeBinding,
) -> String {
  binding.target_triple
}

///|
pub fn native_active_runtime_connector_scope(
  binding : NativeActiveRuntimeBinding,
) -> (String, String, String) {
  (
    binding.connector_registration,
    binding.connector_revision,
    binding.strategy_revision,
  )
}

///|
/// Durable bundle holding owned by the exact launched Site process. The
/// supervisor releases it only after that process is confirmed stopped.
pub fn native_active_runtime_process_hold_id(
  binding : NativeActiveRuntimeBinding,
) -> String {
  binding.process_hold_id
}

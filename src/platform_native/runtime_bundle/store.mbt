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
) -> NativeActiveRuntimeBinding {
  {
    runtime_bundle_cid,
    component_cid,
    target_triple,
    connector_registration,
    connector_revision,
    strategy_revision,
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

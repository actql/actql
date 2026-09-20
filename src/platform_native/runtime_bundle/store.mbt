///|
pub(all) enum NativeRuntimeBundleStoreIssue {
  UnsupportedTarget
  Closed
  InvalidConfiguration
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

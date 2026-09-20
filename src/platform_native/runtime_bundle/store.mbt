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
  CleanupPending
  Bundle(@bundle.RemoteBundleIssue)
  Signature(@signature.NativeSignatureIssue)
  Filesystem(@filesystem.NativeFilesystemIssue)
  Database(@sqlite.NativeSqliteIssue)
}

///|
pub(all) struct NativeRuntimeBundleSnapshot {
  runtime_bundle_cid : String
  manifest_json : String
  artifact_name : String
  generation : @filesystem.NativeFileGeneration
  state : Array[String]
  reclaim_pending : Bool
}

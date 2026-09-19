///|
pub(all) enum NativePublicationStoreIssue {
  UnsupportedTarget
  Closed
  InvalidConfiguration
  Protocol(@payload.PublicationPayloadIssue)
  Filesystem(@filesystem.NativeFilesystemIssue)
  Database(@sqlite.NativeSqliteIssue)
  StateCollision
  RecoveryRequired
  ExistingPayload
  DigestMismatch
  CleanupPending
  ReaderBusy
}

///|
pub(all) struct NativePublicationPayloadInfo {
  material_generation_cid : String
  publication_attempt_cid : String
  result_definition_cid : String
  logical_relation_cid : String
  result_schema_cid : String
  ordering_evidence_cid : String
  durable_codec_cid : String
  row_count : Int64
  physical_digest : String
  object_name : String
  generation : @filesystem.NativeFileGeneration
}

///|
pub(all) struct NativePublicationRecovery {
  retained : Int
  reclaimed : Int
}

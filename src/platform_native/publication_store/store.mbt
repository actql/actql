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
  Delivery(@publication.DeliverySerializationIssue)
  RowFrame(@publication.DurableResultRowFrameIssue)
  SinkProgress(@publication.DeliverySinkProgressIssue)
  DeliveryIssuance(@publication.DeliveryIssuanceIssue)
  DeliveryLimit
  DeliveryIncomplete
  CleanupPending
  ReaderBusy
  ExistingDeliveryAttempt
  DeliveryAttemptUnresolved
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

///|
pub(all) struct NativePublicationDeliveryChunk {
  bytes : Bytes
  eof : Bool
}

///|
pub(all) struct NativePublicationDeliverySummary {
  bytes : Int64
  rows : Int64
  delivery_digest : String
}

///|
pub(all) struct NativeResultDeliverySuccess {
  delivery_attempt_cid : String
  delivery_record_cid : String
  result_delivery_receipt_cid : String
  confirmed_bytes : Int64
  delivered_sha256 : String
}

///|
pub(all) struct NativeResultDeliveryFailure {
  delivery_attempt_cid : String
  delivery_record_cid : String
  confirmed_bytes : Int64
  state : String
}

///|
pub(all) struct NativeResultDeliveryStatus {
  delivery_attempt_cid : String
  delivery_record_cid : String
  state : String
  confirmed_bytes : Int64
  delivered_sha256 : String?
  result_delivery_receipt_cid : String?
}

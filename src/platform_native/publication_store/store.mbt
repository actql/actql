///|
pub(all) enum NativePublicationStoreIssue {
  UnsupportedTarget
  CheckpointEvidence(@checkpoint.CheckpointIssue)
  PreviewAdmission(@publication.EffectPreviewIdentityIssue)
  PrivateEvidence(@signature.NativePrivateEvidenceIssue)
  PrivateCaptureRollback(NativePublicationStoreIssue, @sqlite.NativeSqliteIssue)
  Closed
  InvalidConfiguration
  LegacyStoreFormat(String)
  UnknownStoreFormat(String)
  StoreFormatIo(String)
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
  DeliveryGrantUsage(@publication.DeliveryGrantUsageIssue)
  PublicationCommit(@publication.PublicationCommitIssue)
  PublicationCommitIssuance(@publication.PublicationCommitIssuanceIssue)
  PublicationCommitConflict
  ClockRegression
  DeliveryLimit
  DeliveryIncomplete
  CleanupPending
  ReaderBusy
  ExistingDeliveryAttempt
  DeliveryAttemptUnresolved
}

///|
/// Refusal before physical acquisition is distinct from an acquired or
/// unconfirmed original cleanup responsibility. Neither case grants resend.
pub(all) enum NativePublicationStoreOpenError {
  RefusedBeforeAcquisition(NativePublicationStoreIssue)
  CleanupRequired(NativePublicationStoreOpenFailure)
}

///|
/// Existing constructors that do not yet return their rejected opaque object.
/// Root close does not prove retirement of a missing child Lock. This private
/// gap is cleanup responsibility, never a Run outcome or retry-send permission.
priv enum StoreOpenCleanupGap {
  RejectedRootCustodyUnavailable
  RejectedLockCustodyUnavailable
}

///|
/// Original failed preparation with the same existing physical Owners. No
/// wire, persistence, reservation, authority or substitute Store is issued.
struct NativePublicationStoreOpenFailure {
  original_issue : NativePublicationStoreIssue
  mut root : @filesystem.Root?
  mut failed_root : @filesystem.NativeRootOpenFailure?
  mut lock : @filesystem.Lock?
  mut failed_lock : @filesystem.NativeLockOpenFailure?
  mut database : @sqlite.Database?
  mut failed_database : @sqlite.NativeSqliteOpenFailure?
  cleanup_gap : StoreOpenCleanupGap?
}

///|
pub fn NativePublicationStoreOpenFailure::issue(
  self : NativePublicationStoreOpenFailure,
) -> NativePublicationStoreIssue {
  self.original_issue
}

///|
/// Re-observe only the original handles, in reverse preparation order. No
/// reopen/schema repair and no capacity return are performed here. Missing
/// opaque constructor custody remains pending, not a fabricated empty ACK.
pub fn NativePublicationStoreOpenFailure::retry_cleanup(
  self : NativePublicationStoreOpenFailure,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.failed_database is Some(original) {
    match original.retry_cleanup() {
      Ok(_) => self.failed_database = None
      Err(issue) => return Err(Database(issue))
    }
  }
  if self.database is Some(original) {
    match original.close_checked() {
      Ok(_) => self.database = None
      Err(issue) => return Err(Database(issue))
    }
  }
  if self.failed_lock is Some(original) {
    match original.retry_cleanup() {
      Ok(_) => self.failed_lock = None
      Err(issue) => return Err(Filesystem(issue))
    }
  }
  if self.lock is Some(original) {
    match original.close_checked() {
      Ok(_) => self.lock = None
      Err(issue) => return Err(Filesystem(issue))
    }
  }
  if self.cleanup_gap is Some(_) {
    return Err(CleanupPending)
  }
  if self.failed_root is Some(original) {
    match original.retry_cleanup() {
      Ok(_) => self.failed_root = None
      Err(issue) => return Err(Filesystem(issue))
    }
  }
  if self.root is Some(original) {
    match original.close() {
      Ok(_) => self.root = None
      Err(issue) => return Err(Filesystem(issue))
    }
  }
  Ok(())
}

///|
fn store_open_failure(
  original_issue : NativePublicationStoreIssue,
  root? : @filesystem.Root? = None,
  failed_root? : @filesystem.NativeRootOpenFailure? = None,
  lock? : @filesystem.Lock? = None,
  failed_lock? : @filesystem.NativeLockOpenFailure? = None,
  database? : @sqlite.Database? = None,
  failed_database? : @sqlite.NativeSqliteOpenFailure? = None,
  cleanup_gap? : StoreOpenCleanupGap? = None,
) -> NativePublicationStoreOpenFailure {
  { original_issue, root, failed_root, lock, failed_lock, database, failed_database, cleanup_gap, }
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

///|
/// Retained immutable attempt plus optional latest facts. No record means
/// unresolved delivery, not permission to reopen or resend. The Store does
/// not grant disclosure authority; the Result access service supplies it.
pub(all) struct NativeResultDeliveryLookup {
  attempt : @publication.PublicationContract
  record : @publication.PublicationContract?
  host_release_receipt : @publication.PublicationContract?
}

///|
pub(all) struct NativePublicationCommit {
  public_index_entry_cid : String
  committed : Bool
  idempotent : Bool
}

///|
pub(all) struct NativeCommittedResult {
  public_index_entry : @publication.PublicationContract
  result_manifest : @publication.PublicationContract
  retention : @publication.PublicationContract
  binding : @publication.PublicationContract
  read : @publication.CommittedResultRead
}

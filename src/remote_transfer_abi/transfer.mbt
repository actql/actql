///|
/// The portable in-process boundary exposes the existing Transfer owner.
/// Physical adapters persist its canonical bodies before committing a step.
#export_name("transferAdmitEnvelopeJson")
pub fn transfer_admit_envelope_json(
  body : String,
  request_cid : String,
  manifest_cid : String,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[@transfer.RemoteTransferRequest, @transfer.RemoteTransferIssue] {
  @transfer.admit_transfer_admission_envelope_json(
    body, request_cid, manifest_cid, max_chunks, max_manifest_bytes,
    max_referenced_bytes,
  )
}

///|
#export_name("transferRequestCid")
pub fn transfer_request_cid(request : @transfer.RemoteTransferRequest) -> String {
  @transfer.request_cid(request)
}

///|
#export_name("transferRequestProjection")
pub fn transfer_request_projection(
  request : @transfer.RemoteTransferRequest,
) -> Array[String] {
  @transfer.request_projection(request)
}

///|
#export_name("transferRequestJournalKey")
pub fn transfer_request_journal_key(
  request : @transfer.RemoteTransferRequest,
) -> Array[String] {
  @transfer.request_journal_key(request)
}

///|
#export_name("transferChunkCids")
pub fn transfer_chunk_cids(request : @transfer.RemoteTransferRequest) -> Array[String] {
  @transfer.request_chunk_cids(request)
}

///|
#export_name("transferChunkByteLengths")
pub fn transfer_chunk_byte_lengths(
  request : @transfer.RemoteTransferRequest,
) -> Array[Int64] {
  @transfer.request_chunk_byte_lengths(request)
}

///|
#export_name("transferActiveAt")
pub fn transfer_active_at(
  request : @transfer.RemoteTransferRequest,
  trusted_now : Int64,
) -> Bool {
  @transfer.request_active_at(request, trusted_now)
}

///|
#export_name("transferOpenRecord")
pub fn transfer_open_record(
  request : @transfer.RemoteTransferRequest,
) -> @transfer.RemoteTransferRecord {
  @transfer.open_record(request)
}

///|
#export_name("transferRecordDurableJson")
pub fn transfer_record_durable_json(
  record : @transfer.RemoteTransferRecord,
) -> Result[String, @transfer.RemoteTransferIssue] {
  @transfer.remote_transfer_record_durable_json(record)
}

///|
#export_name("transferAdmitDurableJson")
pub fn transfer_admit_durable_json(
  body : String,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[@transfer.DurableRemoteTransferRecord, @transfer.RemoteTransferIssue] {
  @transfer.admit_durable_remote_transfer_record(
    @utf8.encode(body), max_chunks, max_manifest_bytes, max_referenced_bytes,
  )
}

///|
#export_name("transferRestoreDurable")
pub fn transfer_restore_durable(
  durable : @transfer.DurableRemoteTransferRecord,
) -> Result[@transfer.RemoteTransferRecord, @transfer.RemoteTransferIssue] {
  @transfer.restore_durable_remote_transfer_record(durable)
}

///|
#export_name("transferDurableRevision")
pub fn transfer_durable_revision(
  durable : @transfer.DurableRemoteTransferRecord,
) -> Int {
  @transfer.durable_remote_transfer_record_revision(durable)
}

///|
#export_name("transferDurableRequestCid")
pub fn transfer_durable_request_cid(
  durable : @transfer.DurableRemoteTransferRecord,
) -> String {
  @transfer.durable_remote_transfer_record_request_identity(durable)
}

///|
#export_name("transferPrepareStart")
pub fn transfer_prepare_start(
  record : @transfer.RemoteTransferRecord,
) -> Result[@transfer.RemoteTransferTransition, @transfer.RemoteTransferIssue] {
  @transfer.prepare_start(record)
}

///|
#export_name("transferPrepareSourceSettled")
pub fn transfer_prepare_source_settled(
  record : @transfer.RemoteTransferRecord,
  integrity_verified : Bool,
  object_sealed : Bool,
) -> Result[@transfer.RemoteTransferTransition, @transfer.RemoteTransferIssue] {
  @transfer.prepare_source_settled(record, integrity_verified, object_sealed)
}

///|
#export_name("transferPrepareDestinationCommit")
pub fn transfer_prepare_destination_commit(
  record : @transfer.RemoteTransferRecord,
) -> Result[@transfer.RemoteTransferTransition, @transfer.RemoteTransferIssue] {
  @transfer.prepare_destination_commit(record)
}

///|
#export_name("transferPrepareUnknown")
pub fn transfer_prepare_unknown(
  record : @transfer.RemoteTransferRecord,
) -> Result[@transfer.RemoteTransferTransition, @transfer.RemoteTransferIssue] {
  @transfer.prepare_unknown(record)
}

///|
#export_name("transferPrepareFailure")
pub fn transfer_prepare_failure(
  record : @transfer.RemoteTransferRecord,
  cancelled : Bool,
  source_access_stopped : Bool,
) -> Result[@transfer.RemoteTransferTransition, @transfer.RemoteTransferIssue] {
  @transfer.prepare_failure(record, cancelled, source_access_stopped)
}

///|
#export_name("transferPrepareCleanup")
pub fn transfer_prepare_cleanup(
  record : @transfer.RemoteTransferRecord,
  source_access_stopped : Bool,
  destination_temporary_reclaimed : Bool,
  object_use_released : Bool,
) -> Result[@transfer.RemoteTransferTransition, @transfer.RemoteTransferIssue] {
  @transfer.prepare_cleanup(
    record, source_access_stopped, destination_temporary_reclaimed,
    object_use_released,
  )
}

///|
#export_name("transferTransitionDurableJson")
pub fn transfer_transition_durable_json(
  transition : @transfer.RemoteTransferTransition,
) -> Result[String, @transfer.RemoteTransferIssue] {
  @transfer.remote_transfer_transition_durable_json(transition)
}

///|
#export_name("transferTransitionExpectedRevision")
pub fn transfer_transition_expected_revision(
  transition : @transfer.RemoteTransferTransition,
) -> Int {
  @transfer.remote_transfer_transition_expected_revision(transition)
}

///|
#export_name("transferCommitTransition")
pub fn transfer_commit_transition(
  transition : @transfer.RemoteTransferTransition,
) -> Result[@transfer.RemoteTransferRecord, @transfer.RemoteTransferIssue] {
  @transfer.commit_transition(transition, true)
}

///|
#export_name("transferReplyJson")
pub fn transfer_reply_json(
  record : @transfer.RemoteTransferRecord,
) -> Result[String, @transfer.RemoteTransferIssue] {
  @transfer.remote_transfer_reply_json(record)
}

///|
#export_name("transferRecordIsDestinationCommitted")
pub fn transfer_record_is_destination_committed(
  record : @transfer.RemoteTransferRecord,
) -> Bool {
  @transfer.record_is_destination_committed(record)
}

///|
#export_name("transferRecordRevision")
pub fn transfer_record_revision(record : @transfer.RemoteTransferRecord) -> Int {
  @transfer.record_revision(record)
}

///|
#export_name("transferRecordRequest")
pub fn transfer_record_request(
  record : @transfer.RemoteTransferRecord,
) -> @transfer.RemoteTransferRequest {
  @transfer.record_request(record)
}

///|
#export_name("transferDirectProgress")
pub fn transfer_direct_progress(record : @transfer.RemoteTransferRecord) -> Int {
  match @transfer.direct_transfer_progress(record) {
    @transfer.DirectTransferStart => 0
    @transfer.DirectTransferCopying => 1
    @transfer.DirectTransferSourceSettled => 2
    @transfer.DirectTransferCommitted => 3
    @transfer.DirectTransferReconciliationRequired => 4
  }
}

///|
/// The Store owner starts from the retained Output Plan's exact request.
/// These in-process handles never serve as wire credentials.
#export_name("coordinatorPayloadRequestFromOutput")
pub fn coordinator_payload_request_from_output(
  durable : @remote.DurableCoordinatorOutputRecord,
) -> @payload.PublicationPayloadRequest {
  @remote.durable_coordinator_output_payload_request(durable)
}

///|
#export_name("coordinatorPayloadRequestCid")
pub fn coordinator_payload_request_cid(
  request : @payload.PublicationPayloadRequest,
) -> String {
  @payload.publication_payload_request_identity(request)
}

///|
#export_name("coordinatorPayloadRequestMaxBytes")
pub fn coordinator_payload_request_max_bytes(
  request : @payload.PublicationPayloadRequest,
) -> Int64 {
  @payload.publication_payload_request_max_bytes(request)
}

///|
#export_name("coordinatorPayloadAdmitRequestJson")
pub fn coordinator_payload_admit_request_json(
  body : String,
  claimed_cid : String,
) -> Result[
  @payload.PublicationPayloadRequest,
  @payload.PublicationPayloadIssue,
] {
  @payload.admit_publication_payload_request_json(body, claimed_cid)
}

///|
#export_name("coordinatorPayloadPrepareRecord")
pub fn coordinator_payload_prepare_record(
  request : @payload.PublicationPayloadRequest,
) -> @payload.PublicationPayloadRecord {
  @payload.prepare_publication_payload_record(request)
}

///|
#export_name("coordinatorPayloadRecordDurableJson")
pub fn coordinator_payload_record_durable_json(
  record : @payload.PublicationPayloadRecord,
) -> Result[String, @payload.PublicationPayloadIssue] {
  @payload.publication_payload_record_durable_json(record)
}

///|
#export_name("coordinatorPayloadAdmitDurableJson")
pub fn coordinator_payload_admit_durable_json(
  body : String,
) -> Result[
  @payload.DurablePublicationPayloadRecord,
  @payload.PublicationPayloadIssue,
] {
  @payload.admit_durable_publication_payload_record(@utf8.encode(body))
}

///|
#export_name("coordinatorPayloadDurableRevision")
pub fn coordinator_payload_durable_revision(
  durable : @payload.DurablePublicationPayloadRecord,
) -> Int {
  @payload.durable_publication_payload_record_revision(durable)
}

///|
#export_name("coordinatorPayloadDurableState")
pub fn coordinator_payload_durable_state(
  durable : @payload.DurablePublicationPayloadRecord,
) -> String {
  match @payload.durable_publication_payload_record_state(durable) {
    @payload.Intent => "intent"
    @payload.Reserved => "reserved"
    @payload.Writing => "writing"
    @payload.Sealed => "sealed"
    @payload.Reclaiming => "reclaiming"
    @payload.Reclaimed => "reclaimed"
  }
}

///|
#export_name("coordinatorPayloadDurableRequestCid")
pub fn coordinator_payload_durable_request_cid(
  durable : @payload.DurablePublicationPayloadRecord,
) -> String {
  @payload.durable_publication_payload_record_request_identity(durable)
}

///|
#export_name("coordinatorPayloadRestoreDurable")
pub fn coordinator_payload_restore_durable(
  durable : @payload.DurablePublicationPayloadRecord,
) -> Result[@payload.PublicationPayloadRecord, @payload.PublicationPayloadIssue] {
  @payload.restore_durable_publication_payload_record(durable)
}

///|
#export_name("coordinatorPayloadPrepareReserved")
pub fn coordinator_payload_prepare_reserved(
  record : @payload.PublicationPayloadRecord,
) -> Result[
  @payload.PublicationPayloadTransition,
  @payload.PublicationPayloadIssue,
] {
  @payload.prepare_publication_payload_reserved(record)
}

///|
#export_name("coordinatorPayloadPrepareWriting")
pub fn coordinator_payload_prepare_writing(
  record : @payload.PublicationPayloadRecord,
) -> Result[
  @payload.PublicationPayloadTransition,
  @payload.PublicationPayloadIssue,
] {
  @payload.prepare_publication_payload_writing(record)
}

///|
#export_name("coordinatorPayloadPrepareOpaqueOwned")
pub fn coordinator_payload_prepare_opaque_owned(
  record : @payload.PublicationPayloadRecord,
  custody_cid : String,
) -> Result[
  @payload.PublicationPayloadTransition,
  @payload.PublicationPayloadIssue,
] {
  @payload.prepare_publication_payload_opaque_owned(record, custody_cid)
}

///|
#export_name("coordinatorPayloadPrepareOpaqueSealed")
pub fn coordinator_payload_prepare_opaque_sealed(
  record : @payload.PublicationPayloadRecord,
  custody_cid : String,
  actual_bytes : Int64,
  physical_digest : String,
) -> Result[
  @payload.PublicationPayloadTransition,
  @payload.PublicationPayloadIssue,
] {
  @payload.prepare_publication_payload_opaque_sealed(
    record, custody_cid, actual_bytes, physical_digest,
  )
}

///|
#export_name("coordinatorPayloadPrepareOpaqueReclaiming")
pub fn coordinator_payload_prepare_opaque_reclaiming(
  record : @payload.PublicationPayloadRecord,
  custody_cid : String,
) -> Result[
  @payload.PublicationPayloadTransition,
  @payload.PublicationPayloadIssue,
] {
  @payload.prepare_publication_payload_opaque_reclaiming(record, custody_cid)
}

///|
#export_name("coordinatorPayloadPrepareReclaimed")
pub fn coordinator_payload_prepare_reclaimed(
  record : @payload.PublicationPayloadRecord,
) -> Result[
  @payload.PublicationPayloadTransition,
  @payload.PublicationPayloadIssue,
] {
  @payload.prepare_publication_payload_reclaimed(record)
}

///|
#export_name("coordinatorPayloadTransitionDurableJson")
pub fn coordinator_payload_transition_durable_json(
  transition : @payload.PublicationPayloadTransition,
) -> Result[String, @payload.PublicationPayloadIssue] {
  @payload.publication_payload_transition_durable_json(transition)
}

///|
#export_name("coordinatorPayloadTransitionExpectedRevision")
pub fn coordinator_payload_transition_expected_revision(
  transition : @payload.PublicationPayloadTransition,
) -> Int {
  @payload.publication_payload_transition_expected_revision(transition)
}

///|
#export_name("coordinatorPayloadCommitTransition")
pub fn coordinator_payload_commit_transition(
  transition : @payload.PublicationPayloadTransition,
) -> Result[@payload.PublicationPayloadRecord, @payload.PublicationPayloadIssue] {
  @payload.commit_publication_payload_transition(transition, true)
}

///|
#export_name("coordinatorPayloadRecordOpaqueGeneration")
pub fn coordinator_payload_record_opaque_generation(
  record : @payload.PublicationPayloadRecord,
) -> String? {
  @payload.publication_payload_record_opaque_generation(record)
}

///|
#export_name("coordinatorPayloadRecordOpaqueOwnership")
pub fn coordinator_payload_record_opaque_ownership(
  record : @payload.PublicationPayloadRecord,
) -> String? {
  @payload.publication_payload_record_opaque_ownership(record)
}

///|
#export_name("coordinatorPayloadRecordDigest")
pub fn coordinator_payload_record_digest(
  record : @payload.PublicationPayloadRecord,
) -> String {
  @payload.publication_payload_record_digest(record)
}

///|
#export_name("coordinatorPayloadRecordActualBytes")
pub fn coordinator_payload_record_actual_bytes(
  record : @payload.PublicationPayloadRecord,
) -> Int64 {
  @payload.publication_payload_record_actual_bytes(record)
}

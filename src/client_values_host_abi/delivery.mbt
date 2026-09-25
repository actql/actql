///|
/// Portable in-process access to existing MoonBit Result delivery decisions.
/// Physical authorization, Store I/O, and sink writes remain Host adapters.
pub(all) suberror ClientValuesHostDeliveryIssue {
  Rejected
}

///|
#export_name("clientValuesHostPublicationContractName")
pub fn client_values_host_publication_contract_name(
  contract : @publication.PublicationContract,
) -> String {
  @publication.publication_contract_name(contract)
}

///|
#export_name("clientValuesHostPublicationContractIdentityField")
pub fn client_values_host_publication_contract_identity_field(
  contract : @publication.PublicationContract,
) -> String {
  @publication.publication_contract_identity_field(contract)
}

///|
#export_name("clientValuesHostExistingDeliveryAttemptAction")
pub fn client_values_host_existing_delivery_attempt_action(
  record : @publication.PublicationContract?,
) -> Int {
  @publication.existing_delivery_attempt_action_code(
    @publication.prepare_existing_delivery_attempt(record),
  )
}

///|
#export_name("clientValuesHostDeliveryRecordTransition")
pub fn client_values_host_delivery_record_transition(
  previous : @publication.PublicationContract?,
  next : @publication.PublicationContract,
) -> Bool {
  @publication.validate_delivery_record_transition(previous, next) is Ok(_)
}

///|
#export_name("clientValuesHostDeliverySuccessValid")
pub fn client_values_host_delivery_success_valid(
  attempt : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  record : @publication.PublicationContract,
) -> Bool {
  @publication.validate_delivery_success_evidence(attempt, receipt, record)
  is Ok(_)
}

///|
#export_name("clientValuesHostTrustedClockNotBefore")
pub fn client_values_host_trusted_clock_not_before(
  previous : String?,
  observed_at : String,
) -> Bool {
  @publication.trusted_clock_not_before(previous, observed_at)
}

///|
#export_name("clientValuesHostPrepareDeliveryGrantUsageClaim")
pub fn client_values_host_prepare_delivery_grant_usage_claim(
  grant : @publication.PublicationContract,
  existing_wire : String?,
  attempt : @publication.PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @publication.DeliveryGrantUsageClaim raise ClientValuesHostDeliveryIssue {
  match
    @publication.prepare_delivery_grant_usage_claim(
      grant, existing_wire, attempt, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(_) => raise Rejected
  }
}

///|
#export_name("clientValuesHostDeliveryGrantUsageClaimWire")
pub fn client_values_host_delivery_grant_usage_claim_wire(
  claim : @publication.DeliveryGrantUsageClaim,
) -> String {
  @publication.delivery_grant_usage_claim_wire(claim)
}

///|
#export_name("clientValuesHostDeliveryGrantUsageClaimIsNew")
pub fn client_values_host_delivery_grant_usage_claim_is_new(
  claim : @publication.DeliveryGrantUsageClaim,
) -> Bool {
  @publication.delivery_grant_usage_claim_is_new(claim)
}

///|
#export_name("clientValuesHostBeginResultAccessProgress")
pub fn client_values_host_begin_result_access_progress() -> @publication.ResultAccessProgress {
  @publication.begin_result_access_progress()
}

///|
#export_name("clientValuesHostResultAccessProgressAction")
pub fn client_values_host_result_access_progress_action(
  progress : @publication.ResultAccessProgress,
) -> Int {
  @publication.result_access_progress_action_code(progress)
}

///|
#export_name("clientValuesHostRecordResultAccessRequestAuthorization")
pub fn client_values_host_record_result_access_request_authorization(
  progress : @publication.ResultAccessProgress,
  authorized : Bool,
) -> Bool {
  @publication.record_result_access_request_authorization(progress, authorized)
  is Ok(_)
}

///|
#export_name("clientValuesHostRecordResultAccessResolution")
pub fn client_values_host_record_result_access_resolution(
  progress : @publication.ResultAccessProgress,
  resolved : Bool,
) -> Bool {
  @publication.record_result_access_resolution(progress, resolved) is Ok(_)
}

///|
#export_name("clientValuesHostRecordResultAccessInitialAvailability")
pub fn client_values_host_record_result_access_initial_availability(
  progress : @publication.ResultAccessProgress,
  available : Bool,
) -> Bool {
  @publication.record_result_access_initial_availability(progress, available)
  is Ok(_)
}

///|
#export_name("clientValuesHostRecordResultAccessReadAdmission")
pub fn client_values_host_record_result_access_read_admission(
  progress : @publication.ResultAccessProgress,
  admitted : Bool,
) -> Bool {
  @publication.record_result_access_read_admission(progress, admitted) is Ok(_)
}

///|
#export_name("clientValuesHostRecordResultAccessGrant")
pub fn client_values_host_record_result_access_grant(
  progress : @publication.ResultAccessProgress,
  issued : Bool,
) -> Bool {
  @publication.record_result_access_grant(progress, issued) is Ok(_)
}

///|
#export_name("clientValuesHostDeliveryFailureTerminalAction")
pub fn client_values_host_delivery_failure_terminal_action(
  cancellation_observed : Bool,
) -> Int {
  @publication.delivery_failure_terminal_action_code(
    @publication.prepare_delivery_failure_terminal(cancellation_observed),
  )
}

///|
#export_name("clientValuesHostDeliveryRecordRetryAction")
pub fn client_values_host_delivery_record_retry_action(
  next_record : Int,
  record_count : Int,
) -> Int {
  @publication.delivery_record_retry_action_code(
    @publication.prepare_delivery_record_retry_step(next_record, record_count),
  )
}

///|
#export_name("clientValuesHostIssueResultReadGrant")
pub fn client_values_host_issue_result_read_grant(
  index : @publication.PublicationContract,
  manifest : @publication.PublicationContract,
  result_names : Array[String],
  formats : Array[String],
  principal_id : String,
  purpose : String,
  data_ceiling_cid : String,
  max_bytes : Int,
  max_uses : Int,
  expires_at : String,
  authorization_context_cid : String,
  egress_admission_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @publication.PublicationContract raise ClientValuesHostDeliveryIssue {
  match
    @publication.issue_result_read_grant(
      index, manifest, result_names, formats, principal_id, purpose, data_ceiling_cid,
      max_bytes, max_uses, expires_at, authorization_context_cid, egress_admission_cid,
      max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(_) => raise Rejected
  }
}

///|
#export_name("clientValuesHostIssueDeliveryAttempt")
pub fn client_values_host_issue_delivery_attempt(
  index : @publication.PublicationContract,
  manifest : @publication.PublicationContract,
  grant : @publication.PublicationContract,
  result_name : String,
  format : String,
  attempt_id : String,
  requested_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @publication.PublicationContract raise ClientValuesHostDeliveryIssue {
  match
    @publication.issue_delivery_attempt(
      index, manifest, grant, result_name, format, attempt_id, requested_at, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(_) => raise Rejected
  }
}

///|
#export_name("clientValuesHostDeliveryResultDefinitionCid")
pub fn client_values_host_delivery_result_definition_cid(
  manifest : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
) -> String raise ClientValuesHostDeliveryIssue {
  match @publication.delivery_result_definition_cid(manifest, attempt) {
    Ok(value) => value
    Err(_) => raise Rejected
  }
}

///|
#export_name("clientValuesHostResultReadRetentionPolicyCid")
pub fn client_values_host_result_read_retention_policy_cid(
  manifest : @publication.PublicationContract,
  result_name : String,
) -> String raise ClientValuesHostDeliveryIssue {
  match @publication.result_read_retention_policy_cid(manifest, result_name) {
    Ok(value) => value
    Err(_) => raise Rejected
  }
}

///|
#export_name("clientValuesHostResultReadDefinitionCid")
pub fn client_values_host_result_read_definition_cid(
  manifest : @publication.PublicationContract,
  result_name : String,
) -> String raise ClientValuesHostDeliveryIssue {
  match @publication.result_read_definition_cid(manifest, result_name) {
    Ok(value) => value
    Err(_) => raise Rejected
  }
}

///|
#export_name("clientValuesHostResultReadExtendedAvailability")
pub fn client_values_host_result_read_extended_availability(
  manifest : @publication.PublicationContract,
  result_name : String,
  base : @publication.PublicationContract,
  extension : @publication.PublicationContract,
  observed_at : String,
) -> String raise ClientValuesHostDeliveryIssue {
  match
    @publication.result_read_extended_availability(
      manifest, result_name, base, extension, observed_at,
    ) {
    Ok(value) => value
    Err(_) => raise Rejected
  }
}

///|
#export_name("clientValuesHostResultRetentionClockContractCid")
pub fn client_values_host_result_retention_clock_contract_cid(
  retention : @publication.PublicationContract,
) -> String raise ClientValuesHostDeliveryIssue {
  match @publication.result_retention_clock_contract_cid(retention) {
    Ok(value) => value
    Err(_) => raise Rejected
  }
}

///|
#export_name("clientValuesHostResultReadGrantAllowsBytes")
pub fn client_values_host_result_read_grant_allows_bytes(
  grant : @publication.PublicationContract,
  byte_count : Int,
) -> Bool {
  @publication.result_read_grant_allows_bytes(grant, byte_count)
}

///|
#export_name("clientValuesHostResultReadGrantValidAt")
pub fn client_values_host_result_read_grant_valid_at(
  grant : @publication.PublicationContract,
  observed_at : String,
) -> Bool {
  @publication.result_read_grant_valid_at(grant, observed_at)
}

///|
#export_name("clientValuesHostIssueResultDeliveryReceipt")
pub fn client_values_host_issue_result_delivery_receipt(
  index : @publication.PublicationContract,
  manifest : @publication.PublicationContract,
  grant : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  delivered_byte_count : Int,
  delivered_sha256 : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @publication.PublicationContract raise ClientValuesHostDeliveryIssue {
  match
    @publication.issue_result_delivery_receipt(
      index, manifest, grant, attempt, delivered_byte_count, delivered_sha256, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(_) => raise Rejected
  }
}

///|
#export_name("clientValuesHostIssueDeliveryRecord")
pub fn client_values_host_issue_delivery_record(
  attempt : @publication.PublicationContract,
  previous : @publication.PublicationContract?,
  state : String,
  confirmed_byte_count : Int,
  exposure : String,
  possible_unconfirmed_max_bytes : Int?,
  delivered_sha256 : String?,
  receipt : @publication.PublicationContract?,
  failure_cid : String?,
  observed_at : String,
  cleanup_owner_cids : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @publication.PublicationContract raise ClientValuesHostDeliveryIssue {
  match
    @publication.issue_delivery_record(
      attempt, previous, state, confirmed_byte_count, exposure, possible_unconfirmed_max_bytes,
      delivered_sha256, receipt, failure_cid, observed_at, cleanup_owner_cids, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(_) => raise Rejected
  }
}

///|
#export_name("clientValuesHostPrepareResultDeliverySerializer")
pub fn client_values_host_prepare_result_delivery_serializer(
  format : String,
  schema_wire : String,
  fields : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @publication.ResultDeliverySerializer raise ClientValuesHostDeliveryIssue {
  match
    @publication.prepare_result_delivery_serializer(
      format, schema_wire, fields, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(_) => raise Rejected
  }
}

///|
#export_name("clientValuesHostBeginResultDelivery")
pub fn client_values_host_begin_result_delivery(
  serializer : @publication.ResultDeliverySerializer,
) -> String raise ClientValuesHostDeliveryIssue {
  match @publication.begin_result_delivery(serializer) {
    Ok(value) => value
    Err(_) => raise Rejected
  }
}

///|
#export_name("clientValuesHostNextResultDeliveryRow")
pub fn client_values_host_next_result_delivery_row(
  serializer : @publication.ResultDeliverySerializer,
  row_wire : String,
) -> String raise ClientValuesHostDeliveryIssue {
  match @publication.next_result_delivery_row(serializer, row_wire) {
    Ok(value) => value
    Err(_) => raise Rejected
  }
}

///|
#export_name("clientValuesHostFinishResultDelivery")
pub fn client_values_host_finish_result_delivery(
  serializer : @publication.ResultDeliverySerializer,
) -> String raise ClientValuesHostDeliveryIssue {
  match @publication.finish_result_delivery(serializer) {
    Ok(value) => value
    Err(_) => raise Rejected
  }
}

///|
#export_name("clientValuesHostPrepareDurableResultRowFrames")
pub fn client_values_host_prepare_durable_result_row_frames(
  max_bytes : Int,
  max_rows : Int,
  max_row_bytes : Int,
  max_depth : Int,
  max_frame_bytes : Int,
) -> @publication.DurableResultRowFrames raise ClientValuesHostDeliveryIssue {
  match
    @publication.prepare_durable_result_row_frames(
      max_bytes, max_rows, max_row_bytes, max_depth, max_frame_bytes,
    ) {
    Ok(value) => value
    Err(_) => raise Rejected
  }
}

///|
#export_name("clientValuesHostFeedDurableResultRowFrames")
pub fn client_values_host_feed_durable_result_row_frames(
  frames : @publication.DurableResultRowFrames,
  chunk : Bytes,
) -> Array[String] raise ClientValuesHostDeliveryIssue {
  match @publication.feed_durable_result_row_frames(frames, chunk) {
    Ok(value) => value
    Err(_) => raise Rejected
  }
}

///|
#export_name("clientValuesHostFinishDurableResultRowFrames")
pub fn client_values_host_finish_durable_result_row_frames(
  frames : @publication.DurableResultRowFrames,
) -> Array[Int] raise ClientValuesHostDeliveryIssue {
  match @publication.finish_durable_result_row_frames(frames) {
    Ok(value) => [value.bytes, value.rows]
    Err(_) => raise Rejected
  }
}

///|
#export_name("clientValuesHostCancelDurableResultRowFrames")
pub fn client_values_host_cancel_durable_result_row_frames(
  frames : @publication.DurableResultRowFrames,
) -> Unit {
  @publication.cancel_durable_result_row_frames(frames)
}

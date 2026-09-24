///|
/// The immutable requests derived from a retained Site output. Planning does
/// not open a publication writer or a Transfer reader.
pub(all) struct NativeRemoteObservedOutputPlan {
  payload : @payload.PublicationPayloadRequest
  transfer : @transfer.RemoteTransferRequest
}

///|
pub(all) struct NativeRemoteObservedOutputIntent {
  store_authority_cid : String
  publication_attempt_cid : String
  result_definition_cid : String
  ordering_evidence_cid : String
  coordinator_authority : String
  transfer_attempt : String
  transfer_route : @transfer.RemoteTransferRoute
  destination_site_key : String
  destination_site_generation : Int
  transfer_max_bytes : Int64
  transfer_expires_unix_ms : Int64
  source_grant_cid : String
  destination_grant_cid : String
  route_capability_cid : String
}

///|
pub(all) enum NativeRemoteObservedOutputPlanIssue {
  InvalidOutputFacts
  Publication(@payload.PublicationPayloadIssue)
  Transfer(@transfer.RemoteTransferIssue)
}

///|
/// Share the physical output binding across application and checked Values
/// Sites. The Site supplies observed facts; the Coordinator supplies only
/// intent and movement authority.
pub fn prepare_native_remote_observed_output_plan(
  site_key : String,
  site_generation : Int,
  facts : @runtime.NativeRemoteOutputFacts,
  intent : NativeRemoteObservedOutputIntent,
) -> Result[NativeRemoteObservedOutputPlan, NativeRemoteObservedOutputPlanIssue] {
  let manifest = facts.physical_manifest
  if facts.result_schema_cid != manifest.schema_contract_cid ||
    facts.logical_view_cid != manifest.view_contract_cid ||
    facts.representation_codec_cid != manifest.codec_contract_cid ||
    facts.row_count != manifest.row_count ||
    facts.retained_bytes != manifest.referenced_bytes {
    return Err(InvalidOutputFacts)
  }
  let payload = match
    @payload.prepare_publication_payload_request(
      intent.store_authority_cid,
      intent.publication_attempt_cid,
      facts.material_generation,
      intent.result_definition_cid,
      facts.logical_view_cid,
      facts.result_schema_cid,
      intent.ordering_evidence_cid,
      facts.representation_codec_cid,
      manifest.referenced_bytes,
      manifest.row_count.to_int64(),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Publication(issue))
  }
  let transfer = match
    @transfer.prepare_request(
      intent.coordinator_authority,
      intent.transfer_attempt,
      intent.transfer_route,
      site_key,
      site_generation,
      intent.destination_site_key,
      intent.destination_site_generation,
      facts.material_generation,
      manifest,
      intent.transfer_max_bytes,
      intent.transfer_expires_unix_ms,
      intent.source_grant_cid,
      intent.destination_grant_cid,
      intent.route_capability_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Transfer(issue))
  }
  Ok({ payload, transfer, })
}

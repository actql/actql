///|
pub(all) enum LocalSDKReadPayloadCodecIssue[E] {
  Original(LocalSDKReadDeliveryObservationIssue[E])
  Store(LocalSDKReadStoreIssue[E])
  Observation(E)
  ChangedOriginal
  InvalidLimits
  Schema(@publication.DeliveryIssuanceIssue)
  Serialization(@publication.DeliverySerializationIssue)
  Frames(@publication.DurableResultRowFrameIssue)
}

///|
fn sdk_read_payload_original_matches(
  first : LocalSDKReadDeliveryPreparation,
  saved : LocalSDKReadDeliveryObservation,
) -> Bool {
  @publication.publication_contract_json(first.grant) ==
  @publication.publication_contract_json(saved.grant) &&
  @publication.publication_contract_json(first.attempt) ==
  @publication.publication_contract_json(saved.attempt) &&
  saved.record.map(@publication.publication_contract_json) ==
  Some(@publication.publication_contract_json(first.streaming)) &&
  saved.receipt is None
}

///|
/// Select the existing row-framing and serialization Owners for the original
/// first delivery. This does not open a payload, confirm a sink, renew a grant,
/// acknowledge a Store write or permit replay. The caller must retain the
/// original first-installation custody and reserve its codec workspace before
/// construction; current physical generation and byte disclosure remain separate.
pub fn[E] prepare_local_sdk_read_payload_codecs_for_source(
  source : LocalSDKReadSource,
  account : @authorization.AdmittedAccountConfiguration,
  finite : @host.ClientLocalRunPolicyOriginal,
  selection : @publication.LocalSDKResultReadSelection,
  host_adoption_cid : String,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  first : LocalSDKReadDeliveryPreparation,
  result_name : String,
  format : String,
  attempt_id : String,
  observed_at : String,
  max_results : Int,
  max_row_bytes : Int,
  input_chunk_bytes : Int,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  current : () -> Result[Unit, E],
) -> Result[
  (@publication.DurableResultRowFrames, @publication.ResultDeliverySerializer),
  LocalSDKReadPayloadCodecIssue[E],
] {
  let (_, _, _, _, _, max_bytes, _) = @publication.local_sdk_result_read_selection_parameters(
    selection,
  )
  if max_row_bytes < 1 ||
    max_row_bytes > max_bytes ||
    input_chunk_bytes < 1 ||
    input_chunk_bytes > max_bytes {
    return Err(InvalidLimits)
  }
  let saved = match
    observe_local_sdk_read_delivery_for_source(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, max_results, read, current,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  // Retained metadata alone never chooses a fresh delivery. Match the genuine
  // original first-installation preparation, including its initial record.
  if !sdk_read_payload_original_matches(first, saved) {
    return Err(ChangedOriginal)
  }
  let materials = match
    owner.observed_result_read_materials(view, result_name, max_results) {
    Ok(value) => value
    Err(issue) => return Err(Store(Preparation(StoredChain(issue))))
  }
  let original = materials.read
  if original.byte_count < 0L ||
    original.byte_count > 2147483647L ||
    original.row_count < 0L ||
    original.row_count > 2147483647L {
    return Err(InvalidLimits)
  }
  let schema = match read("result_schema", original.result_schema_cid) {
    Err(issue) => return Err(Observation(issue))
    Ok(None) => return Err(ChangedOriginal)
    Ok(Some(row)) => {
      if row.key != original.result_schema_cid ||
        row.revision != 0L ||
        row.body.length() > 65536 {
        return Err(ChangedOriginal)
      }
      @utf8.decode(row.body) catch {
        _ => return Err(ChangedOriginal)
      }
    }
  }
  match
    @publication.validate_result_schema_wire(
      original.result_schema_cid,
      schema,
      65536,
      8192,
      64,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Schema(issue))
  }
  // Byte availability and the original grant's expiry are current conditions,
  // unlike historical metadata lookup. The same existing issuer checks them.
  let grant = match
    issue_local_sdk_read_grant_for_source(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, observed_at, max_results, read, current,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Store(issue))
  }
  if @publication.publication_contract_json(grant) !=
    @publication.publication_contract_json(first.grant) {
    return Err(ChangedOriginal)
  }
  // Schema/current callbacks can change the attempt or its usage/head. Reuse
  // the same original observation before constructing even these codecs.
  let final_saved = match
    observe_local_sdk_read_delivery_for_source(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, max_results, read, current,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  if !sdk_read_payload_original_matches(first, final_saved) {
    return Err(ChangedOriginal)
  }
  let final_materials = match
    owner.observed_result_read_materials(view, result_name, max_results) {
    Ok(value) => value
    Err(issue) => return Err(Store(Preparation(StoredChain(issue))))
  }
  if @publication.publication_contract_json(final_materials.index) !=
    @publication.publication_contract_json(materials.index) {
    return Err(ChangedOriginal)
  }
  let serializer = match
    @publication.prepare_result_delivery_serializer(
      format,
      schema,
      original.result_fields,
      max_row_bytes,
      8192,
      64,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Serialization(issue))
  }
  let frames = match
    @publication.prepare_durable_result_row_frames(
      original.byte_count.to_int(),
      original.row_count.to_int(),
      max_row_bytes,
      64,
      input_chunk_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Frames(issue))
  }
  Ok((frames, serializer))
}

///|
/// Existing live-run entry preserves its original preflight/current checks.
pub fn[E] prepare_local_sdk_read_payload_codecs(
  preflight : LocalPublicationPreflight,
  account : @authorization.AdmittedAccountConfiguration,
  finite : @host.ClientLocalRunPolicyOriginal,
  selection : @publication.LocalSDKResultReadSelection,
  host_adoption_cid : String,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  first : LocalSDKReadDeliveryPreparation,
  result_name : String,
  format : String,
  attempt_id : String,
  observed_at : String,
  max_results : Int,
  max_row_bytes : Int,
  input_chunk_bytes : Int,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  current : () -> Result[Unit, E],
) -> Result[
  (@publication.DurableResultRowFrames, @publication.ResultDeliverySerializer),
  LocalSDKReadPayloadCodecIssue[E],
] {
  prepare_local_sdk_read_payload_codecs_for_source(
    live_sdk_read_source(preflight),
    account,
    finite,
    selection,
    host_adoption_cid,
    owner,
    view,
    first,
    result_name,
    format,
    attempt_id,
    observed_at,
    max_results,
    max_row_bytes,
    input_chunk_bytes,
    read,
    current,
  )
}

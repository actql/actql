///|
/// Initial delivery materials selected by the existing issuance/usage Owners.
/// No payload may be disclosed from this preparation: its same-Store writes
/// and subsequent original observation are separate physical obligations.
struct LocalSDKReadDeliveryPreparation {
  grant : @publication.PublicationContract
  attempt : @publication.PublicationContract
  streaming : @publication.PublicationContract
  attempt_key : String
  usage_key : String
  usage_revision : Int64?
  usage : @publication.DeliveryGrantUsageClaim
}

///|
pub(all) enum LocalSDKReadDeliveryIssue[E] {
  Store(LocalSDKReadStoreIssue[E])
  Observation(E)
  ChangedObservation
  ExistingAttempt
  UnresolvedUsage
  Issuance(@publication.DeliveryIssuanceIssue)
  Usage(@publication.DeliveryGrantUsageIssue)
}

///|
/// Prepare the original first delivery under the same trusted Store frame.
/// Existing attempt metadata requires its separate lookup path, never a new
/// attempt, renewed grant, payload replay or inferred completion. Query failure
/// is distinct from a confirmed missing row. The caller reserves transfer and
/// physical metadata capacity before applying the returned original CAS.
pub fn[E] prepare_local_sdk_read_delivery_from_store(
  preflight : LocalPublicationPreflight,
  account : @authorization.AdmittedAccountConfiguration,
  finite : @host.ClientLocalRunPolicyOriginal,
  selection : @publication.LocalSDKResultReadSelection,
  host_adoption_cid : String,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  result_name : String,
  format : String,
  attempt_id : String,
  observed_at : String,
  max_results : Int,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  current : () -> Result[Unit, E],
) -> Result[LocalSDKReadDeliveryPreparation, LocalSDKReadDeliveryIssue[E]] {
  let grant = match
    issue_local_sdk_read_grant_from_store(
      preflight, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, observed_at, max_results, read, current,
    ) {
    Ok(grant) => grant
    Err(issue) => return Err(Store(issue))
  }
  // The Native Store uses this same existing attempt-id key. Python never
  // chooses the scope or constructs a substitute key from a public response.
  let attempt_key = @sha.hex(@utf8.encode(attempt_id))
  match read("delivery_attempt", attempt_key) {
    Err(issue) => return Err(Observation(issue))
    Ok(Some(row)) => {
      if row.key != attempt_key || row.revision < 0L {
        return Err(ChangedObservation)
      }
      return Err(ExistingAttempt)
    }
    Ok(None) => ()
  }
  let materials = match
    owner.observed_result_read_materials(view, result_name, max_results) {
    Ok(materials) => materials
    Err(issue) => return Err(Store(Preparation(StoredChain(issue))))
  }
  let attempt = match
    @publication.issue_delivery_attempt(
      materials.index,
      materials.manifest,
      grant,
      result_name,
      format,
      attempt_id,
      observed_at,
      65536,
      8192,
      64,
    ) {
    Ok(attempt) => attempt
    Err(issue) => return Err(Issuance(issue))
  }
  let usage_key = @publication.publication_contract_identity(grant)
  let saved_usage = match read("result_read_grant_usage", usage_key) {
    Ok(row) => row
    Err(issue) => return Err(Observation(issue))
  }
  let (usage_revision, existing_wire) = match saved_usage {
    None => (None, None)
    Some(row) => {
      if row.key != usage_key || row.revision < 0L || row.body.length() > 65536 {
        return Err(ChangedObservation)
      }
      let wire = @utf8.decode(row.body) catch {
        _ => return Err(Usage(DeliveryGrantUsageInvalidWire))
      }
      (Some(row.revision), Some(wire))
    }
  }
  let usage = match
    @publication.prepare_delivery_grant_usage_claim(
      grant, existing_wire, attempt, 65536, 8192, 64,
    ) {
    Ok(usage) => usage
    Err(issue) => return Err(Usage(issue))
  }
  // A claimed original use without its durable attempt mapping is not a
  // fresh delivery. Preserve the partial/unknown installation for lookup.
  if !@publication.delivery_grant_usage_claim_is_new(usage) {
    return Err(UnresolvedUsage)
  }
  let streaming = match
    @publication.issue_delivery_record(
      attempt,
      None,
      "streaming",
      0,
      "exact",
      None,
      None,
      None,
      None,
      observed_at,
      [],
      65536,
      8192,
      64,
    ) {
    Ok(streaming) => streaming
    Err(issue) => return Err(Issuance(issue))
  }
  // Both physical callbacks above may invalidate current authority or the
  // nominal stored-chain view. Reuse the original grant/chain checks after
  // those callbacks before exposing any write materials to the supplier.
  let checked_grant = match
    issue_local_sdk_read_grant_from_store(
      preflight, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, observed_at, max_results, read, current,
    ) {
    Ok(grant) => grant
    Err(issue) => return Err(Store(issue))
  }
  if @publication.publication_contract_json(checked_grant) !=
    @publication.publication_contract_json(grant) {
    return Err(ChangedObservation)
  }
  Ok({
    grant,
    attempt,
    streaming,
    attempt_key,
    usage_key,
    usage_revision,
    usage,
  })
}

///|
/// Original bounded contracts for the same initial atomic Store installation.
/// Their wire bytes are neither a confirmed use nor a durable delivery ACK.
pub fn local_sdk_read_delivery_original(
  original : LocalSDKReadDeliveryPreparation,
  ordinal : Int,
) -> Result[(String, String), LocalSDKReadOriginalsIssue] {
  let contract = match ordinal {
    0 => original.grant
    1 => original.attempt
    2 => original.streaming
    _ => return Err(InvalidOriginal)
  }
  Ok(
    (
      @publication.publication_contract_json(contract),
      @publication.publication_contract_identity(contract),
    ),
  )
}

///|
pub fn local_sdk_read_delivery_attempt_key(
  original : LocalSDKReadDeliveryPreparation,
) -> String {
  original.attempt_key
}

///|
/// The physical supplier applies this original revision in the same TX as
/// the attempt/contracts/streaming record. A failed or unknown COMMIT retains
/// the original attempt and loans and proceeds only through explicit lookup.
pub fn local_sdk_read_delivery_usage_row(
  original : LocalSDKReadDeliveryPreparation,
) -> (String, Int64?, Bytes) {
  (
    original.usage_key,
    original.usage_revision,
    @utf8.encode(@publication.delivery_grant_usage_claim_wire(original.usage)),
  )
}

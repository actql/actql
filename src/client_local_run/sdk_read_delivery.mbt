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
pub fn[E] prepare_local_sdk_read_delivery_for_source(
  source : LocalSDKReadSource,
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
    issue_local_sdk_read_grant_for_source(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
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
    issue_local_sdk_read_grant_for_source(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
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

///|
/// Closed original first-installation writes. A retained/partial installation
/// needs the original lookup path and is never silently overwritten here.
/// The issuer holds the same trusted TX/current frame throughout preparation.
pub fn[E] prepare_local_sdk_read_delivery_storage_for_source(
  source : LocalSDKReadSource,
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
) -> Result[String, LocalSDKReadDeliveryIssue[E]] {
  prepare_local_sdk_read_delivery_installation_for_source(
    source, account, finite, selection, host_adoption_cid, owner, view, result_name,
    format, attempt_id, observed_at, max_results, read, current,
  ).map(pair => pair.1)
}

///|
/// Keep the original typed first-installation preparation with its exact CAS
/// projection. The portable Host borrows it before retiring transport output;
/// wire bytes or saved metadata cannot reconstruct this nominal preparation.
/// Neither component is a Store ACK, byte-disclosure permit or new attempt.
pub fn[E] prepare_local_sdk_read_delivery_installation_for_source(
  source : LocalSDKReadSource,
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
) -> Result[
  (LocalSDKReadDeliveryPreparation, String),
  LocalSDKReadDeliveryIssue[E],
] {
  let prepared = match
    prepare_local_sdk_read_delivery_for_source(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, observed_at, max_results, read, current,
    ) {
    Ok(prepared) => prepared
    Err(issue) => return Err(issue)
  }
  for contract in [prepared.grant, prepared.attempt, prepared.streaming] {
    let key = @publication.publication_contract_identity(contract)
    match read("publication_contract", key) {
      Err(issue) => return Err(Observation(issue))
      Ok(Some(_)) => return Err(UnresolvedUsage)
      Ok(None) => ()
    }
  }
  let attempt_cid = @publication.publication_contract_identity(prepared.attempt)
  match read("delivery_record_head", attempt_cid) {
    Err(issue) => return Err(Observation(issue))
    Ok(Some(_)) => return Err(UnresolvedUsage)
    Ok(None) => ()
  }
  let final_grant = match
    issue_local_sdk_read_grant_for_source(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, observed_at, max_results, read, current,
    ) {
    Ok(grant) => grant
    Err(issue) => return Err(Store(issue))
  }
  if @publication.publication_contract_json(final_grant) !=
    @publication.publication_contract_json(prepared.grant) {
    return Err(ChangedObservation)
  }
  try {
    // One original export slot, not an expanded buffer/pool or new wire domain.
    // Failure to fit stays capacity failure; no partial installation escapes.
    let writer = @encode.writer(1048576, 128, 6)
    @encode.begin_array(writer)
    let entries : Array[(String, String, Int64?, String)] = []
    for contract in [prepared.grant, prepared.attempt, prepared.streaming] {
      entries.push(
        (
          "publication_contract",
          @publication.publication_contract_identity(contract),
          None,
          @publication.publication_contract_json(contract),
        ),
      )
    }
    entries.push(("delivery_attempt", prepared.attempt_key, None, attempt_cid))
    entries.push(
      (
        "result_read_grant_usage",
        prepared.usage_key,
        prepared.usage_revision,
        @publication.delivery_grant_usage_claim_wire(prepared.usage),
      ),
    )
    entries.push(
      (
        "delivery_record_head",
        attempt_cid,
        None,
        @publication.publication_contract_json(prepared.streaming),
      ),
    )
    for (table, key, revision, body) in entries {
      @encode.begin_object(writer)
      @encode.key(writer, "body")
      @encode.string_value(writer, body)
      @encode.key(writer, "key")
      @encode.string_value(writer, key)
      @encode.key(writer, "revision")
      match revision {
        None => @encode.null_value(writer)
        Some(revision) =>
          @encode.decimal_number_value(writer, revision.to_string())
      }
      @encode.key(writer, "table")
      @encode.string_value(writer, table)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    Ok((prepared, @encode.finish(writer)))
  } catch {
    @encode.OutputLimit => Err(Store(Preparation(Codec(CapacityExceeded))))
    _ => Err(Store(Preparation(Codec(Encoding))))
  }
}

///|
/// Existing live-run entrance retains its original preflight/current checks.
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
  prepare_local_sdk_read_delivery_for_source(
    live_sdk_read_source(preflight),
    account,
    finite,
    selection,
    host_adoption_cid,
    owner,
    view,
    result_name,
    format,
    attempt_id,
    observed_at,
    max_results,
    read,
    current,
  )
}

///|
/// Existing live-run entrance retains its original preflight/current checks.
pub fn[E] prepare_local_sdk_read_delivery_storage_from_store(
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
) -> Result[String, LocalSDKReadDeliveryIssue[E]] {
  prepare_local_sdk_read_delivery_storage_for_source(
    live_sdk_read_source(preflight),
    account,
    finite,
    selection,
    host_adoption_cid,
    owner,
    view,
    result_name,
    format,
    attempt_id,
    observed_at,
    max_results,
    read,
    current,
  )
}

///|
/// Existing live-run entrance retains its original preflight/current checks.
pub fn[E] prepare_local_sdk_read_delivery_installation_from_store(
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
) -> Result[
  (LocalSDKReadDeliveryPreparation, String),
  LocalSDKReadDeliveryIssue[E],
] {
  prepare_local_sdk_read_delivery_installation_for_source(
    live_sdk_read_source(preflight),
    account,
    finite,
    selection,
    host_adoption_cid,
    owner,
    view,
    result_name,
    format,
    attempt_id,
    observed_at,
    max_results,
    read,
    current,
  )
}

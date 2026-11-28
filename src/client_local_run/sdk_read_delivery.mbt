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
  evidence : @host.ClientJournalPhysicalRow?
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
  let prepared = match
    prepare_sdk_read_delivery_with_grant(
      grant, owner, view, result_name, format, attempt_id, observed_at, max_results,
      read,
    ) {
    Ok(prepared) => prepared
    Err(issue) => return Err(issue)
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
    @publication.publication_contract_json(prepared.grant) {
    return Err(ChangedObservation)
  }
  Ok(prepared)
}

///|
fn[E] prepare_sdk_read_delivery_with_grant(
  grant : @publication.PublicationContract,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  result_name : String,
  format : String,
  attempt_id : String,
  observed_at : String,
  max_results : Int,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
) -> Result[LocalSDKReadDeliveryPreparation, LocalSDKReadDeliveryIssue[E]] {
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
      if row.key != usage_key ||
        row.revision < 0L ||
        row.revision == 9223372036854775807L ||
        row.body.length() > 65536 {
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
  Ok({
    grant,
    attempt,
    streaming,
    attempt_key,
    usage_key,
    usage_revision,
    usage,
    evidence: None,
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
/// Keep the original typed first-installation preparation for its CAS
/// projection. Wire bytes or saved metadata cannot reconstruct this nominal
/// preparation. This is not a Store ACK, byte-disclosure permit or new attempt.
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
) -> Result[LocalSDKReadDeliveryPreparation, LocalSDKReadDeliveryIssue[E]] {
  let prepared = match
    prepare_local_sdk_read_delivery_for_source(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, observed_at, max_results, read, current,
    ) {
    Ok(prepared) => prepared
    Err(issue) => return Err(issue)
  }
  match check_sdk_read_delivery_installation_slots(prepared, read) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
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
  Ok(prepared)
}

///|
fn[E] check_sdk_read_delivery_installation_slots(
  prepared : LocalSDKReadDeliveryPreparation,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
) -> Result[Unit, LocalSDKReadDeliveryIssue[E]] {
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
  Ok(())
}

///|
/// Prepare one first-delivery group against the actual Store snapshot. The
/// attempt-bound evidence and grant share one original source and validation.
pub fn[E] prepare_local_sdk_read_delivery_group_for_source(
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
  let (original, decision) = match
    sdk_read_store_observation(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, observed_at, max_results, read, current,
    ) {
    Ok(original) => original
    Err(issue) => return Err(Store(issue))
  }
  let grant = match
    issue_sdk_read_grant_for_original(
      original, finite, selection, result_name, format,
    ) {
    Ok(grant) => grant
    Err(issue) => return Err(Store(Grant(issue)))
  }
  let prepared = match
    prepare_sdk_read_delivery_with_grant(
      grant, owner, view, result_name, format, attempt_id, observed_at, max_results,
      read,
    ) {
    Ok(prepared) => prepared
    Err(issue) => return Err(issue)
  }
  match check_sdk_read_delivery_installation_slots(prepared, read) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    check_sdk_read_original_current(
      original, source, account, owner, view, result_name, max_results, current,
    ) {
    Err(issue) => Err(Store(issue))
    Ok(_) => {
      let evidence = match decision {
        Append(row) | Retained(row) => row
      }
      Ok({ ..prepared, evidence: Some(evidence), })
    }
  }
}

///|
pub fn[E] observe_sdk_read_delivery_group(
  prepared : LocalSDKReadDeliveryPreparation,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
) -> Result[Unit, LocalSDKReadDeliveryIssue[E]] {
  guard prepared.evidence is Some(evidence) else {
    return Err(ChangedObservation)
  }
  match
    check_sdk_read_delivery_row(
      "client_local_read_evidence",
      evidence.key,
      evidence.revision,
      evidence.body,
      read,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  for contract in [prepared.grant, prepared.attempt, prepared.streaming] {
    match
      check_sdk_read_delivery_row(
        "publication_contract",
        @publication.publication_contract_identity(contract),
        0L,
        @utf8.encode(@publication.publication_contract_json(contract)),
        read,
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  let attempt_cid = @publication.publication_contract_identity(prepared.attempt)
  match
    check_sdk_read_delivery_row(
      "delivery_attempt",
      prepared.attempt_key,
      0L,
      @utf8.encode(attempt_cid),
      read,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let usage_revision = match prepared.usage_revision {
    Some(revision) => revision + 1L
    None => 0L
  }
  match
    check_sdk_read_delivery_row(
      "result_read_grant_usage",
      prepared.usage_key,
      usage_revision,
      @utf8.encode(@publication.delivery_grant_usage_claim_wire(prepared.usage)),
      read,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  check_sdk_read_delivery_row(
    "delivery_record_head",
    attempt_cid,
    0L,
    @utf8.encode(@publication.publication_contract_json(prepared.streaming)),
    read,
  )
}

///|
fn[E] check_sdk_read_delivery_row(
  table : String,
  key : String,
  revision : Int64,
  body : Bytes,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
) -> Result[Unit, LocalSDKReadDeliveryIssue[E]] {
  match read(table, key) {
    Err(issue) => Err(Observation(issue))
    Ok(Some(row)) if row.key == key &&
      row.revision == revision &&
      row.body == body => Ok(())
    Ok(_) => Err(ChangedObservation)
  }
}

///|
const SDK_DELIVERY_INSTALLATION_MAX : Int = 1048576

///|
const SDK_DELIVERY_INSTALLATION_NODES : Int = 128

///|
const SDK_DELIVERY_INSTALLATION_DEPTH : Int = 6

///|
fn write_sdk_read_delivery_installation_row(
  writer : @encode.Writer,
  table : String,
  key : String,
  revision : Int64?,
  body : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "body")
  @encode.string_value(writer, body)
  @encode.key(writer, "key")
  @encode.string_value(writer, key)
  @encode.key(writer, "revision")
  match revision {
    None => @encode.null_value(writer)
    Some(revision) => @encode.decimal_number_value(writer, revision.to_string())
  }
  @encode.key(writer, "table")
  @encode.string_value(writer, table)
  @encode.end_object(writer)
}

///|
// Measure and emit the same ordered group, with its original evidence first.
fn write_sdk_read_delivery_installation(
  writer : @encode.Writer,
  prepared : LocalSDKReadDeliveryPreparation,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(writer)
  if prepared.evidence is Some(evidence) {
    let body = @utf8.decode(evidence.body) catch {
      _ => raise @encode.OutputLimit
    }
    write_sdk_read_delivery_installation_row(
      writer,
      "client_local_read_evidence",
      evidence.key,
      None,
      body,
    )
  }
  for contract in [prepared.grant, prepared.attempt, prepared.streaming] {
    write_sdk_read_delivery_installation_row(
      writer,
      "publication_contract",
      @publication.publication_contract_identity(contract),
      None,
      @publication.publication_contract_json(contract),
    )
  }
  let attempt_cid = @publication.publication_contract_identity(prepared.attempt)
  write_sdk_read_delivery_installation_row(
    writer,
    "delivery_attempt",
    prepared.attempt_key,
    None,
    attempt_cid,
  )
  write_sdk_read_delivery_installation_row(
    writer,
    "result_read_grant_usage",
    prepared.usage_key,
    prepared.usage_revision,
    @publication.delivery_grant_usage_claim_wire(prepared.usage),
  )
  write_sdk_read_delivery_installation_row(
    writer,
    "delivery_record_head",
    attempt_cid,
    None,
    @publication.publication_contract_json(prepared.streaming),
  )
  @encode.end_array(writer)
}

///|
/// Measure without allocating a transport body or re-reading the Store.
pub fn measure_sdk_read_delivery_installation(
  prepared : LocalSDKReadDeliveryPreparation,
) -> Int raise @encode.EncodeFailure {
  let writer = @encode.measuring_writer(
    SDK_DELIVERY_INSTALLATION_MAX,
    SDK_DELIVERY_INSTALLATION_NODES,
    SDK_DELIVERY_INSTALLATION_DEPTH,
  )
  write_sdk_read_delivery_installation(writer, prepared)
  @encode.finish_measurement(writer)
}

///|
/// Emit the same proposal inside the original measured physical capacity.
pub fn sdk_read_delivery_installation_wire(
  prepared : LocalSDKReadDeliveryPreparation,
  bytes : Int,
) -> String raise @encode.EncodeFailure {
  if bytes < 1 || bytes > SDK_DELIVERY_INSTALLATION_MAX {
    raise @encode.OutputLimit
  }
  let writer = @encode.writer(
    bytes,
    SDK_DELIVERY_INSTALLATION_NODES,
    SDK_DELIVERY_INSTALLATION_DEPTH,
  )
  write_sdk_read_delivery_installation(writer, prepared)
  @encode.finish(writer)
}

///|
/// Scratch for the same six streamed rows, apart from the output slot's wire
/// bytes. The canonical contract and usage text is borrowed from the proposal.
pub fn sdk_read_delivery_installation_transport_capacity(bytes : Int) -> Int64? {
  guard bytes >= 0 &&
    bytes <= SDK_DELIVERY_INSTALLATION_MAX &&
    @encode.text_writer_construction_inventory(
      bytes,
      SDK_DELIVERY_INSTALLATION_NODES,
      SDK_DELIVERY_INSTALLATION_DEPTH,
    )
    is Some(writer) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: writer.record_headers + 12L,
    reference_slots: writer.reference_slots + 20L,
    scalar_words: writer.scalar_words + 16L,
    owned_utf16_units: writer.owned_utf16_units + 20L,
    owned_wire_bytes: 0L,
  })
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
    live_sdk_read_source(preflight, selection~),
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
) -> Result[LocalSDKReadDeliveryPreparation, LocalSDKReadDeliveryIssue[E]] {
  prepare_local_sdk_read_delivery_installation_for_source(
    live_sdk_read_source(preflight, selection~),
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

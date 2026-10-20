///|
/// Original same-Store delivery metadata, never a payload/replay permit.
struct LocalSDKReadDeliveryObservation {
  grant : @publication.PublicationContract
  attempt : @publication.PublicationContract
  record : @publication.PublicationContract?
  receipt : @publication.PublicationContract?
  action : @publication.ExistingDeliveryAttemptAction
}

///|
pub(all) enum LocalSDKReadDeliveryObservationIssue[E] {
  Store(LocalSDKReadStoreIssue[E])
  Observation(E)
  MissingAttempt
  MissingOriginal
  ChangedOriginal
  Contract(@publication.PublicationContractIssue)
  Issuance(@publication.DeliveryIssuanceIssue)
  Usage(@publication.DeliveryGrantUsageIssue)
}

///|
fn[E] sdk_delivery_stored_contract(
  kind : String,
  key : String,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
) -> Result[
  @publication.PublicationContract,
  LocalSDKReadDeliveryObservationIssue[E],
] {
  let row = match read("publication_contract", key) {
    Err(issue) => return Err(Observation(issue))
    Ok(None) => return Err(MissingOriginal)
    Ok(Some(row)) => row
  }
  if row.key != key || row.revision < 0L || row.body.length() > 65536 {
    return Err(ChangedOriginal)
  }
  let wire = @utf8.decode(row.body) catch { _ => return Err(ChangedOriginal) }
  let contract = match
    @publication.admit_publication_contract(kind, wire, 65536, 8192, 64) {
    Ok(contract) => contract
    Err(issue) => return Err(Contract(issue))
  }
  if @publication.publication_contract_identity(contract) != key {
    return Err(ChangedOriginal)
  }
  Ok(contract)
}

///|
/// Observe the original occurrence after a first install or lost ACK. The
/// same attempt key is read once; no Store insert, new attempt, usage claim,
/// clock renewal or payload access is performed. Older requested-at values
/// remain the actual saved attempt, validated by the existing lookup Owner.
/// Query failures and partial originals are not confirmed missing attempts.
pub fn[E] observe_local_sdk_read_delivery_for_source(
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
  max_results : Int,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  current : () -> Result[Unit, E],
) -> Result[
  LocalSDKReadDeliveryObservation,
  LocalSDKReadDeliveryObservationIssue[E],
] {
  // Metadata lookup uses current authority, not current payload availability.
  // Retained grants/timestamps are validated later and are never renewed.
  match current() {
    Err(issue) => return Err(Observation(issue))
    Ok(_) => ()
  }
  match
    validate_sdk_read_original_binding(
      source, account, finite, selection, host_adoption_cid, result_name, format,
      attempt_id,
    ) {
    Err(issue) => return Err(Store(Preparation(issue)))
    Ok(_) => ()
  }
  // Scope/nominal custody must be complete even for a confirmed missing key.
  match owner.observed_result_read_materials(view, result_name, max_results) {
    Err(issue) => return Err(Store(Preparation(StoredChain(issue))))
    Ok(_) => ()
  }
  let attempt_key = @sha.hex(@utf8.encode(attempt_id))
  let row = match read("delivery_attempt", attempt_key) {
    Err(issue) => return Err(Observation(issue))
    Ok(None) => {
      match current() {
        Err(issue) => return Err(Observation(issue))
        Ok(_) => ()
      }
      match
        validate_sdk_read_original_binding(
          source, account, finite, selection, host_adoption_cid, result_name, format,
          attempt_id,
        ) {
        Err(issue) => return Err(Store(Preparation(issue)))
        Ok(_) => ()
      }
      match
        owner.observed_result_read_materials(view, result_name, max_results) {
        Err(issue) => return Err(Store(Preparation(StoredChain(issue))))
        Ok(_) => return Err(MissingAttempt)
      }
    }
    Ok(Some(row)) => row
  }
  if row.key != attempt_key || row.revision < 0L || row.body.length() != 71 {
    return Err(ChangedOriginal)
  }
  let attempt_cid = @utf8.decode(row.body) catch {
    _ => return Err(ChangedOriginal)
  }
  let attempt = match
    sdk_delivery_stored_contract("delivery_attempt", attempt_cid, read) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let requested_at = match @publication.delivery_attempt_requested_at(attempt) {
    Ok(value) => value
    Err(issue) => return Err(Issuance(issue))
  }
  // Recompute the saved body's binding at its actual admitted request time.
  // Current authority remains independent; this grants no present byte access.
  let expected = match
    issue_local_sdk_read_grant_for_source(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, requested_at, max_results, read, current,
    ) {
    Ok(grant) => grant
    Err(issue) => return Err(Store(issue))
  }
  let grant_cid = match @publication.delivery_attempt_read_grant_cid(attempt) {
    Ok(cid) => cid
    Err(issue) => return Err(Issuance(issue))
  }
  let grant = match
    sdk_delivery_stored_contract("result_read_grant", grant_cid, read) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @publication.publication_contract_json(grant) !=
    @publication.publication_contract_json(expected) {
    return Err(ChangedOriginal)
  }
  let materials = match
    owner.observed_result_read_materials(view, result_name, max_results) {
    Ok(materials) => materials
    Err(issue) => return Err(Store(Preparation(StoredChain(issue))))
  }
  let index = match @publication.project_public_index_read(materials.index) {
    Ok(index) => index
    Err(issue) => return Err(Issuance(issue))
  }
  let (principal, _, purpose, _, _, _, _) = @publication.local_sdk_result_read_selection_parameters(
    selection,
  )
  let scope : @publication.DeliveryAttemptLookupScope = {
    namespace_id: index.namespace_id,
    authority_scope_cid: index.authority_scope_cid,
    run_definition_cid: index.run_definition_cid,
    principal_id: principal,
    purpose,
    result_name,
    attempt_id,
  }
  match
    @publication.delivery_attempt_lookup_matches_scope(attempt, grant, scope) {
    Err(issue) => return Err(Issuance(issue))
    Ok(false) => return Err(ChangedOriginal)
    Ok(true) => ()
  }
  let row = match read("result_read_grant_usage", grant_cid) {
    Err(issue) => return Err(Observation(issue))
    Ok(None) => return Err(MissingOriginal)
    Ok(Some(row)) => row
  }
  if row.key != grant_cid || row.revision < 0L || row.body.length() > 65536 {
    return Err(ChangedOriginal)
  }
  let usage_wire = @utf8.decode(row.body) catch {
    _ => return Err(ChangedOriginal)
  }
  let usage = match
    @publication.prepare_delivery_grant_usage_claim(
      grant,
      Some(usage_wire),
      attempt,
      65536,
      8192,
      64,
    ) {
    Ok(usage) => usage
    Err(issue) => return Err(Usage(issue))
  }
  if @publication.delivery_grant_usage_claim_is_new(usage) {
    // A proposed successor is not evidence that the original use was saved.
    return Err(MissingOriginal)
  }
  let record = match read("delivery_record_head", attempt_cid) {
    Err(issue) => return Err(Observation(issue))
    Ok(None) => None
    Ok(Some(row)) => {
      if row.key != attempt_cid ||
        row.revision < 0L ||
        row.body.length() > 65536 {
        return Err(ChangedOriginal)
      }
      let wire = @utf8.decode(row.body) catch {
        _ => return Err(ChangedOriginal)
      }
      let record = match
        @publication.admit_publication_contract(
          "delivery_record", wire, 65536, 8192, 64,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Contract(issue))
      }
      Some(record)
    }
  }
  let receipt = match record {
    None => None
    Some(record) => {
      let projection = match @publication.project_delivery_record(record) {
        Ok(projection) => projection
        Err(issue) => return Err(Issuance(issue))
      }
      if projection.delivery_attempt_cid != attempt_cid {
        return Err(ChangedOriginal)
      }
      match projection.result_delivery_receipt_cid {
        None => None
        Some(cid) => {
          let receipt = match
            sdk_delivery_stored_contract("result_delivery_receipt", cid, read) {
            Ok(receipt) => receipt
            Err(issue) => return Err(issue)
          }
          match
            @publication.validate_delivery_success_evidence(
              attempt, receipt, record,
            ) {
            Err(issue) => return Err(Issuance(issue))
            Ok(_) => Some(receipt)
          }
        }
      }
    }
  }
  let action = @publication.prepare_existing_delivery_attempt(record)
  if action == @publication.DeliveryConfirmSucceededRecord && receipt is None {
    return Err(MissingOriginal)
  }
  // The physical readers may revoke authority or cancel the borrowed full
  // chain. Recheck after the last read before exposing even private metadata.
  let final_grant = match
    issue_local_sdk_read_grant_for_source(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, requested_at, max_results, read, current,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Store(issue))
  }
  if @publication.publication_contract_json(final_grant) !=
    @publication.publication_contract_json(grant) {
    return Err(ChangedOriginal)
  }
  Ok({ grant, attempt, record, receipt, action, })
}

///|
pub fn local_sdk_read_delivery_observation_action(
  original : LocalSDKReadDeliveryObservation,
) -> @publication.ExistingDeliveryAttemptAction {
  original.action
}

///|
pub fn local_sdk_read_delivery_observation_original(
  original : LocalSDKReadDeliveryObservation,
  ordinal : Int,
) -> Result[(String, String)?, LocalSDKReadOriginalsIssue] {
  let contract = match ordinal {
    0 => Some(original.grant)
    1 => Some(original.attempt)
    2 => original.record
    3 => original.receipt
    _ => return Err(InvalidOriginal)
  }
  Ok(
    contract.map(contract => {
      (
        @publication.publication_contract_json(contract),
        @publication.publication_contract_identity(contract),
      )
    }),
  )
}

///|
/// Existing Client delivery-attempt response, produced only by Common's
/// original read-only observation. Confirmed missing is never replay permission.
/// The initial Source-free response allowance is unchanged; oversized metadata
/// is refused, not truncated or reported as a missing/succeeded occurrence.
pub fn[E] local_sdk_read_delivery_lookup_wire_for_source(
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
  max_results : Int,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  current : () -> Result[Unit, E],
) -> Result[String, LocalSDKReadDeliveryObservationIssue[E]] {
  let observed = match
    observe_local_sdk_read_delivery_for_source(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, max_results, read, current,
    ) {
    Ok(observed) => observed
    Err(MissingAttempt) => return Ok("{\"kind\":\"not_found\"}")
    Err(issue) => return Err(issue)
  }
  // These are already admitted canonical contract objects. No user text is
  // concatenated, interpreted as a contract or used to build an authority.
  let attempt = @publication.publication_contract_json(observed.attempt)
  let record = observed.record
    .map(@publication.publication_contract_json)
    .unwrap_or("null")
  let receipt = observed.receipt
    .map(@publication.publication_contract_json)
    .unwrap_or("null")
  let wire = "{\"attempt\":" +
    attempt +
    ",\"hostReleaseReceipt\":" +
    receipt +
    ",\"kind\":\"found\",\"record\":" +
    record +
    "}"
  if @utf8.encode(wire).length() > 8192 {
    return Err(Store(Preparation(Codec(CapacityExceeded))))
  }
  Ok(wire)
}

///|
/// Existing live-run entrance retains its original preflight/current checks.
pub fn[E] observe_local_sdk_read_delivery_from_store(
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
  max_results : Int,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  current : () -> Result[Unit, E],
) -> Result[
  LocalSDKReadDeliveryObservation,
  LocalSDKReadDeliveryObservationIssue[E],
] {
  observe_local_sdk_read_delivery_for_source(
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
    max_results,
    read,
    current,
  )
}

///|
/// Existing live-run entrance retains its original preflight/current checks.
pub fn[E] local_sdk_read_delivery_lookup_wire(
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
  max_results : Int,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  current : () -> Result[Unit, E],
) -> Result[String, LocalSDKReadDeliveryObservationIssue[E]] {
  local_sdk_read_delivery_lookup_wire_for_source(
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
    max_results,
    read,
    current,
  )
}

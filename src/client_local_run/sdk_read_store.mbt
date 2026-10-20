///|
/// The existing Local read evidence envelope and original egress key. The
/// physical Host reserves storage/workspace before copying or installing it.
/// Emitting this packet neither persists it nor authorizes a Result delivery.
pub fn local_sdk_read_evidence_packet(
  original : LocalSDKReadOriginals,
) -> Result[(String, Bytes), LocalSDKReadOriginalsIssue] {
  let request = match
    @host.client_request_identity_record_wire(original.request) {
    Ok(wire) => wire
    Err(_) => return Err(InvalidOriginal)
  }
  try {
    // Identical to the existing Native Local read evidence envelope. Distinct
    // Python domains/purpose/sink are in the original three admitted bodies.
    let writer = @encode.writer(65536, 16, 4)
    @encode.begin_object(writer)
    for
      (name, body) in [
        ("authorization_context", original.authorization.0),
        ("data_ceiling", original.ceiling.0),
        ("egress_admission", original.egress.0),
        ("request", request),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, body)
    }
    @encode.end_object(writer)
    Ok((original.egress.1, @utf8.encode(@encode.finish(writer))))
  } catch {
    @encode.OutputLimit => Err(Codec(CapacityExceeded))
    _ => Err(Codec(Encoding))
  }
}

///|
pub(all) enum LocalSDKReadStoreIssue[E] {
  Observation(E)
  Preparation(LocalSDKReadOriginalsIssue)
  MissingEvidence
  ChangedEvidence
  Grant(@publication.DeliveryIssuanceIssue)
}

///|
/// Issue through the existing delivery Owner only after rereading the exact
/// original evidence from the trusted, fenced Store. None is a confirmed miss;
/// a query/current failure retains its typed cause and is never a miss or retry.
/// The Host keeps the original view/Run, current publisher and all physical
/// reader facts pinned around this call and before adopting its returned bytes.
/// No Store insert, COMMIT ACK, usage claim or delivery is performed here.
fn[E] sdk_read_store_observation(
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
  (LocalSDKReadOriginals, @host.ClientJournalPhysicalRow?),
  LocalSDKReadStoreIssue[E],
] {
  match current() {
    Ok(_) => ()
    Err(issue) => return Err(Observation(issue))
  }
  let original = match
    prepare_local_sdk_read_originals_for_source(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, observed_at, max_results,
    ) {
    Ok(original) => original
    Err(issue) => return Err(Preparation(issue))
  }
  let (key, packet) = match local_sdk_read_evidence_packet(original) {
    Ok(pair) => pair
    Err(issue) => return Err(Preparation(issue))
  }
  let row = match read("client_local_read_evidence", key) {
    Err(issue) => return Err(Observation(issue))
    Ok(row) => row
  }
  // Validate the observation separately from its physical query success. The
  // physical supplier cannot choose the scope, key, acceptance or comparison.
  if row is Some(row) &&
    (row.key != key || row.revision != 0L || row.body != packet) {
    return Err(ChangedEvidence)
  }
  match current() {
    Err(issue) => return Err(Observation(issue))
    Ok(_) => ()
  }
  match source.validate_current(account, result_name) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  // The observation callback may invalidate the original nominal view. Never
  // issue against a cached candidate or a cancelled/retired stored-chain loan.
  let actual = match
    owner.observed_result_read_materials(view, result_name, max_results) {
    Ok(actual) => actual
    Err(issue) => return Err(Preparation(StoredChain(issue)))
  }
  if @publication.publication_contract_json(actual.index) !=
    @publication.publication_contract_json(original.materials.index) ||
    @publication.publication_contract_json(actual.manifest) !=
    @publication.publication_contract_json(original.materials.manifest) {
    return Err(ChangedEvidence)
  }
  Ok((original, row))
}

///|
pub fn[E] issue_local_sdk_read_grant_for_source(
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
) -> Result[@publication.PublicationContract, LocalSDKReadStoreIssue[E]] {
  let (original, saved) = match
    sdk_read_store_observation(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, observed_at, max_results, read, current,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if saved is None {
    return Err(MissingEvidence)
  }
  let actual = original.materials
  let (principal, _, purpose, _, _, max_bytes, max_uses) = @publication.local_sdk_result_read_selection_parameters(
    selection,
  )
  let grant = match
    @publication.issue_result_read_grant(
      actual.index,
      actual.manifest,
      [result_name],
      [format],
      principal,
      purpose,
      original.ceiling.1,
      max_bytes,
      max_uses,
      @host.client_local_run_policy_original_read_expires_at(finite),
      original.authorization.1,
      original.egress.1,
      65536,
      8192,
      64,
    ) {
    Ok(grant) => grant
    Err(issue) => return Err(Grant(issue))
  }
  match current() {
    Err(issue) => Err(Observation(issue))
    Ok(_) =>
      match source.validate_current(account, result_name) {
        Err(issue) => Err(Preparation(issue))
        Ok(_) => {
          // The final current callback can also invalidate the nominal view.
          // Recheck its original stored chain before allowing the grant out.
          let final_materials = match
            owner.observed_result_read_materials(view, result_name, max_results) {
            Err(issue) => return Err(Preparation(StoredChain(issue)))
            Ok(materials) => materials
          }
          if @publication.publication_contract_json(final_materials.index) !=
            @publication.publication_contract_json(actual.index) ||
            @publication.publication_contract_json(final_materials.manifest) !=
            @publication.publication_contract_json(actual.manifest) {
            Err(ChangedEvidence)
          } else {
            Ok(grant)
          }
        }
      }
  }
}

///|
/// This is a physical write proposal or retained original observation, never
/// grant/ACK or permission to replay an unknown attempted transaction.
pub(all) enum LocalSDKReadEvidenceDecision {
  Append(@host.ClientJournalPhysicalRow)
  Retained(@host.ClientJournalPhysicalRow)
}

///|
/// The same Store lookup comes before any first-write proposal. The physical
/// caller uses original same-TX/CAS/current/capacity fences; after an attempted
/// COMMIT Unknown it only looks up the original key, never repeats the proposal.
pub fn[E] prepare_local_sdk_read_evidence_for_source(
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
) -> Result[LocalSDKReadEvidenceDecision, LocalSDKReadStoreIssue[E]] {
  let (original, saved) = match
    sdk_read_store_observation(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, observed_at, max_results, read, current,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match saved {
    Some(row) => Ok(Retained(row))
    None =>
      match local_sdk_read_evidence_packet(original) {
        Err(issue) => Err(Preparation(issue))
        Ok((key, body)) => Ok(Append({ key, body, revision: 0L, }))
      }
  }
}

///|
/// Closed private physical write projection. The key/body/decision come only
/// from the existing Common read/Store checks, never from a Python comparison.
pub fn local_sdk_read_evidence_decision_wire(
  decision : LocalSDKReadEvidenceDecision,
) -> Result[String, LocalSDKReadOriginalsIssue] {
  let (kind, row) = match decision {
    Append(row) => ("append", row)
    Retained(row) => ("retained", row)
  }
  let body = @utf8.decode(row.body) catch { _ => return Err(InvalidOriginal) }
  try {
    // Existing packet cap plus its worst-case JSON quoting and fixed envelope.
    // The existing export slot/physical copy is separately reserved first.
    let writer = @encode.writer(6 * 65536 + 256, 32, 4)
    @encode.begin_object(writer)
    @encode.key(writer, "body")
    @encode.string_value(writer, body)
    @encode.key(writer, "key")
    @encode.string_value(writer, row.key)
    @encode.key(writer, "kind")
    @encode.string_value(writer, kind)
    @encode.key(writer, "revision")
    @encode.decimal_number_value(writer, row.revision.to_string())
    @encode.key(writer, "table")
    @encode.string_value(writer, "client_local_read_evidence")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    @encode.OutputLimit => Err(Codec(CapacityExceeded))
    _ => Err(Codec(Encoding))
  }
}

///|
/// Existing live-run entrance retains its original preflight/current checks.
pub fn[E] issue_local_sdk_read_grant_from_store(
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
) -> Result[@publication.PublicationContract, LocalSDKReadStoreIssue[E]] {
  issue_local_sdk_read_grant_for_source(
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
pub fn[E] prepare_local_sdk_read_evidence_from_store(
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
) -> Result[LocalSDKReadEvidenceDecision, LocalSDKReadStoreIssue[E]] {
  prepare_local_sdk_read_evidence_for_source(
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

///|
/// First Effect acceptance candidates under one original Store observation.
/// The Host must insert the Run and locator and CAS both existing rows in one
/// transaction.
/// These bytes confer neither a COMMIT acknowledgement nor a start claim.
pub struct ClientEffectRunJournalAppend {
  run : ClientRunJournalAppend
  preparing : ClientJournalPhysicalRow
  ready : Bytes
  locator : (String, Bytes)
}

///|
pub fn client_effect_run_journal_append_rows(
  candidate : ClientEffectRunJournalAppend,
) -> (ClientRunJournalAppend, ClientJournalPhysicalRow, Bytes, (String, Bytes)) {
  (candidate.run, candidate.preparing, candidate.ready, candidate.locator)
}

///|
/// Additional workspace for the existing ready-row transport constructor.
/// The admitted candidate and the final output Bytes have separate owners.
pub fn client_effect_run_journal_append_wire_workspace(
  candidate : ClientEffectRunJournalAppend,
) -> Int64? {
  let (key, body, _, count) = client_run_journal_append_rows(candidate.run)
  let decoded_bytes = candidate.preparing.body.length().to_int64() +
    body.length().to_int64() +
    candidate.ready.length().to_int64() +
    count.length().to_int64() +
    candidate.locator.1.length().to_int64()
  let existing_units = key.length().to_int64() +
    candidate.preparing.key.length().to_int64() +
    candidate.locator.0.length().to_int64()
  // Five decoded bodies and three owned-by-caller keys may all require
  // quoting. Six bytes per input unit cover JSON escapes. The fixed
  // envelope includes both decimal revisions, key literals and punctuation.
  let output_bytes = Int64::min(
    1048576L,
    6L * (decoded_bytes + existing_units) + 256L,
  ).to_int()
  guard @encode.text_writer_construction_inventory(output_bytes, 24, 3)
    is Some(writer) else {
    return None
  }
  @execution.preparation_representation_cost({
    // BytesViews, up to five decoder arrays/returned strings, the five
    // field tuples and their Array, decimal strings, Result and stage controls.
    record_headers: writer.record_headers + 32L,
    reference_slots: writer.reference_slots + 40L,
    scalar_words: writer.scalar_words + 32L,
    // Strict decode yields <= one UTF-16 unit per input byte. Allow both
    // input-sized decoder backing and its returned string per body.
    owned_utf16_units: writer.owned_utf16_units + 2L * decoded_bytes + 40L,
    owned_wire_bytes: 0L,
  })
}

///|
/// Project this exact candidate into the existing SDK ready-row transport.
/// The caller funds the wire constructor and owns the later Store transaction.
pub fn client_effect_run_journal_append_wire(
  candidate : ClientEffectRunJournalAppend,
) -> Result[String, ClientJournalEncodingIssue] {
  let (key, body, issued_revision, count) = client_run_journal_append_rows(
    candidate.run,
  )
  let before = candidate.preparing
  let no_tasks : ClientTaskMaterialsOriginal[Unit]? = None
  client_submitted_run_candidate_wire(
    (key, before.key, before.body, body, candidate.ready),
    issued=Some((issued_revision, count)),
    reference_locator=Some(candidate.locator),
    task_materials=no_tasks,
    preparing_revision=before.revision,
  )
}

///|
/// Project the first Saved admission of the original Effect Run. The caller
/// supplies the issued candidate, predecessor and the fully inspected current
/// snapshot and locator from the same protected physical Read. Exact body
/// equality is part of this check; a matching Run identity alone cannot
/// acknowledge a different successor or an already started Run.
pub fn client_first_effect_saved_admission_wire(
  preparing : ClientSavedSubmissionSnapshot,
  saved : ClientSavedSubmissionSnapshot,
  materials : ClientEffectRunMaterials,
  candidate : ClientEffectRunJournalAppend,
  locator : ClientJournalPhysicalRow,
) -> Result[String, ClientSavedSubmissionViewIssue] {
  let (key, body, _, _) = client_run_journal_append_rows(candidate.run)
  guard client_first_effect_saved_original_matches(
      preparing, saved, materials, candidate, locator,
    ) &&
    saved.run is Some({ key: run_key, revision: 0L, body: run_body, }) &&
    run_key == key &&
    run_body == body else {
    return Err(CustodyLost)
  }
  client_saved_submission_admission_wire(saved)
}

///|
fn client_first_effect_saved_original_matches(
  preparing : ClientSavedSubmissionSnapshot,
  saved : ClientSavedSubmissionSnapshot,
  materials : ClientEffectRunMaterials,
  candidate : ClientEffectRunJournalAppend,
  locator : ClientJournalPhysicalRow,
) -> Bool {
  candidate.preparing.key == preparing.submission.key &&
  candidate.preparing.revision == preparing.submission.revision &&
  candidate.preparing.body == preparing.submission.body &&
  saved.submission.body == candidate.ready &&
  locator.key == candidate.locator.0 &&
  locator.revision == 0L &&
  locator.body == candidate.locator.1 &&
  client_first_effect_saved_submission_matches(preparing, saved, materials)
}

///|
fn client_first_effect_saved_submission_matches(
  preparing : ClientSavedSubmissionSnapshot,
  saved : ClientSavedSubmissionSnapshot,
  materials : ClientEffectRunMaterials,
) -> Bool {
  let before = preparing.record
  let after = saved.record
  guard before.run_admission is None &&
    before.preparation_problem is None &&
    before.run_state_original is None &&
    before.run_state_observation is None &&
    preparing.run is None &&
    preparing.submission.revision >= 0L &&
    preparing.submission.revision < 9223372036854775807L &&
    saved.submission.key == preparing.submission.key &&
    saved.submission.revision == preparing.submission.revision + 1L &&
    client_submission_reference_record_wire(after.reference) ==
    client_submission_reference_record_wire(before.reference) &&
    client_submitted_intent_wire(after.intent) ==
    client_submitted_intent_wire(before.intent) &&
    after.preparation_problem is None &&
    after.run_state_original is None &&
    after.run_state_observation is Some((0L, None)) &&
    materials.request is Some(request) &&
    after.run_admission is Some((selected, definition, 0L)) &&
    client_request_identity_relation(selected, request) is SameRequest &&
    definition ==
    @publication.publication_contract_identity(materials.run_definition) &&
    saved.run is Some(run) &&
    run.key == client_request_scope_cid(request) &&
    saved.inspection is Some(inspection) &&
    inspection.checkpoint is None &&
    inspection.task_materials_cid is None else {
    return false
  }
  true
}

///|
/// Join the original checked input, live normalized Effect material and exact
/// preparing bytes. The caller owns authenticated Submit/current, the actual
/// clock, the finite profile selection and the transaction/construction
/// backing. The retained intent must come from the same checked Request.
/// Saved or existing Runs must take the original lookup route.
pub fn[E] prepare_client_effect_run_journal_append(
  snapshot : ClientSavedSubmissionSnapshot,
  intent : ClientSubmittedIntent,
  materials : ClientEffectRunMaterials,
  profile : ClientLocalRunPolicyProfile,
  retention : @publication.PublicationContract,
  host_adoption_cid : String,
  read_selection_cid : String,
  now : Double,
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  confirm_cancellation : () -> Result[Unit, E],
  custody_lost : E,
  indexed_store? : Bool = false,
) -> Result[ClientEffectRunJournalAppend, ClientRunJournalAppendIssue[E]] {
  let record = snapshot.record
  guard record.run_admission is None &&
    record.preparation_problem is None &&
    record.run_state_original is None &&
    record.run_state_observation is None &&
    snapshot.run is None &&
    snapshot.submission.revision < 9223372036854775807L &&
    materials.request is Some(request) &&
    client_submission_reference_matches_request(record.reference, request) else {
    return Err(InvalidOriginal)
  }
  if materials.prepared.source_intent is Some(original) &&
    !physical_equal(original, intent) {
    return Err(InvalidOriginal)
  }
  if client_submitted_intent_wire(intent) !=
    client_submitted_intent_wire(record.intent) {
    return Err(ChangedIntent)
  }
  let definition = materials.run_definition
  let preparing = snapshot.submission
  match read("client_submitted_intents", preparing.key) {
    Ok(Some(row)) if row.key == preparing.key &&
      row.revision == preparing.revision &&
      row.body == preparing.body => ()
    Ok(_) => return Err(Observation(custody_lost))
    Err(issue) => return Err(Observation(issue))
  }
  match
    read_client_retained_run_journal(request, read, validate_run, custody_lost) {
    Ok(None) => ()
    Ok(Some(_)) => return Err(ForeignRun)
    Err(issue) => return Err(issue)
  }
  let epoch = client_submission_epoch_token_body(
    client_submission_reference_record_epoch(record.reference),
  )
  guard now >= 0.0 &&
    now <= 9007199254740991.0 &&
    now.floor() == now &&
    @values.epoch_milliseconds_timestamp(now.to_int64()) is Some(at) &&
    submission_epoch_validity(epoch, now) is Ok(Admissible) &&
    bind_client_local_run_policy_original(
      profile,
      record.reference,
      request,
      definition,
      retention,
      at,
      host_adoption_cid,
      read_selection_cid,
    )
    is Ok(policy) &&
    materials.normalization is Some(custody) &&
    custody.issued is Some(issued) &&
    client_effect_normalization_materials_cid(materials) is Some(materials_cid) &&
    capture_client_effect_run_observation_originals(
      materials.prepared,
      materials.allowed,
      definition,
    )
    is Ok(observation) else {
    return Err(InvalidOriginal)
  }
  let publication_policy = if prepared_client_effect_publication_data_policy_cid(
      materials.prepared,
    )
    is Some(_) {
    guard issue_client_effect_run_policy_originals(materials.prepared)
      is Ok(wire) else {
      return Err(InvalidOriginal)
    }
    Some(wire)
  } else {
    None
  }
  let definition_cid = @publication.publication_contract_identity(definition)
  let reference = client_submission_reference_record_wire(record.reference)
  let packet = match
    client_effect_material_journal_packet_wire({
      intent_cid: client_submitted_intent_cid(intent),
      materials_cid,
      materials_wire: client_effect_issued_normalization_materials_wire(issued),
      request_scope_cid: client_request_scope_cid(request),
      run_definition_cid: definition_cid,
      submission_reference: reference,
    }) {
    Ok(wire) => wire
    Err(issue) => return Err(Encoding(issue))
  }
  let run = match
    project_client_run_journal_append(
      request,
      definition,
      max_records,
      scan,
      read,
      validate_run,
      confirm_cancellation,
      custody_lost,
      Some(policy),
      Some(observation),
      None,
      publication_policy,
      Some(packet),
      indexed_store~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let ready = match
    client_submitted_intent_journal_row_body(
      reference,
      intent,
      run_admission=Some((request, definition_cid, 0L)),
      run_state_observation=Some((0L, None)),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Encoding(issue))
  }
  let locator = match
    client_saved_run_reference_locator(record.reference, request, definition) {
    Ok(value) => value
    Err(issue) => return Err(Encoding(issue))
  }
  Ok({ run, preparing, ready, locator, })
}

///|
/// Bound the intermediate candidate bodies before entering their encoders.
/// The saved preparing bytes and issued material are the same immutable
/// originals that the writer and the physical census will validate.
pub fn client_effect_run_journal_candidate_workspace(
  materials : ClientEffectRunMaterials,
  snapshot : ClientSavedSubmissionSnapshot,
) -> (Int64, Int64)? {
  guard materials.normalization is Some(custody) &&
    custody.issued is Some(issued) &&
    @encode.quoted_string_construction_extent(issued.wire)
    is Some((material, _)) &&
    @encode.quoted_string_construction_extent(
      client_submission_reference_record_wire(snapshot.record.reference),
    )
    is Some((reference, _)) &&
    @encode.quoted_string_construction_extent(
      @publication.publication_contract_json(materials.run_definition),
    )
    is Some((definition, _)) &&
    @encode.quoted_string_construction_extent(
      @publication.run_evidence_value_json(materials.allowed.prepared),
    )
    is Some((prepared, _)) &&
    @encode.quoted_string_construction_extent(
      @publication.run_evidence_value_json(materials.allowed.authorization),
    )
    is Some((authorization, _)) else {
    return None
  }
  let packet = Int64::min(131072L, 512L + material + reference)
  let observation = Int64::min(131072L, 128L + prepared + authorization)
  // Both envelopes emit valid JSON with no literal control code units.
  // Quoting those newly emitted bytes at most doubles their extent.
  // The local policy is bounded at 8192 bytes. The original publication
  // policy, if selected, has its own existing encoder and validation bound.
  let publication_policy = if prepared_client_effect_publication_data_policy_cid(
      materials.prepared,
    )
    is Some(_) {
    131072L
  } else {
    0L
  }
  let run = Int64::min(
    131072L,
    8192L +
    2L * (packet + observation + 8192L) +
    definition +
    publication_policy,
  )
  let ready = Int64::min(
    262144L,
    snapshot.submission.body.length().to_int64() + 8192L,
  )
  let maximum = Int64::max(run, ready).to_int()
  guard @encode.text_writer_construction_inventory(maximum, 32, 4)
    is Some(writer) &&
    @execution.preparation_representation_cost({
      // Candidate, Run and locator tuples, local policy and evidence
      // envelopes, typed output carriers and scalar/hash controls.
      record_headers: 160L,
      reference_slots: 240L,
      scalar_words: 192L,
      owned_utf16_units: packet + observation + 8192L + publication_policy,
      owned_wire_bytes: run + ready + reference + 128L,
    })
    is Some(held) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers + 160L,
      reference_slots: writer.reference_slots + 240L,
      scalar_words: writer.scalar_words + 192L,
      // The canonical comparison/parse and the owned immutable text can
      // coexist with one emitter, including its copied UTF-8 and hash input.
      owned_utf16_units: writer.owned_utf16_units + 4L * maximum.to_int64(),
      owned_wire_bytes: maximum.to_int64() +
      3L * issued.wire.length().to_int64(),
    })
    is Some(work) else {
    return None
  }
  Some((held, work))
}

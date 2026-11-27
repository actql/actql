///|
/// Validated original physical row, not a new admission or a COMMIT ACK.
pub struct ClientRetainedRunJournalRow {
  row : ClientJournalPhysicalRow
  original : ClientRunJournalInspection
}

///|
/// Same-transaction issued CAS and initial Run insert. The physical Host must
/// keep the original current fence and atomically save the submitted ready row.
pub struct ClientRunJournalAppend {
  key : String
  body : Bytes
  issued_revision : Int64
  issued_body : Bytes
}

///|
pub(all) enum ClientRunJournalAppendPlan {
  Retained(ClientRetainedRunJournalRow)
  Append(ClientRunJournalAppend)
}

///|
pub(all) enum ClientRunJournalAppendIssue[E] {
  Observation(E)
  ChangedIntent
  ForeignRun
  CapacityExceeded
  InvalidOriginal
  Encoding(ClientJournalEncodingIssue)
}

///|
pub fn client_retained_run_journal_row(
  value : ClientRetainedRunJournalRow,
) -> ClientJournalPhysicalRow {
  value.row
}

///|
pub fn client_run_journal_append_rows(
  value : ClientRunJournalAppend,
) -> (String, Bytes, Int64, Bytes) {
  (value.key, value.body, value.issued_revision, value.issued_body)
}

///|
/// Lookup precedes any new Plan or policy issuance. The existing validator
/// must check all saved Run originals/custody, not just decode its outer row.
/// Query failure is Observation; confirmed NotFound is not resend permission.
pub fn[E] read_client_retained_run_journal(
  request : ClientRequestIdentity,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  custody_lost : E,
) -> Result[ClientRetainedRunJournalRow?, ClientRunJournalAppendIssue[E]] {
  let key = client_request_scope_cid(request)
  let row = match read("client_runs", key) {
    Ok(Some(value)) if value.key == key && value.revision >= 0L => value
    Ok(None) => return Ok(None)
    Ok(Some(_)) => return Err(Observation(custody_lost))
    Err(issue) => return Err(Observation(issue))
  }
  let original = match validate_run(row) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  match client_request_identity_relation(request, original.request) {
    SameRequest => Ok(Some({ row, original, }))
    ChangedIntent => Err(ChangedIntent)
    DifferentRequest => Err(Observation(custody_lost))
  }
}

///|
/// Finite decision using the existing complete inventory and row codec. Ports
/// must observe one original Store transaction; no write or execution occurs.
/// A candidate is never accepted until the same transaction's ACK is known.
pub fn[E] prepare_client_run_journal_append(
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  confirm_cancellation : () -> Result[Unit, E],
  custody_lost : E,
  local_policy_original? : ClientLocalRunPolicyOriginal? = None,
  run_observation_originals? : ClientRunObservationOriginals? = None,
  task_materials_cid? : String? = None,
  publication_policy_originals? : String? = None,
  definition_presence? : ((String) -> Result[Bool?, E])? = None,
  task_material_count? : ((Int) -> Result[Bool?, E])? = None,
  validate_cancellation_run? : ((ClientJournalPhysicalRow) -> Result[
    ClientCancellationRunJournalInspection,
    E,
  ])? = None,
  inventory_original? : (() -> Result[
    ClientRunJournalInventoryOriginal,
    E,
  ])? = None,
) -> Result[ClientRunJournalAppendPlan, ClientRunJournalAppendIssue[E]] {
  match
    read_client_retained_run_journal(request, read, validate_run, custody_lost) {
    Ok(Some(retained)) => {
      if @publication.publication_contract_identity(
          retained.original.definition,
        ) !=
        @publication.publication_contract_identity(definition) {
        return Err(ForeignRun)
      }
      // Adopt the actually saved bytes, including their original policy/time.
      return Ok(Retained(retained))
    }
    Ok(None) => ()
    Err(issue) => return Err(issue)
  }
  project_client_run_journal_append(
    request,
    definition,
    max_records,
    scan,
    read,
    validate_run,
    confirm_cancellation,
    custody_lost,
    local_policy_original,
    run_observation_originals,
    task_materials_cid,
    publication_policy_originals,
    None,
    definition_presence~,
    task_material_count~,
    validate_cancellation_run~,
    inventory_original~,
  ).map(plan => Append(plan))
}

///|
/// Prepare against the admitted indexed Store. The physical insert owns
/// Definition uniqueness and can classify only an actual collision.
pub fn[E] prepare_indexed_client_run_journal_append(
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
  max_records : Int,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  custody_lost : E,
  local_policy_original : ClientLocalRunPolicyOriginal,
  run_observation_originals : ClientRunObservationOriginals,
  task_materials_cid : String?,
  publication_policy_originals : String?,
) -> Result[ClientRunJournalAppendPlan, ClientRunJournalAppendIssue[E]] {
  let issuance = match
    journal_issuance_anchor("client_run_custody", max_records, read, custody_lost) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  match read_client_retained_run_journal(request, read, validate_run, custody_lost) {
    Ok(Some(retained)) => {
      if @publication.publication_contract_identity(retained.original.definition) !=
        @publication.publication_contract_identity(definition) {
        Err(ForeignRun)
      } else {
        Ok(Retained(retained))
      }
    }
    Err(issue) => Err(issue)
    Ok(None) => {
      if issuance.0 == max_records {
        return Err(CapacityExceeded)
      }
      encode_client_run_journal_append(
        request,
        definition,
        issuance,
        Some(local_policy_original),
        Some(run_observation_originals),
        task_materials_cid,
        publication_policy_originals,
        None,
        None,
      ).map(plan => Append(plan))
    }
  }
}

///|
/// The original preparing row and all successor candidates for one captured
/// Task Run. Only the physical Store can commit their compare-and-swap.
pub struct ClientCapturedTaskFirstRunRows {
  preparing : ClientJournalPhysicalRow
  run : ClientRunJournalAppend
  ready : Bytes
  locator : (String, Bytes)
  task_materials : ClientTaskMaterialsOriginal[ClientCapturedTaskRunMaterials]
  finite_policy : ClientLocalRunPolicyOriginal
  publication_policy_root : String
}

///|
/// Encode this complete candidate using the existing ready-row transport.
/// The caller funds this encoder and will re-observe before physical commit.
pub fn client_captured_task_first_run_rows_wire(
  candidate : ClientCapturedTaskFirstRunRows,
) -> Result[String, ClientJournalEncodingIssue] {
  let (key, body, revision, issued) = client_run_journal_append_rows(
    candidate.run,
  )
  let before = candidate.preparing
  client_submitted_run_candidate_wire(
    (key, before.key, before.body, body, candidate.ready),
    issued=Some((revision, issued)),
    reference_locator=Some(candidate.locator),
    task_materials=Some(candidate.task_materials),
    preparing_revision=before.revision,
  )
}

///|
/// Price the existing ready-row encoder while the immutable rows and Task
/// chunks remain retained. Only physical row bytes require UTF-8 decoding.
pub fn client_captured_task_first_run_rows_wire_workspace(
  candidate : ClientCapturedTaskFirstRunRows,
) -> Int64? {
  let (key, body, _, issued) = client_run_journal_append_rows(candidate.run)
  let decoded = candidate.preparing.body.length().to_int64() +
    body.length().to_int64() +
    issued.length().to_int64() +
    candidate.ready.length().to_int64() +
    candidate.locator.1.length().to_int64()
  let keys = key.length().to_int64() +
    candidate.preparing.key.length().to_int64() +
    candidate.locator.0.length().to_int64()
  let mut chunk_units = 0L
  for (chunk_key, chunk) in candidate.task_materials.chunks {
    chunk_units += chunk_key.length().to_int64() + chunk.length().to_int64()
  }
  let maximum = Int64::min(1048576L, 6L * (decoded + keys + chunk_units) + 512L)
  guard @encode.text_writer_construction_inventory(maximum.to_int(), 24, 3)
    is Some(writer) else {
    return None
  }
  @execution.preparation_representation_cost({
    // Candidate field controls, five bounded UTF-8 decoders, their result
    // strings, up to three borrowed chunk pairs, and the final copied bytes.
    record_headers: writer.record_headers + 36L,
    reference_slots: writer.reference_slots + 46L,
    scalar_words: writer.scalar_words + 36L,
    owned_utf16_units: writer.owned_utf16_units + 2L * decoded + 40L,
    owned_wire_bytes: maximum,
  })
}

///|
/// Retained additions owned by this candidate after wire staging. The
/// preparing row, already funded Task plan and material wire, and finite
/// policy packet are aliases and stay live under their original reservation.
pub fn client_captured_task_first_run_rows_retained(
  candidate : ClientCapturedTaskFirstRunRows,
) -> Int64? {
  let task = candidate.task_materials
  let (_, run, _, issued) = client_run_journal_append_rows(candidate.run)
  let (locator_key, locator) = candidate.locator
  let chunks = task.chunks
  let count = chunks.length().to_int64()
  guard count > 0L && count <= 3L && physical_equal(task.wire, task.plan.wire) else {
    return None
  }
  let mut text = locator_key.length().to_int64() +
    task.cid.length().to_int64() +
    task.publication_policy_originals.length().to_int64()
  for (key, chunk) in chunks {
    text += key.length().to_int64() + chunk.length().to_int64()
  }
  @execution.preparation_representation_cost({
    // Candidate, append, locator and Task original; four new Bytes; three
    // owned fixed strings; the chunk array/control and one tuple + two
    // strings per chunk. Include its actual backing capacity, not its count.
    record_headers: 13L + 3L * count,
    reference_slots: 16L + 2L * count + chunks.capacity().to_int64(),
    scalar_words: 3L,
    owned_utf16_units: text,
    owned_wire_bytes: run.length().to_int64() +
    issued.length().to_int64() +
    candidate.ready.length().to_int64() +
    locator.length().to_int64(),
  })
}

///|
fn[E] require_client_captured_task_preparing_row(
  preparing : ClientJournalPhysicalRow,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
) -> Result[Unit, ClientRunJournalAppendIssue[E]] {
  match read("client_submitted_intents", preparing.key) {
    Ok(Some(row)) if row.key == preparing.key &&
      row.revision == preparing.revision &&
      row.body == preparing.body => Ok(())
    Ok(_) => Err(Observation(custody_lost))
    Err(issue) => Err(Observation(issue))
  }
}

///|
// The File assembler has already selected its checked metadata. Meter the
// three existing row codecs before retaining any successor. Their ordinary
// 131072/262144 limits remain in their unchanged encoder entrances.
fn client_first_file_journal_rows_capacity(
  snapshot : ClientSavedSubmissionSnapshot,
  definition : @publication.PublicationContract,
  local_policy : String?,
  observation : String?,
  publication_policy : String,
) -> (Int64, Int64)? {
  let record = snapshot.record
  let reference = client_submission_reference_record_wire(record.reference)
  guard @scalar.admit_utf8_length(reference, 4096) is Ok(reference_bytes) &&
    @publication.run_definition_namespace(definition) is Some(run_namespace) else {
    return None
  }
  let intent = client_submitted_intent_wire(record.intent)
  // The request identity and run-admission wire keep their separate bounded
  // existing writers. Six bytes per borrowed UTF-16 unit covers JSON quoting.
  let run_fields = @publication.publication_contract_json(definition)
    .length()
    .to_int64() +
    publication_policy.length().to_int64() +
    local_policy.map(body => body.length().to_int64()).unwrap_or(0L) +
    observation.map(body => body.length().to_int64()).unwrap_or(0L) +
    4096L +
    71L
  let run_bytes = Int64::min(131072L, 512L + 6L * run_fields)
  let ready_bytes = Int64::min(
    262144L,
    512L +
    6L * (intent.length().to_int64() + reference.length().to_int64() + 8192L),
  )
  guard @encode.text_writer_construction_inventory(run_bytes.to_int(), 32, 4)
    is Some(run) &&
    @encode.text_writer_construction_inventory(ready_bytes.to_int(), 16, 2)
    is Some(ready) &&
    @encode.text_writer_construction_inventory(4096, 32, 2) is Some(request) &&
    @encode.text_writer_construction_inventory(8192, 8, 2) is Some(admission) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) else {
    return None
  }
  let locator_units = run_namespace.length().to_int64() + 2L * 71L + 2L
  let body_bytes = run_bytes + ready_bytes + reference_bytes.to_int64() + 10L
  let retained : @execution.PreparationRepresentationUnits = {
    // Include the candidate references to the finite policy and live root CID.
    record_headers: 14L,
    reference_slots: 21L,
    scalar_words: 9L,
    owned_utf16_units: 2L * 71L + 64L,
    owned_wire_bytes: body_bytes,
  }
  let work : @execution.PreparationRepresentationUnits = {
    // Run and Ready each use the request encoder. Keep the admission
    // envelope's String while Ready consumes it. The locator uses the
    // existing namespace/scope/definition preimage and one SHA/hex call.
    record_headers: run.record_headers +
    ready.record_headers +
    2L * request.record_headers +
    admission.record_headers +
    hash.record_headers +
    44L,
    reference_slots: run.reference_slots +
    ready.reference_slots +
    2L * request.reference_slots +
    admission.reference_slots +
    hash.reference_slots +
    60L,
    scalar_words: run.scalar_words +
    ready.scalar_words +
    2L * request.scalar_words +
    admission.scalar_words +
    hash.scalar_words +
    48L,
    owned_utf16_units: run.owned_utf16_units +
    ready.owned_utf16_units +
    2L * request.owned_utf16_units +
    admission.owned_utf16_units +
    hash.owned_utf16_units +
    4L * locator_units,
    owned_wire_bytes: 3L * body_bytes +
    3L * locator_units +
    hash.owned_wire_bytes,
  }
  guard @execution.preparation_representation_cost(retained) is Some(bytes) &&
    @execution.preparation_representation_cost(work) is Some(scratch) else {
    return None
  }
  Some((bytes, scratch))
}

///|
/// First captured Task acceptance under the caller's one current Store
/// transaction. The snapshot and compiled materials must be the retained
/// originals. Caller-owned reservation precedes Task chunk construction.
pub fn[E] prepare_client_captured_task_first_run_rows(
  snapshot : ClientSavedSubmissionSnapshot,
  intent : ClientSubmittedIntent,
  materials : ClientCapturedTaskRunMaterials,
  local_policy_original : ClientLocalRunPolicyOriginal,
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
  before_task_materials : (Int64, Int64) -> Result[Unit, E],
  policy_collection : ClientRunPolicyCollectionFunding,
  before_policy_packet : (Int64, Int64) -> Result[Unit, E],
  fund_task_indexes : (Int64) -> Result[Unit, E],
  fund_task_read : (Int64) -> Result[Unit, E],
  fund_rows : (Int64, Int64) -> Result[Unit, E],
  definition_presence? : ((String) -> Result[Bool?, E])? = None,
  task_material_count? : ((Int) -> Result[Bool?, E])? = None,
  indexed_store? : Bool = false,
) -> Result[ClientCapturedTaskFirstRunRows, ClientRunJournalAppendIssue[E]] {
  let { request, compiled, definition, wire, } = materials
  let record = snapshot.record
  let preparing = snapshot.submission
  guard physical_equal(intent, record.intent) &&
    preparing.revision >= 0L &&
    preparing.revision < 9223372036854775807L &&
    record.run_admission is None &&
    record.preparation_problem is None &&
    record.run_state_original is None &&
    record.run_state_observation is None &&
    snapshot.run is None &&
    client_submission_reference_matches_request(record.reference, request) &&
    client_request_input_cid(request) == client_submitted_intent_cid(intent) &&
    client_compiled_run_has_original_definition(compiled, definition) &&
    submission_epoch_validity(
      client_submission_epoch_token_body(
        client_submission_reference_record_epoch(record.reference),
      ),
      now,
    )
    is Ok(Admissible) else {
    return Err(InvalidOriginal)
  }
  match
    require_client_captured_task_preparing_row(preparing, read, custody_lost) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    read_client_retained_run_journal(request, read, validate_run, custody_lost) {
    Ok(None) => ()
    Ok(Some(_)) => return Err(ForeignRun)
    Err(issue) => return Err(issue)
  }
  let observation = match
    capture_client_run_observation_originals(compiled, definition) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  guard client_task_material_original_construction_capacity(wire)
    is Some((retained, scratch)) else {
    return Err(CapacityExceeded)
  }
  match before_task_materials(retained, scratch) {
    Ok(_) => ()
    Err(issue) => return Err(Observation(issue))
  }
  let packet_failure : Ref[E?] = Ref(None)
  let policy_root : Ref[String?] = Ref(None)
  let task_materials = match
    capture_client_task_materials_original(
      materials,
      client_request_scope_cid(request),
      wire,
      () => {
        issue_client_run_policy_originals_with_root(
          compiled.owner,
          Some(compiled),
          Some((retained, scratch) => {
            match before_policy_packet(retained, scratch) {
              Ok(_) => true
              Err(issue) => {
                packet_failure.val = Some(issue)
                false
              }
            }
          }),
          Some(policy_collection),
        ).map(original => {
          policy_root.val = Some(original.1)
          original.0
        }).map_err(issue => {
          match packet_failure.val {
            Some(original) => ClientRunJournalAppendIssue::Observation(original)
            None =>
              if issue is CapacityExceeded {
                ClientRunJournalAppendIssue::CapacityExceeded
              } else {
                ClientRunJournalAppendIssue::InvalidOriginal
              }
          }
        })
      },
      issue => ClientRunJournalAppendIssue::Encoding(issue),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard policy_root.val is Some(publication_policy_root) else {
    return Err(InvalidOriginal)
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
      Some(local_policy_original),
      Some(observation),
      Some(task_materials.cid),
      Some(task_materials.publication_policy_originals),
      None,
      fund_task_indexes=Some(fund_task_indexes),
      fund_task_read=Some(fund_task_read),
      definition_presence~,
      task_material_count~,
      indexed_store~,
      before_row_encoding=Some((policy, observation) => {
        guard client_first_file_journal_rows_capacity(
            snapshot,
            definition,
            policy,
            observation,
            task_materials.publication_policy_originals,
          )
          is Some((retained, scratch)) else {
          return Err(CapacityExceeded)
        }
        fund_rows(retained, scratch).map_err(issue => Observation(issue))
      }),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let ready = match
    client_submitted_intent_journal_row_body(
      client_submission_reference_record_wire(record.reference),
      intent,
      run_admission=Some(
        (request, @publication.publication_contract_identity(definition), 0L),
      ),
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
  // Construction may call back through the physical ports. Keep the actual
  // predecessor pinned before transferring the complete set of candidates.
  require_client_captured_task_preparing_row(preparing, read, custody_lost).map(_ => {
      preparing,
      run,
      ready,
      locator,
      task_materials,
      finite_policy: local_policy_original,
      publication_policy_root,
    },
  )
}

///|
/// Re-observe a retained first candidate during the physical write transaction.
/// Keep the first encoded Run, policy and Task materials through the CAS.
pub fn[E] check_client_captured_task_first_run_rows_current(
  candidate : ClientCapturedTaskFirstRunRows,
  materials : ClientCapturedTaskRunMaterials,
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  confirm_cancellation : () -> Result[Unit, E],
  custody_lost : E,
  fund_task_indexes : (Int64) -> Result[Unit, E],
  fund_task_read : (Int64) -> Result[Unit, E],
  definition_presence? : ((String) -> Result[Bool?, E])? = None,
  task_material_count? : ((Int) -> Result[Bool?, E])? = None,
  indexed_store? : Bool = false,
) -> Result[Unit, ClientRunJournalAppendIssue[E]] {
  guard physical_equal(candidate.task_materials.plan, materials) &&
    candidate.run.key == client_request_scope_cid(materials.request) else {
    return Err(InvalidOriginal)
  }
  match
    require_client_captured_task_preparing_row(
      candidate.preparing,
      read,
      custody_lost,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    read_client_retained_run_journal(
      materials.request,
      read,
      validate_run,
      custody_lost,
    ) {
    Ok(None) => ()
    Ok(Some(_)) => return Err(ForeignRun)
    Err(issue) => return Err(issue)
  }
  match read("client_run_reference_index", candidate.locator.0) {
    Ok(None) => ()
    Ok(Some(_)) => return Err(Observation(custody_lost))
    Err(issue) => return Err(Observation(issue))
  }
  let (count, revision) = match
    observe_client_first_run_append_issuance(
      materials.definition,
      max_records,
      scan,
      read,
      validate_run,
      confirm_cancellation,
      custody_lost,
      fund_task_indexes=Some(fund_task_indexes),
      fund_task_read=Some(fund_task_read),
      definition_presence~,
      task_material_count~,
      indexed_store~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard revision == candidate.run.issued_revision &&
    client_journal_issuance_count(candidate.run.issued_body, max_records)
    is Ok(successor) &&
    successor == count + 1 else {
    return Err(Observation(custody_lost))
  }
  require_client_captured_task_preparing_row(
    candidate.preparing,
    read,
    custody_lost,
  )
}

///|
/// Initial physical rows matched to this retained Task candidate. Later
/// publication must still use the adopted Store and current authorization.
pub struct ClientCapturedTaskFirstSavedRows {
  run : ClientJournalPhysicalRow
  submitted : ClientJournalPhysicalRow
}

///|
fn client_first_captured_task_saved_rows_match(
  preparing : ClientSavedSubmissionSnapshot,
  saved : ClientSavedSubmissionSnapshot,
  materials : ClientCapturedTaskRunMaterials,
  candidate : ClientCapturedTaskFirstRunRows,
  locator : ClientJournalPhysicalRow,
) -> Bool {
  let before = preparing.submission
  let after = saved.submission
  let (run_key, run_body, _, _) = client_run_journal_append_rows(candidate.run)
  guard physical_equal(candidate.task_materials.plan, materials) &&
    candidate.preparing.key == before.key &&
    candidate.preparing.revision == before.revision &&
    candidate.preparing.body == before.body &&
    preparing.record.run_admission is None &&
    preparing.run is None &&
    before.revision >= 0L &&
    before.revision < 9223372036854775807L &&
    after.key == before.key &&
    after.revision == before.revision + 1L &&
    after.body == candidate.ready &&
    saved.run is Some(run) &&
    run.key == run_key &&
    run.revision == 0L &&
    run.body == run_body &&
    locator.key == candidate.locator.0 &&
    locator.revision == 0L &&
    locator.body == candidate.locator.1 else {
    return false
  }
  guard saved.record.run_admission is Some((selected, definition, 0L)) &&
    saved.record.run_state_observation is Some((0L, None)) &&
    client_request_identity_relation(selected, materials.request) is SameRequest &&
    definition ==
    @publication.publication_contract_identity(materials.definition) &&
    saved.inspection is Some(inspection) &&
    inspection.checkpoint is None &&
    inspection.task_materials_cid == Some(candidate.task_materials.cid) &&
    saved.task_materials == Some(candidate.task_materials.wire) else {
    return false
  }
  true
}

///|
/// Match the exact initial rows from the same Store observation. Downstream
/// callers can borrow these original rows without decoding an admission wire.
pub fn client_first_captured_task_saved_rows(
  preparing : ClientSavedSubmissionSnapshot,
  saved : ClientSavedSubmissionSnapshot,
  materials : ClientCapturedTaskRunMaterials,
  candidate : ClientCapturedTaskFirstRunRows,
  locator : ClientJournalPhysicalRow,
) -> Result[ClientCapturedTaskFirstSavedRows, ClientSavedSubmissionViewIssue] {
  guard client_first_captured_task_saved_rows_match(
      preparing, saved, materials, candidate, locator,
    ) &&
    saved.run is Some(run) else {
    return Err(CustodyLost)
  }
  Ok({ run, submitted: saved.submission, })
}

///|
/// Project the first Saved admission from the retained Task candidate and the
/// exact current rows observed by the caller on the same Store transaction.
pub fn client_first_captured_task_saved_admission_wire(
  preparing : ClientSavedSubmissionSnapshot,
  saved : ClientSavedSubmissionSnapshot,
  materials : ClientCapturedTaskRunMaterials,
  candidate : ClientCapturedTaskFirstRunRows,
  locator : ClientJournalPhysicalRow,
) -> Result[String, ClientSavedSubmissionViewIssue] {
  guard client_first_captured_task_saved_rows_match(
    preparing, saved, materials, candidate, locator,
  ) else {
    return Err(CustodyLost)
  }
  client_saved_submission_admission_wire(saved)
}

///|
// First admission and its write fence share the complete predecessor check.
fn[E] observe_client_first_run_append_issuance(
  definition : @publication.PublicationContract,
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  confirm_cancellation : () -> Result[Unit, E],
  custody_lost : E,
  fund_task_indexes? : ((Int64) -> Result[Unit, E])? = None,
  fund_task_read? : ((Int64) -> Result[Unit, E])? = None,
  definition_presence? : ((String) -> Result[Bool?, E])? = None,
  task_material_count? : ((Int) -> Result[Bool?, E])? = None,
  validate_cancellation_run? : ((ClientJournalPhysicalRow) -> Result[
    ClientCancellationRunJournalInspection,
    E,
  ])? = None,
  inventory_original? : (() -> Result[
    ClientRunJournalInventoryOriginal,
    E,
  ])? = None,
  indexed_store? : Bool = false,
) -> Result[(Int, Int64), ClientRunJournalAppendIssue[E]] {
  if indexed_store {
    match journal_issuance_anchor("client_run_custody", max_records, read, custody_lost) {
      Ok((count, _)) if count == max_records => return Err(CapacityExceeded)
      Ok(issuance) => return Ok(issuance)
      Err(issue) => return Err(Observation(issue))
    }
  }
  if @publication.publication_contract_name(definition) != "run_definition" {
    return Err(InvalidOriginal)
  }
  let (count, revision) = match inventory_original {
    Some(observe) =>
      match observe() {
        Ok(proof) if proof.maximum == max_records => (proof.count, proof.revision)
        Ok(_) => return Err(Observation(custody_lost))
        Err(issue) => return Err(Observation(issue))
      }
    None => {
      let original : ClientTaskMaterialsOriginal[Unit]? = None
      match
        inspect_client_run_journal_inventory_with_index_funding(
          max_records,
          scan,
          read,
          validate_run,
          confirm_cancellation,
          custody_lost,
          original,
          fund_task_indexes,
          fund_task_read,
          task_material_count~,
          validate_cancellation_run~,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Observation(issue))
      }
    }
  }
  if revision < 0L {
    return Err(Observation(custody_lost))
  }
  if count == max_records {
    return Err(CapacityExceeded)
  }
  // An installed index observation is valid only on this same physical
  // snapshot. The full inventory and original capacity refusal precede it.
  if definition_presence is Some(observe) {
    match observe(@publication.publication_contract_identity(definition)) {
      Ok(Some(true)) => return Err(ForeignRun)
      Ok(Some(false)) => return Ok((count, revision))
      Ok(None) => ()
      Err(issue) => return Err(Observation(issue))
    }
  }
  let mut cursor = ""
  let mut observed = 0
  while true {
    let row = match scan("client_runs", cursor) {
      Ok(Some(value)) => value
      Ok(None) => break
      Err(issue) => return Err(Observation(issue))
    }
    if observed >= count || row.key <= cursor {
      return Err(Observation(custody_lost))
    }
    observed += 1
    let other = match validate_run(row) {
      Ok(value) => value
      Err(issue) => return Err(Observation(issue))
    }
    if row.revision < 0L || row.key != client_request_scope_cid(other.request) {
      return Err(Observation(custody_lost))
    }
    if @publication.publication_contract_identity(other.definition) ==
      @publication.publication_contract_identity(definition) {
      return Err(ForeignRun)
    }
    cursor = row.key
  }
  if observed != count {
    return Err(Observation(custody_lost))
  }
  Ok((count, revision))
}

///|
// Both first-admission entrances establish absence before entering here.
fn[E] project_client_run_journal_append(
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  confirm_cancellation : () -> Result[Unit, E],
  custody_lost : E,
  local_policy_original : ClientLocalRunPolicyOriginal?,
  run_observation_originals : ClientRunObservationOriginals?,
  task_materials_cid : String?,
  publication_policy_originals : String?,
  effect_material_originals : String?,
  fund_task_indexes? : ((Int64) -> Result[Unit, E])? = None,
  fund_task_read? : ((Int64) -> Result[Unit, E])? = None,
  definition_presence? : ((String) -> Result[Bool?, E])? = None,
  task_material_count? : ((Int) -> Result[Bool?, E])? = None,
  validate_cancellation_run? : ((ClientJournalPhysicalRow) -> Result[
    ClientCancellationRunJournalInspection,
    E,
  ])? = None,
  before_row_encoding? : ((String?, String?) -> Result[
    Unit,
    ClientRunJournalAppendIssue[E],
  ])? = None,
  inventory_original? : (() -> Result[
    ClientRunJournalInventoryOriginal,
    E,
  ])? = None,
  indexed_store? : Bool = false,
) -> Result[ClientRunJournalAppend, ClientRunJournalAppendIssue[E]] {
  let issuance = match
    observe_client_first_run_append_issuance(
      definition,
      max_records,
      scan,
      read,
      validate_run,
      confirm_cancellation,
      custody_lost,
      fund_task_indexes~,
      fund_task_read~,
      definition_presence~,
      task_material_count~,
      validate_cancellation_run~,
      inventory_original~,
      indexed_store~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  encode_client_run_journal_append(
    request,
    definition,
    issuance,
    local_policy_original,
    run_observation_originals,
    task_materials_cid,
    publication_policy_originals,
    effect_material_originals,
    before_row_encoding,
  )
}

///|
fn[E] encode_client_run_journal_append(
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
  issuance : (Int, Int64),
  local_policy_original : ClientLocalRunPolicyOriginal?,
  run_observation_originals : ClientRunObservationOriginals?,
  task_materials_cid : String?,
  publication_policy_originals : String?,
  effect_material_originals : String?,
  before_row_encoding : ((String?, String?) -> Result[
    Unit,
    ClientRunJournalAppendIssue[E],
  ])?,
) -> Result[ClientRunJournalAppend, ClientRunJournalAppendIssue[E]] {
  let (count, revision) = issuance
  let policy = match local_policy_original {
    None => None
    Some(original) => {
      let body = client_local_run_policy_original_body(original)
      if validate_client_local_run_policy_original_run(
          body, request, definition,
        )
        is Err(_) {
        return Err(InvalidOriginal)
      }
      let wire = @utf8.decode(body) catch { _ => return Err(InvalidOriginal) }
      Some(wire)
    }
  }
  let observation = match run_observation_originals {
    None => None
    Some(original) => {
      if @publication.validate_original_interactive_run_evidence(
          definition,
          original.prepared(),
          original.authorization(),
        )
        is Err(_) {
        return Err(InvalidOriginal)
      }
      match original.wire() {
        Ok(wire) => Some(wire)
        Err(_) => return Err(InvalidOriginal)
      }
    }
  }
  if publication_policy_originals is Some(wire) &&
    read_client_run_policy_originals(wire) is Err(_) {
    return Err(InvalidOriginal)
  }
  if before_row_encoding is Some(fund) {
    match fund(policy, observation) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let record : ClientRunJournalEncoding = {
    request,
    definition,
    dispatch_reserved: false,
    physical_start_claimed: false,
    cancellation_head: None,
    publication_binding: None,
    publication_policy_originals,
    effect_material_originals,
    task_materials_cid,
    checkpoint: None,
  }
  let body = match
    client_run_journal_row_body(
      record,
      local_run_policy_originals=policy,
      run_observation_originals=observation,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Encoding(issue))
  }
  Ok({
    key: client_request_scope_cid(request),
    body,
    issued_revision: revision,
    issued_body: @utf8.encode((count + 1).to_string()),
  })
}

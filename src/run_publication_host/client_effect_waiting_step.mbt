///|
pub(all) enum ClientEffectWaitingStepIssue {
  NotCurrent
  ForeignOriginal
  Checkpoint(ClientEffectCheckpointBindingIssue)
  Waiting(ClientWaitingCheckpointRecordIssue)
  Encoding(ClientJournalEncodingIssue)
}

///|
/// The compare/exchange of the claimed Run and the two insert-only companions
/// must share the caller's original transaction. These bytes claim no COMMIT.
pub struct ClientEffectWaitingStep {
  before : ClientJournalPhysicalRow
  body : Bytes
  witness : ClientJournalPhysicalRow
  locator : ClientJournalPhysicalRow
}

///|
/// Prepare waiting only after the caller has confirmed the original private
/// Store custody and reobserved this exact claimed Run under current. The
/// caller funds the Checkpoint, locator and witness codecs in that frame;
/// independently quote the original Run decode and successor encoder.
pub fn prepare_client_effect_waiting_step(
  materials : ClientEffectRunMaterials,
  original : ClientEffectRunJournalAppend,
  claim : ClientEffectFirstStartStep,
  before : ClientJournalPhysicalRow,
  original_checkpoint : @checkpoint.SealedCheckpoint,
  persisted : @checkpoint.PersistedCheckpoint,
  store : (String, String, UInt64, UInt64),
  updated_at : String,
  current_authorization : Bool,
  before_decode? : ((ClientRunJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ])? = None,
  before_checkpoint? : (() -> Bool)? = None,
  before_encode? : ((Int, Int, Int, Int) -> Result[
    Unit,
    ClientJournalEncodingIssue,
  ])? = None,
) -> Result[ClientEffectWaitingStep, ClientEffectWaitingStepIssue] {
  if !current_authorization {
    return Err(NotCurrent)
  }
  guard !claim.dispatch &&
    physical_equal(persisted.artifact, original_checkpoint) &&
    physical_equal(original, claim.original) &&
    materials.request is Some(request) &&
    confirm_client_effect_first_start_step(claim, before) else {
    return Err(ForeignOriginal)
  }
  let definition = materials.run_definition
  let (run, policy, observation) = match
    decode_client_run_journal_row_with_retained_identity(
      before.body,
      request,
      definition,
      require_retained_identity=true,
      before_construction=before_decode,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignOriginal)
  }
  guard run.dispatch_reserved &&
    run.physical_start_claimed &&
    !run.cancellation_requested() &&
    run.checkpoint is None &&
    run.publication_binding is None &&
    run.effect_material_originals is Some(_) &&
    @publication.run_definition_namespace(definition) == Some(store.0) else {
    return Err(ForeignOriginal)
  }
  match
    validate_client_effect_review_checkpoint_subject(
      materials.allowed,
      definition,
      original_checkpoint,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Checkpoint(issue))
  }
  let prepared = materials.prepared
  let count = prepared_client_effect_result_count(prepared)
  let declared_results = Array(capacity=count)
  for index in 0..<count {
    guard prepared_client_effect_result_name(prepared, index) is Some(name) else {
      return Err(ForeignOriginal)
    }
    declared_results.push(name)
  }
  if before_checkpoint is Some(fund) && !fund() {
    return Err(Encoding(CapacityExceeded))
  }
  let (checkpoint, checkpoint_wire) = match
    prepare_client_waiting_checkpoint_record(
      definition,
      persisted,
      declared_results,
      [],
      {
        authorization_context_cid: client_request_authority_scope_cid(request),
        environment_binding_cid: prepared_client_effect_computation_environment_cid(
          prepared,
        ),
      },
      updated_at,
      { max_wire_bytes: 65536, max_nodes: 128, max_depth: 16, },
    ) {
    Ok(value) => value
    Err(issue) => return Err(Waiting(issue))
  }
  let binding = match
    client_publication_store_binding_body(store.0, store.1, store.2, store.3) {
    Ok(binding) => binding
    Err(_) => return Err(ForeignOriginal)
  }
  let body = match
    client_run_journal_row_body(
      {
        ..run,
        checkpoint: Some(checkpoint_wire),
        publication_binding: Some(binding),
      },
      local_run_policy_originals=policy,
      run_observation_originals=observation,
      measure_construction=before_encode is Some(_),
      before_construction=before_encode.map(fund => {
        (bytes, nodes, depth) => {
          fund(bytes, nodes, depth, checkpoint_wire.length())
        }
      }),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Encoding(issue))
  }
  guard client_effect_ledger_base_witness(request, definition, checkpoint)
    is Some(witness) &&
    client_checkpoint_locator_body(request, original_checkpoint) is Ok(locator) else {
    return Err(ForeignOriginal)
  }
  Ok({
    before,
    body,
    witness: { key: before.key, revision: 0L, body: witness, },
    locator: {
      key: client_checkpoint_locator_key(
        client_request_authority_scope_cid(request),
        original_checkpoint.checkpoint.checkpoint_id,
      ),
      revision: 0L,
      body: locator,
    },
  })
}

///|
/// The actual original successor Read must confirm all three keys, revisions
/// and complete bodies. A failed read retains its own error; equality is not
/// physical cleanup, permission to apply, or permission to repeat the CAS.
pub fn[E] confirm_client_effect_waiting_step(
  step : ClientEffectWaitingStep,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
) -> Result[Unit, E] {
  let run : ClientJournalPhysicalRow = {
    key: step.before.key,
    revision: step.before.revision + 1L,
    body: step.body,
  }
  for
    (table, expected) in [
      ("client_runs", run),
      ("client_effect_custody", step.witness),
      ("client_checkpoint_id_index", step.locator),
    ] {
    match read(table, expected.key) {
      Err(issue) => return Err(issue)
      Ok(Some(actual)) if actual.key == expected.key &&
        actual.revision == expected.revision &&
        actual.body == expected.body => ()
      Ok(_) => return Err(custody_lost)
    }
  }
  Ok(())
}

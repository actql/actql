///|
/// Observe the first committed Effect decision through the exact original
/// Submission and scoped checkpoint locator. This reads durable state DATA;
/// it grants no authority to replay a decision or dispatch a continuation.
pub fn[E] observe_client_decided_effect_checkpoint(
  namespace_id : String,
  authority_scope_cid : String,
  store_binding : String,
  row : ClientJournalPhysicalRow,
  run : ClientRunJournalEncoding,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
  fund : (Int, Int, Int) -> Result[Unit, E],
  completed? : Bool = false,
) -> Result[(ClientRunJournalInspection, String), E] {
  let definition_cid = @publication.publication_contract_identity(
    run.definition,
  )
  let request = run.request
  guard (if completed { row.revision >= 9L } else { row.revision == 4L }) &&
    row.key == client_request_scope_cid(request) &&
    client_request_authority_scope_cid(request) == authority_scope_cid &&
    @publication.run_definition_namespace(run.definition) == Some(namespace_id) &&
    run.publication_binding == Some(store_binding) &&
    run.dispatch_reserved &&
    run.physical_start_claimed &&
    !run.cancellation_requested() &&
    run.task_materials_cid is None &&
    run.checkpoint is Some(wire) &&
    run.effect_material_originals is Some(materials_wire) &&
    wire.length() > 0 &&
    wire.length() <= 262144 &&
    materials_wire.length() > 0 &&
    materials_wire.length() <= 131072 else {
    return Err(custody_lost)
  }
  match fund(3 * wire.length() + 6 * materials_wire.length(), 4096, 64) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard decode_client_checkpoint_journal_row(
      wire,
      run.definition,
      client_effect_ledger_wire_limits(),
    )
    is Ok(checkpoint) &&
    checkpoint.artifact.checkpoint.kind == @checkpoint.EffectSet &&
    checkpoint.artifact.checkpoint.phase == @checkpoint.Commit &&
    checkpoint.binding.authorization_context_cid == authority_scope_cid &&
    checkpoint.resolution_cid is Some(_) &&
    checkpoint.verified_wire is Some(_) &&
    !checkpoint.settlement_only &&
    checkpoint.unknown_effects.is_empty() &&
    (if completed {
      checkpoint.state.status == @publication.Succeeded &&
        checkpoint.resume_intent is Some(intent) &&
        intent.state == @checkpoint.ResumeCompleted && intent.generation > 0L
    } else {
      checkpoint.effect_ledger.is_empty() &&
      (match (checkpoint.state.status, checkpoint.resume_intent) {
        (@publication.Cancelled, None) => true
        (@publication.Resuming, Some(intent)) =>
          intent.state == @checkpoint.ResumePending && intent.generation == 0L
        _ => false
      })
    }) &&
    read_client_effect_material_journal_packet(materials_wire) is Ok(materials) &&
    materials.request_scope_cid == row.key &&
    materials.run_definition_cid == definition_cid &&
    materials.materials_cid ==
    "sha256:" + @sha.hex(@utf8.encode(materials.materials_wire)) else {
    return Err(custody_lost)
  }
  let inspection : ClientRunJournalInspection = {
    request,
    definition: run.definition,
    checkpoint: Some(checkpoint.effect_ledger),
    cancellation_head: run.cancellation_head,
    task_materials_cid: None,
  }
  let saved = match
    read_client_saved_run_reference(
      namespace_id,
      authority_scope_cid,
      definition_cid,
      read,
      actual => {
        if actual.key == row.key &&
          actual.revision == row.revision &&
          actual.body == row.body {
          Ok(inspection)
        } else {
          Err(custody_lost)
        }
      },
      custody_lost,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let original = client_saved_submission_record(saved)
  guard materials.intent_cid == client_submitted_intent_cid(original.intent) &&
    materials.submission_reference ==
    client_submission_reference_record_wire(original.reference) &&
    client_checkpoint_locator_body(request, checkpoint.artifact) is Ok(expected) else {
    return Err(custody_lost)
  }
  let locator_key = client_checkpoint_locator_key(
    authority_scope_cid,
    checkpoint.artifact.checkpoint.checkpoint_id,
  )
  match read("client_checkpoint_id_index", locator_key) {
    Err(issue) => return Err(issue)
    Ok(Some(locator)) if locator.key == locator_key &&
      locator.revision == 0L &&
      locator.body == expected => ()
    _ => return Err(custody_lost)
  }
  let custody = if completed {
    confirm_client_completed_file_effect(row, run, checkpoint, read, fund, custody_lost)
      .bind(_ => observe_client_effect_completion_index(
        namespace_id, authority_scope_cid, definition_cid, row.key, checkpoint, read, fund, custody_lost,
      ))
  } else {
    confirm_client_empty_effect_ledger_witness(
      request, run.definition, checkpoint, read, custody_lost,
    )
  }
  match custody {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match fund(checkpoint.state.wire.length() * 3, 128, 16) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard @publication.prepare_run_state_observation(
      checkpoint.state.wire,
      checkpoint.state.run_id,
      row.revision,
      65536,
      8192,
      64,
    ).bind(observation => observation.wire(row.revision))
    is Ok(state) else {
    return Err(custody_lost)
  }
  Ok((inspection, state))
}

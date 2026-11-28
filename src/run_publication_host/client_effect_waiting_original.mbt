///|
/// The waiting checkpoint and its original same-Store Submission. This
/// metadata does not restore a computation or accept a decision.
pub struct ClientEffectWaitingOriginal {
  submission : ClientSavedSubmissionSnapshot
  run : ClientRunJournalEncoding
  checkpoint : ClientCheckpointJournalRecord
  materials : ClientEffectMaterialJournalPacket
}

///|
/// Read the exact, still waiting original. The caller owns the same live
/// physical reader and checks its adopted Account, epoch and Store binding.
/// The selected Run locator and Checkpoint ID locator must both join this Run.
pub fn[E] read_client_waiting_effect_original(
  namespace_id : String,
  authority_scope_cid : String,
  definition_cid : String,
  store_binding : String,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  decode_run : (ClientJournalPhysicalRow) -> Result[ClientRunJournalEncoding, E],
  custody_lost : E,
  fund : (Int, Int, Int) -> Result[Unit, E],
) -> Result[ClientEffectWaitingOriginal, E] {
  let original : Ref[
    (
      ClientRunJournalEncoding,
      ClientCheckpointJournalRecord,
      ClientEffectMaterialJournalPacket,
    )?,
  ] = Ref(None)
  let submission = match
    read_client_saved_run_reference(
      namespace_id,
      authority_scope_cid,
      definition_cid,
      read,
      row => {
        guard row.revision == 3L && original.val is None else {
          return Err(custody_lost)
        }
        let run = match decode_run(row) {
          Ok(run) => run
          Err(issue) => return Err(issue)
        }
        guard client_request_scope_cid(run.request) == row.key &&
          client_request_authority_scope_cid(run.request) == authority_scope_cid &&
          @publication.publication_contract_identity(run.definition) ==
          definition_cid &&
          @publication.run_definition_namespace(run.definition) ==
          Some(namespace_id) &&
          run.publication_binding == Some(store_binding) &&
          run.dispatch_reserved &&
          run.physical_start_claimed &&
          !run.cancellation_requested() &&
          run.task_materials_cid is None &&
          run.checkpoint is Some(wire) &&
          run.effect_material_originals is Some(materials_wire) &&
          0 < wire.length() &&
          wire.length() <= 262144 &&
          0 < materials_wire.length() &&
          materials_wire.length() <= 131072 else {
          return Err(custody_lost)
        }
        match fund(wire.length() * 3 + materials_wire.length() * 6, 4128, 64) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
        guard decode_client_checkpoint_journal_row(wire, run.definition, {
            max_wire_bytes: 65536,
            max_nodes: 128,
            max_depth: 16,
          })
          is Ok(checkpoint) &&
          checkpoint.artifact.checkpoint.kind == @checkpoint.EffectSet &&
          checkpoint.artifact.checkpoint.phase == @checkpoint.Commit &&
          checkpoint.artifact.checkpoint.subject
          is @checkpoint.RunUnit(run_definition_cid~, ..) &&
          run_definition_cid == definition_cid &&
          checkpoint.state.status == @publication.WaitingCheckpoint &&
          checkpoint.binding.authorization_context_cid == authority_scope_cid &&
          checkpoint.resolution_cid is None &&
          checkpoint.verified_wire is None &&
          checkpoint.resume_intent is None &&
          checkpoint.resume_intent_id is None &&
          !checkpoint.settlement_only &&
          read_client_effect_material_journal_packet(materials_wire)
          is Ok(materials) &&
          materials.request_scope_cid == row.key &&
          materials.run_definition_cid == definition_cid &&
          materials.materials_cid ==
          "sha256:" + @sha.hex(@utf8.encode(materials.materials_wire)) else {
          return Err(custody_lost)
        }
        original.val = Some((run, checkpoint, materials))
        Ok({
          request: run.request,
          definition: run.definition,
          checkpoint: Some(checkpoint.effect_ledger),
          cancellation_head: run.cancellation_head,
          task_materials_cid: None,
        })
      },
      custody_lost,
    ) {
    Ok(submission) => submission
    Err(issue) => return Err(issue)
  }
  let record = client_saved_submission_record(submission)
  guard original.val is Some((run, checkpoint, materials)) &&
    materials.intent_cid == client_submitted_intent_cid(record.intent) &&
    materials.submission_reference ==
    client_submission_reference_record_wire(record.reference) else {
    return Err(custody_lost)
  }
  match
    confirm_client_empty_effect_ledger_witness(
      run.request,
      run.definition,
      checkpoint,
      read,
      custody_lost,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let artifact = checkpoint.artifact
  let key = client_checkpoint_locator_key(
    authority_scope_cid,
    artifact.checkpoint.checkpoint_id,
  )
  match read("client_checkpoint_id_index", key) {
    Err(issue) => Err(issue)
    Ok(Some(row)) if row.key == key &&
      row.revision == 0L &&
      client_checkpoint_locator_body(run.request, artifact) is Ok(expected) &&
      row.body == expected => Ok({ submission, run, checkpoint, materials, })
    _ => Err(custody_lost)
  }
}

///|
/// Join the selected Checkpoint locator to the original accepted Run and
/// waiting record in the same physical snapshot. The locator alone is only
/// DATA. Cursor advancement, current RunRead and Read return are Host duties.
pub fn[E] read_client_waiting_effect_checkpoint_locator(
  namespace_id : String,
  authority_scope_cid : String,
  store_binding : String,
  locator : ClientJournalPhysicalRow,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  decode_run : (ClientJournalPhysicalRow) -> Result[ClientRunJournalEncoding, E],
  custody_lost : E,
  fund : (Int, Int, Int) -> Result[Unit, E],
) -> Result[ClientEffectWaitingOriginal, E] {
  guard locator.revision == 0L &&
    locator.body.length() > 0 &&
    locator.body.length() <= 262144 else {
    return Err(custody_lost)
  }
  match fund(locator.body.length(), 4096, 64) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard decode_client_checkpoint_locator(locator.body)
    is Ok((request, id, checkpoint_cid)) &&
    client_request_authority_scope_cid(request) == authority_scope_cid &&
    locator.key == client_checkpoint_locator_key(authority_scope_cid, id) else {
    return Err(custody_lost)
  }
  let scope = client_request_scope_cid(request)
  let row = match read("client_runs", scope) {
    Ok(Some(row)) if row.key == scope && row.revision == 3L => row
    Ok(_) => return Err(custody_lost)
    Err(issue) => return Err(issue)
  }
  let run = match decode_run(row) {
    Ok(run) => run
    Err(issue) => return Err(issue)
  }
  guard client_request_identity_relation(request, run.request) == SameRequest else {
    return Err(custody_lost)
  }
  read_client_waiting_effect_original(
    namespace_id,
    authority_scope_cid,
    @publication.publication_contract_identity(run.definition),
    store_binding,
    read,
    observed => {
      if observed.key == row.key &&
        observed.revision == row.revision &&
        observed.body == row.body {
        Ok(run)
      } else {
        Err(custody_lost)
      }
    },
    custody_lost,
    fund,
  ).bind(original => {
    if original.checkpoint.artifact.checkpoint.checkpoint_id == id &&
      original.checkpoint.artifact.checkpoint_cid == checkpoint_cid &&
      client_checkpoint_locator_body(
        original.run.request,
        original.checkpoint.artifact,
      )
      is Ok(body) &&
      body == locator.body {
      Ok(original)
    } else {
      Err(custody_lost)
    }
  })
}

///|
/// The already joined Run can supply the same nested Journal inspection.
pub fn ClientEffectWaitingOriginal::inspection(
  self : ClientEffectWaitingOriginal,
) -> ClientRunJournalInspection {
  {
    request: self.run.request,
    definition: self.run.definition,
    checkpoint: Some(self.checkpoint.effect_ledger),
    cancellation_head: self.run.cancellation_head,
    task_materials_cid: None,
  }
}

///|
/// The admitted first waiting transition binds its existing Run control
/// generation and checkpoint state. Use the Common public observation codec
/// after joining the same physical Run and Submission.
pub fn ClientEffectWaitingOriginal::status_wire(
  self : ClientEffectWaitingOriginal,
) -> Result[String, ClientCheckpointJournalIssue] {
  guard client_saved_submission_run_row(self.submission) is Some(row) &&
    row.revision == 3L &&
    @publication.run_definition_run_id(self.run.definition) is Ok(run_id) &&
    self.checkpoint.state.run_id == run_id &&
    self.checkpoint.state.checkpoint_cid ==
    Some(self.checkpoint.artifact.checkpoint_cid) else {
    return Err(InvalidMaterial)
  }
  @publication.prepare_run_state_observation(
    self.checkpoint.state.wire,
    run_id,
    row.revision,
    65536,
    8192,
    64,
  )
  .bind(observation => observation.wire(row.revision))
  .map_err(_ => InvalidMaterial)
}

///|
/// Public metadata uses the same checkpoint subject, reason and artifacts
/// read back from the original accepted Run. No Review plaintext is read.
pub fn ClientEffectWaitingOriginal::write_summary(
  self : ClientEffectWaitingOriginal,
  writer : @encode.Writer,
) -> Bool raise {
  let artifact = self.checkpoint.artifact
  let checkpoint = artifact.checkpoint
  guard checkpoint.subject
    is @checkpoint.RunUnit(run_id~, run_definition_cid~, ..) else {
    return false
  }
  @encode.begin_object(writer)
  @encode.key(writer, "checkpointId")
  @encode.string_value(writer, checkpoint.checkpoint_id)
  @encode.key(writer, "checkpointCid")
  @encode.string_value(writer, artifact.checkpoint_cid)
  @encode.key(writer, "kind")
  @encode.string_value(writer, "effect_set")
  @encode.key(writer, "phase")
  @encode.string_value(writer, "commit")
  @encode.key(writer, "subject")
  @encode.begin_object(writer)
  @encode.key(writer, "kind")
  @encode.string_value(writer, "run_unit")
  @encode.key(writer, "runId")
  @encode.string_value(writer, run_id)
  @encode.key(writer, "runDefinitionCid")
  @encode.string_value(writer, run_definition_cid)
  @encode.end_object(writer)
  @encode.key(writer, "requiredArtifact")
  @encode.begin_object(writer)
  @encode.key(writer, "type")
  @encode.string_value(writer, "effect_set_preview")
  @encode.key(writer, "cid")
  @encode.string_value(writer, checkpoint.required_artifact_cid)
  @encode.end_object(writer)
  @encode.key(writer, "reviewProjectionCid")
  @encode.string_value(writer, checkpoint.review_projection_cid)
  @encode.key(writer, "requirements")
  @encode.begin_array(writer)
  for requirement in checkpoint.requirements {
    @encode.string_value(
      writer,
      @checkpoint.checkpoint_requirement_token(requirement),
    )
  }
  @encode.end_array(writer)
  @encode.key(writer, "createdAt")
  @encode.string_value(writer, checkpoint.created_at)
  @encode.key(writer, "expiresAt")
  @encode.string_value(writer, checkpoint.expires_at)
  @encode.key(writer, "humanSummary")
  @encode.string_value(writer, checkpoint.human_summary)
  @encode.end_object(writer)
  true
}

///|
// The ID locator is retained for exact historical/duplicate resolution. A
// pending page excludes a different scope and decided state only after the
// actual scoped locator and, for a decision, its own Run row agree.
fn[E] inspect_client_effect_pending_locator(
  namespace_id : String,
  authority_scope_cid : String,
  store_binding : String,
  locator : ClientJournalPhysicalRow,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  decode_run : (ClientJournalPhysicalRow) -> Result[ClientRunJournalEncoding, E],
  custody_lost : E,
  fund : (Int, Int, Int) -> Result[Unit, E],
) -> Result[ClientEffectWaitingOriginal?, E] {
  guard locator.revision == 0L &&
    locator.body.length() > 0 &&
    locator.body.length() <= 262144 else {
    return Err(custody_lost)
  }
  match fund(locator.body.length(), 4096, 64) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard decode_client_checkpoint_locator(locator.body) is Ok((request, id, cid)) &&
    valid_client_request_cid(cid) else {
    return Err(custody_lost)
  }
  let authority = client_request_authority_scope_cid(request)
  guard locator.key == client_checkpoint_locator_key(authority, id) else {
    return Err(custody_lost)
  }
  if authority != authority_scope_cid {
    return Ok(None)
  }
  let scope = client_request_scope_cid(request)
  let row = match read("client_runs", scope) {
    Ok(Some(row)) if row.key == scope && row.revision >= 3L => row
    Ok(_) => return Err(custody_lost)
    Err(issue) => return Err(issue)
  }
  if row.revision == 3L {
    return read_client_waiting_effect_checkpoint_locator(
      namespace_id, authority_scope_cid, store_binding, locator, read, decode_run,
      custody_lost, fund,
    ).map(original => Some(original))
  }
  let run = match decode_run(row) {
    Ok(run) => run
    Err(issue) => return Err(issue)
  }
  guard client_request_identity_relation(request, run.request) == SameRequest &&
    @publication.run_definition_namespace(run.definition) == Some(namespace_id) &&
    run.publication_binding == Some(store_binding) &&
    run.dispatch_reserved &&
    run.physical_start_claimed &&
    run.effect_material_originals is Some(_) &&
    run.checkpoint is Some(checkpoint_wire) &&
    checkpoint_wire.length() > 0 &&
    checkpoint_wire.length() <= 262144 else {
    return Err(custody_lost)
  }
  match fund(checkpoint_wire.length() * 3, 4096, 64) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard decode_client_checkpoint_journal_row(
      checkpoint_wire,
      run.definition,
      client_effect_ledger_wire_limits(),
    )
    is Ok(checkpoint) &&
    checkpoint.state.status != @publication.WaitingCheckpoint &&
    checkpoint.resolution_cid is Some(_) &&
    checkpoint.verified_wire is Some(_) &&
    checkpoint.artifact.checkpoint_cid == cid &&
    checkpoint.artifact.checkpoint.checkpoint_id == id &&
    client_checkpoint_locator_body(run.request, checkpoint.artifact)
    is Ok(expected) &&
    locator.body == expected else {
    return Err(custody_lost)
  }
  Ok(None)
}

///|
/// Emit a bounded metadata page using the caller's same adopted Read. Index
/// ordering only chooses candidates. Every disclosed item joins the physical
/// locator, original Submission, Run, scope, Store and waiting checkpoint.
pub fn[E] write_client_waiting_effect_checkpoint_page(
  writer : @encode.Writer,
  namespace_id : String,
  authority_scope_cid : String,
  store_binding : String,
  after : String,
  limit : Int,
  checkpoint_id : String?,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  scan_after : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  decode_run : (ClientJournalPhysicalRow) -> Result[ClientRunJournalEncoding, E],
  custody_lost : E,
  fund : (Int, Int, Int) -> Result[Unit, E],
) -> Result[Unit, E] {
  if limit < 1 ||
    limit > 100 ||
    after.length() > 512 ||
    (
      checkpoint_id is Some(id) &&
      (id.is_empty() || id.length() > 512 || !after.is_empty() || limit != 1)
    ) {
    return Err(custody_lost)
  }
  let table = "client_checkpoint_id_index"
  let mut cursor = after
  let mut next = None
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "items")
    @encode.begin_array(writer)
    let mut emitted = 0
    let mut ended = false
    for index in 0..<=1024 {
      let row = match checkpoint_id {
        Some(id) => {
          if index > 0 {
            ended = true
            break
          }
          read(table, client_checkpoint_locator_key(authority_scope_cid, id))
        }
        None => scan_after(table, cursor)
      }
      let original = match row {
        Ok(Some(row)) => row
        Ok(None) => {
          ended = true
          break
        }
        Err(issue) => return Err(issue)
      }
      if index == 1024 ||
        (checkpoint_id is None && original.key.lexical_compare(cursor) <= 0) {
        return Err(custody_lost)
      }
      let selected = match
        inspect_client_effect_pending_locator(
          namespace_id, authority_scope_cid, store_binding, original, read, decode_run,
          custody_lost, fund,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if selected is Some(pending) {
        if emitted == limit {
          next = Some(cursor)
          ended = true
          break
        }
        if checkpoint_id is Some(id) &&
          pending.checkpoint.artifact.checkpoint.checkpoint_id != id {
          return Err(custody_lost)
        }
        if !pending.write_summary(writer) {
          return Err(custody_lost)
        }
        emitted += 1
      }
      cursor = original.key
    }
    if !ended {
      return Err(custody_lost)
    }
    @encode.end_array(writer)
    if next is Some(key) {
      @encode.key(writer, "next")
      @encode.string_value(writer, key)
    }
    @encode.end_object(writer)
    Ok(())
  } catch {
    _ => Err(custody_lost)
  }
}

///|
/// A review request supplies the checkpoint artifact CID. The physical
/// locator inventory chooses the candidate; the full waiting Run join
/// authenticates the selected locator before any holding is opened.
pub fn[E] select_client_waiting_effect_checkpoint_cid(
  namespace_id : String,
  authority_scope_cid : String,
  store_binding : String,
  selected_cid : String,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  scan_after : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  decode_run : (ClientJournalPhysicalRow) -> Result[ClientRunJournalEncoding, E],
  custody_lost : E,
  fund : (Int, Int, Int) -> Result[Unit, E],
) -> Result[ClientEffectWaitingOriginal?, E] {
  if !valid_client_request_cid(selected_cid) {
    return Err(custody_lost)
  }
  let mut after = ""
  for _ in 0..<1024 {
    let row = match scan_after("client_checkpoint_id_index", after) {
      Ok(None) => return Ok(None)
      Ok(Some(row)) => row
      Err(issue) => return Err(issue)
    }
    guard row.key > after &&
      row.revision == 0L &&
      row.body.length() > 0 &&
      row.body.length() <= 262144 else {
      return Err(custody_lost)
    }
    match fund(row.body.length(), 4096, 64) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    guard decode_client_checkpoint_locator(row.body) is Ok((request, id, cid)) &&
      valid_client_request_cid(cid) else {
      return Err(custody_lost)
    }
    let scope = client_request_authority_scope_cid(request)
    guard row.key == client_checkpoint_locator_key(scope, id) else {
      return Err(custody_lost)
    }
    if scope == authority_scope_cid && cid == selected_cid {
      return read_client_waiting_effect_checkpoint_locator(
        namespace_id, authority_scope_cid, store_binding, row, read, decode_run,
        custody_lost, fund,
      ).map(original => Some(original))
    }
    after = row.key
  }
  Err(custody_lost)
}

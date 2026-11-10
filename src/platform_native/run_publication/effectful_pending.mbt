///|
/// The existing Native publication lifecycle for a retained Effectful chain.
/// One preparation/occurrence and its SAME persisted payloads stay here across
/// commit, uncertain failure, observation and child-first cancellation.
struct NativePreparedEffectfulRunPublication {
  service : NativeRunPublicationService
  evidence : NativeEffectfulPublicationEvidence
  intent : NativeRunPublicationIntent
  occurrence : NativeRunPublicationOccurrence
  preparation : NativeRunPublicationPreparation
  material_generation_cids : Array[String]
  reclaimed : Array[Bool]
  mut committed : NativeRunPublicationResult?
  mut cancelled : Bool
  mut closing : Bool
  mut cancelling : Bool
}

///|
pub(all) enum NativeEffectfulPublicationCancellationIssue {
  PublicationCommitted
  PublicationUnresolved(NativeRunPublicationIssue)
  Cleanup(Array[NativeCapturedRunCleanupFailure])
}

///|
/// Retain the exact original attempt before allowing publication/observation.
/// The caller funds the copied reference/control inventories on its original
/// Read. Only actual same-attempt Store payloads acquire cancellation custody.
pub fn prepare_retained_effectful_run_publication_native(
  service : NativeRunPublicationService,
  evidence : NativeEffectfulPublicationEvidence,
  intent : NativeRunPublicationIntent,
  occurrence : NativeRunPublicationOccurrence,
  preparation : NativeRunPublicationPreparation,
) -> Result[NativePreparedEffectfulRunPublication, NativeRunPublicationIssue] {
  match require_effectful_publication_materials(service, evidence) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let request = match
    issue_request(
      service,
      evidence.run_definition,
      evidence.definitions,
      intent,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  if @publication.publication_contract_json(request) !=
    @publication.publication_contract_json(preparation.request) {
    return Err(CommitConflict)
  }
  let attempt = match
    issuance_result(
      @publication.issue_publication_attempt(
        request,
        evidence.run_definition,
        occurrence.attempt_id,
        occurrence.fence_cid,
        occurrence.external_idempotency_key,
        occurrence.started_at,
        service.max_wire_bytes,
        service.max_nodes,
        service.max_depth,
      ),
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  if @publication.publication_contract_json(attempt) !=
    @publication.publication_contract_json(preparation.attempt) {
    return Err(CommitConflict)
  }
  let evidence = {
    ..evidence,
    definitions: evidence.definitions.copy(),
    artifacts: evidence.artifacts.copy(),
    derivations: evidence.derivations.copy(),
    orderings: evidence.orderings.copy(),
    retentions: evidence.retentions.copy(),
    bindings: evidence.bindings.copy(),
    binding_schema_wires: evidence.binding_schema_wires.copy(),
  }
  let index = match
    issuance_result(
      @publication.issue_public_index_entry(
        evidence.run_definition,
        evidence.invocation,
        evidence.manifest,
        evidence.receipt,
        evidence.captured_run,
        evidence.bindings,
        request,
        attempt,
        occurrence.committed_at,
        service.max_wire_bytes,
        service.max_nodes,
        service.max_depth,
      ),
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  match
    @publication.validate_retained_effectful_publication_commit(
      evidence.final_evidence,
      evidence.bindings,
      request,
      attempt,
      index,
    ) {
    Err(issue) => return Err(Store(@store.EffectfulPublication(issue)))
    Ok(_) => ()
  }
  match
    service.store.observe_publication_payload_facts(
      evidence.bindings,
      evidence.binding_schema_wires,
      service.max_wire_bytes,
      service.max_nodes,
      service.max_depth,
    ) {
    Err(issue) => return Err(Store(issue))
    Ok(_) => ()
  }
  let generations = []
  for binding in evidence.bindings {
    let facts = match
      @publication.project_durable_result_binding_read(binding) {
      Err(issue) => return Err(Projection(issue))
      Ok(value) => value
    }
    let payload = match
      service.store.inspect_payload(facts.material_generation_cid) {
      Err(issue) => return Err(Store(issue))
      Ok(value) => value
    }
    if payload.publication_attempt_cid !=
      @publication.publication_contract_identity(preparation.attempt) {
      return Err(CommitConflict)
    }
    generations.push(payload.material_generation_cid)
  }
  match require_effectful_publication_materials(service, evidence) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  Ok({
    service,
    evidence,
    intent,
    occurrence,
    preparation,
    reclaimed: Array::make(generations.length(), false),
    material_generation_cids: generations,
    committed: None,
    cancelled: false,
    closing: false,
    cancelling: false,
  })
}

///|
pub fn NativePreparedEffectfulRunPublication::commit(
  self : NativePreparedEffectfulRunPublication,
) -> Result[NativeRunPublicationResult, NativeRunPublicationIssue] {
  if self.cancelled || self.closing {
    return Err(InvalidConfiguration)
  }
  if self.committed is Some(value) {
    return Ok(value)
  }
  match
    commit_prepared_effectful_run_publication_native(
      self.service,
      self.evidence,
      self.intent,
      self.occurrence,
      self.preparation,
    ) {
    Err(issue) => Err(issue)
    Ok(value) => {
      self.committed = Some(value)
      Ok(value)
    }
  }
}

///|
/// No possibly committed generation is reclaimed from a lost reply. Reconcile
/// through the existing scoped Store/index validator before cancelling payloads.
pub fn NativePreparedEffectfulRunPublication::cancel(
  self : NativePreparedEffectfulRunPublication,
) -> Result[Bool, NativeEffectfulPublicationCancellationIssue] {
  if self.committed is Some(_) {
    return Err(PublicationCommitted)
  }
  if self.cancelled {
    return Ok(true)
  }
  if self.cancelling {
    return Err(PublicationUnresolved(InvalidConfiguration))
  }
  self.closing = true
  self.cancelling = true
  defer {
    self.cancelling = false
  }
  // Reconcile even when another same-request occurrence won before this
  // wrapper attempted commit. Closing prevents reentrant use of this original.
  match
    inspect_existing_effectful_commit(
      self.service,
      self.evidence,
      self.intent,
      self.preparation.request,
    ) {
    Err(issue) => return Err(PublicationUnresolved(issue))
    Ok(Some(value)) => {
      self.committed = Some(value)
      return Err(PublicationCommitted)
    }
    Ok(None) => ()
  }
  let failures : Array[NativeCapturedRunCleanupFailure] = []
  for result, generation in self.material_generation_cids {
    if self.reclaimed[result] {
      continue
    }
    match self.service.store.reclaim_payload(generation) {
      Ok(_) => self.reclaimed[result] = true
      Err(issue) => failures.push({ result, issue, })
    }
  }
  if failures.is_empty() {
    self.cancelled = true
    Ok(true)
  } else {
    Err(Cleanup(failures))
  }
}

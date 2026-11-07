///|
/// Borrowed completion of the compiler-retained Content component. This token
/// is not an execution, holding or cleanup owner. The original input is checked
/// at completion; the generated output subsequently borrows byte custody, not
/// the released source rows, under the existing Content lifetime contract.
struct ClientSerializationGeneration {
  run : ClientCompiledRun
  definition : @publication.PublicationContract
  evidence : @publication.BoundContentGeneration
  output : @execution.CompletedOutput?
  captured : ClientSerializationCapturedInput?
  saved_scope : ClientInferSavedCallScope?
}

///|
pub(all) enum ClientSerializationGenerationIssue {
  MissingComponent
  ForeignRun
  ForeignInput
  QuantityMismatch
  PolicyMismatch
  Output(ClientSerializationOutputIssue)
  Evidence(@publication.RunEvidenceValueIssue)
}

///|
/// Reserve one immutable byte custody cell for the original admitted output
/// before generation. It is separate from the input/prefix's temporary owner.
pub fn client_serialization_byte_holding_cid(
  run : ClientCompiledRun,
  definition : @publication.PublicationContract,
  store_authority_cid : String,
) -> String? {
  guard client_compiled_run_serialization(run) is Some(component) &&
    check_client_compiled_run_definition(run, definition) is Ok(_) else {
    return None
  }
  @publication.content_generation_private_holding_cid(
    definition,
    store_authority_cid,
    component.output.node_id,
    "content_bytes",
  )
}

///|
/// Compile-time selection is not execution evidence. Only the original
/// completed input and a reference issued after verified physical custody may
/// discharge this component. No caller-supplied wire completion is accepted.
pub fn complete_client_serialization_generation(
  run : ClientCompiledRun,
  definition : @publication.PublicationContract,
  input : ClientSerializationInput,
  input_evidence : ClientSerializationInputEvidence,
  candidate : @publication.GeneratedContentReference,
  content : @values.CheckedValue,
  available : () -> Bool,
  limits : @execution.ValueLimits,
  max_name_bytes : Int,
) -> Result[ClientSerializationGeneration, ClientSerializationGenerationIssue] {
  guard client_compiled_run_serialization(run) is Some(component) else {
    return Err(MissingComponent)
  }
  if !physical_equal(component.owner, run.owner) ||
    !physical_equal(
      @lower.serialization_owner(component.barrier),
      @lower.serialization_owner(input.barrier),
    ) ||
    @lower.serialization_step(component.barrier) !=
    @lower.serialization_step(input.barrier) {
    return Err(ForeignInput)
  }
  let (rows, bytes) = @publication.content_byte_generation_limits(input.encoder)
  if rows > component.max_rows || bytes > component.max_bytes {
    return Err(QuantityMismatch)
  }
  if @publication.generated_content_reference_policy(candidate) !=
    @publication.captured_effect_dependency_body_cid(component.policy) {
    return Err(PolicyMismatch)
  }
  if check_client_compiled_run_definition(run, definition) is Err(_) {
    return Err(ForeignRun)
  }
  if !physical_equal(input_evidence.run, run) ||
    !physical_equal(input_evidence.input, input) {
    return Err(ForeignInput)
  }
  let (proof_bytes, proof_nodes, proof_depth) = client_serialization_evidence_codec_bounds()
  let evidence = match
    @publication.bind_generated_content_observation(
      run.template,
      @publication.publication_contract_identity(definition),
      component.output.node_id,
      component.output.logical_cid,
      input_evidence.artifact,
      candidate,
      content,
      proof_bytes,
      proof_nodes,
      proof_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  let output = match
    complete_client_serialization_output(
      input, candidate, content, available, limits, max_name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Output(issue))
  }
  Ok({
    run,
    definition,
    evidence,
    output: Some(output),
    captured: input_evidence.captured,
    saved_scope: None,
  })
}

///|
/// Restored proof custody has no fresh encoder completion. Both forms borrow
/// the existing holding and its current permission; neither owns reclamation.
fn client_serialization_generation_available_for(
  generation : ClientSerializationGeneration,
  run : ClientCompiledRun,
) -> Bool {
  if !physical_equal(generation.run, run) ||
    @publication.bound_content_generation_value(generation.evidence) is None {
    return false
  }
  match (generation.output, generation.saved_scope) {
    (Some(output), None) => @execution.completed_output_available(output)
    (None, Some(saved)) =>
      client_infer_saved_call_scope_matches_run(
        saved,
        run,
        generation.definition,
      ) &&
      client_serialization_recovery_matches_infer(
        run,
        generation.definition,
        saved.plan,
        saved.occurrence,
        generation.evidence,
      )
    _ => false
  }
}

///|
/// A completion from another admitted Run, even with identical compiled bytes,
/// cannot become this Run's execution evidence. Revocation is checked live.
pub fn client_serialization_generation_output_for(
  generation : ClientSerializationGeneration,
  run : ClientCompiledRun,
) -> @execution.CompletedOutput? {
  if !client_serialization_generation_available_for(generation, run) {
    return None
  }
  generation.output
}

///|
/// Reference identity from this completed and currently readable occurrence,
/// for its containing observation. It is not a byte-CID authority shortcut.
pub fn client_serialization_generation_reference_for(
  generation : ClientSerializationGeneration,
  run : ClientCompiledRun,
) -> String? {
  if !client_serialization_generation_available_for(generation, run) {
    return None
  }
  @publication.bound_content_generation_reference(generation.evidence)
}

///|
/// Transfer the original completion or authenticated recovered proof custody
/// to the existing Receipt/CapturedRun issuer. Raw saved JSON cannot substitute
/// the current opaque Ref and original checked Model-input scope.
pub fn client_serialization_generation_capture(
  generation : ClientSerializationGeneration,
) -> @publication.BoundContentGeneration? {
  client_serialization_generation_capture_for(
    generation,
    generation.run,
    generation.definition,
  )
}

///|
/// The mixed publication path borrows only this admitted Run's original
/// generation. Equal saved evidence from another execution cannot substitute.
pub fn client_serialization_generation_capture_for(
  generation : ClientSerializationGeneration,
  run : ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> @publication.BoundContentGeneration? {
  if !client_serialization_generation_available_for(generation, run) ||
    @publication.publication_contract_identity(generation.definition) !=
    @publication.publication_contract_identity(definition) ||
    @publication.bound_content_generation_value(generation.evidence) is None {
    return None
  }
  Some(generation.evidence)
}

///|
/// Original Source closure survives release of the acquired rows. This borrows
/// immutable observations from the admitted generation, not a new acquisition
/// or an egress grant. The generated byte holding must still be available.
pub fn client_serialization_generation_source_observations_for(
  generation : ClientSerializationGeneration,
  run : ClientCompiledRun,
) -> Array[(String, @publication.ModelSourceObservation)]? {
  guard client_serialization_generation_capture_for(
      generation,
      run,
      generation.definition,
    )
    is Some(_) &&
    client_compiled_run_serialization(run) is Some(component) else {
    return None
  }
  let source_free = @strategy.graph_source_free_inputs_complete(run.owner.graph)
  if generation.saved_scope is Some(saved) {
    return Some(saved.named_sources.copy())
  }
  match generation.captured {
    None if source_free => Some([])
    Some(captured) if !source_free &&
      physical_equal(captured.owner, run.owner) &&
      captured.task == component.task &&
      captured.step == component.step => Some(captured.named_sources.copy())
    _ => None
  }
}

///|
/// Select the consumer from this Run's retained mixed Plan, not the legacy
/// task-zero helper. Acquired/keyed components can occupy a later graph task.
pub fn client_serialization_generation_infer_occurrence(
  generation : ClientSerializationGeneration,
  run : ClientCompiledRun,
  plan : ClientInferPlanGraph,
) -> ClientInferOccurrence? {
  guard physical_equal(generation.run, run) &&
    client_compiled_run_has_infer(run, plan) &&
    client_compiled_run_serialization(run) is Some(component) &&
    plan.serialization is Some(selected) &&
    physical_equal(component, selected) &&
    @strategy.graph_task_owner(run.owner.graph, plan.task) is Some(preparation) &&
    client_serialization_generation_source_observations_for(generation, run)
    is Some(_) else {
    return None
  }
  let occurrence : ClientInferOccurrence = {
    owner: run.owner,
    task: plan.task,
    stage: plan.stage,
    step: plan.source_ordinal,
    preparation,
  }
  if client_infer_occurrence_matches_plan(occurrence, plan) {
    Some(occurrence)
  } else {
    None
  }
}

///|
fn client_serialization_generation_sources_for_infer(
  generation : ClientSerializationGeneration,
  occurrence : ClientInferOccurrence,
  plan : ClientInferPlanGraph,
) -> Array[(String, @publication.ModelSourceObservation)]? {
  guard client_serialization_generation_infer_occurrence(
      generation,
      generation.run,
      plan,
    )
    is Some(original) &&
    physical_equal(original.owner, occurrence.owner) &&
    client_infer_occurrence_coordinates(original) ==
    client_infer_occurrence_coordinates(occurrence) else {
    return None
  }
  client_serialization_generation_source_observations_for(
    generation,
    generation.run,
  )
}

///|
/// The existing private holding adapter receives only this original checked
/// generation's closed saved evidence inventory. It cannot substitute another
/// input, Run, output node or Store by supplying JSON.
pub fn client_serialization_generation_recovery_bindings(
  generation : ClientSerializationGeneration,
  run : ClientCompiledRun,
  store_authority_cid : String,
) -> Array[(String, String, String, String)]? {
  guard client_serialization_generation_available_for(generation, run) &&
    @publication.bound_content_generation_value(generation.evidence)
    is Some(evidence) &&
    @publication.bound_content_generation_derivation(generation.evidence)
    is Some(derivation) &&
    @publication.bound_content_generation_input_artifact(generation.evidence)
    is Some(input) &&
    @publication.bound_content_generation_location(generation.evidence)
    is Some((store, node_id)) &&
    store == store_authority_cid else {
    return None
  }
  let output = []
  for
    (name, value) in [
      ("content_input_artifact", input),
      ("content_evidence", derivation),
      ("content_generation", evidence),
    ] {
    guard @publication.content_generation_private_holding_cid(
        generation.definition,
        store_authority_cid,
        node_id,
        name,
      )
      is Some(holding_cid) else {
      return None
    }
    output.push(
      (
        name,
        @publication.run_evidence_value_identity(value),
        @publication.run_evidence_value_json(value),
        holding_cid,
      ),
    )
  }
  Some(output)
}

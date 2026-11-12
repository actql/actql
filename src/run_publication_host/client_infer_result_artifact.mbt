///|
/// The actual producer Artifact bound to a completed pre-Model input port.
/// This borrows existing custody; it owns no execution, permission or cleanup.
struct ClientInferResultArtifactInput {
  occurrence : ClientInferOccurrence
  input : @execution.CompletedOutput
  artifact : ClientEffectLocalResultArtifact
  manifest : ClientEffectLocalManifest
  interface : @checked.BuiltResultInterface
}

///|
/// Bind an actual checked Result import before Model dispatch. Equal rows,
/// raw Source identities or another read of that producer are not substitutes
/// for the inputs retained by this completed prefix's original provider.
/// The bounded borrowed wrapper uses existing Common preparation overhead;
/// variable Artifact bodies and retained inventories keep their original owner.
pub fn prepare_client_infer_result_artifact_input(
  occurrence : ClientInferOccurrence,
  plan : ClientInferPlanGraph,
  import_index : Int,
  input : @execution.CompletedOutput,
  sequence : @execution.GeneratedSequence,
  bindings : Array[(Int, Int, @execution.ProducerRead)],
  completed : @execution.CompletedSegmentInputs,
  artifact : ClientEffectLocalResultArtifact,
  manifest : ClientEffectLocalManifest,
) -> Result[ClientInferResultArtifactInput, ClientInferCallScopeIssue] {
  let owner = artifact.invocation.owner
  if !client_infer_occurrence_matches_plan(occurrence, plan) ||
    !physical_equal(
      occurrence.owner.graph,
      @strategy.checked_effect_computation_graph(owner.graph),
    ) ||
    !physical_equal(
      @execution.generated_sequence_owner(sequence),
      occurrence.preparation,
    ) ||
    !@execution.completed_output_matches_port(
      input,
      occurrence.preparation,
      @pipeline.Step(occurrence.step - 1),
    ) ||
    !client_effect_local_artifact_matches_computation(artifact, owner) ||
    !client_effect_local_manifest_matches(
      manifest,
      owner,
      artifact.invocation,
      manifest.artifacts,
    ) ||
    !manifest.artifacts.any(original => physical_equal(original, artifact)) {
    return Err(ForeignInput)
  }
  let program = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  guard @checked.unit_result_import_at(program, occurrence.stage, import_index)
    is Some(interface) &&
    artifact.source is ResultSource(borrow, definition) &&
    interface.producer_unit_definition_cid == definition.unit_definition_cid &&
    interface.result_name == definition.result_name &&
    artifact.invocation.unit < occurrence.stage &&
    @strategy.captured_any_result_borrow_cell_output(borrow) is Some(original) else {
    return Err(ForeignInput)
  }
  let pipeline = @lower.pipeline(
    @lower.bound_preparation(occurrence.preparation),
  )
  let mut selected = None
  for index in 0..<@pipeline.input_count(pipeline) {
    if @pipeline.input_at(pipeline, index).map(value => value.0) ==
      Some(interface.input_name) {
      selected = Some(index)
    }
  }
  guard selected is Some(slot) &&
    @execution.completed_segment_inputs_output(completed, sequence, bindings)
    is Some(actual) &&
    physical_equal(actual, input) &&
    @execution.completed_segment_inputs_has_original_pipeline_input(
      completed,
      occurrence.preparation,
      slot,
      original,
    ) &&
    client_effect_local_artifact_matches_computation(artifact, owner) else {
    return Err(ForeignInput)
  }
  Ok({ occurrence, input, artifact, manifest, interface, })
}

///|
/// Read the existing checked input label and semantic Artifact identity only.
pub fn client_infer_result_artifact_input_binding(
  value : ClientInferResultArtifactInput,
  occurrence : ClientInferOccurrence,
  input : @execution.CompletedOutput,
) -> Result[(String, String), ClientInferCallScopeIssue] {
  if !physical_equal(value.occurrence, occurrence) ||
    !physical_equal(value.input, input) ||
    !physical_equal(value.manifest.invocation, value.artifact.invocation) ||
    !client_effect_local_artifact_matches_computation(
      value.artifact,
      value.artifact.invocation.owner,
    ) {
    return Err(ForeignInput)
  }
  Ok(
    (
      value.interface.input_name,
      client_effect_local_result_artifact_cid(value.artifact),
    ),
  )
}

///|
/// Checked import cardinality only; this grants no Artifact or input borrow.
pub fn client_infer_occurrence_result_import_count(
  occurrence : ClientInferOccurrence,
) -> Int {
  @checked.unit_result_import_count(
    @strategy.graph_program(occurrence.owner.graph),
    occurrence.stage,
  ).unwrap_or(0)
}

///|
/// Original checked producer coordinates for the installing caller's bounded
/// cache. This is immutable inventory DATA, never an Artifact or read grant.
pub fn client_infer_occurrence_result_imports(
  occurrence : ClientInferOccurrence,
) -> Array[(Int, String)] {
  let program = @strategy.graph_program(occurrence.owner.graph)
  let count = @checked.unit_result_import_count(program, occurrence.stage).unwrap_or(
    0,
  )
  Array::makei(count, index => {
    let imported = @checked.unit_result_import_at(
      program,
      occurrence.stage,
      index,
    ).unwrap()
    let mut producer = -1
    for unit in 0..<occurrence.stage {
      if @checked.unit_definition_cid(program, unit) ==
        Some(imported.producer_unit_definition_cid) {
        producer = unit
        break
      }
    }
    (producer, imported.result_name)
  })
}

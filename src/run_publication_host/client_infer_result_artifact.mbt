///|
/// The actual producer Artifact bound to a completed pre-Model input port.
/// This borrows existing custody; it owns no execution, permission or cleanup.
struct ClientInferResultArtifactInput {
  occurrence : ClientInferOccurrence
  input : @execution.CompletedOutput
  original : ClientInferResultArtifactOriginal
  interface : @checked.BuiltResultInterface
}

///|
priv enum ClientInferResultArtifactOriginal {
  Effect(ClientEffectLocalResultArtifact, ClientEffectLocalManifest)
  Whole(ClientWholeLocalResultArtifact, ClientWholeLocalResultManifest)
}

///|
fn client_infer_result_artifact_original_cids(
  value : ClientInferResultArtifactInput,
) -> (String, String) {
  match value.original {
    Effect(artifact, manifest) =>
      (client_effect_local_result_artifact_cid(artifact), manifest.cid)
    Whole(artifact, manifest) =>
      (client_whole_local_result_artifact_cid(artifact), manifest.cid)
  }
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
  prepare_client_infer_result_artifact_input_original(
    occurrence,
    plan,
    import_index,
    input,
    sequence,
    completed,
    artifact,
    manifest,
    () => {
      @execution.completed_segment_inputs_output(completed, sequence, bindings)
    },
  )
}

///|
/// The same Artifact admission consumes the complete mixed prefix proof.
pub fn prepare_client_infer_fixed_result_artifact_input(
  occurrence : ClientInferOccurrence,
  plan : ClientInferPlanGraph,
  import_index : Int,
  input : @execution.CompletedOutput,
  sequence : @execution.GeneratedSequence,
  bindings : Array[(Int, Int, @execution.FixedRelationRead)],
  completed : @execution.CompletedSegmentInputs,
  artifact : ClientEffectLocalResultArtifact,
  manifest : ClientEffectLocalManifest,
) -> Result[ClientInferResultArtifactInput, ClientInferCallScopeIssue] {
  prepare_client_infer_result_artifact_input_original(
    occurrence,
    plan,
    import_index,
    input,
    sequence,
    completed,
    artifact,
    manifest,
    () => {
      @execution.completed_fixed_segment_inputs_output(
        completed, sequence, bindings,
      )
    },
  )
}

///|
fn prepare_client_infer_result_artifact_input_original(
  occurrence : ClientInferOccurrence,
  plan : ClientInferPlanGraph,
  import_index : Int,
  input : @execution.CompletedOutput,
  sequence : @execution.GeneratedSequence,
  completed : @execution.CompletedSegmentInputs,
  artifact : ClientEffectLocalResultArtifact,
  manifest : ClientEffectLocalManifest,
  original_output : () -> @execution.CompletedOutput?,
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
    artifact.invocation.unit < occurrence.stage else {
    return Err(ForeignInput)
  }
  // Cells retain their existing completion directly. A resident Artifact
  // was sealed against its exact managed bridge/export receipt by its issuer;
  // borrow THAT completed source, never equal rows or another physical import.
  let original = match
    @strategy.captured_any_result_borrow_cell_output(borrow) {
    Some(value) => value
    None => {
      guard @strategy.captured_any_result_borrow_requires_managed_export(borrow) &&
        @execution.completed_relation_export_original_source(
          artifact.export_receipt,
        )
        is Some(value) else {
        return Err(ForeignInput)
      }
      value
    }
  }
  guard client_infer_result_input_slot(occurrence, interface) is Some(slot) &&
    original_output() is Some(actual) &&
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
  Ok({ occurrence, input, original: Effect(artifact, manifest), interface, })
}

///|
/// A Whole-backed Model prefix must consume the canonical exported Result
/// from the already completed producer Unit at its own checked input port.
pub fn prepare_client_infer_whole_result_artifact_input(
  occurrence : ClientInferOccurrence,
  plan : ClientInferPlanGraph,
  import_index : Int,
  input : @execution.CompletedOutput,
  sequence : @execution.GeneratedSequence,
  bindings : Array[(Int, Int, @execution.FixedRelationRead)],
  completed : @execution.CompletedSegmentInputs,
  artifact : ClientWholeLocalResultArtifact,
  manifest : ClientWholeLocalResultManifest,
) -> Result[ClientInferResultArtifactInput, ClientInferCallScopeIssue] {
  let owner = artifact.invocation.owner
  let program = @strategy.graph_program(occurrence.owner.graph)
  guard client_infer_occurrence_matches_plan(occurrence, plan) &&
    physical_equal(owner.scope.origin.compiled.owner, occurrence.owner) &&
    artifact.invocation.unit < occurrence.stage &&
    @checked.unit_result_import_at(program, occurrence.stage, import_index)
    is Some(interface) &&
    interface.producer_unit_definition_cid ==
    artifact.source.unit_definition_cid &&
    interface.result_name == artifact.source.result_name &&
    client_whole_local_result_manifest_matches(manifest, artifact) &&
    @execution.completed_output_matches_port(
      input,
      occurrence.preparation,
      @pipeline.Step(occurrence.step - 1),
    ) &&
    @execution.completed_fixed_segment_inputs_output(
      completed, sequence, bindings,
    )
    is Some(actual) &&
    physical_equal(actual, input) &&
    @strategy.captured_completed_unit_result_input_original(artifact.custody)
    is Some(original) else {
    return Err(ForeignInput)
  }
  guard client_infer_result_input_slot(occurrence, interface) is Some(slot) &&
    @execution.completed_segment_inputs_has_exact_pipeline_input(
      completed,
      occurrence.preparation,
      slot,
      original,
    ) &&
    client_whole_local_result_manifest_matches(manifest, artifact) else {
    return Err(ForeignInput)
  }
  Ok({ occurrence, input, original: Whole(artifact, manifest), interface, })
}

///|
fn client_infer_result_input_slot(
  occurrence : ClientInferOccurrence,
  interface : @checked.BuiltResultInterface,
) -> Int? {
  let pipeline = @lower.pipeline(
    @lower.bound_preparation(occurrence.preparation),
  )
  for index in 0..<@pipeline.input_count(pipeline) {
    if @pipeline.input_at(pipeline, index).map(value => value.0) ==
      Some(interface.input_name) {
      return Some(index)
    }
  }
  None
}

///|
fn client_infer_whole_result_sources_match(
  artifact : ClientWholeLocalResultArtifact,
  supplied : ClientInferComposedSources,
) -> Bool {
  let original = artifact.invocation.owner.sources
  if original.inputs.length() != supplied.inputs.length() ||
    supplied.keyed is Some(_) {
    return false
  }
  for index, input in original.inputs {
    let actual = supplied.inputs[index]
    if !physical_equal(input.observation, actual.observation) ||
      !physical_equal(input.source, actual.source) {
      return false
    }
  }
  true
}

///|
fn client_infer_whole_result_scope_sources_match(
  artifact : ClientWholeLocalResultArtifact,
  named : Array[(String, @publication.ModelSourceObservation)],
  sources : Array[@publication.ModelSourceObservation],
) -> Bool {
  let original = artifact.invocation.owner.sources.inputs
  if named.length() != original.length() ||
    sources.length() != original.length() {
    return false
  }
  for index, input in original {
    if !physical_equal(input.observation, sources[index]) ||
      !physical_equal(input.observation, named[index].1) {
      return false
    }
  }
  true
}

///|
fn client_infer_result_artifact_original_current(
  value : ClientInferResultArtifactInput,
) -> Bool {
  match value.original {
    Effect(artifact, manifest) =>
      physical_equal(manifest.invocation, artifact.invocation) &&
      client_effect_local_artifact_matches_computation(
        artifact,
        artifact.invocation.owner,
      )
    Whole(artifact, manifest) =>
      client_whole_local_result_manifest_matches(manifest, artifact)
  }
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
    !client_infer_result_artifact_original_current(value) {
    return Err(ForeignInput)
  }
  Ok(
    (
      value.interface.input_name,
      client_infer_result_artifact_original_cids(value).0,
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
    client_infer_occurrence_result_import_at(occurrence, index).unwrap_or(
      (-1, ""),
    )
  })
}

///|
/// Borrow one checked import coordinate without building a result inventory.
pub fn client_infer_occurrence_result_import_at(
  occurrence : ClientInferOccurrence,
  index : Int,
) -> (Int, String)? {
  let program = @strategy.graph_program(occurrence.owner.graph)
  guard @checked.unit_result_import_at(program, occurrence.stage, index)
    is Some(imported) else {
    return None
  }
  for unit in 0..<occurrence.stage {
    if @checked.unit_definition_cid(program, unit) ==
      Some(imported.producer_unit_definition_cid) {
      return Some((unit, imported.result_name))
    }
  }
  Some((-1, imported.result_name))
}

///|
/// Select one checked receiving edge on the original Whole graph. A matching
/// producer Result alone is insufficient when two ports import the same view.
pub fn client_infer_whole_result_input_edge(
  occurrence : ClientInferOccurrence,
  index : Int,
  run : @strategy.CapturedDAG,
  port : @results.ResultPort,
) -> Int? {
  let graph = @strategy.captured_dag_graph(run)
  let program = @strategy.graph_program(occurrence.owner.graph)
  guard client_infer_occurrence_matches(occurrence, occurrence.owner) &&
    @strategy.source_inputs_dag_matches_original(graph, occurrence.owner.graph) &&
    @checked.unit_result_import_at(program, occurrence.stage, index)
    is Some(imported) &&
    client_infer_result_input_slot(occurrence, imported) is Some(slot) else {
    return None
  }
  let mut selected = None
  for i in 0..<@strategy.graph_data_count(graph) {
    let edge = @strategy.graph_data_at(graph, i).unwrap()
    if @strategy.data_edge_consumer(edge) != occurrence.task {
      continue
    }
    let target = match @strategy.data_edge_operation_input(edge) {
      Some((step, input)) =>
        @lower.node_at(@lower.bound_preparation(occurrence.preparation), step).bind(node => {
            @lower.node_input_target(node, input)
          },
        )
      None => Some(@pipeline.Input(@strategy.data_edge_input(edge)))
    }
    if target != Some(@pipeline.Input(slot)) {
      continue
    }
    guard selected is None &&
      @strategy_view.graph_result_input_port(graph, i) is Ok(Some(actual)) &&
      physical_equal(actual, port) else {
      return None
    }
    selected = Some(i)
  }
  selected
}

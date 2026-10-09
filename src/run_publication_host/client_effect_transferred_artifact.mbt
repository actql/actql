///|
pub(all) enum ClientEffectTransferredArtifactIssue {
  Unavailable
  ForeignInput
  ForeignRun
  ForeignArtifact
  ForeignExport
  Current(ClientRetainedTaskInputIssue)
}

///|
/// Establish independent receiver custody of an already-issued producer
/// Artifact. Native supplies the current exact destination-borrow observation;
/// neither equal rows nor this semantic binding alone authorize execution.
/// The acquired producer remains retained until this handoff is confirmed.
/// Sender and receiver may separately reconstruct the original checked owner.
/// The sender token still proves its exact live owner; this handoff preserves
/// original semantic wires while connecting them to the checked receiver view.
pub fn bind_transferred_client_effect_local_result_artifact(
  materials : ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  captured : @strategy.CapturedEffectResultImport,
  exported : @strategy.CapturedEffectLocalResultExport,
  receipt : @execution.CompletedRelationExportReceipt,
  producer_artifact : ClientEffectProducerArtifact,
  input : ClientRetainedTaskInput,
  current : ClientRetainedInputCurrent,
  borrow_current : () -> Bool,
) -> Result[
  ClientEffectLocalResultArtifact,
  ClientEffectTransferredArtifactIssue,
] {
  let artifact = producer_artifact.artifact
  if @remote.dispatch_request_identity(producer_artifact.dispatch) !=
    @remote.dispatch_request_identity(input.producer.request) {
    return Err(ForeignInput)
  }
  let owner = materials.prepared
  if bind_client_effect_compiled_run(
      owner,
      materials.allowed,
      materials.run_definition,
    )
    is Err(_) {
    return Err(ForeignInput)
  }
  let producer = @strategy.captured_effect_result_import_producer(captured)
  let consumer = @strategy.captured_effect_result_import_consumer(captured)
  if !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) ||
    !@strategy.captured_effect_result_import_matches(
      captured, inputs, consumer, producer,
    ) ||
    consumer != 1 ||
    @strategy.captured_effect_local_result_stage(producer) != 0 ||
    @strategy.captured_effect_local_result_task(producer) != 0 ||
    !physical_equal(
      @strategy.captured_effect_local_result_export_result(exported),
      producer,
    ) {
    return Err(ForeignInput)
  }
  let run = @publication.publication_contract_identity(materials.run_definition)
  guard artifact.custody is AcquiredUnit(sender) else {
    return Err(ForeignArtifact)
  }
  if !client_effect_producer_artifact_current(producer_artifact) ||
    @strategy.captured_effect_local_unit_inputs_run_definition_cid(sender)
    is None {
    return Err(Unavailable)
  }
  if @strategy.captured_effect_inputs_run_definition_cid(inputs) != Some(run) ||
    client_effect_local_artifact_run_definition_cid(artifact) != Some(run) {
    return Err(ForeignRun)
  }
  let edge = match
    prepare_client_effect_retained_input_edge(
      materials.allowed,
      materials.run_definition,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignInput)
  }
  if client_retained_input_edge_projection(edge) !=
    client_retained_input_edge_projection(input.producer.edge) ||
    client_retained_input_edge_schema_cid(edge) !=
    client_retained_input_edge_schema_cid(input.producer.edge) {
    return Err(ForeignInput)
  }
  match validate_client_retained_task_input_current(input, current) {
    Ok(_) => ()
    Err(issue) => return Err(Current(issue))
  }
  if !borrow_current() ||
    !client_effect_producer_artifact_current(producer_artifact) ||
    !@strategy.captured_effect_result_import_matches(
      captured, inputs, consumer, producer,
    ) {
    return Err(Unavailable)
  }
  guard artifact.custody is AcquiredUnit(_) &&
    artifact.source is ResultSource(_, definition) &&
    client_effect_local_artifact_matches_computation(
      artifact,
      producer_artifact.bound.computation,
    ) &&
    client_effect_local_result_definition_matches(
      definition,
      producer_artifact.bound.computation,
      0,
      @execution.managed_result_occurrence_name(
        @strategy.captured_any_result_borrow_occurrence(
          @strategy.captured_effect_local_result_borrow(producer),
        ),
      ),
    ) else {
    return Err(ForeignArtifact)
  }
  let interface = @strategy.captured_effect_result_import_interface(captured)
  if interface.producer_unit_definition_cid != definition.unit_definition_cid ||
    interface.result_name != definition.result_name {
    return Err(ForeignArtifact)
  }
  let sender_owner = producer_artifact.bound.computation
  let sender_identity = prepared_client_effect_identity(sender_owner)
  let receiver_identity = prepared_client_effect_identity(owner)
  if sender_identity != receiver_identity ||
    prepared_client_effect_computation_definition_cid(sender_owner) !=
    prepared_client_effect_computation_definition_cid(owner) ||
    prepared_client_effect_computation_semantics_cid(sender_owner) !=
    prepared_client_effect_computation_semantics_cid(owner) ||
    prepared_client_effect_computation_environment_cid(sender_owner) !=
    prepared_client_effect_computation_environment_cid(owner) ||
    !client_effect_local_invocation_matches(
      artifact.invocation,
      sender_owner,
      0,
    ) {
    return Err(ForeignArtifact)
  }
  // Rebind only the checked context of this already-issued semantic evidence.
  // No Source observation, Invocation, Definition, Artifact or Run is reissued.
  let receiver_definition = if physical_equal(sender_owner, owner) {
    definition
  } else {
    { ..definition, owner, }
  }
  let receiver_invocation = if physical_equal(sender_owner, owner) {
    artifact.invocation
  } else {
    { ..artifact.invocation, owner, }
  }
  if !client_effect_local_result_definition_matches(
      receiver_definition,
      owner,
      0,
      interface.result_name,
    ) ||
    !client_effect_local_invocation_matches(receiver_invocation, owner, 0) {
    return Err(ForeignArtifact)
  }
  if !@strategy.captured_effect_local_result_export_matches_receipt(
      inputs, exported, receipt,
    ) {
    return Err(ForeignExport)
  }
  // Compare the actual receiver's checked Result projection, not the raw
  // Transfer order or its Carrier contract. These identities are distinct.
  let original = artifact.export_receipt
  if @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(receipt),
    ) !=
    @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(original),
    ) ||
    @execution.relation_schema_cid(
      @execution.completed_relation_export_schema_identity(receipt),
    ) !=
    @execution.relation_schema_cid(
      @execution.completed_relation_export_schema_identity(original),
    ) ||
    @execution.completed_relation_export_measurement(receipt).row_count !=
    @execution.completed_relation_export_measurement(original).row_count ||
    @execution.output_stream_identity(
      @execution.completed_relation_export_content(receipt),
    ) !=
    @execution.output_stream_identity(
      @execution.completed_relation_export_content(original),
    ) {
    return Err(ForeignExport)
  }
  // Trusted current callbacks can reenter cleanup or revoke the consumer.
  // Recheck both current physical custody and the exact captured import.
  match validate_client_retained_task_input_current(input, current) {
    Ok(_) => ()
    Err(issue) => return Err(Current(issue))
  }
  if !borrow_current() ||
    !@strategy.captured_effect_result_import_matches(
      captured, inputs, consumer, producer,
    ) ||
    !client_effect_producer_artifact_current(producer_artifact) {
    return Err(Unavailable)
  }
  Ok({
    ..artifact,
    custody: EffectInputs(inputs),
    invocation: receiver_invocation,
    source: ResultSource(
      @strategy.captured_effect_local_result_borrow(producer),
      receiver_definition,
    ),
    export_receipt: receipt,
  })
}

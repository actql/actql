///|
/// Identity context for one checked INFER occurrence. It is not
/// a dispatch permission, completed model capture or reusable egress grant.
pub struct ClientInferCallScope {
  owner : PreparedClientProgram
  plan : ClientInferPlanGraph
  input : @execution.CompletedOutput
  artifact : @publication.RunEvidenceValue
  effective : @publication.RunEvidenceValue
  source : @publication.ModelSourceObservation?
  sources : Array[@publication.ModelSourceObservation]
  named_sources : Array[(String, @publication.ModelSourceObservation)]
  unit_definition_cid : String
  source_ordinal : Int
}

///|
pub(all) enum ClientInferCallScopeIssue {
  ForeignOwner
  ForeignInput
  UnsupportedBindings
  Encoding
  Evidence(@publication.RunEvidenceValueIssue)
}

///|
/// Bind the completed input and its exact export receipt. An acquired input
/// supplies its checked capture owner, never a caller-provided CID map. Opaque
/// invocation bindings still require their separate authority admission.
pub fn issue_prepared_client_infer_call_scope(
  owner : PreparedClientProgram,
  plan : ClientInferPlanGraph,
  step : Int,
  input : @execution.CompletedOutput,
  receipt : @execution.CompletedRelationExportReceipt,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  captured? : ClientInferCapturedInput? = None,
) -> Result[ClientInferCallScope, ClientInferCallScopeIssue] {
  guard prepared_client_infer_execution_occurrence(owner, step)
    is Some(occurrence) else {
    return Err(ForeignOwner)
  }
  issue_client_infer_occurrence_call_scope(
    occurrence,
    plan,
    input,
    receipt,
    max_wire_bytes,
    max_nodes,
    max_depth,
    captured~,
  )
}

///|
/// Bind the actual Unit/task to the same completed-input identity owner used
/// by the installed component. A checked Effect view remains private here.
pub fn issue_client_infer_occurrence_call_scope(
  occurrence : ClientInferOccurrence,
  plan : ClientInferPlanGraph,
  input : @execution.CompletedOutput,
  receipt : @execution.CompletedRelationExportReceipt,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  captured? : ClientInferCapturedInput? = None,
  sources? : ClientInferComposedSources? = None,
) -> Result[ClientInferCallScope, ClientInferCallScopeIssue] {
  let owner = occurrence.owner
  let step = occurrence.step
  let prefix = occurrence.preparation
  if sources is Some(value) &&
    (
      captured is Some(_) ||
      !client_infer_composed_sources_matches(value, occurrence)
    ) {
    return Err(ForeignInput)
  }
  if captured is Some(value) &&
    client_infer_captured_input_source(value, owner, step) is None {
    return Err(ForeignInput)
  }
  if client_infer_occurrence_has_captured_sources(occurrence) &&
    captured is None &&
    sources is None {
    // An imported Source path needs its complete capture closure; it cannot
    // silently take the no-external-sources identity route.
    return Err(ForeignInput)
  }
  guard client_infer_occurrence_matches_plan(occurrence, plan) &&
    @checked.unit_definition_cid(
      @strategy.graph_program(owner.graph),
      occurrence.stage,
    )
    is Some(unit_definition_cid) else {
    return Err(ForeignOwner)
  }
  if !@execution.completed_output_matches_port(
      input,
      prefix,
      @pipeline.Step(step - 1),
    ) ||
    !@execution.completed_relation_export_matches_output(receipt, input) {
    return Err(ForeignInput)
  }
  let bindings = match
    issue_prepared_client_empty_invocation_bindings(
      owner, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(UnsupportedBindings)
  }
  let identity = prepared_client_identity(owner)
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  let effective_body = try {
    @encode.begin_object(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-model-effective-inputs/0.1")
    @encode.key(writer, "parameter_values_cid")
    @encode.string_value(writer, identity.parameter_values_cid)
    @encode.key(writer, "invocation_bindings_cid")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_identity(bindings),
    )
    @encode.key(writer, "input_artifacts")
    @encode.begin_object(writer)
    if captured is Some(value) {
      @encode.key(writer, value.name)
      @encode.string_value(
        writer,
        @publication.run_evidence_value_identity(value.logical),
      )
    }
    if sources is Some(value) {
      for input in value.inputs {
        @encode.key(writer, input.name)
        @encode.string_value(
          writer,
          @publication.run_evidence_value_identity(input.logical),
        )
      }
    }
    @encode.end_object(writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
  let effective = match
    @publication.seal_run_evidence_value(
      "model_effective_inputs", effective_body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  let artifact_body = "{\"version\":\"actql-model-input-artifact/0.1\"," +
    "\"program_definition_cid\":\"" +
    identity.program_definition_cid +
    "\",\"unit_definition_cid\":\"" +
    unit_definition_cid +
    "\",\"source_ordinal\":" +
    step.to_string() +
    ",\"effective_inputs_cid\":\"" +
    @publication.run_evidence_value_identity(effective) +
    "\",\"input_fragment_cid\":\"" +
    plan.input_fragment_cid +
    "\",\"logical_relation_cid\":\"" +
    @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(receipt),
    ) +
    "\",\"relation_schema_cid\":\"" +
    @execution.relation_schema_cid(
      @execution.completed_relation_export_schema_identity(receipt),
    ) +
    "\",\"ordered_rows_cid\":\"" +
    @execution.output_stream_identity(
      @execution.completed_relation_export_content(receipt),
    ).0 +
    "\",\"completeness\":\"complete\"}"
  let artifact = match
    @publication.seal_run_evidence_value(
      "model_input_artifact", artifact_body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  Ok({
    owner,
    plan,
    input,
    artifact,
    effective,
    source: captured.map(value => value.observation),
    sources: sources
    .map(client_infer_composed_source_observations)
    .unwrap_or([]),
    named_sources: match captured {
      Some(value) => [(value.name, value.observation)]
      None =>
        sources
        .map(value => value.inputs.map(input => (input.name, input.observation)))
        .unwrap_or([])
    },
    unit_definition_cid,
    source_ordinal: step,
  })
}

///|
pub fn client_infer_call_scope_matches(
  value : ClientInferCallScope,
  owner : PreparedClientProgram,
  input : @execution.CompletedOutput,
) -> Bool {
  physical_equal(value.owner, owner) &&
  @execution.completed_output_available(input) &&
  @execution.completed_output_same_occurrence(value.input, input)
}

///|
pub fn client_infer_call_scope_artifact(
  value : ClientInferCallScope,
) -> @publication.RunEvidenceValue {
  value.artifact
}

///|
/// Saved replay matches the actual input even when its logical slot inventory
/// is empty. This validates original evidence, never fresh dispatch authority.
pub fn check_client_infer_saved_observation_scope(
  scope : ClientInferCallScope,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
) -> Result[Unit, @publication.RunEvidenceValueIssue] {
  @publication.check_saved_model_observation(
    admission,
    definition,
    observation,
    scope.artifact,
    prepared_client_identity(scope.owner).program_definition_cid,
    prepared_client_program_semantics_cid(scope.owner),
    prepared_client_check_environment_cid(scope.owner),
    @environment.model_task_data_handling_cid(
      @environment.model_execution_task(scope.plan.execution),
    ),
    source=scope.source,
    sources=scope.sources,
  )
}

///|
pub fn client_infer_call_scope_source_observations(
  scope : ClientInferCallScope,
) -> Array[@publication.ModelSourceObservation] {
  match scope.source {
    Some(value) => [value]
    None => scope.sources.copy()
  }
}

///|
pub fn client_infer_call_scope_matches_rows(
  value : ClientInferCallScope,
  rows : @execution.PreparedInferRows,
  fixed_request_cid : String,
) -> Bool {
  fixed_request_cid == value.plan.request_cid &&
  @execution.prepared_infer_rows_matches_completed_input(rows, value.input) &&
  physical_equal(
    @infer.model_task(@execution.prepared_infer_rows_owner(rows)),
    @environment.model_execution_task(value.plan.execution),
  )
}

///|
/// The key identity is supplied by the typed request-preparation owner. This
/// value remains identity material, never proof that a model has been called.
pub fn issue_client_infer_call_slot(
  value : ClientInferCallScope,
  key : @publication.RunEvidenceValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunEvidenceValue, ClientInferCallScopeIssue] {
  if !@execution.completed_output_available(value.input) ||
    @publication.run_evidence_value_name(key) != "model_input_key" {
    return Err(ForeignInput)
  }
  let identity = prepared_client_identity(value.owner)
  let body = "{\"version\":\"actql-model-call-slot/0.1\"," +
    "\"program_definition_cid\":\"" +
    identity.program_definition_cid +
    "\",\"unit_definition_cid\":\"" +
    value.unit_definition_cid +
    "\",\"source_ordinal\":" +
    value.source_ordinal.to_string() +
    ",\"effective_inputs_cid\":\"" +
    @publication.run_evidence_value_identity(value.effective) +
    "\",\"input_artifact_cid\":\"" +
    @publication.run_evidence_value_identity(value.artifact) +
    "\",\"input_key_cid\":\"" +
    @publication.run_evidence_value_identity(key) +
    "\",\"model_task_cid\":\"" +
    @environment.model_task_identity(
      @environment.model_execution_task(value.plan.execution),
    ).2 +
    "\",\"fixed_request_cid\":\"" +
    value.plan.request_cid +
    "\"}"
  @publication.seal_run_evidence_value(
    "model_call_slot", body, max_wire_bytes, max_nodes, max_depth,
  ).map_err(issue => Evidence(issue))
}

///|
/// The exact completed input remains with its original execution owner.
/// Exporting or restoring it uses the ordinary bounded Relation/Store path.
pub fn client_infer_call_scope_input(
  value : ClientInferCallScope,
) -> @execution.CompletedOutput? {
  if @execution.completed_output_available(value.input) {
    Some(value.input)
  } else {
    None
  }
}

///|
/// The authored Unit coordinate selected by the same checked occurrence.
pub fn client_infer_call_scope_unit_id(value : ClientInferCallScope) -> String? {
  @syntax.stages(value.owner.source)
  .get(value.plan.stage)
  .map(stage => stage.id)
}

///|
/// Exact private originals for a completed fixed input. This record is not
/// a public artifact or permission; authenticated Store custody is required
/// before it can be used by the saved-scope reader below.
pub fn client_infer_call_scope_snapshot(
  value : ClientInferCallScope,
) -> Result[String, ClientInferCallScopeIssue] {
  if !@execution.completed_output_available(value.input) {
    return Err(ForeignInput)
  }
  let writer = @encode.writer(1000000, 100000, 100) catch {
    _ => return Err(Encoding)
  }
  let body = try {
    @encode.begin_object(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-host-model-input-scope/0.1")
    @encode.key(writer, "input_artifact_wire")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_json(value.artifact),
    )
    @encode.key(writer, "effective_inputs_wire")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_json(value.effective),
    )
    @encode.key(writer, "sources")
    @encode.begin_array(writer)
    for (name, observation) in value.named_sources {
      let (source, input, started, completed) = @publication.model_source_observation_originals(
        observation,
      )
      @encode.begin_object(writer)
      for
        (field, text) in [
          ("name", name),
          ("source_evidence_wire", @publication.run_evidence_value_json(source)),
          ("source_input_wire", @publication.run_evidence_value_json(input)),
          ("capture_started_at", started),
          ("capture_completed_at", completed),
        ] {
        @encode.key(writer, field)
        @encode.string_value(writer, text)
      }
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
  guard parse_plan_identity_value(body, 1000000, 100000, 100) is Some(parsed) else {
    return Err(Encoding)
  }
  Ok(@canonical.stringify_value(parsed, 1000000, 100000, 100)) catch {
    _ => Err(Encoding)
  }
}

///|
/// A receiving owner for authenticated historical input provenance. It has
/// no Source callback and cannot confer infer, egress or Effect permission.
pub struct ClientInferSavedCallScope {
  compiled : ClientCompiledRun
  definition : @publication.PublicationContract
  occurrence : ClientInferOccurrence
  plan : ClientInferPlanGraph
  artifact : @publication.RunEvidenceValue
  effective : @publication.RunEvidenceValue
  named_sources : Array[(String, @publication.ModelSourceObservation)]
  available : () -> Bool
}

///|
fn infer_scope_string(
  value : @canonical.CanonicalValue,
  field : String,
) -> String? {
  match @canonical.object_field(value, field) {
    Some(@canonical.String(text)) => Some(text)
    _ => None
  }
}

///|
fn infer_scope_evidence(
  name : String,
  wire : String,
) -> Result[@publication.RunEvidenceValue, ClientInferCallScopeIssue] {
  let value = match
    @publication.admit_run_evidence_value(name, wire, 1000000, 100000, 100) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  if @publication.run_evidence_value_json(value) != wire {
    return Err(ForeignInput)
  }
  Ok(value)
}

///|
/// Resolve original Source names and contracts from the checked graph alone.
/// Preparing these logical acquisitions never contacts a Source provider.
fn infer_scope_expected_sources(
  occurrence : ClientInferOccurrence,
) -> Result[
  Array[(String, @planning.QuerySourceEvidenceFacts)],
  ClientInferCallScopeIssue,
] {
  let owner = occurrence.owner
  let graph = owner.graph
  if client_acquired_infer_prefix_owner(owner, 0, occurrence.step) is Some(_) {
    guard prepare_client_query_acquisition(owner, occurrence.stage, 0)
      is Ok(acquisition) &&
      @planning.query_acquisition_source_evidence_facts(acquisition)
      is Some(facts) &&
      @acquisition.pipeline_request_at(
        @acquisition.query_acquisition_owner(acquisition),
        @acquisition.query_acquisition_source_index(acquisition),
      )
      is Some(@acquisition.Direct(mode, _)) else {
      return Err(ForeignInput)
    }
    let name = @acquisition.declaration(@acquisition.mode_input(mode)).input_name
    return Ok([(name, facts)])
  }
  let count = @strategy.graph_captured_prefix(graph)
  if count == 0 {
    return Ok([])
  }
  if count != 2 || occurrence.task != count {
    return Err(UnsupportedBindings)
  }
  let pipeline = @lower.pipeline(
    @lower.bound_preparation(occurrence.preparation),
  )
  let incoming : Array[(Int, Int)] = []
  for index in 0..<@strategy.graph_data_count(graph) {
    guard @strategy.graph_data_at(graph, index) is Some(edge) else {
      return Err(ForeignInput)
    }
    if @strategy.data_edge_consumer(edge) == occurrence.task {
      incoming.push(
        (@strategy.data_edge_producer(edge), @strategy.data_edge_input(edge)),
      )
    }
  }
  if incoming.length() != count {
    return Err(ForeignInput)
  }
  let expected : Array[(String, @planning.QuerySourceEvidenceFacts)] = []
  for task in 0..<count {
    let ports = incoming.filter(edge => edge.0 == task)
    guard ports.length() == 1 &&
      @pipeline.input_at(pipeline, ports[0].1) is Some((name, _)) &&
      @strategy.graph_task_unit_index(graph, task) is Some(stage) &&
      prepare_client_query_acquisition(owner, stage, 0) is Ok(acquisition) &&
      @planning.query_acquisition_source_evidence_facts(acquisition)
      is Some(facts) else {
      return Err(ForeignInput)
    }
    if expected.any(item => item.0 == name) {
      return Err(ForeignInput)
    }
    expected.push((name, facts))
  }
  Ok(expected)
}

///|
/// Re-admit historical source observations without a fresh acquisition or a
/// completed ObservationSet. The Host callback must authenticate the exact
/// original Run/scope snapshot and keep its durable holding available.
pub fn read_client_infer_saved_call_scope(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : ClientInferOccurrence,
  plan : ClientInferPlanGraph,
  snapshot_wire : String,
  authority_scope_cid : String,
  custody_available : () -> Bool,
) -> Result[ClientInferSavedCallScope, ClientInferCallScopeIssue] {
  if !custody_available() ||
    !client_infer_occurrence_matches_compiled_run(occurrence, compiled) ||
    check_client_compiled_run_definition(compiled, definition) is Err(_) ||
    !client_infer_occurrence_matches_plan(occurrence, plan) ||
    client_compiled_run_infer(compiled) is None ||
    !physical_equal(client_compiled_run_infer(compiled).unwrap(), plan) {
    return Err(ForeignOwner)
  }
  guard parse_plan_identity_value(snapshot_wire, 1000000, 100000, 100)
    is Some(snapshot) &&
    @canonical.object_field_count(snapshot) == Some(4) &&
    infer_scope_string(snapshot, "version") ==
    Some("actql-host-model-input-scope/0.1") &&
    infer_scope_string(snapshot, "input_artifact_wire") is Some(artifact_wire) &&
    infer_scope_string(snapshot, "effective_inputs_wire")
    is Some(effective_wire) &&
    @canonical.object_field(snapshot, "sources")
    is Some(@canonical.Array(source_values)) else {
    return Err(ForeignInput)
  }
  let canonical = @canonical.stringify_value(snapshot, 1000000, 100000, 100) catch {
    _ => return Err(Encoding)
  }
  if canonical != snapshot_wire {
    return Err(ForeignInput)
  }
  let artifact = match
    infer_scope_evidence("model_input_artifact", artifact_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let effective = match
    infer_scope_evidence("model_effective_inputs", effective_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let expected = match infer_scope_expected_sources(occurrence) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let sources = @canonical.array_values(source_values)
  if sources.length() != expected.length() {
    return Err(ForeignInput)
  }
  let named_sources : Array[(String, @publication.ModelSourceObservation)] = []
  let logicals : Array[(String, @publication.RunEvidenceValue)] = []
  for index in 0..<sources.length() {
    let source = sources[index]
    let (name, facts) = expected[index]
    guard @canonical.object_field_count(source) == Some(5) &&
      infer_scope_string(source, "name") == Some(name) &&
      infer_scope_string(source, "source_evidence_wire") is Some(source_wire) &&
      infer_scope_string(source, "source_input_wire") is Some(input_wire) &&
      infer_scope_string(source, "capture_started_at") is Some(started) &&
      infer_scope_string(source, "capture_completed_at") is Some(completed) else {
      return Err(ForeignInput)
    }
    let evidence = match infer_scope_evidence("source_evidence", source_wire) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let input = match infer_scope_evidence("source_input_logical", input_wire) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let observation = match
      @publication.admit_model_source_observation(
        evidence,
        input,
        facts.source_ref,
        facts.source_contract_cid,
        authority_scope_cid,
        facts.source_data_policy_cid,
        started,
        completed,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Evidence(issue))
    }
    named_sources.push((name, observation))
    logicals.push((name, input))
  }
  let identity = prepared_client_identity(occurrence.owner)
  let bindings = match
    issue_prepared_client_empty_invocation_bindings(
      occurrence.owner,
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(_) => return Err(UnsupportedBindings)
  }
  guard parse_plan_identity_value(effective_wire, 1000000, 100000, 100)
    is Some(effective_value) &&
    infer_scope_string(effective_value, "parameter_values_cid") ==
    Some(identity.parameter_values_cid) &&
    infer_scope_string(effective_value, "invocation_bindings_cid") ==
    Some(@publication.run_evidence_value_identity(bindings)) &&
    @canonical.object_field(effective_value, "input_artifacts")
    is Some(input_map) &&
    @canonical.object_field_count(input_map) == Some(logicals.length()) else {
    return Err(ForeignInput)
  }
  for (name, input) in logicals {
    if infer_scope_string(input_map, name) !=
      Some(@publication.run_evidence_value_identity(input)) {
      return Err(ForeignInput)
    }
  }
  guard @checked.unit_definition_cid(
      @strategy.graph_program(occurrence.owner.graph),
      occurrence.stage,
    )
    is Some(unit_cid) &&
    parse_plan_identity_value(artifact_wire, 1000000, 100000, 100)
    is Some(artifact_value) &&
    @canonical.object_field(artifact_value, "source_ordinal")
    is Some(@canonical.Number(source_ordinal)) &&
    source_ordinal == occurrence.step.to_double() else {
    return Err(ForeignInput)
  }
  for
    (field, expected) in [
      ("program_definition_cid", identity.program_definition_cid),
      ("unit_definition_cid", unit_cid),
      (
        "effective_inputs_cid",
        @publication.run_evidence_value_identity(effective),
      ),
      ("input_fragment_cid", plan.input_fragment_cid),
      ("completeness", "complete"),
    ] {
    if infer_scope_string(artifact_value, field) != Some(expected) {
      return Err(ForeignInput)
    }
  }
  if !custody_available() {
    return Err(ForeignInput)
  }
  Ok({
    compiled,
    definition,
    occurrence,
    plan,
    artifact,
    effective,
    named_sources,
    available: custody_available,
  })
}

///|
pub fn client_infer_saved_call_scope_matches_run(
  value : ClientInferSavedCallScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Bool {
  (value.available)() &&
  physical_equal(value.compiled, compiled) &&
  @publication.publication_contract_identity(value.definition) ==
  @publication.publication_contract_identity(definition)
}

///|
pub fn client_infer_saved_call_scope_matches_occurrence(
  value : ClientInferSavedCallScope,
  occurrence : ClientInferOccurrence,
  plan : ClientInferPlanGraph,
) -> Bool {
  (value.available)() &&
  client_infer_occurrence_matches(value.occurrence, occurrence.owner) &&
  client_infer_occurrence_coordinates(value.occurrence) ==
  client_infer_occurrence_coordinates(occurrence) &&
  physical_equal(value.plan, plan)
}

///|
/// Adopt the restored completion only after its ordinary live identity scan.
/// All historical input and Source identities remain unchanged.
pub fn restore_client_infer_call_scope(
  value : ClientInferSavedCallScope,
  input : @execution.CompletedOutput,
  receipt : @execution.CompletedRelationExportReceipt,
) -> Result[ClientInferCallScope, ClientInferCallScopeIssue] {
  let occurrence = value.occurrence
  if !(value.available)() ||
    !@execution.completed_output_matches_port(
      input,
      occurrence.preparation,
      @pipeline.Step(occurrence.step - 1),
    ) ||
    !@execution.completed_relation_export_matches_output(receipt, input) {
    return Err(ForeignInput)
  }
  guard parse_plan_identity_value(
      @publication.run_evidence_value_json(value.artifact),
      1000000,
      100000,
      100,
    )
    is Some(artifact) &&
    @checked.unit_definition_cid(
      @strategy.graph_program(occurrence.owner.graph),
      occurrence.stage,
    )
    is Some(unit_definition_cid) else {
    return Err(ForeignInput)
  }
  for
    (field, expected) in [
      (
        "logical_relation_cid",
        @execution.logical_relation_cid(
          @execution.completed_relation_export_identity(receipt),
        ),
      ),
      (
        "relation_schema_cid",
        @execution.relation_schema_cid(
          @execution.completed_relation_export_schema_identity(receipt),
        ),
      ),
      (
        "ordered_rows_cid",
        @execution.output_stream_identity(
          @execution.completed_relation_export_content(receipt),
        ).0,
      ),
    ] {
    if infer_scope_string(artifact, field) != Some(expected) {
      return Err(ForeignInput)
    }
  }
  if !(value.available)() {
    return Err(ForeignInput)
  }
  Ok({
    owner: occurrence.owner,
    plan: value.plan,
    input,
    artifact: value.artifact,
    effective: value.effective,
    source: if value.named_sources.length() == 1 {
      Some(value.named_sources[0].1)
    } else {
      None
    },
    sources: if value.named_sources.length() == 1 {
      []
    } else {
      value.named_sources.map(item => item.1)
    },
    named_sources: value.named_sources.copy(),
    unit_definition_cid,
    source_ordinal: occurrence.step,
  })
}

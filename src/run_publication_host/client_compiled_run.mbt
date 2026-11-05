///|
pub(all) enum ClientRunCompilation {
  Values(ClientValuesCompilation)
  Tasks(ClientTaskCompilation)
  Effects(ClientEffectAllowedRun)
}

///|
/// One in-process compilation and its checked owner retain issued admission
/// evidence. Serialized identity is never a replacement for this provenance.
pub struct ClientCompiledRun {
  owner : PreparedClientProgram
  compilation : ClientRunCompilation
  template : @publication.RunEvidenceValue
  plan : @publication.PublicationContract
  prepared : @publication.RunEvidenceValue
  authorization : @publication.RunEvidenceValue
  admission : @publication.RunPublicationAdmission
  source_free_result_policy : @publication.CapturedEffectDependencyBody?
  mut definition_binding : ClientCompiledRunDefinitionFacts?
}

///|
/// One completed immutable binding in the existing compiled holder. Retained
/// tokens and typed results contain no permission, clock or physical resource.
struct ClientCompiledRunDefinitionFacts {
  owner : PreparedClientProgram
  compilation : ClientRunCompilation
  template : @publication.RunEvidenceValue
  plan : @publication.PublicationContract
  prepared : @publication.RunEvidenceValue
  authorization : @publication.RunEvidenceValue
  admission : @publication.RunPublicationAdmission
  definition : @publication.PublicationContract
  binding : ClientCompiledRunDefinitionBinding
}

///|
priv enum ClientCompiledRunDefinitionBinding {
  ValuesDefinition(ClientValuesRunBinding)
  TaskDefinition(ClientTaskRunBinding)
}

///|
pub(all) enum ClientCompiledRunIssue {
  ForeignOwner
  MissingResultPolicy
  InvalidResultPolicy
  Policy(ClientAllowedRunEvidenceIssue)
  Admission(@publication.RunPublicationAdmissionIssue)
  Contract(@publication.PublicationContractIssue)
  ValuesBinding(ClientValuesRunBindingIssue)
  TaskBinding(ClientTaskRunBindingIssue)
  EffectBinding(ClientEffectCompiledRunIssue)
}

///|
pub fn client_compiled_run_matches(
  value : ClientCompiledRun,
  owner : PreparedClientProgram,
) -> Bool {
  physical_equal(value.owner, owner)
}

///|
/// Bind the actual Task compiler retained by this Run, including its Model
/// graph and manifests. Equal Plan bytes or another compiler invocation do
/// not supply this immutable original; no current callback is involved.
pub fn client_compiled_run_matches_tasks(
  value : ClientCompiledRun,
  owner : PreparedClientProgram,
  compilation : ClientTaskCompilation,
) -> Bool {
  match value.compilation {
    Tasks(original) =>
      physical_equal(value.owner, owner) &&
      physical_equal(original, compilation)
    Values(_) | Effects(_) => false
  }
}

///|
/// Match the original Pure artifact retained by a Request. The existing Task
/// predicate remains its owner; Values compares its own compiler original.
/// Equal Plan bytes and Effect artifacts cannot substitute for either one.
pub fn client_compiled_run_matches_pure_compilation(
  value : ClientCompiledRun,
  owner : PreparedClientProgram,
  compilation : ClientRunCompilation,
) -> Bool {
  match compilation {
    Tasks(original) => client_compiled_run_matches_tasks(value, owner, original)
    Values(original) =>
      match value.compilation {
        Values(actual) =>
          physical_equal(value.owner, owner) && physical_equal(actual, original)
        Tasks(_) | Effects(_) => false
      }
    Effects(_) => false
  }
}

///|
/// Borrow the compiler's original checked view only for its exact Effect owner.
/// Never reparse or issue a substitute Effect-free Program for recovery.
pub fn client_compiled_effect_program(
  value : ClientCompiledRun,
  owner : PreparedClientEffectComputation,
) -> PreparedClientProgram? {
  match value.compilation {
    Effects(allowed) if physical_equal(allowed.compilation.owner, owner) =>
      Some(value.owner)
    _ => None
  }
}

///|
/// Result declarations come from the exact checked compilation, including
/// Effect-bearing Runs. A Host must not invent names in lifecycle projections.
pub fn client_compiled_run_result_names(
  value : ClientCompiledRun,
) -> Array[String] {
  match value.compilation {
    Values(compilation) => client_values_compilation_result_names(compilation)
    Tasks(compilation) => client_task_compilation_result_names(compilation)
    Effects(allowed) =>
      client_effect_compilation_result_names(allowed.compilation)
  }
}

///|
/// The shared Run owner retains the selected model barrier through admission.
/// None denotes another compilation path, not permission to synthesize one.
pub fn client_compiled_run_infer(
  value : ClientCompiledRun,
) -> ClientInferPlanGraph? {
  match value.compilation {
    Values(_) => None
    Tasks(compilation) => compilation.infer
    Effects(allowed) => allowed.compilation.compiled.infer
  }
}

///|
/// Return exact compiler-retained components, never reconstructed graphs.
pub fn client_compiled_run_infers(
  value : ClientCompiledRun,
) -> Array[ClientInferPlanGraph] {
  match value.compilation {
    Values(_) => []
    Tasks(compilation) => compilation.infers.copy()
    Effects(allowed) => allowed.compilation.compiled.infers.copy()
  }
}

///|
pub fn client_compiled_run_has_infer(
  value : ClientCompiledRun,
  plan : ClientInferPlanGraph,
) -> Bool {
  client_compiled_run_infers(value).any(selected => {
    physical_equal(selected, plan)
  })
}

///|
/// Model execution may share an admitted Effect Run without adopting an
/// Effect-free publication owner. Retain the exact original compilation.
pub fn client_compiled_run_matches_effect(
  value : ClientCompiledRun,
  owner : PreparedClientEffectComputation,
  compilation : ClientEffectCompilation,
) -> Bool {
  match value.compilation {
    Effects(allowed) =>
      physical_equal(allowed.compilation, compilation) &&
      physical_equal(compilation.owner, owner)
    Values(_) | Tasks(_) => false
  }
}

///|
/// Model egress and the enclosing Run's Result policy are different owners.
/// Source-backed Results retain their checked policy; source-free Effect
/// Results use the Host's explicit unknown-provenance policy original.
pub fn client_compiled_run_infer_observation_policy(
  value : ClientCompiledRun,
) -> String? {
  if client_compiled_run_infers(value).is_empty() {
    return None
  }
  match value.compilation {
    Effects(allowed) =>
      if @strategy.graph_source_free_inputs_complete(
          @strategy.checked_effect_computation_graph(
            allowed.compilation.owner.graph,
          ),
        ) {
        value.source_free_result_policy.map(
          @publication.captured_effect_dependency_body_cid,
        )
      } else {
        prepared_client_effect_publication_data_policy_cid(
          allowed.compilation.owner,
        )
      }
    Tasks(_) =>
      if prepared_client_acquisition_count(value.owner) == 0 {
        value.source_free_result_policy.map(
          @publication.captured_effect_dependency_body_cid,
        )
      } else {
        prepared_client_publication_data_policy_cid(value.owner)
      }
    Values(_) => None
  }
}

///|
/// The installed Host binds its real source-free Result Policy original
/// before defining this Run. Model egress is not a substitute for that policy.
/// Source-backed publication always retains its checked contributing policy.
pub fn with_client_infer_result_policy(
  value : ClientCompiledRun,
  cid : String,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientCompiledRun, ClientCompiledRunIssue] {
  guard value.compilation is Tasks(_) &&
    !client_compiled_run_infers(value).is_empty() else {
    return Err(ForeignOwner)
  }
  if prepared_client_acquisition_count(value.owner) != 0 {
    return Ok(value)
  }
  with_client_source_free_result_policy(
    value, cid, wire, max_bytes, max_nodes, max_depth,
  )
}

///|
/// Add the installed Host's exact unknown-provenance Result policy original to
/// an Effect-free source-free compilation. This pure admission is not publish,
/// read or egress authority, and never replaces a contributing Source policy.
pub fn with_client_source_free_result_policy(
  value : ClientCompiledRun,
  cid : String,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientCompiledRun, ClientCompiledRunIssue] {
  if value.compilation is Effects(_) ||
    prepared_client_acquisition_count(value.owner) != 0 {
    return Err(ForeignOwner)
  }
  let original = match
    admit_source_free_result_policy_body(
      cid, wire, max_bytes, max_nodes, max_depth,
    ) {
    Ok(original) => original
    Err(issue) => return Err(issue)
  }
  if value.source_free_result_policy is Some(saved) &&
    @publication.captured_effect_dependency_body_cid(saved) != cid {
    return Err(InvalidResultPolicy)
  }
  Ok({ ..value, source_free_result_policy: Some(original), })
}

///|
/// The exact original admitted by the common Host owner. Its CID alone is not
/// sufficient for saved Effect dependency admission or restart.
pub fn client_compiled_run_source_free_result_policy_body(
  value : ClientCompiledRun,
) -> @publication.CapturedEffectDependencyBody? {
  value.source_free_result_policy
}

///|
/// Optional Evidence copies retain the actual Result policy, including Source
/// restrictions and unknown Model provenance. An input egress contract is not
/// an authority to publish the output. No new policy is issued here.
pub fn client_compiled_run_evaluation_policy_body(
  value : ClientCompiledRun,
) -> (String, String, String)? {
  guard client_compiled_run_infer_observation_policy(value) is Some(cid) else {
    return None
  }
  if value.source_free_result_policy is Some(body) &&
    @publication.captured_effect_dependency_body_cid(body) == cid {
    return Some(
      (
        @publication.captured_effect_dependency_body_kind(body),
        cid,
        @publication.captured_effect_dependency_body_json(body),
      ),
    )
  }
  let program = @strategy.graph_program(value.owner.graph)
  let count = @checked.unit_count(program)
  let mut remaining = 4096
  if count > remaining {
    return None
  }
  remaining -= count
  for unit in 0..<count {
    let publications = @checked.unit_publication_count(program, unit).unwrap_or(
      0,
    )
    if publications > remaining {
      return None
    }
    remaining -= publications
    for index in 0..<publications {
      guard @checked.unit_publication_at(program, unit, index)
        is Some(publication) else {
        return None
      }
      if @checked.publication_source_policy(publication) is Some(policy) &&
        policy.cid == cid {
        let writer = @encode.writer(16384, 1024, 20) catch { _ => return None }
        @checked.emit_publication_source_policy(policy, writer) catch {
          _ => return None
        }
        let wire = @encode.finish(writer) catch { _ => return None }
        if "sha256:" + @sha.hex(@utf8.encode(wire)) != cid {
          return None
        }
        return Some(("data_policy", cid, wire))
      }
    }
  }
  None
}

///|
/// Retrieve the exact checked selection retained by compilation. None means
/// a direct Result, not permission to accept a foreign or missing occurrence.
pub fn client_compiled_run_result_transformation(
  value : ClientCompiledRun,
  owner : PreparedClientProgram,
  result : Int,
) -> Result[ClientResultTransformation?, ClientCompiledRunIssue] {
  if !client_compiled_run_matches(value, owner) ||
    @strategy.graph_result_occurrence(owner.graph, result) is None {
    return Err(ForeignOwner)
  }
  let selections = match value.compilation {
    Values(compilation) => compilation.plan.transformations
    Tasks(compilation) => compilation.plan.plan.transformations
    Effects(_) => return Err(ForeignOwner)
  }
  for selection in selections {
    if client_result_transformation_matches(selection, owner, result) {
      return Ok(Some(selection))
    }
  }
  Ok(None)
}

///|
pub fn issue_client_values_compiled_run(
  owner : PreparedClientProgram,
  compilation : ClientValuesCompilation,
  execution_context_cid : String,
  host_policy_cid : String,
  expires_at : String,
) -> Result[ClientCompiledRun, ClientCompiledRunIssue] {
  if !physical_equal(owner, compilation.owner) {
    return Err(ForeignOwner)
  }
  issue_client_compiled_run(
    owner,
    Values(compilation),
    compilation.template,
    compilation.compiled_plan,
    execution_context_cid,
    host_policy_cid,
    expires_at,
  )
}

///|
pub fn issue_client_task_compiled_run(
  owner : PreparedClientProgram,
  compilation : ClientTaskCompilation,
  execution_context_cid : String,
  host_policy_cid : String,
  expires_at : String,
) -> Result[ClientCompiledRun, ClientCompiledRunIssue] {
  if !physical_equal(owner, compilation.owner) {
    return Err(ForeignOwner)
  }
  let issued = match
    issue_client_compiled_run(
      owner,
      Tasks(compilation),
      compilation.template,
      compilation.compiled_plan,
      execution_context_cid,
      host_policy_cid,
      expires_at,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // The Content Plan already binds the admitted input policy original. Retain
  // that same original for generation/recovery; a fresh CID or Model egress
  // policy cannot substitute for it after compilation.
  match compilation.serialization {
    Some(content) if @strategy.graph_source_free_inputs_complete(owner.graph) =>
      Ok({ ..issued, source_free_result_policy: Some(content.policy), })
    _ => Ok(issued)
  }
}

///|
/// The original checked Content component, including a mixed Model Plan.
pub fn client_compiled_run_serialization(
  value : ClientCompiledRun,
) -> ClientSerializationPlanGraph? {
  match value.compilation {
    Tasks(compilation) => compilation.serialization
    Effects(allowed) => allowed.compilation.compiled.serialization
    _ => None
  }
}

///|
/// The compiler-retained Content policy original for both source-free and
/// acquired generation. The latter is never labelled source-free evidence.
pub fn client_compiled_run_serialization_policy_body(
  value : ClientCompiledRun,
) -> @publication.CapturedEffectDependencyBody? {
  client_compiled_run_serialization(value).map(component => component.policy)
}

///|
fn issue_client_compiled_run(
  owner : PreparedClientProgram,
  compilation : ClientRunCompilation,
  template : @publication.RunEvidenceValue,
  plan : @publication.PublicationContract,
  execution_context_cid : String,
  host_policy_cid : String,
  expires_at : String,
) -> Result[ClientCompiledRun, ClientCompiledRunIssue] {
  let (prepared, authorization) = match
    issue_client_allowed_run_evidence(
      template, plan, execution_context_cid, host_policy_cid, expires_at,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Policy(issue))
  }
  let admission = match
    admit_prepared_client_run_publication(
      owner, template, prepared, authorization, plan,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  Ok({
    owner,
    compilation,
    template,
    plan,
    prepared,
    authorization,
    admission,
    source_free_result_policy: None,
    definition_binding: None,
  })
}

///|
pub fn client_compiled_run_template(
  value : ClientCompiledRun,
) -> @publication.RunEvidenceValue {
  value.template
}

///|
pub fn client_compiled_run_plan(
  value : ClientCompiledRun,
) -> @publication.PublicationContract {
  value.plan
}

///|
pub fn client_compiled_run_prepared(
  value : ClientCompiledRun,
) -> @publication.RunEvidenceValue {
  value.prepared
}

///|
pub fn client_compiled_run_authorization(
  value : ClientCompiledRun,
) -> @publication.RunEvidenceValue {
  value.authorization
}

///|
pub fn client_compiled_run_admission(
  value : ClientCompiledRun,
) -> @publication.RunPublicationAdmission {
  value.admission
}

///|
pub fn check_client_compiled_run_definition(
  value : ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[Unit, ClientCompiledRunIssue] {
  check_client_compiled_run_definition_owned(value, definition)
}

///|
fn check_client_compiled_run_definition_owned(
  value : ClientCompiledRun,
  definition : @publication.PublicationContract,
  bind? : (ClientCompiledRun, @publication.PublicationContract) -> Result[
    ClientCompiledRunDefinitionBinding?,
    ClientCompiledRunIssue,
  ] = bind_client_compiled_run_definition,
) -> Result[Unit, ClientCompiledRunIssue] {
  if value.definition_binding is Some(original) &&
    client_compiled_run_definition_facts_match(original, value, definition) {
    return Ok(())
  }
  match bind(value, definition) {
    Ok(Some(binding)) => {
      // Validating restored bytes must not replace the live issued original.
      if value.definition_binding is Some(original) &&
        client_compiled_run_definition_facts_match(
          original,
          value,
          original.definition,
        ) &&
        @publication.publication_contract_identity(original.definition) ==
        @publication.publication_contract_identity(definition) {
        return Ok(())
      }
      value.definition_binding = Some({
        owner: value.owner,
        compilation: value.compilation,
        template: value.template,
        plan: value.plan,
        prepared: value.prepared,
        authorization: value.authorization,
        admission: value.admission,
        definition,
        binding,
      })
      Ok(())
    }
    Ok(None) => Ok(())
    Err(issue) => Err(issue)
  }
}

///|
fn client_compiled_run_definition_facts_match(
  original : ClientCompiledRunDefinitionFacts,
  value : ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Bool {
  if !physical_equal(original.owner, value.owner) ||
    !physical_equal(original.template, value.template) ||
    !physical_equal(original.plan, value.plan) ||
    !physical_equal(original.prepared, value.prepared) ||
    !physical_equal(original.authorization, value.authorization) ||
    !physical_equal(original.admission, value.admission) ||
    !physical_equal(original.definition, definition) {
    return false
  }
  match (original.compilation, value.compilation, original.binding) {
    (Values(before), Values(after), ValuesDefinition(binding)) =>
      physical_equal(before, after) &&
      client_values_run_binding_definition_cid(binding) ==
      @publication.publication_contract_identity(definition)
    (Tasks(before), Tasks(after), TaskDefinition(binding)) =>
      physical_equal(before, after) &&
      client_task_run_binding_definition_cid(binding) ==
      @publication.publication_contract_identity(definition)
    _ => false
  }
}

///|
fn bind_client_compiled_run_definition(
  value : ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[ClientCompiledRunDefinitionBinding?, ClientCompiledRunIssue] {
  match value.compilation {
    Values(compilation) =>
      bind_source_free_client_values_run(
        value.owner,
        compilation,
        value.admission,
        definition,
      )
      .map(binding => Some(ValuesDefinition(binding)))
      .map_err(issue => ValuesBinding(issue))
    Tasks(compilation) =>
      bind_client_task_run(
        value.owner,
        compilation,
        value.admission,
        definition,
      )
      .map(binding => Some(TaskDefinition(binding)))
      .map_err(issue => TaskBinding(issue))
    Effects(allowed) =>
      bind_client_effect_compiled_run(
        allowed.compilation.owner,
        allowed,
        definition,
      )
      .map(_ => None)
      .map_err(issue => EffectBinding(issue))
  }
}

///|
pub fn issue_client_compiled_run_definition(
  value : ClientCompiledRun,
  scope_id : String,
  run_id : String,
  created_at : String,
  valid_until : String,
) -> Result[@publication.PublicationContract, ClientCompiledRunIssue] {
  let definition = match
    @publication.issue_run_definition(
      value.admission,
      scope_id,
      run_id,
      @publication.empty_initial_input_artifact_set_cid(),
      created_at,
      valid_until,
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  check_client_compiled_run_definition(value, definition).map(_ => definition)
}

///|
/// Restoring durable bytes is a real admission boundary, unlike forwarding
/// newly issued evidence inside one runtime. Never reconstruct a new Run here.
pub fn admit_client_compiled_run_definition(
  value : ClientCompiledRun,
  wire : String,
) -> Result[@publication.PublicationContract, ClientCompiledRunIssue] {
  let definition = match
    @publication.admit_publication_contract(
      "run_definition", wire, 100000, 10000, 100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Contract(issue))
  }
  check_client_compiled_run_definition(value, definition).map(_ => definition)
}

///|
pub fn issue_client_compiled_values_invocation(
  value : ClientCompiledRun,
  definition : @publication.PublicationContract,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  if check_client_compiled_run_definition(value, definition) is Err(_) {
    return Err(@publication.RunEvidenceReferenceMismatch("values_run"))
  }
  match value.compilation {
    Values(compilation) =>
      issue_client_values_source_free_invocation(
        compilation, data_policy_cid, max_wire_bytes, max_nodes, max_depth,
      )
    Tasks(_) | Effects(_) =>
      Err(@publication.RunEvidenceReferenceMismatch("values_run"))
  }
}

///|
pub fn issue_client_compiled_source_free_task_invocation(
  value : ClientCompiledRun,
  definition : @publication.PublicationContract,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  if check_client_compiled_run_definition(value, definition) is Err(_) {
    return Err(@publication.RunEvidenceReferenceMismatch("task_run"))
  }
  match value.compilation {
    Tasks(compilation) =>
      issue_client_task_source_free_invocation(
        compilation, data_policy_cid, max_wire_bytes, max_nodes, max_depth,
      )
    Values(_) | Effects(_) =>
      Err(@publication.RunEvidenceReferenceMismatch("task_run"))
  }
}

///|
/// Dispatch the already selected original source-free compilation through its
/// existing semantic issuer. The Host supplies no kind discriminator, and the
/// Values/Tasks issuers retain their original definition and input laws.
pub fn issue_client_compiled_source_free_invocation(
  value : ClientCompiledRun,
  definition : @publication.PublicationContract,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  match value.compilation {
    Values(_) =>
      issue_client_compiled_values_invocation(
        value, definition, data_policy_cid, max_wire_bytes, max_nodes, max_depth,
      )
    Tasks(_) =>
      issue_client_compiled_source_free_task_invocation(
        value, definition, data_policy_cid, max_wire_bytes, max_nodes, max_depth,
      )
    Effects(_) =>
      Err(@publication.RunEvidenceReferenceMismatch("source_free_run"))
  }
}

///|
pub fn issue_client_compiled_task_invocation(
  value : ClientCompiledRun,
  definition : @publication.PublicationContract,
  source_evidence_wire : String,
  input_logical_wire : String,
  source_ref : String,
  source_contract_cid : String,
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  match value.compilation {
    Tasks(compilation) =>
      issue_client_task_invocation(
        value.owner,
        compilation,
        value.admission,
        definition,
        source_evidence_wire,
        input_logical_wire,
        source_ref,
        source_contract_cid,
        authority_scope_cid,
        data_policy_cid,
        capture_started_at,
        capture_completed_at,
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
    Values(_) | Effects(_) =>
      Err(@publication.RunEvidenceReferenceMismatch("task_run"))
  }
}

///|
pub fn issue_client_compiled_multi_task_invocation(
  value : ClientCompiledRun,
  definition : @publication.PublicationContract,
  captures : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  requirements : Array[@planning.QueryRequirement],
  source_evidence_wires : Array[String],
  input_logical_wires : Array[String],
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  match value.compilation {
    Tasks(compilation) =>
      issue_client_multi_task_invocation(
        value.owner,
        compilation,
        value.admission,
        definition,
        captures,
        identities,
        requirements,
        source_evidence_wires,
        input_logical_wires,
        authority_scope_cid,
        data_policy_cid,
        capture_started_at,
        capture_completed_at,
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
    Values(_) | Effects(_) =>
      Err(@publication.RunEvidenceReferenceMismatch("task_run"))
  }
}

///|
/// The captured inventory and original typed observations are retained facts,
/// not serialized substitutes. Source coverage and live keyed custody remain
/// the same semantic boundary as external wire admission.
pub fn issue_client_compiled_captured_invocation(
  run : ClientCompiledRun,
  definition : @publication.PublicationContract,
  captures : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  requirements : Array[@planning.QueryRequirement],
  sources : Array[@publication.RunEvidenceValue],
  inputs : Array[@publication.RunEvidenceValue],
  keyed : ClientKeyedLookupObservation?,
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  guard run.compilation is Tasks(compilation) &&
    compilation.infers.is_empty() &&
    bind_client_task_run(run.owner, compilation, run.admission, definition)
    is Ok(_) else {
    return Err(@publication.RunEvidenceReferenceMismatch("task_run"))
  }
  if max_wire_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(@publication.RunEvidenceInvalidLimits)
  }
  for evidence in sources {
    if !@publication.run_evidence_value_fits(
        evidence, max_wire_bytes, max_nodes, max_depth,
      ) {
      return Err(@publication.RunEvidenceInvalidWire)
    }
  }
  for input in inputs {
    if !@publication.run_evidence_value_fits(
        input, max_wire_bytes, max_nodes, max_depth,
      ) {
      return Err(@publication.RunEvidenceInvalidWire)
    }
  }
  if keyed is Some(observation) {
    if captures.length() != 1 ||
      identities.length() != 1 ||
      requirements.length() != 1 ||
      sources.length() != 1 ||
      inputs.length() != 1 {
      return Err(@publication.RunEvidenceReferenceMismatch("source_coverage"))
    }
    return issue_client_compiled_keyed_task_invocation_original(
      run,
      definition,
      captures[0],
      identities[0],
      requirements[0],
      sources[0],
      inputs[0],
      observation,
      authority_scope_cid,
      data_policy_cid,
      capture_started_at,
      capture_completed_at,
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
  }
  if compilation.serialization is Some(_) {
    return Err(@publication.RunEvidenceReferenceMismatch("content_generation"))
  }
  let count = prepared_client_acquisition_count(run.owner)
  if (count != 1 && count != 2) ||
    (count == 1 && !client_single_direct_observation_covers_sources(run.owner)) {
    return Err(@publication.RunEvidenceReferenceMismatch("source_coverage"))
  }
  issue_client_multi_capture_observation(
    run.owner,
    client_task_compilation_template(compilation),
    captures,
    identities,
    requirements,
    OriginalSourceObservations(sources, inputs),
    count,
    authority_scope_cid,
    data_policy_cid,
    capture_started_at,
    capture_completed_at,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Exact immutable compiler inventory, without copying the retained Array.
/// A recovery consumer cannot bind a subset, reorder or equal graph copy.
pub fn client_compiled_run_infer_originals_match(
  value : ClientCompiledRun,
  plans : Array[ClientInferPlanGraph],
) -> Bool {
  let originals = match value.compilation {
    Values(_) => return false
    Tasks(compilation) => compilation.infers
    Effects(allowed) => allowed.compilation.compiled.infers
  }
  if plans.length() != originals.length() || plans.is_empty() {
    return false
  }
  for index in 0..<plans.length() {
    if !physical_equal(plans[index], originals[index]) {
      return false
    }
  }
  true
}

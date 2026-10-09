///|
/// Original Effect Run reconstructed from bounded materials. No acquisition,
/// Preview, approval or physical write occurs during this admission.
pub(all) struct ClientEffectRunMaterials {
  prepared : PreparedClientEffectComputation
  compilation : ClientEffectCompilation
  allowed : ClientEffectAllowedRun
  run_definition : @publication.PublicationContract
}

///|
pub(all) enum ClientEffectRunMaterialsIssue {
  Input(ClientValuesRunMaterialsIssue)
  Program(ClientEffectComputationIssue)
  Compilation(ClientEffectCompilationIssue)
  Binding(ClientEffectCompiledRunIssue)
  RunMismatch
}

///|
/// Project an already admitted Effect Run using the ordinary materials codec.
/// The exact input must be rechecked against the retained Effect owner first.
pub fn issue_client_effect_run_materials(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  environment : @checked.CheckEnvironment,
  environment_wire : String,
  program : String,
  parameters_wire : String?,
  effect_limits : ClientEffectComputationLimits,
) -> Result[String, ClientEffectRunMaterialsIssue] {
  let prepared = client_effect_compilation_owner(allowed.compilation)
  match bind_client_effect_compiled_run(prepared, allowed, definition) {
    Ok(_) => ()
    Err(issue) => return Err(Binding(issue))
  }
  let environment_cid = @checked.checking_environment_cid(environment)
  guard environment_cid ==
    prepared_client_effect_computation_environment_cid(prepared) &&
    @environment.read(@utf8.encode(environment_wire), environment_cid, {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 64,
      max_members: 256,
    })
    is Ok(_) else {
    return Err(Input(MaterialsEnvironment))
  }
  // Use the same bounded encoder and Parameter Values decoder as ordinary
  // Run materials. Neither operation adds a grant or refreshes the lifetime.
  let wire = match
    encode_client_run_materials_body(
      allowed.admission,
      definition,
      environment_cid,
      environment_wire,
      program,
      parameters_wire,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  let parameters = match
    decode_client_run_materials_parameters(parameters_wire) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  let checked = match
    prepare_client_effect_computation(
      program,
      Json,
      environment,
      parameters,
      [],
      effect_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Program(issue))
  }
  guard prepared_client_effect_identity(checked) ==
    prepared_client_effect_identity(prepared) else {
    return Err(RunMismatch)
  }
  Ok(wire)
}

///|
/// Recompile with the existing Effect Owner and admit the saved invocation
/// and authorization. The full original Run CID must match before any Site
/// start claim or physical I/O; current Site authority is a separate check.
pub fn admit_client_effect_run_materials(
  materials : String,
  expected_run_definition_cid : String,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
  manifests : ClientCompilationManifests,
  limits : ClientValuesRunMaterialsLimits,
  effect_limits : ClientEffectComputationLimits,
) -> Result[ClientEffectRunMaterials, ClientEffectRunMaterialsIssue] {
  let body = match
    read_client_run_materials_body(materials, expressions, operations) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  let prepared = match
    prepare_client_effect_computation(
      body.program,
      Json,
      body.environment,
      body.parameters,
      [],
      effect_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Program(issue))
  }
  let compilation = match
    issue_prepared_client_effect_compilation(
      prepared,
      manifests,
      limits.sequence,
      limits.max_sequence_steps,
      limits.max_sequence_work,
      limits.max_evidence_bytes,
      limits.max_evidence_nodes,
      limits.max_evidence_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Compilation(issue))
  }
  let evidence = fn(name : String, wire : String) {
    @publication.admit_run_evidence_value(
      name,
      wire,
      limits.max_evidence_bytes,
      limits.max_evidence_nodes,
      limits.max_evidence_depth,
    ).map_err(_ => ClientEffectRunMaterialsIssue::Input(MaterialsEvidence(name)))
  }
  let invocation = match evidence("prepared_invocation", body.prepared_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let authorization = match
    evidence("run_authorization", body.authorization_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let allowed = match
    admit_client_effect_allowed_run(compilation, invocation, authorization) {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  let run_definition = match
    issue_client_effect_run_definition(
      allowed,
      body.scope_id,
      body.run_id,
      body.created_at,
      body.valid_until,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  if @publication.publication_contract_identity(run_definition) !=
    expected_run_definition_cid {
    return Err(RunMismatch)
  }
  Ok({ prepared, compilation, allowed, run_definition, })
}

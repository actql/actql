///|
/// Original Effect Run reconstructed from bounded materials. No acquisition,
/// Preview, approval or physical write occurs during this admission.
pub(all) struct ClientEffectRunMaterials {
  normalization : ClientEffectNormalizationMaterialCustody?
  prepared : PreparedClientEffectComputation
  compilation : ClientEffectCompilation
  allowed : ClientEffectAllowedRun
  run_definition : @publication.PublicationContract
  request : ClientRequestIdentity?
}

///|
pub(all) enum ClientEffectRunMaterialsIssue {
  Input(ClientValuesRunMaterialsIssue)
  Program(ClientEffectComputationIssue)
  Compilation(ClientEffectCompilationIssue)
  Binding(ClientEffectCompiledRunIssue)
  RunMismatch
  Request(ClientRequestIdentityIssue)
  Normalization(ClientEffectNormalizationIssue)
  TargetSelection(ClientEffectUpdateTargetIssue)
}

///|
/// Inspect the transported original request without issuing a replacement.
/// Missing context remains missing: it cannot authorize Preview/approval.
/// The exact dispatch and checked Program must agree before Provider I/O.
pub fn client_effect_run_materials_request_for_dispatch(
  materials : ClientEffectRunMaterials,
  dispatch : @remote.DispatchRequest,
) -> Result[ClientRequestIdentity?, ClientRequestIdentityIssue] {
  guard materials.request is Some(request) else { return Ok(None) }
  if bind_client_effect_compiled_run(
      materials.prepared,
      materials.allowed,
      materials.run_definition,
    )
    is Err(_) ||
    !physical_equal(materials.compilation, materials.allowed.compilation) {
    return Err(IdentityMismatch)
  }
  if @remote.dispatch_request_task_scope(dispatch).0 !=
    @publication.publication_contract_identity(materials.run_definition) ||
    @remote.dispatch_request_journal_key(dispatch)[0] !=
    client_request_authority_scope_cid(request) ||
    client_request_input_cid(request) !=
    client_effect_original_input_intent_cid(materials.prepared) {
    return Err(IdentityMismatch)
  }
  match prepared_client_effect_request_scope(materials.prepared, request) {
    Ok(_) => Ok(Some(request))
    Err(issue) => Err(issue)
  }
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
  request? : ClientRequestIdentity? = None,
) -> Result[String, ClientEffectRunMaterialsIssue] {
  if allowed.compilation.normalization_profile is Some(_) {
    return Err(Normalization(MissingOriginalJournal))
  }
  let prepared = client_effect_compilation_owner(allowed.compilation)
  if prepared.target_selections is Some(_) && prepared.source_intent is None {
    return Err(TargetSelection(OriginalOwnerRequired))
  }
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
  if prepared.source_intent is Some(_) {
    guard request is Some(value) &&
      client_request_input_cid(value) ==
      client_effect_original_input_intent_cid(prepared) else {
      return Err(Request(IdentityMismatch))
    }
    let (original_program, original_parameters, _) = match
      client_effect_original_input_wires(prepared) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if program != original_program || parameters_wire != original_parameters {
      return Err(RunMismatch)
    }
    return issue_prepared_client_effect_run_materials(
      allowed,
      definition,
      request~,
    )
  }
  // Use the same bounded encoder and Parameter Values decoder as ordinary
  // Run materials. Neither operation adds a grant or refreshes the lifetime.
  let source_free_policy_input = match
    client_effect_original_source_free_policy_input(allowed.compilation) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let request_wire = match request {
    None => None
    Some(value) => {
      match prepared_client_effect_request_scope(prepared, value) {
        Ok(_) => ()
        Err(issue) => return Err(Request(issue))
      }
      if client_request_input_cid(value) !=
        source_free_caller_input_intent_cid() {
        return Err(Request(IdentityMismatch))
      }
      match client_request_identity_record_wire(value) {
        Ok(wire) => Some(wire)
        Err(issue) => return Err(Request(issue))
      }
    }
  }
  let infer_inputs_wire = match
    client_effect_original_infer_inputs(allowed.compilation) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let wire = match
    encode_client_run_materials_body(
      allowed.admission,
      definition,
      environment_cid,
      environment_wire,
      program,
      parameters_wire,
      request_wire~,
      source_free_policy_input~,
      infer_inputs_wire~,
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
  original_materials? : ClientEffectIssuedNormalizationMaterials? = None,
  expected_request? : ClientRequestIdentity? = None,
  original_source? : ClientSourcePreparation? = None,
  numeric_profile_cid? : String? = None,
  original_compilation? : ClientEffectCompilation? = None,
  before_compilation? : ((ClientEffectCompilationConstructionInput) -> Result[
    Unit,
    ClientEffectRunMaterialsIssue,
  ])? = None,
) -> Result[ClientEffectRunMaterials, ClientEffectRunMaterialsIssue] {
  let body = match
    read_client_run_materials_body(
      materials,
      expressions,
      operations,
      numeric_profile_cid~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  match original_materials {
    Some(issued) =>
      if body.normalization_wire is None ||
        !original_effect_materials_match(
          issued, materials, expected_run_definition_cid,
        ) {
        return Err(Normalization(UnverifiedOriginalMaterials))
      }
    None => ()
  }
  // A Request-owned restoration already paid for its original checker and
  // compiler. Reuse that nominal output; the independent Run/Request and the
  // complete canonical material comparison below bind every original input.
  // Wire-only callers retain their existing parser/check/compiler path.
  let prepared = match original_compilation {
    Some(original) => original.owner
    None =>
      match
        prepare_client_effect_computation(
          body.program,
          Json,
          body.environment,
          body.parameters,
          [],
          effect_limits,
        ) {
        Ok(value) => value
        Err(Candidate(@checked.MissingEffects)) if body.infer_inputs_wire
          is Some(_) =>
          return Err(Input(MaterialsEvidence("infer_execution_contracts")))
        Err(issue) => return Err(Program(issue))
      }
  }
  let prepared = match original_source {
    None => prepared
    Some(original) => {
      guard original.preparation is Effect(source_prepared) &&
        (
          original_compilation is None ||
          physical_equal(source_prepared, prepared)
        ) &&
        prepared_client_effect_identity(source_prepared) ==
        prepared_client_effect_identity(prepared) &&
        prepared_client_effect_computation_environment_cid(source_prepared) ==
        prepared_client_effect_computation_environment_cid(prepared) &&
        source_prepared.source_intent is Some(intent) &&
        physical_equal(intent, original.intent) else {
        return Err(Request(IdentityMismatch))
      }
      source_prepared
    }
  }
  let prepared = if original_source is Some(_) ||
    original_compilation is Some(_) {
    if prepared_client_effect_target_selections(prepared) !=
      body.target_selections_wire {
      return Err(TargetSelection(InvalidMaterials))
    }
    prepared
  } else {
    match body.target_selections_wire {
      None => prepared
      Some(wire) => {
        let selection = match
          admit_client_effect_target_selections(prepared.candidate, wire) {
          Ok(value) => value
          Err(issue) => return Err(TargetSelection(issue))
        }
        { ..prepared, target_selections: Some(selection), }
      }
    }
  }
  let infer = match original_compilation {
    Some(_) => None
    None =>
      match
        restore_client_effect_original_infer(
          prepared,
          body.infer_input,
          limits,
          native_read_profile=body.infer_native_read_profile,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
  }
  let infers = match (original_compilation, body.infer_inputs_wire) {
    (None, Some(wire)) =>
      match
        read_plural_client_infer_run_graphs(
          client_effect_program_view(prepared),
          wire,
          limits,
        ) {
        Ok(value) => value
        Err(_) =>
          return Err(Input(MaterialsEvidence("infer_execution_contracts")))
      }
    _ => []
  }
  let source_free_policy = match original_compilation {
    Some(_) => None
    None =>
      match
        restore_client_effect_original_source_free_policy(
          prepared,
          body.source_free_policy_input,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
  }
  // Profile selection is an audit of the restored checked owners, not a
  // catalog string or caller boolean. No custody escapes until saved
  // invocation/authorization and the independently selected Run/request bind it.
  let (normalization_profile, normalization_inventory, normalization_journal) = match
    body.normalization_wire {
    None => (None, None, None)
    Some(wire) => {
      let retained_inventory = match original_compilation {
        Some(original) => original.normalization_profile
        None => None
      }
      let inventory = match retained_inventory {
        Some(original) => {
          if !client_effect_normalization_inventory_matches(original, prepared) {
            return Err(Normalization(ForeignPreparation))
          }
          original
        }
        None =>
          match checked_client_effect_normalization_inventory(prepared) {
            Ok(value) => value
            Err(issue) => return Err(Normalization(issue))
          }
      }
      if original_materials is Some(issued) {
        match issued.normalization_profile {
          Some(_) =>
            if !same_client_effect_normalization_profile(
                Some(inventory),
                issued.normalization_profile,
              ) {
              return Err(Normalization(ForeignCatalog))
            }
          None =>
            if !(inventory is MappedCreate(_) &&
              issued.original.inventory is MappedCreate(_)) {
              return Err(Normalization(ForeignCatalog))
            }
        }
      }
      let journal = match
        admit_completion_free_material_journal(wire, inventory) {
        Ok(value) => value
        Err(issue) => return Err(Normalization(issue))
      }
      // Preserve original nominal mapped-create custody on a legacy Template.
      // Generic wire cannot acquire this exception, and update never uses it.
      if original_materials is Some(issued) &&
        issued.normalization_profile is None {
        (None, Some(inventory), Some(journal))
      } else {
        (Some(inventory), Some(inventory), Some(journal))
      }
    }
  }
  // The original parser/checker/Model preparation has already completed.
  // A caller may grow its SAME current construction holding here, before
  // the single artifact compiler. Failure retains that caller's responsibility.
  // Existing wire-only/default and already-compiled entrances stay unchanged.
  if original_compilation is None && before_compilation is Some(prepare) {
    let components = match infer {
      Some(component) => [component]
      None => infers
    }
    match
      prepare({
        owner: prepared,
        components,
        normalization: normalization_profile,
      }) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let compilation = match original_compilation {
    Some(original) => {
      if !physical_equal(original.owner, prepared) ||
        !same_client_effect_normalization_profile(
          normalization_profile,
          original.normalization_profile,
        ) {
        return Err(Binding(ForeignCompilation))
      }
      original
    }
    None =>
      match
        issue_client_effect_compilation_internal(
          prepared,
          manifests,
          limits.sequence,
          limits.max_sequence_steps,
          limits.max_sequence_work,
          limits.max_evidence_bytes,
          limits.max_evidence_nodes,
          limits.max_evidence_depth,
          normalization_profile,
          infer~,
          infers~,
          source_free_policy~,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Compilation(issue))
      }
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
    Err(issue) => {
      if normalization_profile is Some(_) && original_materials is None {
        return Err(Normalization(UnverifiedOriginalMaterials))
      }
      return Err(Binding(issue))
    }
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
  let request = match body.request_wire {
    None => None
    Some(wire) => {
      let value = match admit_client_request_identity_record_wire(wire) {
        Ok(value) => value
        Err(issue) => return Err(Request(issue))
      }
      match prepared_client_effect_request_scope(prepared, value) {
        Ok(_) => ()
        Err(issue) => return Err(Request(issue))
      }
      if client_request_input_cid(value) !=
        client_effect_original_input_intent_cid(prepared) {
        return Err(Request(IdentityMismatch))
      }
      Some(value)
    }
  }
  if (original_source is Some(_) || original_compilation is Some(_)) &&
    (request is None || expected_request is None || request != expected_request) {
    return Err(Request(IdentityMismatch))
  }
  // The original Run CID binds the compiler profile, not a logical caller
  // request. Wire-only restoration also needs the original request selected
  // independently by the trusted durable Host/journal context. Do not derive
  // that expected identity from these candidate material bytes.
  if source_free_policy is Some(_) &&
    original_materials is None &&
    (request is None || expected_request is None) {
    return Err(Request(IdentityMismatch))
  }
  if (
      normalization_profile is Some(_) ||
      prepared.target_selections is Some(_) ||
      source_free_policy is Some(_)
    ) &&
    original_materials is None &&
    request != expected_request {
    return Err(Request(IdentityMismatch))
  }
  if normalization_profile is Some(_) ||
    prepared.target_selections is Some(_) ||
    infer is Some(_) ||
    source_free_policy is Some(_) ||
    original_source is Some(_) ||
    original_compilation is Some(_) {
    let canonical = match
      encode_prepared_client_effect_materials(
        allowed,
        run_definition,
        body.request_wire,
        body.normalization_wire,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if canonical != materials {
      if original_compilation is Some(_) {
        return Err(RunMismatch)
      }
      if prepared.target_selections is Some(_) {
        return Err(TargetSelection(InvalidMaterials))
      }
      return Err(Normalization(UnverifiedOriginalMaterials))
    }
  }
  // Reusing an immutable compiler must not displace that Owner's already
  // retained material custody. Matching transport bytes reuse its original
  // journal/handle; equal Program identity alone cannot replace a live tuple.
  if original_compilation is Some(_) &&
    prepared.normalization_custody is Some(custody) {
    let material_cid = match original_materials {
      Some(issued) => original_effect_materials_cid(issued)
      None => "sha256:" + @sha.hex(@utf8.encode(materials))
    }
    if !physical_equal(custody.compilation, compilation) ||
      custody.run_cid != expected_run_definition_cid ||
      custody.request != request ||
      custody.materials_cid != material_cid ||
      body.normalization_wire != Some(custody.journal_wire) {
      return Err(Normalization(ForeignMaterials))
    }
    return Ok({
      normalization: Some(custody),
      prepared,
      compilation,
      allowed,
      run_definition,
      request,
    })
  }
  let normalization = match body.normalization_wire {
    None => None
    Some(wire) => {
      let custody : ClientEffectNormalizationMaterialCustody = {
        issued: original_materials,
        compilation,
        run_cid: expected_run_definition_cid,
        prepared_cid: @publication.run_evidence_value_identity(allowed.prepared),
        authorization_cid: @publication.run_evidence_value_identity(
          allowed.authorization,
        ),
        request,
        journal_wire: wire,
        journal: normalization_journal.unwrap(),
        inventory: normalization_inventory.unwrap(),
        materials_cid: match original_materials {
          Some(issued) => original_effect_materials_cid(issued)
          None => "sha256:" + @sha.hex(@utf8.encode(materials))
        },
      }
      prepared.normalization_custody = Some(custody)
      Some(custody)
    }
  }
  Ok({ normalization, prepared, compilation, allowed, run_definition, request, })
}

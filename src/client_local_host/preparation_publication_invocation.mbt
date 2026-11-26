///|
/// Issue and bind the invocation as one fixed transition. No caller-supplied
/// invocation or serialized CID can substitute for this exact per-Run result.
/// The semantic issuer is unchanged; selected BND remain restrictions only.
pub fn issue_program_publication_invocation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  ClientClosedValuesPreparationIssue,
] {
  match
    begin_program_publication_invocation(owner, prepared, compiled, definition) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    @publication_host.issue_client_compiled_source_free_invocation(
      compiled, definition, data_policy_cid, max_wire_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => Err(PublicationInvocation(issue))
    Ok((evidence, invocation)) => {
      owner.publication_definition = Some(definition)
      owner.publication_invocation = Some(invocation)
      Ok((evidence, invocation))
    }
  }
}

///|
fn begin_program_publication_invocation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[Unit, ClientClosedValuesPreparationIssue] {
  match managed_run_publication_body(owner, prepared) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !@publication_host.client_compiled_run_matches(compiled, prepared) ||
    !@publication_host.client_compiled_run_has_original_definition(
      compiled, definition,
    ) {
    return Err(ForeignOriginal)
  }
  if owner.publication_invocation_started {
    return Err(WrongPhase)
  }
  owner.publication_invocation_started = true
  Ok(())
}

///|
/// Captured Whole File evidence from the same adopted Run. The caller must
/// retain the original publication issuer for the duration of this binding.
pub(all) struct ClientWholeModelPublicationSources {
  captures : Array[@row_source_host.RowSourceCapture]
  evidence : Array[@publication.RunEvidenceValue]
  started_at : String
  completed_at : String
}

///|
/// Adopt the original Model issuer on the same captured Run. Whole File
/// publication also checks each actual capture against its installed plan.
pub fn bind_program_model_publication_invocation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  captured : @strategy.CapturedDAG,
  observation : @publication.RunEvidenceValue,
  invocation : @publication.PublicationContract,
  inputs : Array[String],
  policy_cid : String,
  whole_sources? : ClientWholeModelPublicationSources? = None,
) -> Result[Unit, ClientClosedValuesPreparationIssue] {
  guard owner.source_free_captured is Some(original) &&
    physical_equal(original, captured) &&
    installed_managed_run_compilation_original(owner, prepared)
    is Some(@publication_host.Tasks(compilation)) &&
    @publication_host.client_compiled_run_matches_tasks(
      compiled, prepared, compilation,
    ) &&
    compilation.serialization is None &&
    !compilation.infers.is_empty() &&
    inputs.length() == compilation.infers.length() &&
    @publication_host.client_compiled_run_infer_observation_policy(compiled) ==
    Some(policy_cid) else {
    return Err(ForeignOriginal)
  }
  let template = @publication_host.client_compiled_run_template(compiled)
  let matches = match (owner.captured_preparation, whole_sources) {
    (None, None) =>
      !@publication_host.prepared_client_has_checked_sources(prepared) &&
      @publication.model_invocation_matches(
        template, observation, invocation, inputs, policy_cid,
      )
    (Some(plan), Some(sources)) => {
      guard physical_equal(plan.prepared, prepared) &&
        physical_equal(plan.request, owner.request) &&
        !plan.whole_sources.is_empty() &&
        sources.captures.length() == plan.whole_sources.length() &&
        sources.evidence.length() == sources.captures.length() else {
        return Err(ForeignOriginal)
      }
      for index, capture in sources.captures {
        if !whole_source_publication_capture_matches(
            owner,
            plan,
            capture,
            index~,
          ) {
          return Err(ForeignOriginal)
        }
      }
      @publication.model_invocation_matches(
        template,
        observation,
        invocation,
        inputs,
        policy_cid,
        source_evidence=sources.evidence,
        capture_interval=Some((sources.started_at, sources.completed_at)),
      )
    }
    _ => false
  }
  if !matches {
    return Err(ForeignOriginal)
  }
  match
    begin_program_publication_invocation(owner, prepared, compiled, definition) {
    Err(issue) => Err(issue)
    Ok(_) => {
      owner.publication_definition = Some(definition)
      owner.publication_invocation = Some(invocation)
      Ok(())
    }
  }
}

///|
/// Retire the same semantic aliases after the Native publication child is
/// done. The original Model still owns the issuer and its independent cleanup.
pub fn retire_program_model_publication_invocation(
  owner : ClientInstalledManagedRun,
  invocation : @publication.PublicationContract,
) -> Bool {
  guard owner.publication_invocation is Some(original) &&
    physical_equal(original, invocation) else {
    return false
  }
  clear_managed_run_publication(owner)
  true
}

///|
/// Bind the original captured inventory to the same adopted Run exactly once.
/// Immutable evidence DATA cannot replace the checked capture/Plan lineage.
pub fn issue_program_captured_publication_invocation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  captures : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  requirements : Array[@planning.QueryRequirement],
  sources : Array[@publication.RunEvidenceValue],
  inputs : Array[@publication.RunEvidenceValue],
  keyed : @publication_host.ClientKeyedLookupObservation?,
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  ClientClosedValuesPreparationIssue,
] {
  guard owner.captured_preparation is Some(plan) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, owner.request) else {
    return Err(ForeignOriginal)
  }
  match
    begin_program_publication_invocation(owner, prepared, compiled, definition) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    @publication_host.issue_client_compiled_captured_invocation(
      compiled, definition, captures, identities, requirements, sources, inputs,
      keyed, authority_scope_cid, data_policy_cid, capture_started_at, capture_completed_at,
      max_wire_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => Err(PublicationInvocation(issue))
    Ok((evidence, invocation)) => {
      owner.publication_definition = Some(definition)
      owner.publication_invocation = Some(invocation)
      Ok((evidence, invocation))
    }
  }
}

///|
/// Issue only the terminal generation of this adopted Request/Run. Retain
/// the single publication transition before the generation's availability
/// callback may reenter. Neither caller-authored invocation DATA nor a
/// released prefix can become publication evidence.
pub fn issue_program_terminal_serialization_invocation(
  owner : ClientInstalledManagedRun,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  generation : @publication_host.ClientSerializationGeneration,
  demand : ClientSerializationOutputDemand,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (
    @publication.RunEvidenceValue,
    @publication.PublicationContract,
    @publication.BoundContentGeneration,
  ),
  ClientClosedValuesPreparationIssue,
] {
  guard owner.content is SerializationContent(selected) &&
    selected.terminal_output is Some(original_demand) &&
    physical_equal(original_demand, demand) &&
    demand.result_limits is Some(_) &&
    physical_equal(selected.request, request) &&
    physical_equal(owner.request, request) &&
    physical_equal(selected._observed_compiled, compiled) &&
    physical_equal(selected._observed_definition, definition) &&
    owner.preparation is Some(PreparationContentManaged(_, prepared)) &&
    physical_equal(prepared, selected.prepared) &&
    owner.serialization_prefix is Some(prefix) &&
    !prefix.released else {
    return Err(ForeignOriginal)
  }
  if owner.publication_invocation_started {
    return Err(WrongPhase)
  }
  owner.publication_invocation_started = true
  if require_installed_managed_run(owner) is Err(_) {
    return Err(ForeignOriginal)
  }
  guard @publication_host.client_serialization_generation_capture_for(
      generation, compiled, definition,
    )
    is Some(content) else {
    return Err(ForeignOriginal)
  }
  let issued = @publication_host.issue_client_serialization_invocation(
    compiled, definition, generation, max_wire_bytes, max_nodes, max_depth,
  )
  let (observation, invocation) = match issued {
    Ok(value) => value
    Err(issue) => return Err(PublicationInvocation(issue))
  }
  guard owner.content is SerializationContent(original) &&
    physical_equal(original, selected) &&
    owner.serialization_prefix is Some(original_prefix) &&
    physical_equal(original_prefix, prefix) &&
    !prefix.released &&
    require_installed_managed_run(owner) is Ok(_) &&
    !prefix.released else {
    return Err(ForeignOriginal)
  }
  owner.publication_definition = Some(definition)
  owner.publication_invocation = Some(invocation)
  Ok((observation, invocation, content))
}

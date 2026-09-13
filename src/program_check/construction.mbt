///|
pub suberror ConstructionFailure {
  InvalidLimits
  BudgetExceeded
  Operations(@context.ProgramOperationResolutionIssue)
  Values(@context.ValuesPublicationIssue)
  Joins(@context.JoinRequirementIssue)
  Incoming(@context.IncomingIssue)
  Links(@context.IncomingLinksIssue)
  Requirements(@context.StageRequirementIssue)
  UnresolvedOperation(@context.OperationRequirementSite)
  IncompleteInventory(Int)
  Gates(@context.ProgramIncomingGatesIssue)
  Contracts(@context.CoreContractIssue)
}

///|
// Private orchestration phase, not a successful CheckedProgram. In particular,
// collecting core contracts does not certify complete semantic role selection.
// The formal constructor must retain these exact owners through its final audit.
fn prepare_owned_closure(
  identity : @context.ProgramSourceIdentity,
  budget : IdentityBudget,
) -> (
  @context.StageRequirementClosure,
  @context.ProgramIncomingGates,
  @context.CoreContractInventory,
) raise ConstructionFailure {
  if budget.work < 0 || budget.bytes < 0 || budget.nodes < 0 || budget.depth < 0 {
    raise InvalidLimits
  }
  let (prefix, _, _) = @context.program_identity_usage(identity)
  if prefix > budget.work {
    raise BudgetExceeded
  }
  let ceiling = budget.work
  let initial_resolutions = match
    @context.resolve_program_operations(identity, {
      max_work: ceiling,
      max_requirements: ceiling - prefix,
      max_resolutions: ceiling - prefix,
    }) {
    Ok(v) => v
    Err(e) => raise Operations(e)
  }
  let values_resolutions = match
    @context.resolve_program_values_resources(initial_resolutions, {
      max_work: ceiling,
      max_values: ceiling - prefix,
      max_payload_bytes: budget.bytes,
      max_payload_nodes: budget.nodes,
      max_depth: budget.depth,
      metadata: {
        max_bytes: budget.bytes,
        max_nodes: budget.nodes,
        max_depth: budget.depth,
        max_candidates: 2,
      },
    }) {
    Ok(v) => v
    Err(e) => raise Values(e)
  }
  let resolutions = match
    @context.link_program_join_requirements(
      values_resolutions,
      ceiling,
      ceiling - prefix,
    ) {
    Ok(v) => v
    Err(e) => raise Joins(e)
  }
  let resolution_work = @context.operation_resolution_work(resolutions)
  let (values_bytes, values_nodes) = @context.operation_resolution_values_usage(
    resolutions,
  )
  let incoming = match
    @context.collect_program_incoming(identity, {
      max_work: prefix + (ceiling - resolution_work),
      max_name_units: ceiling - resolution_work,
      max_requirements: ceiling - resolution_work,
    }) {
    Ok(v) => v
    Err(e) => raise Incoming(e)
  }
  let owner = match
    @context.link_resolved_program_incoming(resolutions, incoming, {
      max_work: ceiling,
      max_name_units: ceiling,
      max_requirements: ceiling,
    }) {
    Ok(v) => v
    Err(e) => raise Links(e)
  }
  let owner_work = @context.incoming_links_work(owner)
  let requirements = match
    @context.close_stage_requirements(owner, {
      max_work: ceiling,
      max_requirements: ceiling - owner_work,
      max_local_inputs: ceiling - owner_work,
    }) {
    Ok(v) => v
    Err(
      @context.StageRequirementIssue::Operations(
        @context.OperationClosureIssue::IncompleteResolution(index)
      )
    ) =>
      match
        @context.operation_requirements_at(
          @context.operation_resolution_requirements(resolutions),
          index,
        ) {
        Some(site) => raise UnresolvedOperation(site)
        None => raise IncompleteInventory(index)
      }
    Err(e) => raise Requirements(e)
  }
  let (requirement_work, _) = @context.stage_requirement_usage(requirements)
  let gates = match
    @context.prepare_program_incoming_gates(owner, {
      max_work: owner_work + (ceiling - requirement_work),
      max_bytes: budget.bytes - values_bytes,
      max_nodes: budget.nodes - values_nodes,
      max_depth: budget.depth,
    }) {
    Ok(v) => v
    Err(e) => raise Gates(e)
  }
  let (gate_work, gate_bytes, gate_nodes) = @context.program_incoming_gates_usage(
    gates,
  )
  let used = requirement_work + (gate_work - owner_work)
  let profiles = @context.operation_profile_links_calendar(
    @context.operation_resolution_profiles(resolutions),
  )
  let profile_work = @context.operation_calendar_work(profiles)
  let contracts = match
    @context.collect_core_contracts(
      identity,
      {
        max_work: profile_work + (ceiling - used),
        max_roots: ceiling - used,
        max_bodies: ceiling - used,
        max_edges: ceiling - used,
      },
      profile_checks=Some(profiles),
      hash_limits=Some({
        max_bytes: budget.bytes - values_bytes - gate_bytes,
        max_nodes: budget.nodes - values_nodes - gate_nodes,
        max_depth: budget.depth,
      }),
    ) {
    Ok(v) => v
    Err(e) => raise Contracts(e)
  }
  let (contract_work, _) = @context.core_contract_usage(contracts)
  let (contract_bytes, contract_nodes) = @context.core_contract_hash_usage(
    contracts,
  )
  // Commit aggregate usage only after every branch succeeds. Each branch counts
  // its shared owner internally; only its nonshared suffix is charged here.
  budget.work = ceiling - used - (contract_work - profile_work)
  budget.bytes -= values_bytes + gate_bytes + contract_bytes
  budget.nodes -= values_nodes + gate_nodes + contract_nodes
  (requirements, gates, contracts)
}

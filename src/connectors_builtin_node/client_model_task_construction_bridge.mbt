///|
/// Pure Model constructor quantities. The existing Host service reserves them
/// on its SAME initialization owner before calling the original Task methods.
/// No Ledger, raw Resource, Task issuer or caller permission is exported.
#export_name("clientProgramPublicModelTaskReadConstructionCapacity")
pub fn client_program_public_model_task_read_construction_capacity(
  wire : String,
  format : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_members : Int,
  contract_nodes : Int,
  contract_depth : Int,
  contract_text : Int,
  max_work : Int,
) -> @execution.ExecutionCapacity? {
  guard @check_environment.public_model_task_document_construction_extent(
      wire,
      format,
      {
        bodies: { max_bytes, max_nodes, max_depth, max_members, },
        contracts: {
          max_nodes: contract_nodes,
          max_depth: contract_depth,
          max_text_bytes: contract_text,
        },
        max_work,
      },
    )
    is Some(peak) else {
    return None
  }
  // Until its actual return, constructor output and scratch remain one
  // conservative live peak. Success then selects its original retained data.
  client_check_environment_capacity(peak, peak)
}

///|
#export_name("clientProgramPublicModelTaskRetainedCapacity")
pub fn client_program_public_model_task_retained_capacity(
  original : @check_environment.PublicModelTaskDeclaration,
) -> @execution.ExecutionCapacity? {
  guard @check_environment.public_model_task_declaration_retained_extent(
      original,
    )
    is Some(retained) else {
    return None
  }
  client_check_environment_capacity(retained, retained)
}

///|
#export_name("clientProgramPublicModelTaskNormalizationConstructionCapacity")
pub fn client_program_public_model_task_normalization_construction_capacity(
  original : @check_environment.PublicModelTaskDeclaration,
  defaults : @publication_host.ClientModelProviderDefaults,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_members : Int,
  contract_nodes : Int,
  contract_depth : Int,
  contract_text : Int,
  max_work : Int,
) -> @execution.ExecutionCapacity? {
  guard @check_environment.public_model_task_normalization_construction_extent(
      original,
      {
        bodies: { max_bytes, max_nodes, max_depth, max_members, },
        contracts: {
          max_nodes: contract_nodes,
          max_depth: contract_depth,
          max_text_bytes: contract_text,
        },
        max_work,
      },
    )
    is Some(peak) else {
    return None
  }
  let (resolution, _) = @publication_host.client_model_provider_defaults_resolution_extents(
    defaults,
    @check_environment.public_model_task_declaration_limits(original).1,
  )
  let combined = client_check_environment_add_extent(peak, resolution)
  client_check_environment_capacity(combined, combined)
}

///|
#export_name("clientProgramPublicModelTaskNormalizedRetainedCapacity")
pub fn client_program_public_model_task_normalized_retained_capacity(
  original : @check_environment.NormalizedPublicModelTask,
) -> @execution.ExecutionCapacity? {
  let retained = @check_environment.normalized_public_model_task_retained_extent(
    original,
  )
  client_check_environment_capacity(retained, retained)
}

///|
/// Incremental SAME-owner quantity; no earlier Task/provider inventory is
/// traversed. Missing means first prefix only, never an absent current quote.
#export_name("clientProgramAccumulateModelTaskConstructionCapacity")
pub fn client_program_accumulate_model_task_construction_capacity(
  previous : @execution.ExecutionCapacity?,
  current : @execution.ExecutionCapacity?,
) -> Result[@execution.ExecutionCapacity?, @resources.PreparationCapacityIssue] {
  guard current is Some(current) else { return Err(@resources.InvalidExtent) }
  match previous {
    None => Ok(Some(current))
    Some(previous) =>
      match @execution.add_execution_capacity(previous, current) {
        Some(sum) => Ok(Some(sum))
        None => Err(@resources.InvalidExtent)
      }
  }
}

///|
#export_name("clientProgramModelProviderDefaultsReadConstructionCapacity")
pub fn client_program_model_provider_defaults_read_construction_capacity(
  provider : String,
  installation : String,
  contract : String,
  configuration : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_members : Int,
) -> @execution.ExecutionCapacity? {
  guard @publication_host.client_model_provider_defaults_construction_extent(
      provider,
      installation,
      contract,
      configuration,
      { max_bytes, max_nodes, max_depth, max_members, },
    )
    is Some(peak) else {
    return None
  }
  client_check_environment_capacity(peak, peak)
}

///|
#export_name("clientProgramModelProviderDefaultsRetainedCapacity")
pub fn client_program_model_provider_defaults_retained_capacity(
  original : @publication_host.ClientModelProviderDefaults,
) -> @execution.ExecutionCapacity? {
  guard @publication_host.client_model_provider_defaults_retained_extent(
      original,
    )
    is Some(retained) else {
    return None
  }
  client_check_environment_capacity(retained, retained)
}

///|
#export_name("clientProgramModelProviderDefaultsResolutionCapacities")
pub fn client_program_model_provider_defaults_resolution_capacities(
  original : @publication_host.ClientModelProviderDefaults,
  tokens : Int64?,
) -> Array[@execution.ExecutionCapacity?] {
  let (peak, retained) = @publication_host.client_model_provider_defaults_resolution_extents(
    original, tokens,
  )
  [
    client_check_environment_capacity(peak, peak),
    client_check_environment_capacity(retained, retained),
  ]
}

///|
/// Fixed borrowed selection/tuple and loop controls. Registry strings stay
/// with the original registry; traversal work retains its independent bound.
#export_name("clientProgramProjectModelTaskSelectionConstructionCapacity")
pub fn client_program_project_model_task_selection_construction_capacity(
  registry : @publication_host.ClientProjectModelRegistry,
) -> @execution.ExecutionCapacity? {
  let count = registry.task_count().to_int64() +
    registry.provider_count().to_int64()
  let peak : @check_environment.RegistryConstructionExtent = {
    record_headers: 16L + 3L * count,
    reference_slots: 28L + 6L * count,
    scalar_words: 24L + 3L * count,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  client_check_environment_capacity(peak, peak)
}

///|
#export_name("clientProgramPublicModelTaskEnvironmentLimits")
pub fn client_program_public_model_task_environment_limits(
  bytes : Int,
  nodes : Int,
  depth : Int,
  members : Int,
  existing_tasks : Int,
  tasks : Array[@check_environment.NormalizedPublicModelTask],
) -> Array[Int]? {
  guard @check_environment.public_model_task_environment_limits(
      bytes, nodes, depth, members, existing_tasks, tasks,
    )
    is Some(limits) else {
    return None
  }
  Some([
    limits.bodies.max_bytes,
    limits.bodies.max_nodes,
    limits.bodies.max_depth,
    limits.bodies.max_members,
    limits.contracts.max_nodes,
    limits.contracts.max_depth,
    limits.contracts.max_text_bytes,
    limits.max_work,
  ])
}

///|
#export_name("clientProgramPublicModelTaskEnvironmentConstructionCapacity")
pub fn client_program_public_model_task_environment_construction_capacity(
  bytes : Int,
  nodes : Int,
  depth : Int,
  members : Int,
  existing_tasks : Int,
  tasks : Array[@check_environment.NormalizedPublicModelTask],
) -> @execution.ExecutionCapacity? {
  guard @check_environment.public_model_task_environment_construction_extent(
      bytes, nodes, depth, members, existing_tasks, tasks,
    )
    is Some(peak) else {
    return None
  }
  client_check_environment_capacity(peak, peak)
}

///|
#export_name("clientProgramProjectModelTaskSelectionRetainedCapacity")
pub fn client_program_project_model_task_selection_retained_capacity() -> @execution.ExecutionCapacity? {
  // Core selection, pair and JS borrowed selection record; no registry tree copy.
  let retained : @check_environment.RegistryConstructionExtent = {
    record_headers: 5L,
    reference_slots: 12L,
    scalar_words: 3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  client_check_environment_capacity(retained, retained)
}

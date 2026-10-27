///|
pub suberror EnvironmentFailure {
  BudgetExceeded
  Registry(@environment.ContractIssue)
  Catalog(@environment.CatalogIssue)
  References(@environment.ReferenceIssue)
  Policies(@environment.DataPolicyIssue)
  Values(@environment.ValueContractIssue)
  Shapes(@environment.SourceViewShapeIssue)
  Modes(@environment.SourceReadModeIssue)
  Carriers(@environment.CarrierSchemaIssue)
  Requests(@environment.SourceRequestIssue)
  ForeignPreparedCatalog
}

///|
fn environment_begin(b : IdentityBudget) -> Unit raise EnvironmentFailure {
  if b.work <= 0 || b.bytes < 0 || b.nodes < 0 || b.depth < 0 {
    raise BudgetExceeded
  }
  b.work -= 1
}

///|
// Body readers expose three separate bounded dimensions, not a shared work
// counter. Reserve the same per-axis allowance and bill three times the largest
// observed dimension. This conservative metric permits exact replay without
// allowing any one reader to exceed the remaining aggregate allowance.
fn environment_body_usage(
  b : IdentityBudget,
  bytes : Int,
  nodes : Int,
  entries : Int,
) -> Unit raise EnvironmentFailure {
  let peak = Int::max(bytes, Int::max(nodes, entries))
  if peak > b.work / 3 || bytes > b.bytes || nodes > b.nodes {
    raise BudgetExceeded
  }
  b.work -= peak * 3
  b.bytes -= bytes
  b.nodes -= nodes
}

///|
fn environment_body_caps(b : IdentityBudget) -> @environment.Limits {
  {
    max_bytes: Int::min(b.bytes, b.work / 3),
    max_nodes: Int::min(b.nodes, b.work / 3),
    max_depth: b.depth,
    max_members: b.work / 3,
  }
}

///|
fn environment_contents_caps(
  b : IdentityBudget,
  limits : @environment.Limits?,
) -> @environment.Limits {
  let caps = environment_body_caps(b)
  match limits {
    None => caps
    Some(limits) =>
      {
        max_bytes: Int::min(caps.max_bytes, limits.max_bytes),
        max_nodes: Int::min(caps.max_nodes, limits.max_nodes),
        max_depth: Int::min(caps.max_depth, limits.max_depth),
        max_members: Int::min(caps.max_members, limits.max_members),
      }
  }
}

///|
fn environment_work(
  b : IdentityBudget,
  work : Int,
) -> Unit raise EnvironmentFailure {
  if work < 0 || work > b.work {
    raise BudgetExceeded
  }
  b.work -= work
}

///|
// Admit the interpretation chain internally from the integrity-checked wire
// Environment. This does not establish issuer authority or backend support.
fn prepare_environment(
  environment : @environment.WireEnvironment,
  budget : IdentityBudget,
) -> (@environment.SourceRequestContracts, @environment.CatalogReferences) raise EnvironmentFailure {
  prepare_environment_with_contents_limits(environment, budget, None)
}

///|
fn prepare_environment_with_contents_limits(
  environment : @environment.WireEnvironment,
  budget : IdentityBudget,
  contents_limits : @environment.Limits?,
) -> (@environment.SourceRequestContracts, @environment.CatalogReferences) raise EnvironmentFailure {
  let b = IdentityBudget::{
    work: budget.work,
    bytes: budget.bytes,
    nodes: budget.nodes,
    depth: budget.depth,
  }
  let registry = prepare_environment_registry(environment, b, contents_limits)
  finish_environment_registry(registry, b, budget, contents_limits)
}

///|
fn prepare_environment_registry(
  environment : @environment.WireEnvironment,
  b : IdentityBudget,
  contents_limits : @environment.Limits?,
) -> @environment.ContractRegistry raise EnvironmentFailure {
  environment_begin(b)
  let registry = match
    @environment.check_contract_registry(
      environment,
      environment_contents_caps(b, contents_limits),
    ) {
    Ok(v) => v
    Err(e) => raise Registry(e)
  }
  let (bytes, nodes, entries) = @environment.contract_registry_usage(registry)
  environment_body_usage(b, bytes, nodes, entries)
  registry
}

///|
fn finish_environment_registry(
  registry : @environment.ContractRegistry,
  b : IdentityBudget,
  budget : IdentityBudget,
  contents_limits : @environment.Limits?,
) -> (@environment.SourceRequestContracts, @environment.CatalogReferences) raise EnvironmentFailure {
  let contents = prepare_environment_contents(registry, b, contents_limits)
  finish_environment_contents(contents, b, budget)
}

///|
fn prepare_environment_contents(
  registry : @environment.ContractRegistry,
  b : IdentityBudget,
  contents_limits : @environment.Limits?,
) -> @environment.CatalogContents raise EnvironmentFailure {
  environment_begin(b)
  let contents = match
    @environment.check_catalog_contents(
      registry,
      environment_contents_caps(b, contents_limits),
    ) {
    Ok(v) => v
    Err(e) => raise Catalog(e)
  }
  let (bytes, nodes, entries) = @environment.catalog_usage(contents)
  environment_body_usage(b, bytes, nodes, entries)
  contents
}

///|
fn finish_environment_contents(
  contents : @environment.CatalogContents,
  b : IdentityBudget,
  budget : IdentityBudget,
) -> (@environment.SourceRequestContracts, @environment.CatalogReferences) raise EnvironmentFailure {
  let references = prepare_environment_references(contents, b)
  finish_environment_references(references, b, budget)
}

///|
fn prepare_environment_references(
  contents : @environment.CatalogContents,
  b : IdentityBudget,
) -> @environment.CatalogReferences raise EnvironmentFailure {
  environment_begin(b)
  let (result, spent) = @environment.observe_catalog_references(contents, {
    max_work: b.work,
    max_references: b.work,
  })
  environment_work(b, spent)
  match result {
    Ok(value) => value
    Err(issue) => raise References(issue)
  }
}

///|
fn finish_environment_references(
  references : @environment.CatalogReferences,
  b : IdentityBudget,
  budget : IdentityBudget,
) -> (@environment.SourceRequestContracts, @environment.CatalogReferences) raise EnvironmentFailure {
  let policies = prepare_environment_policies(references, b)
  finish_environment_policies(policies, b, budget)
}

///|
fn prepare_environment_policies(
  references : @environment.CatalogReferences,
  b : IdentityBudget,
) -> @environment.SourceDataPolicies raise EnvironmentFailure {
  environment_begin(b)
  let (result, spent) = @environment.observe_source_data_policies(references, {
    max_work: b.work,
    max_policies: b.work,
  })
  environment_work(b, spent)
  match result {
    Ok(value) => value
    Err(issue) => raise Policies(issue)
  }
}

///|
fn finish_environment_policies(
  policies : @environment.SourceDataPolicies,
  b : IdentityBudget,
  budget : IdentityBudget,
) -> (@environment.SourceRequestContracts, @environment.CatalogReferences) raise EnvironmentFailure {
  let values = prepare_environment_values(policies, b)
  finish_environment_values(values, b, budget)
}

///|
fn prepare_environment_values(
  policies : @environment.SourceDataPolicies,
  b : IdentityBudget,
) -> @environment.ProtocolValueContracts raise EnvironmentFailure {
  environment_begin(b)
  let caps = environment_body_caps(b)
  let (result, nodes, text, entries) = @environment.observe_protocol_value_contracts(
    policies,
    {
      max_envelopes: caps.max_members,
      contracts: {
        max_nodes: caps.max_nodes,
        max_depth: caps.max_depth,
        max_text_bytes: caps.max_bytes,
      },
    },
  )
  environment_body_usage(b, text, nodes, entries)
  match result {
    Ok(value) => value
    Err(issue) => raise Values(issue)
  }
}

///|
fn finish_environment_values(
  values : @environment.ProtocolValueContracts,
  b : IdentityBudget,
  budget : IdentityBudget,
) -> (@environment.SourceRequestContracts, @environment.CatalogReferences) raise EnvironmentFailure {
  let modes = prepare_environment_views(values, b)
  finish_environment_modes(modes, b, budget)
}

///|
fn prepare_environment_views(
  values : @environment.ProtocolValueContracts,
  b : IdentityBudget,
) -> @environment.SourceReadModes raise EnvironmentFailure {
  environment_begin(b)
  let (result, spent) = @environment.observe_source_view_shapes(values, {
    max_work: b.work,
    max_views: b.work,
  })
  environment_work(b, spent)
  let shapes = match result {
    Ok(value) => value
    Err(issue) => raise Shapes(issue)
  }
  environment_begin(b)
  let (result, spent) = @environment.observe_source_read_modes(shapes, b.work)
  environment_work(b, spent)
  match result {
    Ok(value) => value
    Err(issue) => raise Modes(issue)
  }
}

///|
fn finish_environment_modes(
  modes : @environment.SourceReadModes,
  b : IdentityBudget,
  budget : IdentityBudget,
) -> (@environment.SourceRequestContracts, @environment.CatalogReferences) raise EnvironmentFailure {
  finish_environment_carriers(prepare_environment_carriers(modes, b), b, budget)
}

///|
fn prepare_environment_carriers(
  modes : @environment.SourceReadModes,
  b : IdentityBudget,
) -> @environment.CarrierSchemas raise EnvironmentFailure {
  environment_begin(b)
  let caps = environment_body_caps(b)
  let (result, bytes, nodes, work, entries) = @environment.observe_carrier_schemas(
    modes,
    {
      max_work: b.work / 2,
      max_schemas: Int::min(caps.max_members, b.work / 6),
      bodies: {
        max_bytes: Int::min(caps.max_bytes, b.work / 6),
        max_nodes: Int::min(caps.max_nodes, b.work / 6),
        max_depth: caps.max_depth,
      },
    },
  )
  // Work and body admission have independent underlying caps. Bill the same
  // conservative allowance to each side so replay fits both caps exactly.
  let peak = Int::max(work, 3 * Int::max(bytes, Int::max(nodes, entries)))
  if peak > b.work / 2 {
    raise BudgetExceeded
  }
  b.work -= peak * 2
  b.bytes -= bytes
  b.nodes -= nodes
  match result {
    Ok(value) => value
    Err(issue) => raise Carriers(issue)
  }
}

///|
fn finish_environment_carriers(
  carriers : @environment.CarrierSchemas,
  b : IdentityBudget,
  budget : IdentityBudget,
) -> (@environment.SourceRequestContracts, @environment.CatalogReferences) raise EnvironmentFailure {
  finish_environment_requests(
    prepare_environment_requests(carriers, b),
    b,
    budget,
  )
}

///|
fn prepare_environment_requests(
  carriers : @environment.CarrierSchemas,
  b : IdentityBudget,
) -> @environment.SourceRequestContracts raise EnvironmentFailure {
  environment_begin(b)
  let (result, spent, _) = @environment.observe_source_request_contracts(
    carriers,
    { max_work: b.work, max_roles: b.work, },
  )
  // A typed refusal does not refund this same reader's consumed prefix.
  environment_work(b, spent)
  match result {
    Ok(value) => value
    Err(issue) => raise Requests(issue)
  }
}

///|
fn finish_environment_requests(
  requests : @environment.SourceRequestContracts,
  b : IdentityBudget,
  budget : IdentityBudget,
) -> (@environment.SourceRequestContracts, @environment.CatalogReferences) {
  let policies = @environment.value_contract_policies(
    @environment.source_view_shape_values(
      @environment.read_mode_shapes(
        @environment.carrier_schema_modes(
          @environment.source_request_carriers(requests),
        ),
      ),
    ),
  )
  budget.work = b.work
  budget.bytes = b.bytes
  budget.nodes = b.nodes
  (requests, @environment.data_policy_references(policies))
}

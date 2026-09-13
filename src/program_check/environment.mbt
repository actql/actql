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
) -> @environment.SourceRequestContracts raise EnvironmentFailure {
  let b = IdentityBudget::{
    work: budget.work,
    bytes: budget.bytes,
    nodes: budget.nodes,
    depth: budget.depth,
  }
  environment_begin(b)
  let registry = match
    @environment.check_contract_registry(environment, environment_body_caps(b)) {
    Ok(v) => v
    Err(e) => raise Registry(e)
  }
  let (bytes, nodes, entries) = @environment.contract_registry_usage(registry)
  environment_body_usage(b, bytes, nodes, entries)
  environment_begin(b)
  let contents = match
    @environment.check_catalog_contents(registry, environment_body_caps(b)) {
    Ok(v) => v
    Err(e) => raise Catalog(e)
  }
  let (bytes, nodes, entries) = @environment.catalog_usage(contents)
  environment_body_usage(b, bytes, nodes, entries)
  environment_begin(b)
  let references = match
    @environment.check_catalog_references(contents, {
      max_work: b.work,
      max_references: b.work,
    }) {
    Ok(v) => v
    Err(e) => raise References(e)
  }
  environment_work(b, @environment.reference_usage(references).0)
  environment_begin(b)
  let policies = match
    @environment.check_source_data_policies(references, {
      max_work: b.work,
      max_policies: b.work,
    }) {
    Ok(v) => v
    Err(e) => raise Policies(e)
  }
  environment_work(b, @environment.data_policy_usage(policies).0)
  environment_begin(b)
  let caps = environment_body_caps(b)
  let values = match
    @environment.check_protocol_value_contracts(policies, {
      max_envelopes: caps.max_members,
      contracts: {
        max_nodes: caps.max_nodes,
        max_depth: caps.max_depth,
        max_text_bytes: caps.max_bytes,
      },
    }) {
    Ok(v) => v
    Err(e) => raise Values(e)
  }
  let (nodes, text, entries) = @environment.protocol_value_usage(values)
  environment_body_usage(b, text, nodes, entries)
  environment_begin(b)
  let shapes = match
    @environment.check_source_view_shapes(values, {
      max_work: b.work,
      max_views: b.work,
    }) {
    Ok(v) => v
    Err(e) => raise Shapes(e)
  }
  environment_work(b, @environment.source_view_shape_usage(shapes).0)
  environment_begin(b)
  let modes = match @environment.check_source_read_modes(shapes, b.work) {
    Ok(v) => v
    Err(e) => raise Modes(e)
  }
  environment_work(b, @environment.read_mode_usage(modes).0)
  environment_begin(b)
  let caps = environment_body_caps(b)
  let carriers = match
    @environment.check_carrier_schemas(modes, {
      max_work: b.work / 2,
      max_schemas: Int::min(caps.max_members, b.work / 6),
      bodies: {
        max_bytes: Int::min(caps.max_bytes, b.work / 6),
        max_nodes: Int::min(caps.max_nodes, b.work / 6),
        max_depth: caps.max_depth,
      },
    }) {
    Ok(v) => v
    Err(e) => raise Carriers(e)
  }
  let (bytes, nodes, work, entries) = @environment.carrier_schema_usage(
    carriers,
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
  environment_begin(b)
  let requests = match
    @environment.check_source_request_contracts(carriers, {
      max_work: b.work,
      max_roles: b.work,
    }) {
    Ok(v) => v
    Err(e) => raise Requests(e)
  }
  environment_work(b, @environment.source_request_usage(requests).0)
  budget.work = b.work
  budget.bytes = b.bytes
  budget.nodes = b.nodes
  requests
}

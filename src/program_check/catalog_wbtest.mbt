///|
test "Catalog-backed construction does not change Local semantic identities" {
  let local_budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (local_identity, _, _, _, local_units) = local_construction_fixture(
    local_budget,
    second_stage=true,
  )
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (identity, _, _, _, units) = local_construction_fixture(
    budget,
    second_stage=true,
    through_catalog=true,
  )
  assert_eq(
    @context.program_identity_definition_cid(identity),
    @context.program_identity_definition_cid(local_identity),
  )
  assert_eq(units.length(), local_units.length())
  for i in 0..<units.length() {
    assert_eq(units[i].definition_cid, local_units[i].definition_cid)
    assert_eq(units[i].contracts_cid, local_units[i].contracts_cid)
  }
  let exact = IdentityBudget::{
    work: 10000000 - budget.work,
    bytes: 1000000 - budget.bytes,
    nodes: 100000 - budget.nodes,
    depth: 100,
  }
  let _ = local_construction_fixture(
    exact,
    second_stage=true,
    through_catalog=true,
  )
  assert_eq((exact.work, exact.bytes, exact.nodes), (0, 0, 0))
}

///|
fn catalog_fixture(
  environment : @environment.WireEnvironment,
) -> @environment.SourceRequestContracts {
  let caps : @environment.Limits = {
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
    max_members: 1000,
  }
  let registry = @environment.check_contract_registry(environment, caps).unwrap()
  let contents = @environment.check_catalog_contents(registry, caps).unwrap()
  let references = @environment.check_catalog_references(contents, {
    max_work: 1000000,
    max_references: 10000,
  }).unwrap()
  let policies = @environment.check_source_data_policies(references, {
    max_work: 1000000,
    max_policies: 1000,
  }).unwrap()
  let values = @environment.check_protocol_value_contracts(policies, {
    max_envelopes: 1000,
    contracts: { max_nodes: 100000, max_depth: 100, max_text_bytes: 1000000, },
  }).unwrap()
  let shapes = @environment.check_source_view_shapes(values, {
    max_work: 1000000,
    max_views: 1000,
  }).unwrap()
  let modes = @environment.check_source_read_modes(shapes, 1000000).unwrap()
  let carriers = @environment.check_carrier_schemas(modes, {
    max_work: 1000000,
    max_schemas: 1000,
    bodies: { max_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
  }).unwrap()
  @environment.check_source_request_contracts(carriers, {
    max_work: 1000000,
    max_roles: 10000,
  }).unwrap()
}

///|

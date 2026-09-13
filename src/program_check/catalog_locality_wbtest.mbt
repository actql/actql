///|
test "unused admitted Catalog contracts affect checking but not Unit identity" {
  // Independently sealed with Node crypto; these are input fixtures, not
  // identities generated from the compiler's contract selection output.
  let contract =
    #|{"body":{"nullable":false,"type":"string"},"cid":"sha256:3799373b5ec003592a9780e43cbfcbfcb14520af27859adba3f8da2f4d9e83c8","id":"unused","kind":"checkpoint","schema":"actql.contract/0.1","version":"fixture"}
  let catalog = "{\"catalog_cid\":\"sha256:95445a06f301a3e1b4abb89640e3d223c31232774fc0845f134c247748a066be\",\"commands\":[],\"connector_id\":\"unused\",\"connector_version\":\"fixture\",\"contracts\":[" +
    contract +
    "],\"schema\":\"actql.connector_catalog/0.1\",\"source_views\":[]}"
  let base_budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (base, _, _, _, base_units) = local_construction_fixture(
    base_budget,
    second_stage=true,
  )
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (extended, _, _, _, units) = local_construction_fixture(
    budget,
    second_stage=true,
    registry_entries="[" + contract + "]",
    catalog_entries="[" + catalog + "]",
  )
  assert_eq(
    @context.program_identity_definition_cid(base),
    @context.program_identity_definition_cid(extended),
  )
  assert_true(budget.work < base_budget.work)
  assert_true(budget.bytes < base_budget.bytes)
  assert_true(budget.nodes < base_budget.nodes)
  for i in 0..<2 {
    assert_eq(units[i].contracts, base_units[i].contracts)
    assert_eq(units[i].contracts_cid, base_units[i].contracts_cid)
    assert_eq(units[i].definition_cid, base_units[i].definition_cid)
    assert_eq(units[i].imports, base_units[i].imports)
    assert_eq(units[i].gates, base_units[i].gates)
  }
}

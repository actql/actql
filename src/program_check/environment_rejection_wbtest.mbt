///|
test "correct identities do not admit an invalid unused checked contract" {
  // Independent Node crypto pins: the contract and Catalog identities are
  // correct, but the checked string contract lacks its required nullable flag.
  let contract =
    #|{"body":{"type":"string"},"cid":"sha256:c530e4fed05bf58669fc416e17911ce95246627e3223362d330b4a5ec32320b0","id":"unused","kind":"checkpoint","schema":"actql.contract/0.1","version":"fixture"}
  let catalog = "{\"catalog_cid\":\"sha256:0bca4f5ab6cd43cf484e016dc7e6855c6ab545ccb7a8723bd3e0c97bc759bad5\",\"commands\":[],\"connector_id\":\"unused\",\"connector_version\":\"fixture\",\"contracts\":[" +
    contract +
    "],\"schema\":\"actql.connector_catalog/0.1\",\"source_views\":[]}"
  for through_catalog in [false, true] {
    let budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let before = (budget.work, budget.bytes, budget.nodes)
    try
      local_construction_fixture(
        budget,
        through_catalog~,
        registry_entries="[" + contract + "]",
        catalog_entries="[" + catalog + "]",
      )
    catch {
      LocalConstructionFailure::Environment(
        EnvironmentFailure::Values(@environment.InvalidContract(0, _))
      ) => ()
      e => raise e
    } noraise {
      _ => fail("valid identity bypassed checked contract admission")
    }
    assert_eq((budget.work, budget.bytes, budget.nodes), before)
  }
}

///|
test "Local construction cannot bypass the identity of an unused registry contract" {
  let entries = "[{\"body\":{\"nullable\":false,\"type\":\"string\"},\"cid\":\"sha256:" +
    "0".repeat(64) +
    "\",\"id\":\"bad\",\"kind\":\"request_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"fixture\"}]"
  for through_catalog in [false, true] {
    let budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let before = (budget.work, budget.bytes, budget.nodes)
    // The enclosing wire Environment is resealed correctly by the fixture;
    // the nested contract deliberately retains an incorrect self identity.
    try
      local_construction_fixture(
        budget,
        through_catalog~,
        registry_entries=entries,
      )
    catch {
      LocalConstructionFailure::Environment(
        EnvironmentFailure::Registry(@environment.IdentityMismatch(0))
      ) => ()
      e => raise e
    } noraise {
      _ => fail("unused registry contract bypassed internal admission")
    }
    assert_eq((budget.work, budget.bytes, budget.nodes), before)
  }
}

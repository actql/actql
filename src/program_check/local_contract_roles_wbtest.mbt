///|
test "Local derive Program selects every declared semantic role exactly once" {
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 10000000,
    nodes: 1000000,
    depth: 100,
  }
  let (_, _, _, contracts, _) = local_construction_fixture(budget)
  // Expected from the source fixture and the normative role inventory, not
  // from the collector's discovered bodies or its implementation dispatch.
  let expected : Array[@context.CoreContractSite] = [
    StageEnvironmentRules(0),
    StageSourceGrammar(0),
    StageCanonicalIdentityRules(0),
    StageLocalInputRules(0, 0),
    StageLocalInputType(0, 0),
    StageSemanticRules(0, @environment.SourceRules),
    StageSemanticRules(0, @environment.StageLaws),
    StageSemanticRules(0, @environment.LocalContracts),
    StageSemanticRules(0, @environment.LocalDependencies),
    StageExpression(0),
    StagePublicationRules(0, 0),
    OperationTransferRules(0, 0, 0),
    OperationRelationCountRules(0, 0, 0),
    OperationLaw(0, 0, 0, 0, 0),
    OperationLaw(0, 0, 0, 0, 1),
  ]
  assert_eq(@context.core_contract_root_count(contracts), expected.length())
  for site in expected {
    let mut count = 0
    for i in 0..<@context.core_contract_root_count(contracts) {
      if @context.core_contract_root_at(contracts, i).unwrap().site == site {
        count += 1
      }
    }
    assert_eq(count, 1)
  }
  // This independently authored schema-only preimage excludes observations
  // and Host policy. Type interpretation is distinct from its governing law.
  let type_body =
    #|{"output_carrier":"relation","schema":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"source_ref":"source:local/first/rows","version":"actql-local-input-schema/0.1"}
  let type_cid = "sha256:" + @sha.hex(@utf8.encode(type_body))
  for i in 0..<@context.core_contract_root_count(contracts) {
    let root = @context.core_contract_root_at(contracts, i).unwrap()
    match root.site {
      StageLocalInputType(0, 0) =>
        assert_eq(root.body, LocalInputType(type_cid))
      StagePublicationRules(0, 0) =>
        assert_eq(root.body, AdoptedBody(@pipeline.RelaPrimitive))
      OperationLaw(0, 0, 0, 0, 0) =>
        assert_eq(root.body, AdoptedBody(@pipeline.RelaScalar))
      OperationLaw(0, 0, 0, 0, 1) =>
        assert_eq(root.body, AdoptedBody(@pipeline.RelaPrimitive))
      OperationTransferRules(0, 0, 0) =>
        assert_eq(root.body, BoundTransferRules)
      OperationRelationCountRules(0, 0, 0) =>
        assert_eq(root.body, RelationCountRules)
      _ => ()
    }
  }
}

///|
test "Result consumer contract roles do not inherit producer operation roots" {
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 10000000,
    nodes: 1000000,
    depth: 100,
  }
  let (_, _, _, contracts, _) = local_construction_fixture(
    budget,
    second_stage=true,
  )
  // first: the 15 roles above; second: 9 common/publication roles plus two
  // Result interfaces and one predecessor gate. Imports are not Local inputs.
  assert_eq(@context.core_contract_root_count(contracts), 27)
  let expected : Array[@context.CoreContractSite] = [
    StageEnvironmentRules(1),
    StageSourceGrammar(1),
    StageCanonicalIdentityRules(1),
    StageSemanticRules(1, @environment.SourceRules),
    StageSemanticRules(1, @environment.StageLaws),
    StageSemanticRules(1, @environment.LocalContracts),
    StageSemanticRules(1, @environment.LocalDependencies),
    StageExpression(1),
    StagePublicationRules(1, 0),
    IncomingRules(0),
    IncomingRules(1),
    IncomingRules(2),
  ]
  for site in expected {
    let mut count = 0
    for i in 0..<@context.core_contract_root_count(contracts) {
      if @context.core_contract_root_at(contracts, i).unwrap().site == site {
        count += 1
      }
    }
    assert_eq(count, 1)
  }
  let mut interfaces = 0
  let mut gates = 0
  for i in 0..<@context.core_contract_root_count(contracts) {
    let root = @context.core_contract_root_at(contracts, i).unwrap()
    if root.site is IncomingRules(_) {
      match root.body {
        StageSemantics(@environment.ResultImportInterface) => interfaces += 1
        StageSemantics(@environment.GateRequirement) => gates += 1
        _ => fail("unexpected incoming interpretation")
      }
    }
  }
  assert_eq(interfaces, 2)
  assert_eq(gates, 1)
}

///|
test "closed Values contract dependency envelope matches pinned constructor closure" {
  let b : CoreContractBuilder = {
    limits: { max_work: 10000, max_roots: 100, max_bodies: 100, max_edges: 100, },
    roots: [], bodies: [], seen: {}, dependencies: {}, work: 0, edges: 0,
    hash_limits: { max_bytes: 10000, max_nodes: 10000, max_depth: 100, },
    hash_bytes: 0, hash_nodes: 0,
  }
  core_contract_stage_environment_roots(b, 0)
  for rules in [@environment.SourceRules, @environment.StageLaws, @environment.LocalContracts, @environment.LocalDependencies] {
    core_contract_root(b, StageSemanticRules(0, rules), StageSemantics(rules))
  }
  core_contract_root(b, StageExpression(0), ExpressionBody(@environment.ExpressionRoot))
  core_contract_root(b, StagePublicationRules(0, 0), AdoptedBody(@pipeline.RelaPrimitive))
  core_contract_root(b, OperationTransferRules(0, 0, 0), BoundTransferRules)
  core_contract_root(b, OperationValuesWireLaw(0, 0, 0), ValuesWireLaw)
  core_contract_root(b, OperationValuesExecutionRules(0, 0, 0), ValuesExecutionRules)
  core_contract_root(b, OperationCountLaw(0, 0, 0), ValuesCountLaw)
  for i in 0..<@pipeline.operation_profile_adopted_law_count(@pipeline.RelA) {
    core_contract_root(b, OperationLaw(0, 0, 0, 0, i), AdoptedBody(@pipeline.operation_profile_adopted_law_at(@pipeline.RelA, i).unwrap()))
  }
  core_contract_complete_dependencies(b)
  let shape = closed_values_contract_shape()
  assert_eq(b.roots.length(), shape.roots)
  assert_eq(b.bodies.length(), shape.bodies)
  assert_eq(b.edges, shape.visited_edges)
  assert_eq(b.dependencies.length(), shape.dependency_owners)
  let mut unique = 0
  for _, dependency in b.dependencies {
    unique += dependency.targets.length()
  }
  assert_eq(unique, shape.unique_edges)
}

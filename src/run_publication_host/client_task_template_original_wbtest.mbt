///|
test "task compilation keeps its same-construction admitted template" {
  let prepared = values_compilation_parts_prepared()
  let limits = run_materials_limits()
  let (plan, original, graph) = issue_prepared_client_task_plan_parts(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  let compiled = finish_client_task_compilation(
    prepared, plan, original, graph, 100000, 10000, 100,
  ).unwrap()
  assert_true(physical_equal(compiled.template, original))
  // Reproduce the previous full wire admission independently. Its complete
  // identity and downstream Plan must remain identical to the original route.
  let read = @publication.admit_run_evidence_value(
    "bound_invocation_template",
    @publication.run_evidence_value_json(original),
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(!physical_equal(read, original))
  let old = finish_client_task_compilation(
    prepared, plan, read, graph, 100000, 10000, 100,
  ).unwrap()
  let public = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  for candidate in [compiled, public] {
    assert_eq(
      @publication.run_evidence_value_json(candidate.template),
      @publication.run_evidence_value_json(old.template),
    )
    assert_eq(
      @publication.run_evidence_value_identity(candidate.template),
      @publication.run_evidence_value_identity(old.template),
    )
    assert_eq(candidate.plan.plan.wire, old.plan.plan.wire)
    assert_eq(candidate.plan.plan.cid, old.plan.plan.cid)
    assert_eq(
      @publication.publication_contract_json(candidate.compiled_plan),
      @publication.publication_contract_json(old.compiled_plan),
    )
  }
}

///|
test "task original template preserves full construction bounds and nominal owner" {
  let prepared = values_compilation_parts_prepared()
  let limits = run_materials_limits()
  for
    (bytes, nodes, depth) in [
      (0, 10000, 100),
      (-1, 10000, 100),
      (1, 10000, 100),
      (100000, 0, 100),
      (100000, -1, 100),
      (100000, 1, 100),
      (100000, 10000, 0),
      (100000, 10000, -1),
      (100000, 10000, 1),
    ] {
    assert_true(
      issue_prepared_client_task_compilation(
        prepared,
        run_materials_manifests(),
        limits.sequence,
        32,
        64,
        bytes,
        nodes,
        depth,
      )
      is Err(_),
    )
  }
  let compiled = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  let foreign = values_compilation_parts_prepared()
  assert_eq(
    prepared_client_identity(foreign),
    prepared_client_identity(prepared),
  )
  assert_true(!physical_equal(foreign, prepared))
  assert_true(
    issue_client_task_compiled_run(
      foreign,
      compiled,
      "sha256:" + "a".repeat(64),
      "sha256:" + "b".repeat(64),
      "2099-01-01T00:00:00.000Z",
    )
    is Err(ForeignOwner),
  )
}

///|
fn values_compilation_parts_prepared() -> PreparedClientProgram {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  prepare_effect_free_client_program(
    run_materials_document,
    Json,
    environment,
    None,
    run_materials_limits().preparation,
  ).unwrap()
}

///|
test "Values compilation parts retain the original checked components without reissuance" {
  let prepared = values_compilation_parts_prepared()
  let limits = run_materials_limits()
  let parts = issue_prepared_client_values_executable_plan_parts(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  let compiled = issue_client_values_compilation_with_parts(
    prepared, parts, 100000, 10000, 100,
  ).unwrap()
  assert_true(physical_equal(compiled.owner, prepared))
  assert_eq(compiled.plan.transformations.length(), 0)
  assert_true(physical_equal(compiled.plan, parts.plan))
  assert_true(physical_equal(compiled.template, parts.template))
  assert_true(physical_equal(compiled.fragment, parts.fragment))
  // Standalone public issuers keep their existing bytes. Their independent
  // calls here are compatibility controls, not work of one compilation.
  let standalone = issue_prepared_client_values_executable_plan(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  assert_eq(parts.plan.wire, standalone.wire)
  assert_eq(parts.plan.cid, standalone.cid)
  assert_eq(parts.plan.fact_manifest_wire, standalone.fact_manifest_wire)
  assert_eq(
    @publication.run_evidence_value_json(parts.template),
    @publication.run_evidence_value_json(
      issue_prepared_source_free_client_bound_template(
        prepared,
        run_materials_manifests(),
        limits.sequence,
        100000,
        10000,
        100,
      ).unwrap(),
    ),
  )
  assert_eq(
    parts.fragment.wire,
    issue_prepared_client_values_fragment(
      prepared,
      0,
      limits.sequence,
      100000,
      10000,
      100,
    ).unwrap().wire,
  )
}

///|
test "Values compilation parts reject a CID-equal foreign checked owner" {
  let prepared = values_compilation_parts_prepared()
  let foreign = values_compilation_parts_prepared()
  assert_true(!physical_equal(prepared, foreign))
  assert_eq(
    prepared_client_identity(prepared),
    prepared_client_identity(foreign),
  )
  let parts = issue_prepared_client_values_executable_plan_parts(
    prepared,
    run_materials_manifests(),
    run_materials_limits().sequence,
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(
    issue_client_values_compilation_with_parts(
      foreign, parts, 100000, 10000, 100,
    )
    is Err(Plan(Graph(UnsupportedGraph))),
  )
  let compiled = issue_client_values_compilation_with_parts(
    prepared, parts, 100000, 10000, 100,
  ).unwrap()
  assert_true(
    issue_client_values_compiled_run(
      foreign,
      compiled,
      "sha256:" + "a".repeat(64),
      "sha256:" + "b".repeat(64),
      "2099-01-01T00:00:00.000Z",
    )
    is Err(ForeignOwner),
  )
}

///|
test "Values compilation parts preserve original preparation and encoding limits" {
  let prepared = values_compilation_parts_prepared()
  for maximum in [0, -1] {
    assert_true(
      issue_prepared_client_values_compilation(
        prepared,
        run_materials_manifests(),
        run_materials_limits().sequence,
        maximum,
        64,
        100000,
        10000,
        100,
      )
      is Err(Plan(InvalidLimits)),
    )
  }
  assert_true(
    issue_prepared_client_values_compilation(
      prepared,
      run_materials_manifests(),
      run_materials_limits().sequence,
      32,
      64,
      1,
      10000,
      100,
    )
    is Err(_),
  )
}

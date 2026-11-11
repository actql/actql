///|
test "Native default checking retains the shipped numeric profile" {
  let environment = local_admitted_check_environment(
    explain_update_environment_wire, "sha256:dde2a4ab7160672ec8f2fc7fc49e1b9e0ebd7992b7a60851d57e5a9ea161694b",
  ).unwrap()
  assert_eq(
    @checked.checking_environment_profile_selection(environment).numeric_profile_cid,
    Some(@numeric.cid(@numeric.builtin_profile())),
  )
}

///|
test "Native default Number SUM and AVG reach actual checked lowering" {
  let environment = local_admitted_check_environment(
    explain_update_environment_wire, "sha256:dde2a4ab7160672ec8f2fc7fc49e1b9e0ebd7992b7a60851d57e5a9ea161694b",
  ).unwrap()
  let context = @frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(environment),
    model_tasks=@checked.checking_environment_model_tasks(environment),
  ).unwrap()
  for aggregate in ["SUM", "AVG"] {
    let document = "WITH x AS (SELECT 1 AS n UNION ALL SELECT 2 AS n) SELECT " +
      aggregate +
      "(n) AS total FROM x"
    let prepared = @local_host.prepare_native_client_program(
      document,
      Sql,
      environment,
      None,
      Some(context),
      [],
      @run_host.client_standard_effect_computation_limits(),
    ).unwrap()
    assert_true(prepared is Computation(_))
    assert_true(local_static_plan_view(prepared).contains("total"))
  }
}

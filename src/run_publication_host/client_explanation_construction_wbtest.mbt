///|
test "first Facts geometry precedes key issuance and equals retained Values and Tasks originals" {
  for tasks in [false, true] {
    let (prepared, compiled, _) = local_values_invocation_fixture(tasks)
    let geometry = measure_client_compiled_explanation_facts(
      compiled, prepared, 1000000, 100000, 100,
    ).unwrap()
    let (original, plan) = capture_client_structural_explanation_plan_original(
      compiled, prepared, 1000000, 100000, 100,
    ).unwrap()
    assert_eq(
      plan,
      client_compiled_run_static_plan_view(
        compiled, prepared, 1000000, 100000, 100,
      ).unwrap(),
    )
    assert_eq(
      geometry,
      measure_client_structural_explanation_facts(
        original, compiled, prepared, 1000000, 100000, 100,
      ).unwrap(),
    )
    let facts = seal_client_structural_explanation_facts(
      original,
      compiled,
      prepared,
      geometry.complete.0,
      geometry.complete.1,
      geometry.complete.2,
    ).unwrap()
    assert_eq(
      geometry.complete,
      interactive_geometry_actual(@publication.run_evidence_value_json(facts)),
    )
  }
}

///|
test "first typed predicate Facts measurement keeps original parameters and exact bounded output" {
  let prepared = structural_explanation_prepared(
    "{\"gt\":[{\"field\":\"id\"},{\"$param\":\"threshold\"}]}",
    parameter=true,
  )
  let compiled = issue_client_task_compiled_run(
    prepared,
    structural_explanation_compiled(prepared),
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let geometry = measure_client_compiled_explanation_facts(
    compiled, prepared, 1000000, 100000, 100,
  ).unwrap()
  let original = capture_client_structural_explanation_original(
    compiled, prepared, 1000000, 100000, 100,
  ).unwrap()
  assert_eq(
    geometry,
    measure_client_structural_explanation_facts(
      original, compiled, prepared, 1000000, 100000, 100,
    ).unwrap(),
  )
  assert_true(
    measure_client_compiled_explanation_facts(
      compiled,
      prepared,
      geometry.complete.0 - 1,
      100000,
      100,
    )
    is Err(Encoding(_)),
  )
}

///|
test "first Facts measurement refuses foreign original and invalid limits without a Plan projection" {
  let (prepared, compiled, _) = local_values_invocation_fixture(false)
  let (foreign, _, _) = local_values_invocation_fixture(false)
  assert_true(
    measure_client_compiled_explanation_facts(
      compiled, foreign, 1000000, 100000, 100,
    )
    is Err(ForeignOriginal),
  )
  for (bytes, nodes, depth) in [(0, 1000, 10), (10000, 0, 10), (10000, 1000, 0)] {
    assert_true(
      measure_client_compiled_explanation_facts(
        compiled, prepared, bytes, nodes, depth,
      )
      is Err(InvalidReadLimits),
    )
  }
}

///|
test "Request compiler geometry is available before Run issuance and rejects a foreign owner" {
  let prepared = input_result_prepared(run_materials_document)
  let foreign = input_result_prepared(run_materials_document)
  let tasks : ClientRunCompilation = Tasks(
    structural_explanation_compiled(prepared),
  )
  let values : ClientRunCompilation = Values(
    issue_prepared_client_values_compilation(
      prepared,
      run_materials_manifests(),
      run_materials_limits().sequence,
      1000,
      1000,
      1000000,
      100000,
      100,
    ).unwrap(),
  )
  for compilation in [tasks, values] {
    // No ClientCompiledRun, authorization or definition exists at this call.
    let plan_geometry = measure_client_pure_compilation_static_plan_view(
      compilation, prepared, 1000000, 100000, 100,
    ).unwrap()
    let facts_geometry = measure_client_pure_compilation_explanation_facts(
      compilation, prepared, 1000000, 100000, 100,
    ).unwrap()
    assert_true(
      measure_client_pure_compilation_static_plan_view(
        compilation, foreign, 1000000, 100000, 100,
      )
      is Err(ForeignCompilation),
    )
    assert_true(
      measure_client_pure_compilation_explanation_facts(
        compilation, foreign, 1000000, 100000, 100,
      )
      is Err(ForeignOriginal),
    )
    let compiled = match compilation {
      Tasks(original) =>
        issue_client_task_compiled_run(
          prepared,
          original,
          "sha256:" + "a".repeat(64),
          "sha256:" + "b".repeat(64),
          "2099-01-01T00:00:00.000Z",
        ).unwrap()
      Values(original) =>
        issue_client_values_compiled_run(
          prepared,
          original,
          "sha256:" + "a".repeat(64),
          "sha256:" + "b".repeat(64),
          "2099-01-01T00:00:00.000Z",
        ).unwrap()
      Effects(_) => fail("unexpected Effect compiler")
    }
    assert_eq(
      plan_geometry,
      measure_client_compiled_run_static_plan_view(
        compiled, prepared, 1000000, 100000, 100,
      ).unwrap(),
    )
    assert_eq(
      facts_geometry,
      measure_client_compiled_explanation_facts(
        compiled, prepared, 1000000, 100000, 100,
      ).unwrap(),
    )
  }
}

///|
fn complete_result_inventory_prepared() -> PreparedClientProgram {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"complete-result-plans","stages":[{"id":"main","inputs":{},"steps":[{"as":"v","values":{"schema":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"id":1,"label":"日本語😀"}]}}],"results":{"complete":{"from":"v","fields":["id","label"]},"only_id":{"from":"v","fields":["id"]}}}],"results":{"complete":{"from":{"stage":"main","result":"complete"}},"projected":{"from":{"stage":"main","result":"only_id"}}}}
  prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    run_materials_limits().preparation,
  ).unwrap()
}

///|
test "complete Result inventory retains both direct and transformed original Plans" {
  let value = complete_result_inventory_prepared()
  let graph = issue_prepared_client_values_plan_graph(
    value,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  assert_eq(graph.result_plans.length(), 2)
  assert_eq(graph.transformations.length(), 1)
  let calls = Ref(0)
  for result in 0..<2 {
    let plan = client_material_result_plan(
      value,
      result,
      graph.result_plans,
      100000,
      10000,
      100,
      (owner, result, b, n, d) => {
        calls.val += 1
        issue_prepared_client_result_plan(owner, result, b, n, d)
      },
    ).unwrap()
    assert_true(physical_equal(plan, graph.result_plans[result]))
    assert_eq(plan.result, result)
    assert_true(physical_equal(plan.owner, value))
  }
  assert_eq(calls.val, 0)
  assert_true(graph.result_plans[0].cid != graph.result_plans[1].cid)
}

///|
test "compiled Values and Tasks Result readers consume the retained artifact Plans" {
  for tasks in [false, true] {
    let (_, compiled, _) = local_values_invocation_fixture(tasks)
    let originals = match compiled.compilation {
      Values(value) => value.plan.result_plans
      Tasks(value) => value.plan.plan.result_plans
      _ => fail("unexpected Effect fixture")
    }
    assert_eq(originals.length(), 1)
    let original = originals[0]
    let (b, n, d) = original.codec_limits
    let read = prepare_client_compiled_result_transformation(
      compiled, 0, b, n, d,
    ).unwrap()
    assert_true(physical_equal(read.plan, original))
    let standalone = prepare_client_result_transformation(
      compiled.owner,
      0,
      b,
      n,
      d,
    ).unwrap()
    assert_false(physical_equal(standalone.plan, original))
    assert_eq(standalone.plan.cid, original.cid)
    let changed = prepare_client_compiled_result_transformation(
      compiled,
      0,
      b - 1,
      n,
      d,
    ).unwrap()
    assert_false(physical_equal(changed.plan, original))
    assert_eq(changed.plan.cid, original.cid)
    for result in [-1, 1] {
      assert_true(
        prepare_client_compiled_result_transformation(compiled, result, b, n, d)
        is Err(MissingResult),
      )
      assert_true(
        prepare_client_result_transformation(compiled.owner, result, b, n, d)
        is Err(MissingResult),
      )
    }
    assert_true(physical_equal(original, originals[0]))
  }
}

///|
test "compiled Effect Result reader retains its actual component Plan originals" {
  let (_, allowed, _) = original_effect_materials_fixture()
  let compiled = client_effect_allowed_component_run(allowed, None)
  let originals = allowed.compilation.compiled.plan.plan.result_plans
  assert_true(originals.length() > 0)
  for original in originals {
    let (b, n, d) = original.codec_limits
    let read = prepare_client_compiled_result_transformation(
      compiled,
      original.result,
      b,
      n,
      d,
    ).unwrap()
    assert_true(physical_equal(read.plan, original))
  }
}

///|
test "direct Result foreign changed and restored evidence retains the original full paths" {
  let value = values_compilation_parts_prepared()
  let foreign = values_compilation_parts_prepared()
  let graph = issue_prepared_client_values_plan_graph(
    value,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  let original = graph.result_plans[0]
  let calls = Ref(0)
  let issue = (owner, result, b, n, d) => {
    calls.val += 1
    issue_prepared_client_result_plan(owner, result, b, n, d)
  }
  let other = client_material_result_plan(
    foreign,
    0,
    graph.result_plans,
    100000,
    10000,
    100,
    issue,
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_eq(original.cid, other.cid)
  assert_false(physical_equal(original, other))
  let changed = client_material_result_plan(
    value,
    0,
    graph.result_plans,
    99999,
    10000,
    100,
    issue,
  ).unwrap()
  assert_eq(calls.val, 2)
  assert_eq(original.cid, changed.cid)
  assert_false(physical_equal(original, changed))
  assert_true(
    client_material_result_plan(value, 0, graph.result_plans, 1, 1, 1, issue)
    is Err(_),
  )
  assert_eq(calls.val, 3)
  let restored = admit_prepared_client_result_plan(
    value,
    0,
    original.wire,
    100000,
    10000,
    100,
  ).unwrap()
  assert_eq(restored.cid, original.cid)
  assert_false(physical_equal(restored, original))
  assert_true(
    admit_prepared_client_result_plan(value, 0, "{}", 100000, 10000, 100)
    is Err(_),
  )
}

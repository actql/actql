///|
test "public Task Environment work follows 129 actual members instead of unused document maxima" {
  let environment = project_task_empty_environment()
  let tasks = Array::makei(129, index => project_task_normalized("model-task:registry.\{index}"))
  let limits : ModelTaskLimits = {
    bodies: {max_bytes: 2000000, max_nodes: 100000, max_depth: 64, max_members: 1000},
    contracts: {max_nodes: 10000, max_depth: 64, max_text_bytes: 1000000},
    max_work: 2000000,
  }
  let (wire, identity, work) = project_public_model_task_environment(environment, tasks, limits).unwrap()
  assert_true(work < limits.max_work)
  let original = read(@utf8.encode(wire), identity, limits.bodies).unwrap()
  let admitted = check_model_tasks(original, limits).unwrap()
  assert_eq(model_tasks_usage(admitted).5, 129)
  assert_true(check_model_tasks(original, {..limits, bodies: {..limits.bodies, max_members: 128}}) is Err(_))
}

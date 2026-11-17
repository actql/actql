///|
test "public Task Environment work follows 129 actual members instead of unused document maxima" {
  let environment = project_task_empty_environment()
  let tasks = Array::makei(129, index => {
    project_task_normalized("model-task:registry.\{index}")
  })
  let limits : ModelTaskLimits = {
    bodies: {
      max_bytes: 2000000,
      max_nodes: 100000,
      max_depth: 64,
      max_members: 1000,
    },
    contracts: { max_nodes: 10000, max_depth: 64, max_text_bytes: 1000000, },
    max_work: 2000000,
  }
  let (wire, identity, work) = project_public_model_task_environment(
    environment, tasks, limits,
  ).unwrap()
  assert_true(work < limits.max_work)
  let original = read(@utf8.encode(wire), identity, limits.bodies).unwrap()
  let admitted = check_model_tasks(original, limits).unwrap()
  assert_eq(model_tasks_usage(admitted).5, 129)
  assert_true(
    check_model_tasks(original, {
      ..limits,
      bodies: { ..limits.bodies, max_members: 128, },
    })
    is Err(_),
  )
}

///|
test "default final Model admission uses exact member totals while explicit policies remain smaller" {
  let source = project_task_empty_environment()
  let task = project_task_normalized("model-task:final.original")
  let projected = project_public_model_task_environment(
    source,
    [task],
    declaration_limits(),
  ).unwrap()
  let original = read(
    @utf8.encode(projected.0),
    projected.1,
    declaration_limits().bodies,
  ).unwrap()
  let limits = original_model_tasks_admission_limits(original).unwrap()
  let (bytes, nodes) = member_usage(
    member_at(original, ModelTaskContracts, 0).unwrap(),
  )
  assert_eq(limits.bodies.max_bytes, bytes)
  assert_eq(limits.bodies.max_nodes, nodes)
  assert_eq(limits.bodies.max_members, 1)
  assert_eq(
    model_tasks_usage(check_model_tasks(original, limits).unwrap()).5,
    1,
  )
  assert_true(
    check_model_tasks(original, {
      ..limits,
      bodies: { ..limits.bodies, max_bytes: bytes - 1, },
    })
    is Err(_),
  )
  assert_true(model_tasks_admission_construction_extent(original) is Some(_))
  assert_true(model_tasks_admission_construction_extent(source) is Some(_))
}

///|
test "public Task final constructor follows actual ordered member usage for 129 tasks" {
  let base = project_task_empty_environment()
  let tasks = Array::makei(129, index => {
    project_task_normalized("model-task:funded.\{index}")
  })
  let limits = public_model_task_environment_limits(
    base.bytes,
    base.nodes,
    3,
    base.members,
    0,
    tasks,
  ).unwrap()
  assert_true(limits.bodies.max_bytes > 65536)
  let extent = public_model_task_environment_construction_extent(
    base.bytes,
    base.nodes,
    3,
    base.members,
    0,
    tasks,
  ).unwrap()
  assert_true(extent.record_headers > 0L)
  let (wire, identity, _) = project_public_model_task_environment(
    base, tasks, limits,
  ).unwrap()
  let raw = read(@utf8.encode(wire), identity, limits.bodies).unwrap()
  assert_eq(
    model_tasks_usage(
      check_model_tasks(
        raw,
        original_model_tasks_admission_limits(raw).unwrap(),
      ).unwrap(),
    ).5,
    129,
  )
  assert_true(
    public_model_task_environment_limits(
      base.bytes,
      base.nodes,
      65,
      base.members,
      0,
      tasks,
    )
    is None,
  )
  assert_true(
    public_model_task_environment_limits(
      base.bytes,
      base.nodes,
      3,
      base.members,
      1,
      tasks,
    )
    is None,
  )
}

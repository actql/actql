///|
test "Program gates retain Stage sites and share aggregate emission budgets" {
  let (identity, _, _) = prepared_identity_fixture(third_stage=true)
  let resolved = resolve_program_operations(identity, {
    max_work: 10000000,
    max_requirements: 100,
    max_resolutions: 100,
  }).unwrap()
  let incoming_limits : IncomingLimits = {
    max_work: 10000000,
    max_name_units: 10000,
    max_requirements: 100,
  }
  let incoming = collect_program_incoming(identity, incoming_limits).unwrap()
  let owner = link_resolved_program_incoming(
    resolved, incoming, incoming_limits,
  ).unwrap()
  let limits : IncomingGateLimits = {
    max_work: 10000000,
    max_bytes: 10000,
    max_nodes: 100,
    max_depth: 10,
  }
  let gates = prepare_program_incoming_gates(owner, limits).unwrap()
  assert_true(physical_equal(program_incoming_gates_owner(gates), owner))
  assert_eq(program_incoming_gates_stage_count(gates), 3)
  assert_eq(program_incoming_gates_count(gates, 0), Some(0))
  assert_eq(program_incoming_gates_count(gates, 1), Some(1))
  assert_eq(program_incoming_gates_count(gates, 2), Some(1))
  // Two gates and three Result imports. The latter are not gate resolutions.
  assert_eq(program_incoming_count(incoming), 5)
  let first = program_incoming_gates_at(gates, 1, 0).unwrap()
  let second = program_incoming_gates_at(gates, 2, 0).unwrap()
  assert_true(
    physical_equal(
      incoming_gate_check(first).site,
      program_incoming_at(incoming, 0).unwrap(),
    ),
  )
  assert_true(
    physical_equal(
      incoming_gate_check(second).site,
      program_incoming_at(incoming, 3).unwrap(),
    ),
  )
  assert_eq(
    incoming_gate_cid(first),
    "sha256:85a0b8224d380e8e7072f4ab9bfdf3634ce9e39f5e9823d186f93e690d638891",
  )
  // Independently hashed canonical literal, not obtained from the constructor.
  assert_eq(
    incoming_gate_cid(second),
    "sha256:c4c4e617c41bcbdf65fc6fb46b417fbe242717f3af64c6fbee21967fc449e696",
  )
  let (work, bytes, nodes) = program_incoming_gates_usage(gates)
  assert_eq(
    work,
    incoming_links_work(owner) +
    1 +
    3 +
    5 +
    (incoming_gate_usage(first).0 - incoming_links_work(owner)) +
    (incoming_gate_usage(second).0 - incoming_links_work(owner)),
  )
  assert_eq(bytes, 499) // completed: producer "first" then "second"
  assert_eq(nodes, 18)
  let exact : IncomingGateLimits = {
    max_work: work,
    max_bytes: bytes,
    max_nodes: nodes,
    max_depth: 2,
  }
  assert_true(prepare_program_incoming_gates(owner, exact) is Ok(_))
  assert_true(
    prepare_program_incoming_gates(owner, { ..exact, max_work: work - 1, })
    is Err(_),
  )
  for
    short in [
      { ..exact, max_bytes: bytes - 1, },
      { ..exact, max_nodes: nodes - 1, },
    ] {
    // Each individual gate fits. The second cannot reset the aggregate cap.
    assert_true(prepare_incoming_gate(owner, 0, short) is Ok(_))
    assert_true(prepare_incoming_gate(owner, 3, short) is Ok(_))
    assert_true(
      prepare_program_incoming_gates(owner, short) is Err(Gate(3, Hash(_))),
    )
  }
  assert_true(
    prepare_program_incoming_gates(owner, { ..exact, max_depth: 1, })
    is Err(Gate(0, Hash(_))),
  )
  for
    invalid in [
      { ..exact, max_work: -1, },
      { ..exact, max_bytes: -1, },
      { ..exact, max_nodes: -1, },
      { ..exact, max_depth: -1, },
    ] {
    assert_true(
      prepare_program_incoming_gates(owner, invalid) is Err(InvalidLimits),
    )
  }
  for index in [-2147483648, -1, 3, 2147483647] {
    assert_eq(program_incoming_gates_count(gates, index), None)
    assert_true(program_incoming_gates_at(gates, index, 0) is None)
  }
  assert_true(program_incoming_gates_at(gates, 0, 0) is None)
  assert_true(program_incoming_gates_at(gates, 1, -1) is None)
  assert_true(program_incoming_gates_at(gates, 2, 1) is None)
}

///|
fn gate_fixture(accepted : Bool) -> ProgramIncomingLinks {
  let identity = incoming_fixture(accepted~)
  let resolved = resolve_program_operations(identity, {
    max_work: 10000000,
    max_requirements: 100,
    max_resolutions: 100,
  }).unwrap()
  let limits : IncomingLimits = {
    max_work: 10000000,
    max_name_units: 10000,
    max_requirements: 100,
  }
  link_resolved_program_incoming(
    resolved,
    collect_program_incoming(identity, limits).unwrap(),
    limits,
  ).unwrap()
}

///|
test "owned empty-Effect gates have fixed canonical preimages without observed success" {
  // SHA-256 independently computed from these canonical UTF-8 literals.
  for
    (accepted, cid, milestone) in [
      (
        true, "sha256:3038b33d39a9cedfbaf3b4f85d42beb1b4c52a6214cfdcf0bad82dedad6b62cd",
        "accepted",
      ),
      (
        false, "sha256:85a0b8224d380e8e7072f4ab9bfdf3634ce9e39f5e9823d186f93e690d638891",
        "completed",
      ),
    ] {
    let owner = gate_fixture(accepted)
    let gate = prepare_incoming_gate(owner, 0, {
      max_work: 10000000,
      max_bytes: 10000,
      max_nodes: 100,
      max_depth: 10,
    }).unwrap()
    let expected = "{\"completion_contracts\":{},\"completion_nodes\":{},\"effect_contracts\":{},\"effect_nodes\":{},\"empty_items\":\"require-successful-computation-and-preflight\",\"milestone\":\"" +
      milestone +
      "\",\"producer_node_id\":\"first\",\"version\":\"actql-graph-success-requirement/0.1\"}"
    assert_eq(incoming_gate_cid(gate), cid)
    assert_true(physical_equal(incoming_gate_owner(gate), owner))
    assert_true(
      physical_equal(
        incoming_gate_check(gate).site,
        program_incoming_at(incoming_links_requirements(owner), 0).unwrap(),
      ),
    )
    assert_eq(
      incoming_execution_missing(incoming_gate_check(gate)),
      AwaitPredecessor,
    )
    let (work, bytes, nodes) = incoming_gate_usage(gate)
    assert_eq(bytes, expected.length())
    assert_eq(nodes, 9)
    let writer = @encode.writer(bytes, nodes, 2)
    emit_incoming_gate_preimage(gate, writer)
    assert_eq(@encode.finish(writer), expected)
    let full = @encode.writer(10000, 100, 2)
    emit_incoming_gate(gate, full)
    assert_eq(
      @encode.finish(full),
      expected.replace(
        old="\"version\":",
        new="\"self_cid\":\"" + cid + "\",\"version\":",
      ),
    )
    let exact : IncomingGateLimits = {
      max_work: work,
      max_bytes: bytes,
      max_nodes: nodes,
      max_depth: 2,
    }
    assert_true(prepare_incoming_gate(owner, 0, exact) is Ok(_))
    for
      short in [
        { ..exact, max_work: work - 1, },
        { ..exact, max_bytes: bytes - 1, },
        { ..exact, max_nodes: nodes - 1, },
        { ..exact, max_depth: 1, },
      ] {
      assert_true(prepare_incoming_gate(owner, 0, short) is Err(_))
    }
    assert_true(prepare_incoming_gate(owner, 1, exact) is Err(NotSuccessGate))
    for index in [-2147483648, -1, 2, 2147483647] {
      assert_true(
        prepare_incoming_gate(owner, index, exact) is Err(MissingSite),
      )
    }
    for
      invalid in [
        { ..exact, max_work: -1, },
        { ..exact, max_bytes: -1, },
        { ..exact, max_nodes: -1, },
        { ..exact, max_depth: -1, },
      ] {
      assert_true(
        prepare_incoming_gate(owner, 0, invalid) is Err(InvalidLimits),
      )
    }
    let foreign = gate_fixture(accepted)
    let other = prepare_incoming_gate(foreign, 0, {
      ..exact,
      max_work: 10000000,
    }).unwrap()
    assert_eq(incoming_gate_cid(other), cid)
    assert_false(physical_equal(incoming_gate_owner(other), owner))
    assert_false(
      physical_equal(
        incoming_gate_check(other).site,
        incoming_gate_check(gate).site,
      ),
    )
  }
}

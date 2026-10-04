///|
/// The managed driver rejects any poll whose actual work exceeds its quantum.
/// Outcome equivalence across quantum sizes does not establish this boundary.
test "Delta diff respects each admitted poll quantum" {
  let preparation = prepare(
    delta_fixture_storage(false),
    delta_fixture_storage(true),
    json_contract(),
    @graph_contract.cid(delta_fixture_contract()),
    delta_fixture_limits(),
  ).unwrap()
  for poll_index in 0..<100000 {
    let poll = advance(preparation, 1).unwrap()
    let (work, terminal) = match poll {
      Continue(work~, ..) => (work, false)
      Complete(_, work~, ..) => (work, true)
      Failed(issue, ..) => {
        debug_inspect(issue)
        fail("fixture failed before completion")
      }
    }
    if work < 0 || work > 1 {
      let phase = if preparation.phase == SnapshotRight {
        "SnapshotRight"
      } else {
        "other"
      }
      assert_true(cleanup(preparation))
      fail("poll \{poll_index}: phase=\{phase}, actual work=\{work}, quantum=1")
    }
    if terminal {
      assert_true(cleanup(preparation))
      return
    }
  }
  assert_true(cleanup(preparation))
  fail("fixture did not terminate")
}

///|
test "Delta apply respects each admitted poll quantum" {
  let preparation = prepare_fixture_apply(
    delta_fixture_storage(false),
    delta_fixture_expected(),
  )
  for poll_index in 0..<100000 {
    let poll = advance_apply(preparation, 1).unwrap()
    let (work, terminal) = match poll {
      ApplyContinue(work~, ..) => (work, false)
      ApplyComplete(_, work~, ..) => (work, true)
      ApplyFailed(issue, ..) => {
        debug_inspect(issue)
        fail("fixture failed before completion")
      }
    }
    if work < 0 || work > 1 {
      let phase = if preparation.phase == ApplyNodes {
        "ApplyNodes"
      } else {
        "other"
      }
      assert_true(cleanup_apply(preparation))
      fail("poll \{poll_index}: phase=\{phase}, actual work=\{work}, quantum=1")
    }
    if terminal {
      assert_true(cleanup_apply(preparation))
      return
    }
  }
  assert_true(cleanup_apply(preparation))
  fail("fixture did not terminate")
}

///|
/// Isolate the repaired selection/validation stages. The two tests above still
/// require the entire operation, including snapshot framing, to obey quantum.
test "Delta diff selection and output validation respect each poll quantum" {
  let preparation = prepare(
    delta_fixture_storage(false),
    delta_fixture_storage(true),
    json_contract(),
    @graph_contract.cid(delta_fixture_contract()),
    delta_fixture_limits(),
  ).unwrap()
  while preparation.phase == SnapshotLeft || preparation.phase == SnapshotRight {
    guard advance(preparation, 1) is Ok(Continue(..)) else {
      fail("fixture snapshot preparation failed")
    }
  }
  assert_true(preparation.phase == Nodes)
  for _ in 0..<100000 {
    match advance(preparation, 1).unwrap() {
      Continue(work~, ..) => assert_true(work >= 0 && work <= 1)
      Complete(result, work~, ..) => {
        assert_true(work >= 0 && work <= 1)
        assert_eq(delta_wire(value(result)), delta_fixture_expected())
        assert_true(cleanup(preparation))
        return
      }
      Failed(issue, ..) => {
        debug_inspect(issue)
        fail("selection or output validation failed")
      }
    }
  }
  assert_true(cleanup(preparation))
  fail("fixture did not terminate")
}

///|
test "Delta diff cancellation drops a pending action without publishing" {
  let base = delta_fixture_storage(false)
  let target = delta_fixture_storage(true)
  let preparation = prepare(
    base,
    target,
    json_contract(),
    @graph_contract.cid(delta_fixture_contract()),
    delta_fixture_limits(),
  ).unwrap()
  for _ in 0..<100000 {
    guard advance(preparation, 1) is Ok(Continue(..)) else {
      fail("fixture completed before its pending action")
    }
    if preparation.action is Some(action) {
      assert_true(action.usage is None)
      assert_true(cleanup(preparation))
      assert_true(preparation.action is None)
      assert_true(preparation.comparison_recheck is None)
      assert_true(preparation.output_recheck is None)
      assert_true(advance(preparation, 1) is Err(Terminal))
      assert_true(cleanup(preparation))
      assert_eq(@storage.node_count(base), 3)
      assert_eq(@storage.edge_count(target), 2)
      return
    }
  }
  assert_true(cleanup(preparation))
  fail("fixture did not create a pending action")
}

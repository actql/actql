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
    let phase_before_poll = preparation.phase
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
      let phase = if phase_before_poll == AppendRecord {
        "AppendRecord"
      } else if phase_before_poll == ValidateBefore {
        "ValidateBefore"
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
  while preparation.phase == SnapshotLeft ||
        preparation.phase == SnapshotRight ||
        preparation.phase == ReadLeftBody ||
        preparation.phase == ReadRightBody {
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

///|
test "Delta snapshot framing cancellation releases every active data owner" {
  for stopped_phase in [ParseBody, DecodeBody, AdmitBody] {
    let base = delta_fixture_storage(false)
    let target = delta_fixture_storage(true)
    let preparation = prepare(
      base,
      target,
      json_contract(),
      @graph_contract.cid(delta_fixture_contract()),
      delta_fixture_limits(),
    ).unwrap()
    let mut body : BodyAdmission? = None
    for _ in 0..<100000 {
      guard advance(preparation, 1) is Ok(Continue(work~, ..)) else {
        fail("fixture completed before the requested cancellation boundary")
      }
      assert_true(work > 0 && work <= 1)
      if preparation.body_admission is Some(active) {
        let reached = match (stopped_phase, active.phase) {
          (ParseBody, ParseBody)
          | (DecodeBody, DecodeBody)
          | (AdmitBody, AdmitBody) => true
          _ => false
        }
        if reached {
          body = Some(active)
          break
        }
      }
    }
    let active = body.unwrap()
    assert_true(cleanup(preparation))
    assert_true(cleanup(preparation))
    assert_true(preparation.body_admission is None)
    assert_true(active.parser is None)
    assert_true(active.source_node is None)
    assert_true(active.decoder is None)
    assert_true(active.decoded is None)
    assert_true(active.admission is None)
    assert_true(active.chunks.is_empty())
    assert_eq(active.chunks.capacity(), 0)
    assert_eq(preparation.chunks.capacity(), 0)
    assert_true(active.phase is BodyFinished)
    assert_true(advance(preparation, 1) is Err(Terminal))
    assert_eq(@storage.node_count(base), 3)
    assert_eq(@storage.edge_count(target), 2)
  }
}

///|
test "Delta snapshot framing retires streamed backing before body parsing" {
  let base = delta_fixture_storage(false)
  let target = delta_fixture_storage(true)
  let preparation = prepare(
    base,
    target,
    json_contract(),
    @graph_contract.cid(delta_fixture_contract()),
    delta_fixture_limits(),
  ).unwrap()
  let mut body : BodyAdmission? = None
  for _ in 0..<100000 {
    guard advance(preparation, 1) is Ok(Continue(work~, ..)) else {
      fail("fixture completed before body parsing")
    }
    assert_true(work > 0 && work <= 1)
    if preparation.body_admission is Some(active) && active.phase is StartBody {
      assert_true(active.chunks.length() > 0)
      assert_true(active.chunks.capacity() > 0)
      body = Some(active)
      break
    }
  }
  let active = body.unwrap()
  assert_true(advance(preparation, 1) is Ok(Continue(work=1, ..)))
  assert_true(active.phase is ParseBody)
  assert_true(active.parser is Some(_))
  // Joining transfers wire text to the existing parser. Merely setting the
  // chunk-table length to zero leaves its backing/removed references on non-JS.
  assert_eq(active.chunks.capacity(), 0)
  assert_eq(preparation.chunks.capacity(), 0)
  assert_true(cleanup(preparation))
  assert_true(cleanup(preparation))
  assert_eq(active.chunks.capacity(), 0)
  assert_eq(preparation.chunks.capacity(), 0)
  assert_eq(@storage.node_count(base), 3)
  assert_eq(@storage.edge_count(target), 2)
}

///|
test "Delta apply snapshot framing retires backing across body cancellation" {
  for stopped_phase in [StartBody, ParseBody, DecodeBody, AdmitBody] {
    let base = delta_fixture_storage(false)
    let preparation = prepare_fixture_apply(base, delta_fixture_expected())
    let mut body : BodyAdmission? = None
    for _ in 0..<100000 {
      assert_true(
        advance_apply(preparation, 1) is Ok(ApplyContinue(work=1, ..)),
      )
      if preparation.body_admission is Some(active) {
        let reached = match (stopped_phase, active.phase) {
          (StartBody, StartBody)
          | (ParseBody, ParseBody)
          | (DecodeBody, DecodeBody)
          | (AdmitBody, AdmitBody) => true
          _ => false
        }
        if reached {
          if stopped_phase is StartBody {
            assert_true(active.chunks.capacity() > 0)
          } else {
            assert_eq(active.chunks.capacity(), 0)
          }
          body = Some(active)
          break
        }
      }
    }
    let active = body.unwrap()
    assert_true(cleanup_apply(preparation))
    assert_true(cleanup_apply(preparation))
    assert_true(preparation.body_admission is None)
    assert_eq(active.chunks.capacity(), 0)
    assert_eq(preparation.chunks.capacity(), 0)
    assert_true(active.parser is None)
    assert_true(active.source_node is None)
    assert_true(active.decoder is None)
    assert_true(active.decoded is None)
    assert_true(active.admission is None)
    assert_true(active.phase is BodyFinished)
    assert_true(advance_apply(preparation, 1) is Err(Terminal))
    assert_eq(@storage.node_count(base), 3)
    assert_eq(@storage.edge_count(base), 2)
  }
}

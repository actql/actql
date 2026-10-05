///|
test "Delta action admission does not traverse identities before the first poll" {
  let base = delta_fixture_storage(false)
  let apply = start_apply(
    base,
    delta_cursor(delta_fixture_expected()),
    delta_fixture_limits(),
    storage_limits(),
  ).unwrap()
  assert_true(apply.phase == AdmitNodeActions)
  assert_true(apply.nodes.add.is_empty())
  assert_true(apply.nodes.remove.is_empty())
  assert_true(apply.nodes.update.is_empty())
  assert_true(apply.edges.add.is_empty())
  assert_true(apply.builder is None)
  assert_true(advance_apply(apply, 1) is Ok(ApplyContinue(work=1, progress=0)))
  assert_true(apply.nodes.add.is_empty())
  assert_true(apply.node_admission.unwrap().phase is SelectAction)
  assert_true(cleanup_apply(apply))
  assert_true(apply.node_admission is None && apply.edge_admission is None)
  assert_eq(@storage.node_count(base), 3)
}

///|
test "Delta resumed action admission preserves result and quantum-independent work" {
  let mut expected_work = None
  for quantum in [1, 7, 64] {
    let base = delta_fixture_storage(false)
    let apply = start_apply(
      base,
      delta_cursor(delta_fixture_expected()),
      delta_fixture_limits(),
      storage_limits(),
    ).unwrap()
    let mut work = 0L
    let mut result = None
    for _ in 0..<100000 {
      let poll = advance_apply(apply, quantum).unwrap()
      let used = match poll {
        ApplyContinue(work~, ..) => work
        ApplyComplete(storage, work~, ..) => {
          result = Some(storage)
          work
        }
        ApplyFailed(_, ..) => abort("resumed action fixture failed")
      }
      assert_true(used > 0 && used <= quantum.to_int64())
      work += used
      if result is Some(_) {
        break
      }
    }
    if expected_work is Some(expected) {
      assert_eq(work, expected)
    } else {
      expected_work = Some(work)
    }
    let result = result.unwrap()
    assert_eq(delta_snapshot_wire(result), delta_expected_target_snapshot())
    assert_true(cleanup_apply(apply))
    assert_eq(@storage.node_count(result), 3)
    @storage.discard(result)
    @storage.discard(base)
  }
}

///|
test "Delta resumed action rejection preserves synchronous validation rules" {
  let base = delta_fixture_storage(false)
  let invalid = [
    delta_fixture_expected().replace_all(old="\"key\":[11]", new="\"key\":[10]"),
    delta_fixture_expected().replace_all(
      old="},\"key\":[3],\"props\"",
      new="},\"props\"",
    ),
    delta_fixture_expected().replace_all(
      old="\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]},\"key\":[1],\"props\":{\"score\":null}",
      new="\"key\":[99],\"key_types\":[{\"kind\":\"number\"}]},\"key\":[1],\"props\":{\"score\":null}",
    ),
  ]
  for text in invalid {
    assert_true(text != delta_fixture_expected())
    assert_true(
      prepare_apply(
        base,
        delta_cursor(text),
        delta_fixture_limits(),
        storage_limits(),
      )
      is Err(InvalidDelta),
    )
    let apply = start_apply(
      base,
      delta_cursor(text),
      delta_fixture_limits(),
      storage_limits(),
    ).unwrap()
    let mut failed = false
    for _ in 0..<100000 {
      match advance_apply(apply, 1).unwrap() {
        ApplyContinue(work~, progress~) => {
          assert_eq(work, 1)
          assert_eq(progress, 0)
        }
        ApplyFailed(issue, work~, progress~) => {
          assert_eq(issue, InvalidDelta)
          assert_eq(work, 1)
          assert_eq(progress, 0)
          failed = true
          break
        }
        ApplyComplete(_, ..) => abort("invalid actions published a Graph")
      }
    }
    assert_true(failed)
    assert_true(apply.builder is None && apply.result is None)
    assert_true(cleanup_apply(apply))
    assert_true(advance_apply(apply, 1) is Err(Terminal))
    assert_eq(@storage.node_count(base), 3)
    assert_eq(@storage.edge_count(base), 2)
  }
}

///|
test "Delta action admission cleanup releases each active key stage without changing input" {
  for stage in [0, 1, 2, 3] {
    let base = delta_fixture_storage(false)
    let apply = start_apply(
      base,
      delta_cursor(delta_fixture_expected()),
      delta_fixture_limits(),
      storage_limits(),
    ).unwrap()
    let mut entered = false
    for _ in 0..<100000 {
      assert_true(advance_apply(apply, 1) is Ok(ApplyContinue(work=1, ..)))
      let node = apply.node_admission.unwrap()
      let reached = match (stage, node.phase, node.key) {
        (0, SelectAction, _) => true
        (1, ReadActionKey, Some(key)) => key.phase is AdmitActionKey
        (2, ReadActionKey, Some(key)) => key.phase is EmitActionKey
        (3, CommitAction, _) => true
        _ => false
      }
      if reached {
        entered = true
        break
      }
    }
    assert_true(entered)
    let node = apply.node_admission.unwrap()
    let key = node.key
    assert_true(cleanup_apply(apply))
    assert_true(cleanup_apply(apply))
    assert_true(node.key is None && node.array is None)
    assert_true(node.before is None && node.after is None)
    assert_true(node.seen.is_empty())
    if key is Some(key) {
      assert_true(
        key.admission is None && key.emitter is None && key.writer is None,
      )
    }
    assert_true(apply.nodes.add.is_empty() && apply.edges.add.is_empty())
    assert_eq(@storage.node_count(base), 3)
    assert_eq(@storage.edge_count(base), 2)
    @storage.discard(base)
  }
}

///|
test "Delta resumed action admission rechecks the borrowed Graph before every poll" {
  for boundary in [AdmitNodeActions, AdmitEdgeActions] {
    let (view, completed, live) = delta_fixture_view()
    let apply = start_apply_view(
      view,
      @graph_contract.graph(delta_fixture_contract()),
      delta_cursor(delta_fixture_expected()),
      delta_fixture_limits(),
      storage_limits(),
    ).unwrap()
    let mut reached = false
    for _ in 0..<100000 {
      if apply.phase == boundary {
        reached = true
        break
      }
      assert_true(
        advance_apply(apply, 1) is Ok(ApplyContinue(work=1, progress=0)),
      )
    }
    assert_true(reached)
    live.val = false
    assert_true(
      advance_apply(apply, 1)
      is Ok(ApplyFailed(Snapshot(@snapshot.InvalidGraph), progress=0, work=0)),
    )
    assert_true(apply.builder is None && apply.result is None)
    assert_true(cleanup_apply(apply))
    assert_true(apply.node_admission is None && apply.edge_admission is None)
    assert_true(@graph_runtime.discard_completed(completed))
  }
}

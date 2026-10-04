///|
fn delta_expected_target_snapshot() -> String {
  (
    #|["actql-property-graph-snapshot/0.1","sha256:a8248c5cd6d92997c058bdb9794747453581acd6336746b92b1779290e544443",{"domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","edge_definitions":[{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Link":[]},"name":"E","properties":{},"source_definition":"N","target_definition":"N"}],"identity_law_cid":"sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc","node_definitions":[{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Other":[]},"name":"M","properties":{}},{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Node":["score"]},"name":"N","properties":{"score":{"nullable":true,"type":"number"}}}],"value_law_cid":"sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc","version":"actql-property-graph-contract/0.1"},[{"id":{"definition":"M","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[1],"key_types":[{"kind":"number"}]},"key":[1],"props":{}},{"id":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[1],"key_types":[{"kind":"number"}]},"key":[1],"props":{"score":null}},{"id":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[3],"key_types":[{"kind":"number"}]},"key":[3],"props":{"score":9}}],[{"dst":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[3],"key_types":[{"kind":"number"}]},"id":{"definition":"E","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[10],"key_types":[{"kind":"number"}]},"key":[10],"props":{},"src":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[1],"key_types":[{"kind":"number"}]}},{"dst":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[3],"key_types":[{"kind":"number"}]},"id":{"definition":"E","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[12],"key_types":[{"kind":"number"}]},"key":[12],"props":{},"src":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[1],"key_types":[{"kind":"number"}]}}]]
  )
}

///|
fn complete_apply(
  value : ApplyPreparation,
  quantum : Int,
) -> @storage.Storage raise {
  for _ in 0..<100000 {
    match advance_apply(value, quantum).unwrap() {
      ApplyContinue(..) => ()
      ApplyComplete(storage, ..) => return storage
      ApplyFailed(issue, ..) => {
        debug_inspect(issue)
        fail("apply failed")
      }
    }
  }
  fail("apply did not complete")
}

///|
fn apply_failure_issue(value : ApplyPreparation) -> Issue raise {
  for _ in 0..<100000 {
    match advance_apply(value, 1).unwrap() {
      ApplyContinue(..) => ()
      ApplyComplete(_, ..) => fail("invalid Delta published a Graph")
      ApplyFailed(issue, ..) => return issue
    }
  }
  fail("apply did not terminate")
}

///|
fn delta_snapshot_wire(storage : @storage.Storage) -> String raise {
  let preparation = @snapshot.prepare_property(
    storage,
    snapshot_limits(delta_fixture_limits()),
  ).unwrap()
  let chunks = []
  for _ in 0..<100000 {
    let poll = @snapshot.advance(preparation, 1).unwrap()
    chunks.push(@snapshot.take_property_output(preparation).unwrap())
    match poll {
      @snapshot.Continue(..) => ()
      @snapshot.Complete(snapshot, ..) => {
        assert_true(@snapshot.cleanup(snapshot))
        return chunks.join("")
      }
    }
  }
  fail("snapshot did not complete")
}

///|
fn prepare_fixture_apply(
  base : @storage.Storage,
  text : String,
) -> ApplyPreparation {
  prepare_apply(
    base,
    delta_cursor(text),
    delta_fixture_limits(),
    storage_limits(),
  ).unwrap()
}

///|
test "property delta apply validates independently authored records and exact target snapshot" {
  let base = delta_fixture_storage(false)
  let preparation = prepare_fixture_apply(base, delta_fixture_expected())
  let result = complete_apply(preparation, 1)
  assert_eq(delta_snapshot_wire(result), delta_expected_target_snapshot())
  assert_eq(@storage.node_count(result), 3)
  assert_eq(@storage.edge_count(result), 2)
  assert_true(advance_apply(preparation, 1) is Err(Terminal))
  assert_true(cleanup_apply(preparation))
  assert_true(cleanup_apply(preparation))
  // Cleanup of the kernel never mutates the transferred immutable result.
  assert_eq(delta_snapshot_wire(result), delta_expected_target_snapshot())
  assert_eq(@storage.node_count(base), 3)
  assert_eq(@storage.edge_count(base), 2)
}

///|
test "property delta diff then apply yields the independent target without tuple collapse" {
  let base = delta_fixture_storage(false)
  let target = delta_fixture_storage(true)
  let preparation = prepare(
    base,
    target,
    json_contract(),
    @graph_contract.cid(delta_fixture_contract()),
    delta_fixture_limits(),
  ).unwrap()
  let delta = complete_diff(preparation, 64)
  let applying = prepare_fixture_apply(base, delta_wire(value(delta)))
  let result = complete_apply(applying, 64)
  assert_eq(delta_snapshot_wire(result), delta_expected_target_snapshot())
  assert_true(cleanup_apply(applying))
  assert_true(cleanup(preparation))
  assert_eq(@storage.edge_count(base), 2)
  assert_eq(@storage.edge_count(target), 2)
}

///|
test "property delta wrong base is rejected before provisional Graph allocation" {
  let target = delta_fixture_storage(true)
  let preparation = prepare_fixture_apply(target, delta_fixture_expected())
  assert_eq(apply_failure_issue(preparation), WrongBase)
  assert_true(preparation.builder is None)
  assert_true(preparation.result is None)
  assert_true(advance_apply(preparation, 1) is Err(Terminal))
  assert_true(cleanup_apply(preparation))
  assert_eq(delta_snapshot_wire(target), delta_expected_target_snapshot())
}

///|
test "property delta rejects retired snapshot identity without format fallback" {
  let base = delta_fixture_storage(false)
  // Node crypto hashes of the independently authored fixture records under the
  // retired four-element domain, not values obtained from product output.
  let retired_base = prepare_fixture_apply(
    base,
    delta_fixture_expected().replace_all(
      old="sha256:c50c44bfeaa72f109a02dd512b22c031c9cd7d9e503fa474a7320e863300e4a8",
      new="sha256:ae28c07f50bb973ce54bf0b6cd21f4809700079a6f3e881e0175a5c8afad976e",
    ),
  )
  assert_eq(apply_failure_issue(retired_base), WrongBase)
  assert_true(retired_base.builder is None)
  assert_true(retired_base.result is None)
  assert_true(cleanup_apply(retired_base))
  let retired_target = prepare_fixture_apply(
    base,
    delta_fixture_expected().replace_all(
      old="sha256:84a3ee72261465a8864d987b0215329de2222270827c7f0436a449ec55ac1e3f",
      new="sha256:427b4161a991848279136a8ac37c688eae5fc8ccdd6887d8ad3d8bdf5cabc8d1",
    ),
  )
  assert_eq(apply_failure_issue(retired_target), TargetMismatch)
  assert_true(advance_apply(retired_target, 1) is Err(Terminal))
  assert_true(cleanup_apply(retired_target))
  assert_true(retired_target.result is None)
  assert_eq(@storage.node_count(base), 3)
  assert_eq(@storage.edge_count(base), 2)
}

///|
test "property delta exact before mismatch and target mismatch publish no partial Graph" {
  let base = delta_fixture_storage(false)
  let wrong_before = prepare_fixture_apply(
    base,
    delta_fixture_expected().replace_all(old="\"score\":7", new="\"score\":8"),
  )
  assert_eq(apply_failure_issue(wrong_before), BeforeMismatch)
  assert_true(advance_apply(wrong_before, 1) is Err(Terminal))
  assert_true(cleanup_apply(wrong_before))
  assert_true(wrong_before.builder is None)
  let wrong_target = prepare_fixture_apply(
    base,
    delta_fixture_expected().replace_all(
      old="sha256:84a3ee72261465a8864d987b0215329de2222270827c7f0436a449ec55ac1e3f",
      new="sha256:" + "0".repeat(64),
    ),
  )
  assert_eq(apply_failure_issue(wrong_target), TargetMismatch)
  assert_true(wrong_target.result is Some(_))
  assert_true(cleanup_apply(wrong_target))
  assert_true(wrong_target.result is None)
  assert_eq(@storage.node_count(base), 3)
  assert_eq(@storage.edge_count(base), 2)
}

///|
test "property delta duplicate actions and old complete record shape are rejected" {
  let base = delta_fixture_storage(false)
  let limits = delta_fixture_limits()
  let duplicate_edge = delta_fixture_expected().replace_all(
    old="\"key\":[11]",
    new="\"key\":[10]",
  )
  assert_true(
    prepare_apply(base, delta_cursor(duplicate_edge), limits, storage_limits())
    is Err(InvalidDelta),
  )
  // Remove only the outer key evidence, leaving the scoped id untouched.
  let old_node = delta_fixture_expected().replace_all(
    old="},\"key\":[3],\"props\"",
    new="},\"props\"",
  )
  assert_true(
    prepare_apply(base, delta_cursor(old_node), limits, storage_limits())
    is Err(InvalidDelta),
  )
  assert_true(
    prepare_apply(
      base,
      delta_cursor(delta_fixture_expected()),
      { ..limits, max_workspace_slots: 0, },
      storage_limits(),
    )
    is Err(WorkspaceLimit),
  )
  assert_eq(@storage.node_count(base), 3)
  assert_eq(@storage.edge_count(base), 2)
}

///|
test "property delta cancellation reclaims provisional builder but leaves the base intact" {
  let base = delta_fixture_storage(false)
  let preparation = prepare_fixture_apply(base, delta_fixture_expected())
  let mut allocated = false
  for _ in 0..<100000 {
    assert_true(advance_apply(preparation, 1) is Ok(ApplyContinue(..)))
    if preparation.builder is Some(builder) &&
      @storage.builder_node_count(builder) > 0 {
      allocated = true
      break
    }
  }
  assert_true(allocated)
  let builder = preparation.builder.unwrap()
  assert_true(@storage.builder_retained_value_bytes(builder) > 0)
  assert_true(cleanup_apply(preparation))
  assert_eq(@storage.builder_retained_value_bytes(builder), 0)
  assert_eq(@storage.builder_workspace_slots(builder), 0)
  assert_true(preparation.builder is None)
  assert_true(advance_apply(preparation, 1) is Err(Terminal))
  assert_true(cleanup_apply(preparation))
  assert_eq(@storage.node_count(base), 3)
  assert_eq(@storage.edge_count(base), 2)
}

///|
test "property delta failed append preserves the existing builder work report" {
  let base = delta_fixture_storage(false)
  // The outer key disagrees with the admitted identity. Parsing the Delta is
  // not permission to replace the Graph owner's identity/key validation.
  let malformed = delta_fixture_expected().replace_all(
    old="},\"key\":[3],\"props\"",
    new="},\"key\":[4],\"props\"",
  )
  let preparation = prepare_fixture_apply(base, malformed)
  let mut reached_append = false
  for _ in 0..<100000 {
    if preparation.phase == ApplyNodes && preparation.base_cursor == 3 {
      reached_append = true
      break
    }
    assert_true(advance_apply(preparation, 1) is Ok(ApplyContinue(..)))
  }
  assert_true(reached_append)
  let builder = preparation.builder.unwrap()
  let before = @storage.builder_construction_work(builder)
  guard advance_apply(preparation, 1)
    is Ok(ApplyFailed(Storage(InvalidIdentity), work~, ..)) else {
    fail("identity mismatch did not fail at the existing Graph owner")
  }
  let actual_work = @storage.builder_construction_work(builder) - before
  assert_true(actual_work > 0)
  assert_true(work >= actual_work.to_int64())
  assert_true(preparation.result is None)
  assert_true(advance_apply(preparation, 1) is Err(Terminal))
  assert_true(cleanup_apply(preparation))
  assert_true(cleanup_apply(preparation))
  assert_eq(@storage.builder_retained_value_bytes(builder), 0)
  assert_eq(@storage.node_count(base), 3)
}

///|
test "property delta storage budget failure retains work and cleanup custody" {
  let base = delta_fixture_storage(false)
  let preparation = prepare_apply(
    base,
    delta_cursor(delta_fixture_expected()),
    delta_fixture_limits(),
    { ..storage_limits(), max_work: 1, },
  ).unwrap()
  for _ in 0..<100000 {
    if preparation.phase == ApplyNodes {
      break
    }
    assert_true(advance_apply(preparation, 1) is Ok(ApplyContinue(..)))
  }
  assert_true(preparation.phase == ApplyNodes)
  let builder = preparation.builder.unwrap()
  let before = @storage.builder_construction_work(builder)
  guard advance_apply(preparation, 1)
    is Ok(ApplyFailed(Storage(WorkLimit), work~, ..)) else {
    fail("provisional storage work limit did not reject")
  }
  let actual_work = @storage.builder_construction_work(builder) - before
  assert_eq(actual_work, 1)
  assert_true(work >= actual_work.to_int64())
  assert_true(preparation.builder is Some(_))
  assert_true(preparation.result is None)
  assert_true(cleanup_apply(preparation))
  assert_eq(@storage.builder_workspace_slots(builder), 0)
  assert_true(advance_apply(preparation, 1) is Err(Terminal))
  assert_eq(@storage.node_count(base), 3)
}

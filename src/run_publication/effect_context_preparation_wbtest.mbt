///|
fn context_test_body() -> String {
  let body =
    #|{"authoring_context":{"k":7},"effect_dependency_inventory":[],"effect_plan_logical_cids":{},"effect_plans":{},"effect_source_artifacts":{},"effect_source_holding_cids":{},"effect_source_local_inventory":{},"effects":{},"model_invocation_evidence":[],"model_invocation_evidence_cids":[],"pending_source_state_advances":[],"result_artifacts":{},"result_fields":{},"result_values":{},"version":"actql-run-effect-context/0.1"}
  body
}

///|
fn context_test_start(
  snapshots? : Array[CapturedResultSnapshot] = [],
  bytes? : Int = 10000,
  nodes? : Int = 1000,
  depth? : Int = 16,
  workspace? : Int = 10000,
) -> EffectContextPreparation {
  let authoring : RunEvidenceValue = {
    name: "authoring_context",
    identity: "authoring",
    wire: "{\"k\":7}",
    wire_usage: None, // This private fixture is not an admitted bound witness.
    value: parse_contract_wire("{\"k\":7}", 10000, 1000, 16).unwrap(),
  }
  start_effect_context_preparation(
    snapshots,
    [],
    [],
    { bodies: [], wire: "[]", },
    [],
    authoring,
    [],
    None,
    [],
    bytes,
    nodes,
    depth,
    workspace,
  ).unwrap()
}

///|
fn context_test_finish(
  preparation : EffectContextPreparation,
  quantum : Int,
) -> Result[(@json.CanonicalValue, Int), CapturedRunIssuanceIssue] raise {
  let mut total = 0
  for _ in 0..<100000 {
    match preparation.advance(quantum) {
      Err(issue) => return Err(issue)
      Ok((done, used)) => {
        assert_true(used <= quantum)
        total += used
        if done {
          return preparation.finish().map(value => (value, total))
        }
        assert_true(used > 0)
      }
    }
  }
  fail("context preparation did not terminate")
}

///|
test "Effect context preparation keeps the independent preimage and quantum work" {
  let body = context_test_body()
  let identity = "sha256:" + @sha.text_hex(body).unwrap()
  let expected = body.replace(
    old=",\"effect_dependency_inventory\"",
    new=",\"effect_context_cid\":\"" +
      identity +
      "\",\"effect_dependency_inventory\"",
  )
  let mut work = None
  for quantum in [1, 7, 64] {
    let preparation = context_test_start()
    assert_true(preparation.finish() is Err(CaptureIssuanceEncoding))
    let (value, used) = context_test_finish(preparation, quantum).unwrap()
    assert_eq(@json.stringify_value(value, 10000, 1000, 16), expected)
    if work is Some(previous) {
      assert_eq(used, previous)
    }
    work = Some(used)
    assert_eq(preparation.live, 0)
    assert_true(preparation.inputs is None)
    assert_true(preparation.finish() is Err(CaptureIssuanceEncoding))
    preparation.cancel()
    assert_eq(
      optional_string(@json.object_field(value, "effect_context_cid")),
      Some(identity),
    )
  }
}

///|
test "Effect context preparation enforces exact writer and control workspace bounds" {
  // Independent ASCII body: 17 nodes and two container levels. The 12 fixed
  // control entries overlap three canonical frames plus one growth reserve.
  let bytes = context_test_body().length()
  let exact = context_test_start(bytes~, nodes=17, depth=2, workspace=16)
  ignore(context_test_finish(exact, 1).unwrap())
  assert_eq(exact.peak, 16)
  for
    preparation in [
      context_test_start(bytes=bytes - 1),
      context_test_start(nodes=16),
      context_test_start(depth=1),
      context_test_start(workspace=15),
    ] {
    assert_true(
      context_test_finish(preparation, 1) is Err(CaptureIssuanceEncoding),
    )
    assert_eq(preparation.live, 0)
    assert_true(preparation.inputs is None)
    assert_true(preparation.writer is None)
  }
}

///|
test "Effect context cancellation inside emitted Text keeps the original snapshot" {
  let wire = "[{\"s\":\"" + String::make(257, 'é') + "e\u0301\\r\\n😀\"}]"
  let snapshot = snapshot_admission_finish(
    snapshot_admission_fixture(wire, ["s"], 1),
    1,
  ).unwrap()
  let snapshots = [snapshot]
  let preparation = context_test_start(snapshots~)
  let mut start = None
  let mut reached = false
  for _ in 0..<10000 {
    ignore(preparation.advance(1).unwrap())
    if preparation.phase is Value(_) &&
      preparation.continuation is Some(SectionNext(13, 1)) {
      let (bytes, _, _) = @json.material_progress(preparation.material.unwrap())
      match start {
        None => start = Some(bytes)
        Some(before) =>
          if bytes >= before + 64 {
            reached = true
            break
          }
      }
    }
  }
  assert_true(reached)
  preparation.cancel()
  preparation.cancel()
  assert_eq(preparation.live, 0)
  assert_true(preparation.inputs is None)
  assert_true(preparation.advance(1) is Err(CaptureIssuanceEncoding))
  assert_true(preparation.finish() is Err(CaptureIssuanceEncoding))
  assert_eq(snapshots.length(), 1)
  assert_eq(snapshot.fields, ["s"])
  assert_eq(@json.stringify_value(snapshot.rows, 10000, 1000, 16), wire)
}

///|
test "Effect context cancellation retires emission parsing admission and hashing" {
  let mut phases = (false, false, false, false, false)
  // The dependency envelope still uses actual parse/admission phases. The
  // assembled outer body no longer enters those phases.
  for wanted in 0..<5 {
    let preparation = context_test_start()
    let mut reached = false
    for _ in 0..<10000 {
      ignore(preparation.advance(1).unwrap())
      let matches = match (wanted, preparation.phase) {
        (0, Value(_)) => true
        (1, Parse(_, false)) => true
        (2, Decode(_, false)) => true
        (3, Canonical(_, false)) => true
        (4, Hash(_)) => true
        _ => false
      }
      if matches {
        reached = true
        break
      }
    }
    assert_true(reached)
    preparation.cancel()
    assert_true(preparation.writer is None)
    assert_true(preparation.value is None)
    assert_true(preparation.sorted is None)
    assert_eq(preparation.live, 0)
    phases = match wanted {
      0 => (true, phases.1, phases.2, phases.3, phases.4)
      1 => (phases.0, true, phases.2, phases.3, phases.4)
      2 => (phases.0, phases.1, true, phases.3, phases.4)
      3 => (phases.0, phases.1, phases.2, true, phases.4)
      _ => (phases.0, phases.1, phases.2, phases.3, true)
    }
  }
  assert_eq(phases, (true, true, true, true, true))
}

///|
test "Effect context sorted IDs retain the original member plan position" {
  // Isolate the private encoding child's position contract. The outer issuer
  // separately admits Preview identity, plan contents and source inventories.
  let preview = {
    ..effect_receipt_test_two_member_preview(),
    member_effect_ids: ["zeta", "alpha"],
    member_effect_plan_cids: [Some(effect_receipt_test_cid("3")), None],
  }
  let authoring : RunEvidenceValue = {
    name: "authoring_context",
    identity: "authoring",
    wire: "{\"k\":7}",
    wire_usage: None, // This private fixture is not an admitted bound witness.
    value: parse_contract_wire("{\"k\":7}", 10000, 1000, 16).unwrap(),
  }
  let plan = parse_contract_wire("{\"k\":9}", 10000, 1000, 16).unwrap()
  let body = context_test_body()
    .replace(
      old="\"effect_plan_logical_cids\":{}",
      new="\"effect_plan_logical_cids\":{\"zeta\":\"" +
        effect_receipt_test_cid("3") +
        "\"}",
    )
    .replace(
      old="\"effect_plans\":{}",
      new="\"effect_plans\":{\"zeta\":{\"k\":9}}",
    )
    .replace(old="\"effects\":{}", new="\"effects\":{\"alpha\":{},\"zeta\":{}}")
  let identity = "sha256:" + @sha.text_hex(body).unwrap()
  let expected = body.replace(
    old=",\"effect_dependency_inventory\"",
    new=",\"effect_context_cid\":\"" +
      identity +
      "\",\"effect_dependency_inventory\"",
  )
  let mut work = None
  for quantum in [1, 7, 64] {
    let preparation = start_effect_context_preparation(
      [],
      [],
      [],
      { bodies: [], wire: "[]", },
      [],
      authoring,
      [],
      Some(preview),
      [("zeta", plan)],
      10000,
      1000,
      16,
      10000,
    ).unwrap()
    let (value, used) = context_test_finish(preparation, quantum).unwrap()
    assert_eq(@json.stringify_value(value, 10000, 1000, 16), expected)
    if work is Some(previous) {
      assert_eq(used, previous)
    }
    work = Some(used)
    assert_eq(preparation.live, 0)
    assert_true(preparation.sorted is None)
  }
  assert_eq(preview.member_effect_ids, ["zeta", "alpha"])
  assert_eq(preview.member_effect_plan_cids, [
    Some(effect_receipt_test_cid("3")),
    None,
  ])
}

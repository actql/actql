///|
fn ordered_inventory_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn ordered_inventory_contract(
  name : String,
  digit : String,
) -> PublicationContract {
  {
    name,
    identity_field: "self_cid",
    wire_usage: None,
    identity: ordered_inventory_cid(digit),
    wire: "{}",
    value: stream_fixture_value("{}"),
  }
}

///|
fn ordered_inventory_snapshot_fixture(
  names : Array[String],
) -> CapturedOrderedInventoryInput {
  let definition = ordered_inventory_contract("result_definition", "1")
  let artifact = ordered_inventory_contract("result_artifact", "2")
  // Isolated ordering/membership fixture, not a complete admitted Run.
  // Membership retains the previous existence rule; root admission is separate.
  let snapshots = names.map(name => {
    let rows = stream_fixture_value("[{\"value\":7}]")
    let writer = @encode.measuring_writer(64, 16, 8) catch {
      _ => abort("Invalid ordering fixture extent")
    }
    @json.emit_value(rows, writer) catch {
      _ => abort("Invalid ordering fixture rows")
    }
    let (row_wire_bytes, row_nodes, row_depth) = @encode.finish_measurement_usage(
      writer,
    ) catch {
      _ => abort("Invalid ordering fixture measurement")
    }
    {
      name,
      definition,
      artifact,
      rows,
      fields: ["value"],
      row_wire_bytes,
      row_nodes,
      row_depth,
    }
  })
  Snapshots(names.map(_ => definition), names.map(_ => artifact), snapshots)
}

///|
fn ordered_inventory_model_fixture() -> CapturedOrderedInventoryInput {
  // Literal inventory identities isolate ordering, not Model body admission.
  let a : RunEvidenceValue = {
    name: "model_invocation_evidence",
    identity: ordered_inventory_cid("1"),
    wire: "{}",
    value: stream_fixture_value("{}"),
  }
  let b = { ..a, identity: ordered_inventory_cid("2"), }
  let receipt = {
    ..ordered_inventory_contract("run_receipt", "3"),
    value: stream_fixture_value(
      "{\"external_observation_evidence\":[{\"evidence_cid\":\"" +
      b.identity +
      "\",\"kind\":\"model_invocation\"},{\"evidence_cid\":\"" +
      a.identity +
      "\",\"kind\":\"model_invocation\"}]}",
    ),
  }
  Models(receipt, [b, a])
}

///|
fn ordered_inventory_test_refusal(
  input : CapturedOrderedInventoryInput,
  budget : Int,
) -> CapturedRunIssuanceIssue raise {
  let check = start_captured_ordered_inventory(input, budget)
  for _ in 0..<1000 {
    match check.advance(1) {
      Err(issue) => {
        assert_eq(check.live, 0)
        assert_true(check.inputs is None && check.sorted is None)
        assert_true(check.snapshots.is_empty() && check.models.is_empty())
        return issue
      }
      Ok((true, _)) => abort("foreign inventory accepted")
      Ok((false, _)) => ()
    }
  } nobreak {
    abort("inventory did not terminate")
  }
}

///|
test "capture input inventories use independent control and private slot limits" {
  for
    (input, expected_work) in [
      (ordered_inventory_snapshot_fixture(["beta", "alpha"]), 20),
      (ordered_inventory_model_fixture(), 29),
    ] {
    // Two-entry sort: two initializations, prepare, two outputs, swap, finish.
    // Snapshots: Begin + three collects + seven sort polls + three visits
    // + two definition/two Artifact checks + two appends = 20.
    // Models: Begin + three collects + seven sort polls + three visits
    // + three external visits + seven sort polls + five comparisons = 29.
    // Frame twelve + two four-slot tuples/sort indices + two output refs = 22.
    for quantum in [1, 7, 64] {
      let check = start_captured_ordered_inventory(input, 22)
      let mut total = 0
      let mut finished = false
      for _ in 0..<30 {
        let (done, used) = check.advance(quantum).unwrap()
        assert_true(used > 0 && used <= quantum)
        total += used
        if done {
          finished = true
          break
        }
      }
      assert_true(finished)
      assert_eq(total, expected_work)
      assert_eq(check.peak, 22)
      match check.finish().unwrap() {
        OrderedSnapshots(output) => {
          assert_eq(output.map(snapshot => snapshot.name), ["alpha", "beta"])
          assert_eq(stream_fixture_wire(output[0].rows), "[{\"value\":7}]")
          guard input is Snapshots(_, _, borrowed) else { abort("wrong input") }
          assert_eq(borrowed.map(snapshot => snapshot.name), ["beta", "alpha"])
        }
        OrderedModels(output) => {
          assert_eq(output.map(model => model.identity), [
            ordered_inventory_cid("1"),
            ordered_inventory_cid("2"),
          ])
          guard input is Models(_, borrowed) else { abort("wrong input") }
          assert_eq(borrowed.map(model => model.identity), [
            ordered_inventory_cid("2"),
            ordered_inventory_cid("1"),
          ])
        }
      }
      assert_eq(check.live, 0)
    }
    assert_eq(
      ordered_inventory_test_refusal(input, 21),
      CaptureIssuanceEncoding,
    )
  }
  let empty_receipt = {
    ..ordered_inventory_contract("run_receipt", "3"),
    value: stream_fixture_value("{\"external_observation_evidence\":[]}"),
  }
  for
    (input, work) in [
      (Snapshots([], [], []), 4),
      (Models(empty_receipt, []), 7),
    ] {
    let check = start_captured_ordered_inventory(input, 12)
    let mut total = 0
    for _ in 0..<8 {
      let (done, used) = check.advance(1).unwrap()
      total += used
      if done {
        break
      }
    }
    assert_eq(total, work)
    assert_eq(check.peak, 12)
    let _ = check.finish().unwrap()
    assert_eq(
      ordered_inventory_test_refusal(input, 11),
      CaptureIssuanceEncoding,
    )
  }
}

///|
test "capture input inventories retain typed ownership and observation refusals" {
  let input = ordered_inventory_snapshot_fixture(["beta", "alpha"])
  guard input is Snapshots(definitions, artifacts, snapshots) else {
    abort("wrong snapshot fixture")
  }
  assert_eq(
    ordered_inventory_test_refusal(Snapshots([], artifacts, snapshots), 128),
    CaptureIssuanceInventoryMismatch("results"),
  )
  let duplicate = [{ ..snapshots[0], name: "alpha", }, snapshots[1]]
  assert_eq(
    ordered_inventory_test_refusal(
      Snapshots(definitions, artifacts, duplicate),
      128,
    ),
    CaptureIssuanceInventoryMismatch("alpha"),
  )
  let foreign = ordered_inventory_contract("run_definition", "3")
  for
    bad in [
      Snapshots([foreign, foreign], artifacts, snapshots),
      Snapshots(definitions, [foreign, foreign], snapshots),
    ] {
    assert_eq(
      ordered_inventory_test_refusal(bad, 128),
      CaptureIssuanceInventoryMismatch("alpha"),
    )
  }
  guard ordered_inventory_model_fixture() is Models(receipt, models) else {
    abort("wrong Model fixture")
  }
  for
    (bad, issue) in [
      (
        CapturedOrderedInventoryInput::Models(receipt, [models[0], models[0]]),
        CaptureIssuanceInventoryMismatch("model_evidence"),
      ),
      (
        CapturedOrderedInventoryInput::Models(receipt, [
          { ..models[0], name: "authoring_context", },
          models[1],
        ]),
        CaptureIssuanceInventoryMismatch("model_evidence"),
      ),
      (
        CapturedOrderedInventoryInput::Models(receipt, [models[0]]),
        CaptureIssuanceReferenceMismatch("model_evidence"),
      ),
      (
        CapturedOrderedInventoryInput::Models(
          { ..receipt, value: stream_fixture_value("{}"), },
          models,
        ),
        CaptureIssuanceReferenceMismatch("external_observations"),
      ),
      (
        CapturedOrderedInventoryInput::Models(
          {
            ..receipt,
            value: stream_fixture_value(
              "{\"external_observation_evidence\":[{\"kind\":\"model_invocation\"}]}",
            ),
          },
          models,
        ),
        CaptureIssuanceReferenceMismatch("external_observations"),
      ),
      (
        CapturedOrderedInventoryInput::Models(
          {
            ..receipt,
            value: stream_fixture_value(
              "{\"external_observation_evidence\":[{\"evidence_cid\":\"" +
              models[0].identity +
              "\",\"kind\":\"model_invocation\"},{\"evidence_cid\":\"" +
              models[0].identity +
              "\",\"kind\":\"model_invocation\"}]}",
            ),
          },
          models,
        ),
        CaptureIssuanceReferenceMismatch("model_evidence"),
      ),
    ] {
    assert_eq(ordered_inventory_test_refusal(bad, 128), issue)
  }
}

///|
test "capture input inventories cancel inside sorting membership and long-name comparison" {
  let prefix = "é".repeat(257) + "😀"
  let input = ordered_inventory_snapshot_fixture([prefix + "b", prefix + "a"])
  let complete = start_captured_ordered_inventory(input, 22)
  let mut fragments = 0
  let mut done = false
  for _ in 0..<100 {
    let (finished, _) = complete.advance(1).unwrap()
    if complete.phase is Snapshot(_, offset) && offset > 0 {
      fragments += 1
    }
    if finished {
      done = true
      break
    }
  }
  assert_true(done)
  assert_eq(fragments, 4)
  guard complete.finish() is Ok(OrderedSnapshots(output)) else {
    abort("wrong output")
  }
  assert_eq(output.map(snapshot => snapshot.name), [prefix + "a", prefix + "b"])
  for wanted in [0, 1, 2, 3, 4] {
    let check = start_captured_ordered_inventory(input, 22)
    let mut reached = false
    for _ in 0..<100 {
      let (finished, _) = check.advance(1).unwrap()
      assert_true(!finished)
      let hit = match check.phase {
        Sort(_, false) => wanted == 0 && check.keys.length() == 2
        Snapshot(_, offset) => wanted == 1 && offset >= 128
        Definition(index, _) => wanted == 2 && index == 1
        Artifact(index, _) => wanted == 3 && index == 1
        AppendSnapshot(index) => wanted == 4 && index == 1
        _ => false
      }
      if hit {
        reached = true
        break
      }
    }
    assert_true(reached)
    check.cancel()
    check.cancel()
    assert_eq(check.live, 0)
    assert_true(check.inputs is None && check.sorted is None)
    assert_true(check.snapshots.is_empty())
    guard input is Snapshots(_, _, borrowed) else { abort("wrong input") }
    assert_eq(borrowed.map(snapshot => snapshot.name), [
      prefix + "b",
      prefix + "a",
    ])
  }
  let model_input = ordered_inventory_model_fixture()
  for wanted in [0, 1, 2] {
    let check = start_captured_ordered_inventory(model_input, 22)
    let mut reached = false
    for _ in 0..<30 {
      let (finished, _) = check.advance(1).unwrap()
      assert_true(!finished)
      let hit = match check.phase {
        Model(1) => wanted == 0
        Sort(_, true) => wanted == 1
        Compare(_, offset) => wanted == 2 && offset == 64
        _ => false
      }
      if hit {
        reached = true
        break
      }
    }
    assert_true(reached)
    check.cancel()
    assert_eq(check.live, 0)
    assert_true(check.models.is_empty() && check.keys.is_empty())
  }
}

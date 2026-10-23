///|
fn receipt_original_nominal_inputs() -> ComputationEvidenceInputs {
  // Isolate the final nested comparison; these nominal envelopes do not claim
  // admission of a complete Run. The blackbox case exercises that full chain.
  let receipt = {
    ..snapshot_contract("run_receipt", "fixture", "{\"value\":[1]}"),
    wire_usage: Some((13, 3, 2)),
  }
  let capture = snapshot_contract(
    "captured_run", "fixture", "{\"effect_context\":{},\"receipt\":null}",
  )
  let captured_run = {
    ..capture,
    value: @json.object_with_replaced_fields(capture.value, [
      ("receipt", receipt.value),
    ]).unwrap(),
  }
  {
    run_definition: receipt,
    invocation: receipt,
    definitions: [],
    artifacts: [],
    manifest: receipt,
    receipt,
    captured_run,
    preview: None,
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 32,
  }
}

///|
fn receipt_original_nominal_check(
  inputs : ComputationEvidenceInputs,
) -> ComputationPreludePreparation {
  let check = start_computation_prelude(inputs, 32768)
  check.phase = Capture
  check
}

///|
fn receipt_original_nominal_work(
  inputs : ComputationEvidenceInputs,
  quantum : Int,
) -> (Result[Unit, RunEvidenceChainIssue], Int) {
  let check = receipt_original_nominal_check(inputs)
  let mut work = 0
  for _ in 0..<1000 {
    match check.advance(quantum) {
      Err(issue) => return (Err(issue), work)
      Ok((done, used)) => {
        work += used
        if done {
          check.cancel()
          return (Ok(()), work)
        }
      }
    }
  }
  abort("Finite Receipt comparison did not finish")
}

///|
test "Captured Receipt limits and missing original usage keep stream checks" {
  let inputs = receipt_original_nominal_inputs()
  let cold_value = stream_fixture_value("{\"value\":[1]}")
  let cold = {
    ..inputs,
    captured_run: {
      ..inputs.captured_run,
      value: @json.object_with_replaced_fields(inputs.captured_run.value, [
        ("receipt", cold_value),
      ]).unwrap(),
    },
  }
  assert_false(physical_equal(cold_value, inputs.receipt.value))
  let (_, cold_work) = receipt_original_nominal_work(cold, 1)
  assert_true(cold_work > 1)
  for quantum in [1, 7, 64] {
    assert_eq(receipt_original_nominal_work(inputs, quantum), (Ok(()), 1))
    assert_eq(receipt_original_nominal_work(cold, quantum), (Ok(()), cold_work))
    assert_eq(
      receipt_original_nominal_work(
        { ..inputs, receipt: { ..inputs.receipt, wire_usage: None, }, },
        quantum,
      ),
      (Ok(()), cold_work),
    )
  }
  assert_eq(
    receipt_original_nominal_work(
      { ..inputs, max_wire_bytes: 13, max_nodes: 3, max_depth: 2, },
      1,
    ),
    (Ok(()), 1),
  )
  for (bytes, nodes, depth) in [(12, 3, 2), (13, 2, 2), (13, 3, 1), (0, 3, 2)] {
    let (result, _) = receipt_original_nominal_work(
      { ..inputs, max_wire_bytes: bytes, max_nodes: nodes, max_depth: depth, },
      1,
    )
    assert_eq(result, Err(EvidenceReferenceMismatch("receipt")))
  }
}

///|
test "Captured Receipt changed child refuses and pending cancellation clears aliases" {
  let inputs = receipt_original_nominal_inputs()
  let changed = {
    ..inputs,
    captured_run: {
      ..inputs.captured_run,
      value: @json.object_with_replaced_fields(inputs.captured_run.value, [
        ("receipt", stream_fixture_value("{\"value\":[2]}")),
      ]).unwrap(),
    },
  }
  let (result, _) = receipt_original_nominal_work(changed, 1)
  assert_eq(result, Err(EvidenceReferenceMismatch("receipt")))
  let check = receipt_original_nominal_check(changed)
  assert_eq(check.advance(1).unwrap(), (false, 1))
  guard check.phase is Check(child, _, _) else {
    fail("Changed child must retain the original stream")
  }
  check.cancel()
  check.cancel()
  assert_true(child.closed && child.value is None)
  assert_true(check.inputs is None && check.context is None)
  assert_true(check.advance(1) is Err(EvidenceEncoding))
  assert_true(check.finish() is Err(EvidenceEncoding))
  assert_eq(stream_fixture_wire(inputs.receipt.value), "{\"value\":[1]}")
}

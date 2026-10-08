///|
fn capture_inventory_fixture(
  expected : String,
  values : String,
  fields : String,
  artifacts? : String = expected,
) -> CaptureInventoryInputs {
  {
    context: stream_fixture_value(
      "{\"result_artifacts\":" +
      artifacts +
      ",\"result_fields\":" +
      fields +
      ",\"result_values\":" +
      values +
      "}",
    ),
    manifest_results: stream_fixture_value(expected),
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 32,
  }
}

///|
test "capture inventories use exact canonical streams and independent control limits" {
  let expected = "{\"alpha\":null,\"beta\":null}"
  let inputs = capture_inventory_fixture(
    expected, "{\"alpha\":[],\"beta\":[]}", expected,
  )
  let original = stream_fixture_wire(inputs.context)
  // Two six-transition emitters and six comparisons, plus Begin/Done = 20.
  // Inventory Begin, two (Names + two comparisons + end) and Done = 10.
  // Parent twelve + stream twelve + two 1024 buffers + four pending frames
  // + one provisional emitter slot = 2077.
  for quantum in [1, 7, 64] {
    let check = start_capture_inventory(inputs, 2077)
    let mut work = 0
    let mut done = false
    for _ in 0..<31 {
      let result = check.advance(quantum).unwrap()
      assert_true(result.1 > 0 && result.1 <= quantum)
      work += result.1
      if result.0 {
        done = true
        break
      }
    }
    assert_true(done)
    assert_eq(work, 30)
    assert_eq(check.peak, 2077)
    let (values, fields) = check.finish().unwrap()
    assert_eq(stream_fixture_wire(values), "{\"alpha\":[],\"beta\":[]}")
    assert_eq(stream_fixture_wire(fields), expected)
    assert_eq(check.live, 0)
    assert_true(check.current is None && check.inputs is None)
  }
  let short = start_capture_inventory(inputs, 2076)
  let mut refused = false
  for _ in 0..<31 {
    match short.advance(1) {
      Err(EvidenceInventoryMismatch("captured_result_artifacts")) => {
        refused = true
        break
      }
      Err(_) => abort("unrelated capture inventory refusal")
      Ok((true, _)) => abort("one-short inventory budget accepted")
      Ok((false, _)) => ()
    }
  }
  assert_true(refused)
  assert_eq(short.live, 0)
  assert_eq(stream_fixture_wire(inputs.context), original)
}

///|
test "capture inventories yield on long keys and preserve typed refusal order" {
  let name = "é".repeat(257) + "😀"
  let expected = "{\"" + name + "\":null}"
  let inputs = capture_inventory_fixture(expected, expected, expected)
  let original = stream_fixture_wire(inputs.context)
  let check = start_capture_inventory(inputs, 8192)
  let mut fragments = 0
  let mut done = false
  for _ in 0..<200 {
    let result = check.advance(1).unwrap()
    if check.phase is Compare(_, _, offset) && offset > 0 {
      fragments += 1
    }
    if result.0 {
      done = true
      break
    }
  }
  assert_true(done)
  // Two name inventories with five fragments each retain four offsets.
  assert_eq(fragments, 8)
  let _ = check.finish().unwrap()
  for
    (bad, expected_issue) in [
      (
        capture_inventory_fixture(expected, "{}", "{}", artifacts="{}"),
        EvidenceInventoryMismatch("captured_result_artifacts"),
      ),
      (
        capture_inventory_fixture(expected, "{}", "{}"),
        EvidenceInventoryMismatch("result_values"),
      ),
      (
        capture_inventory_fixture(expected, expected, "{}"),
        EvidenceInventoryMismatch("result_fields"),
      ),
      (
        capture_inventory_fixture(expected, "null", expected),
        EvidenceInventoryMismatch("result_values"),
      ),
      (
        capture_inventory_fixture(expected, "{\"foreign\":null}", expected),
        EvidenceInventoryMismatch("result_values"),
      ),
    ] {
    let check = start_capture_inventory(bad, 8192)
    let mut observed = None
    for _ in 0..<200 {
      match check.advance(1) {
        Err(issue) => {
          observed = Some(issue)
          break
        }
        Ok((true, _)) => abort("foreign capture inventory accepted")
        Ok((false, _)) => ()
      }
    }
    assert_true(observed == Some(expected_issue))
    assert_eq(check.live, 0)
  }
  let missing = @json.object_without_field(inputs.context, "result_values").unwrap()
  let check = start_capture_inventory({ ..inputs, context: missing, }, 8192)
  let mut refused = false
  for _ in 0..<200 {
    match check.advance(1) {
      Err(EvidenceMissingField("result_values")) => {
        refused = true
        break
      }
      Err(_) => abort("unrelated missing capture inventory refusal")
      Ok(_) => ()
    }
  }
  assert_true(refused)
  for phase in [0, 1, 2] {
    let check = start_capture_inventory(inputs, 8192)
    let mut reached = false
    let mut visits = 0
    for _ in 0..<200 {
      let (done, _) = check.advance(1).unwrap()
      assert_true(!done)
      let hit = match check.phase {
        Artifacts(_) => phase == 0
        Compare(section, _, offset) => phase == section + 1 && offset > 0
        _ => false
      }
      if hit {
        visits += 1
      }
      if visits == 2 {
        reached = true
        break
      }
    }
    assert_true(reached)
    check.cancel()
    check.cancel()
    assert_eq(check.live, 0)
    assert_true(
      check.inputs is None && check.values is None && check.current is None,
    )
    assert_true(check.advance(1) is Err(EvidenceEncoding))
    assert_eq(stream_fixture_wire(inputs.context), original)
  }
}

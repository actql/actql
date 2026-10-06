///|
fn before_actual(text : String) -> @value.Value {
  let checked = @value.admit(
    json_contract(),
    delta_cursor(text),
    delta_fixture_limits().value_limits,
  ).unwrap()
  @value.json_payload(checked.value).unwrap()
}

///|
test "Delta complete before equality resumes without wire reserialization" {
  let actual = before_actual("{\"key\":[1],\"props\":{\"p\":null,\"q\":[7,8]}}")
  // Source member order is deliberately different. The complete record is
  // compared by the existing canonical JSON meaning, including explicit NULL.
  for
    (text, expected) in [
      ("{\"props\":{\"q\":[7,8],\"p\":null},\"key\":[1]}", true),
      ("{\"key\":[1],\"props\":{\"q\":[7,8]}}", false),
      ("{\"key\":[1],\"props\":{\"p\":7,\"q\":[7,8]}}", false),
      ("{\"key\":[1],\"props\":{\"p\":null,\"q\":[7,9]}}", false),
    ] {
    let check = start_before(delta_cursor(text), actual, delta_fixture_limits()).unwrap()
    let mut finished = false
    for _ in 0..<10000 {
      match advance_before(check, 1) {
        BeforeContinue(work~) => assert_true(work > 0 && work <= 1)
        BeforeComplete(work~) => {
          assert_true(work >= 0 && work <= 1)
          assert_true(expected)
          finished = true
          break
        }
        BeforeFailed(issue, work~) => {
          assert_true(work >= 0 && work <= 1)
          assert_true(!expected)
          assert_eq(issue, BeforeMismatch)
          finished = true
          break
        }
      }
    }
    assert_true(finished)
    cleanup_before(check)
  }
}

///|
test "Delta before cancellation drops every active Value continuation" {
  let text = "{\"key\":[1],\"props\":{\"p\":null,\"q\":[7,8]}}"
  for stop in [AdmitBefore, RecheckActual, CompareBefore] {
    let check = start_before(
      delta_cursor(text),
      before_actual(text),
      delta_fixture_limits(),
    ).unwrap()
    let mut reached = false
    for _ in 0..<10000 {
      let at_stop = match (check.phase, stop) {
        (AdmitBefore, AdmitBefore)
        | (RecheckActual, RecheckActual)
        | (CompareBefore, CompareBefore) => true
        _ => false
      }
      if at_stop {
        reached = true
        break
      }
      guard advance_before(check, 1) is BeforeContinue(work~) else {
        fail("before equality ended before the requested cancellation point")
      }
      assert_eq(work, 1)
    }
    assert_true(reached)
    cleanup_before(check)
    cleanup_before(check)
    assert_true(check.actual is None)
    assert_true(check.admission is None)
    assert_true(check.recheck is None)
    assert_true(check.before is None)
    assert_true(check.comparison is None)
    assert_true(advance_before(check, 1) is BeforeFailed(Terminal, work=0))
  }
}

///|
test "Delta Apply before cancellation retains base and releases provisional custody" {
  let base = delta_fixture_storage(false)
  let preparation = prepare_fixture_apply(base, delta_fixture_expected())
  for _ in 0..<100000 {
    if preparation.phase == ValidateBefore {
      let check = preparation.before_admission.unwrap()
      let builder = preparation.builder.unwrap()
      assert_eq(@storage.builder_node_count(builder), 1)
      assert_true(preparation.pending_output is Some(_))
      assert_true(preparation.base_decoded is Some(_))
      assert_true(cleanup_apply(preparation))
      assert_true(cleanup_apply(preparation))
      assert_true(preparation.before_admission is None)
      assert_true(preparation.pending_output is None)
      assert_true(preparation.base_decoded is None)
      assert_true(check.admission is None)
      assert_true(check.actual is None)
      assert_eq(@storage.builder_retained_value_bytes(builder), 0)
      assert_eq(@storage.builder_workspace_slots(builder), 0)
      assert_true(preparation.result is None)
      assert_eq(@storage.node_count(base), 3)
      assert_eq(@storage.edge_count(base), 2)
      return
    }
    assert_true(advance_apply(preparation, 1) is Ok(ApplyContinue(..)))
  }
  assert_true(cleanup_apply(preparation))
  fail("fixture did not reach complete-before validation")
}

///|
// Semantic continuation/callback control on a genuine admitted Content chain.
// This finite local meter is not Resource admission or physical Store evidence;
// original Run numeric ownership has separate Client/Resource controls.
test "metered capture returns its Work segment before each actual Content authorization callback" {
  let active = Ref(false)
  let authorizations = Ref(0)
  let live = Ref(true)
  let (chain, generation) = content_capture_test_chain(live, available=() => {
    if active.val {
      panic()
    }
    authorizations.val += 1
    true
  })
  let original_calls = authorizations.val
  let preparation = content_capture_test_start(chain, [generation])
  let remaining = Ref(2000000)
  let work = fn(units : Int) -> Bool {
    if units < 0 || units > remaining.val {
      return false
    }
    remaining.val -= units
    true
  }
  let mut boundaries = 0
  let mut done = false
  for _ in 0..<200000 {
    if preparation.next_step_requires_reference_callback() {
      let before = authorizations.val
      let budget = remaining.val
      active.val = true
      let blocked = preparation.advance_with_work(256, work)
      active.val = false
      assert_true(blocked is Ok((false, 0)))
      assert_eq(remaining.val, budget)
      assert_eq(authorizations.val, before)
      // The actual callback runs only after that synchronous segment returned.
      done = preparation.advance(1).unwrap().0
      assert_eq(authorizations.val, before + 1)
      boundaries += 1
    } else {
      active.val = true
      let progress = preparation.advance_with_work(256, work)
      active.val = false
      done = progress.unwrap().0
    }
    if done {
      break
    }
  }
  assert_true(done)
  assert_eq(boundaries, 5)
  assert_eq(authorizations.val - original_calls, 5)
  assert_true(remaining.val < 2000000 && remaining.val >= 0)
  let captured = preparation.finish().unwrap()
  assert_eq(captured_content_generation_count(captured), Some(1))
  let ordinary = content_capture_test_finish(
      content_capture_test_start(chain, [generation]),
      256,
    ).unwrap().0
  assert_eq(
    publication_contract_json(captured),
    publication_contract_json(ordinary),
  )
}

///|
test "metered capture refuses exhausted work before a step and never revives the cancelled issuer" {
  let (chain, generation) = content_capture_test_chain(Ref(true))
  let preparation = content_capture_test_start(chain, [generation])
  let remaining = Ref(1)
  let work = fn(units : Int) -> Bool {
    if units < 0 || units > remaining.val {
      return false
    }
    remaining.val -= units
    true
  }
  assert_true(
    preparation.advance_with_work(256, work) is Err(CaptureIssuanceEncoding),
  )
  assert_eq(remaining.val, 0)
  assert_true(
    preparation.advance_with_work(1, work) is Err(CaptureIssuanceEncoding),
  )
  assert_true(preparation.finish() is Err(CaptureIssuanceEncoding))
  assert_true(bound_content_generation_value(generation) is Some(_))
}

///|
test "physical batch export debits every transition before entry and preserves canonical bytes" {
  let stream = physical_batch_fixture(128)
  let charged = Ref(0)
  let text = StringBuilder()
  let mut steps = 0
  for _ in 0..<100 {
    let next = advance_completed_output_export(
      stream,
      7,
      3,
      batch=true,
      before_step=Some(fn() {
        charged.val += 1
        true
      }),
    ).unwrap()
    steps += next.steps
    assert_eq(charged.val, steps)
    if next.batch is Some(part) {
      text.write_string(part)
    }
    if next.complete {
      break
    }
  }
  assert_eq((charged.val, steps), (32, 32))
  let (receipt, tail) = finish_completed_output_export(stream).unwrap()
  text.write_string(tail)
  assert_eq(
    text.to_string(),
    "[{\"n\":1,\"s\":\"é\"},{\"n\":2,\"s\":\"😀\"}]",
  )
  assert_eq(
    receipt.content.cid,
    "sha256:1f3a78f3ede9a4385bbcbf098a3f0fdb9b16dc3e0e8d78f05255682d9c25f3e0",
  )
  cancel_completed_export_receipt(receipt)
}

///|
test "physical batch debit refusal enters no transition and failing admitted work stays spent" {
  for grants in [0, 15, 31] {
    let stream = physical_batch_fixture(128)
    let charged = Ref(0)
    assert_true(
      advance_completed_output_export(
        stream,
        64,
        3,
        batch=true,
        before_step=Some(fn() {
          if charged.val == grants {
            false
          } else {
            charged.val += 1
            true
          }
        }),
      )
      is Err(Admission(CaptureLimit)),
    )
    assert_eq(charged.val, grants)
    assert_eq(completed_output_export_poll_steps(stream), grants)
    assert_true(stream.source is None && stream.pending_row is None)
    cancel_completed_output_export(stream)
    assert_eq(completed_output_export_poll_steps(stream), grants)
    assert_true(finish_completed_output_export(stream) is Err(Closed))
  }
  let stream = physical_batch_fixture(128)
  let charged = Ref(0)
  let mut rejected = false
  for _ in 0..<32 {
    match
      advance_completed_output_export(
        stream,
        1,
        2,
        batch=true,
        before_step=Some(fn() {
          charged.val += 1
          true
        }),
      ) {
      Ok(_) => ()
      Err(Admission(CaptureLimit)) => {
        rejected = true
        assert_eq(completed_output_export_poll_steps(stream), 1)
        break
      }
      Err(_) => fail("unexpected export failure")
    }
  }
  assert_true(rejected && charged.val > 0)
  let spent = charged.val
  cancel_completed_output_export(stream)
  assert_eq(charged.val, spent)
  assert_eq(completed_output_export_poll_steps(stream), 1)
}

///|
test "physical batch debit callback cannot leave revoked or closed source usable" {
  for close in [false, true] {
    let source = export_fixture(capture_fixture())
    let available = Ref(true)
    let restricted = restrict_completed_output(source, fn() { available.val })
    let stream = prepare_completed_output_export(
      restricted,
      2,
      stream_value_limits(),
      row_wire_limits(),
      128,
    ).unwrap()
    let charged = Ref(0)
    assert_true(
      advance_completed_output_export(
        stream,
        32,
        3,
        batch=true,
        before_step=Some(fn() {
          charged.val += 1
          if close {
            cancel_completed_output_export(stream)
          } else {
            available.val = false
          }
          true
        }),
      )
      is Err(Unavailable),
    )
    assert_eq(charged.val, 1)
    assert_eq(completed_output_export_poll_steps(stream), 0)
    assert_true(stream.source is None && stream.pending_row is None)
    assert_true(completed_output_available(source))
  }
}

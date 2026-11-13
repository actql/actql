///|
test "physical batch growth uses measured row demand not the configured ceiling" {
  let stream = physical_batch_fixture(128)
  let requests : Array[Int] = []
  let text = StringBuilder()
  let mut steps = 0
  for _ in 0..<100 {
    let next = advance_completed_output_export(
      stream,
      7,
      3,
      batch=true,
      before_batch_growth=Some(fn(bytes) {
        requests.push(bytes)
        Ok(true)
      }),
    ).unwrap()
    steps += next.steps
    assert_eq(completed_output_export_poll_steps(stream), next.steps)
    if next.batch is Some(part) {
      text.write_string(part)
    }
    if next.complete {
      break
    }
  }
  assert_eq(steps, 32)
  assert_eq(requests.length(), 2)
  assert_true(requests[0] < 128 && requests[1] < 128)
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
test "physical batch byte refusal precedes emission transition and retains measured work" {
  let stream = physical_batch_fixture(128)
  let calls = Ref(0)
  let mut prefix_work = 0
  let mut refused = false
  for _ in 0..<100 {
    let before = @encode.observed_writer_usage(stream.writer).0
    match
      advance_completed_output_export(
        stream,
        1,
        3,
        batch=true,
        before_batch_growth=Some(fn(_bytes) {
          calls.val += 1
          Ok(false)
        }),
      ) {
      Ok(next) => prefix_work += next.steps
      Err(Admission(CaptureLimit)) => {
        assert_eq(completed_output_export_poll_steps(stream), 0)
        assert_eq(@encode.observed_writer_usage(stream.writer).0, before)
        assert_eq(before, 1) // Existing funded array prefix, no row emitted.
        refused = true
        break
      }
      Err(_) => fail("unexpected growth failure")
    }
  }
  assert_true(refused && prefix_work > 0)
  assert_eq(calls.val, 1)
  assert_true(stream.source is None && stream.pending_row is None)
}

///|
test "physical batch growth preserves full first-row bound when the drain hint saturates" {
  let stream = physical_batch_fixture(20)
  let requested = Ref(0)
  assert_true(
    advance_completed_output_export(
      stream,
      64,
      3,
      batch=true,
      before_batch_growth=Some(fn(bytes) {
        requested.val = bytes
        Ok(false)
      }),
    )
    is Err(Admission(CaptureLimit)),
  )
  // This physical row actually fits 20 bytes, but its conservative key hint
  // does not. The hint's earlier partial value cannot fund the row/frame.
  assert_eq(requested.val, 20)
}

///|
test "physical batch only defers definite policy refusal and never retries failed growth" {
  for unknown in [false, true] {
    let stream = physical_batch_fixture(128)
    let calls = Ref(0)
    let text = StringBuilder()
    let mut failed = false
    for _ in 0..<100 {
      match
        advance_completed_output_export(
          stream,
          7,
          3,
          batch=true,
          before_batch_growth=Some(fn(bytes) {
            calls.val += 1
            if bytes <= 40 {
              Ok(true)
            } else if unknown {
              Err(Unavailable)
            } else {
              Ok(false)
            }
          }),
        ) {
        Ok(next) => {
          if next.batch is Some(part) {
            text.write_string(part)
          }
          if next.complete {
            break
          }
        }
        Err(Unavailable) => {
          failed = true
          break
        }
        Err(_) => fail("unexpected batch error")
      }
    }
    if unknown {
      assert_true(failed)
      assert_eq(calls.val, 2)
      assert_true(stream.source is None)
    } else {
      assert_false(failed)
      assert_eq(calls.val, 3)
      let (receipt, tail) = finish_completed_output_export(stream).unwrap()
      text.write_string(tail)
      assert_eq(
        text.to_string(),
        "[{\"n\":1,\"s\":\"é\"},{\"n\":2,\"s\":\"😀\"}]",
      )
      cancel_completed_export_receipt(receipt)
    }
  }
}

///|
test "physical batch growth callback cannot keep revoked or closed original usable" {
  for close in [false, true] {
    for funded in [false, true] {
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
      assert_true(
        advance_completed_output_export(
          stream,
          32,
          3,
          batch=true,
          before_batch_growth=Some(fn(_bytes) {
            if close {
              cancel_completed_output_export(stream)
            } else {
              available.val = false
            }
            Ok(funded)
          }),
        )
        is Err(Unavailable),
      )
      assert_true(stream.source is None && stream.pending_row is None)
      assert_true(completed_output_available(source))
    }
  }
}

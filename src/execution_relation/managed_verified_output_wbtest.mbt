///|
test "installed summary verifier issues one exact bounded receipt" {
  let owner = capture_fixture()
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  let stream = prepare_managed_output_values(
    receiver,
    Step(0),
    2,
    stream_value_limits(),
    100,
    managed_test_measure_limits(),
  ).unwrap()
  let token = Ref(())
  let port = prepare_managed_verified_output_port(stream, (proof : Ref[Unit]) => {
    if !physical_equal(proof, token) {
      None
    } else {
      Some({
        rows: 2,
        columns: [
          {
            rows: 2,
            bytes: 2,
            nodes: 2,
            max_value_bytes: 1,
            null_rows: 0,
            admitted_depth: 10,
          },
        ],
        admission_usage: { nodes: 0, text_bytes: 0, work: 0, },
      })
    }
  }).unwrap()
  assert_true(append_managed_output_values(stream, 1, _ => None) is Err(Closed))
  assert_true(finish_managed_verified_output(port, Ref(())) is Err(Unverified))
  assert_false(cancel_managed_verified_output_port(port))

  let stream = prepare_managed_output_values(
    receiver,
    Step(0),
    2,
    stream_value_limits(),
    100,
    managed_test_measure_limits(),
  ).unwrap()
  let port = prepare_managed_verified_output_port(stream, (proof : Ref[Unit]) => {
    if physical_equal(proof, token) {
      Some({
        rows: 2,
        columns: [
          {
            rows: 2,
            bytes: 2,
            nodes: 2,
            max_value_bytes: 1,
            null_rows: 0,
            admitted_depth: 10,
          },
        ],
        admission_usage: { nodes: 0, text_bytes: 0, work: 0, },
      })
    } else {
      None
    }
  }).unwrap()
  let receipt = finish_managed_verified_output(port, token).unwrap()
  assert_eq(managed_output_value_row_count(receipt), 2)
  assert_eq(managed_output_value_measurement(receipt), (4, 2, 2))
  assert_true(finish_managed_verified_output(port, token) is Err(Closed))
}

///|
test "installed summary verifier rejects inconsistent and oversized facts" {
  for mode in 0..<4 {
    let owner = capture_fixture()
    let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
    let stream = prepare_managed_output_values(
      receiver,
      Step(0),
      2,
      stream_value_limits(),
      100,
      {
        ..managed_test_measure_limits(),
        max_bytes: if mode == 2 {
          1
        } else {
          1000
        },
      },
    ).unwrap()
    let holder : Ref[ManagedVerifiedOutputPort[Unit]?] = Ref(None)
    let port = prepare_managed_verified_output_port(stream, (_ : Unit) => {
      if mode == 0 {
        return None
      }
      if mode == 3 {
        cancel_managed_verified_output_port(holder.val.unwrap()) |> ignore
      }
      Some({
        rows: 2,
        columns: [
          {
            rows: if mode == 1 {
              1
            } else {
              2
            },
            bytes: 2,
            nodes: 2,
            max_value_bytes: 1,
            null_rows: 0,
            admitted_depth: 10,
          },
        ],
        admission_usage: { nodes: 0, text_bytes: 0, work: 0, },
      })
    }).unwrap()
    holder.val = Some(port)
    let result = finish_managed_verified_output(port, ())
    match mode {
      0 => assert_true(result is Err(Unverified))
      1 => assert_true(result is Err(InconsistentFacts))
      2 => assert_true(result is Err(OutputRepresentationRequired))
      _ => assert_true(result is Err(Closed))
    }
    assert_false(stream.open)
  }
}

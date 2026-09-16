///|
test "managed view issuer preserves logical charges and seals independent output" {
  let owner = capture_fixture()
  let live = Ref(true)
  let source = managed_read_fixture(owner, live)
  let receiver = typed_receiver(
    owner, "[{\"select\":[\"n\",\"s\"]},{\"filter\":\"n > 1\"},{\"derive\":{\"copy\":\"s\",\"new\":\"n + 1\"}},{\"sort\":[]},{\"take\":1}]",
  )
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let plan = prepare_managed_view_plan(
    input,
    Array::makei(5, i => row_kernel(receiver, i)),
    1000,
    10000,
    100,
  ).unwrap()
  let producer = prepare_reused_managed_producer_measurement(
    [input],
    Step(4),
    max_rows=2,
    max_value_bytes=100,
    managed_test_measure_limits(),
    1000,
  ).unwrap()
  let stream = prepare_reused_managed_output_values(
    producer,
    stream_value_limits(),
  ).unwrap()
  let retention = prepare_managed_output_retention_port(stream, (
    receipt : ManagedOutputValueReceipt,
  ) => Some((receipt, "independent-output", 14L, fn() { true }))).unwrap()
  let token = Ref(())
  // Test Host issuer: exact proof identity stands for its adopted implementation's
  // completed execution. This is a boundary test, not a backend execution proof.
  let port = prepare_managed_view_output_port(plan, stream, (proof : Ref[Unit]) => {
    if !physical_equal(proof, token) {
      None
    } else {
      let scalar : ManagedColumnMeasurement = {
        rows: 1,
        bytes: 1,
        nodes: 1,
        max_value_bytes: 1,
        null_rows: 0,
        admitted_depth: 10,
      }
      let text = { ..scalar, bytes: 6, max_value_bytes: 6, }
      Some({
        rows: 1,
        columns: [text, scalar, scalar, text],
        admission_usage: { nodes: 0, text_bytes: 0, work: 0, },
      })
    }
  }).unwrap()
  assert_true(append_managed_output_values(stream, 4, _ => None) is Err(Closed))
  assert_true(finish_managed_output_values(stream) is Err(Closed))
  let receipt = finish_managed_view_output(port, token).unwrap()
  assert_eq(managed_output_value_measurement(receipt), (5, 14, 4))
  assert_eq(
    managed_output_value_managed_measurement_usage(receipt),
    Some((11, 26, 8)),
  )
  assert_true(stream.buffer.rows.is_empty())
  assert_eq(receipt.column_maxima, [6, 1, 1, 6])
  let retained = retain_managed_output(retention, receipt).unwrap()
  live.val = false
  assert_true(managed_retained_output_matches(retained, receipt))
  assert_eq(
    managed_retained_output_payload(retained),
    Some("independent-output"),
  )
  assert_true(finish_managed_view_output(port, token) is Err(Closed))
}

///|
test "managed view issuer rejects inconsistent unverified revoked and oversized output" {
  for mode in 0..<6 {
    let owner = capture_fixture()
    let live = Ref(true)
    let source = managed_read_fixture(owner, live)
    let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
    let input = prepare_managed_producer_read(
      receiver, 0, owner, source, 1000, 10000,
    ).unwrap()
    let plan = prepare_managed_view_plan(
      input,
      [row_kernel(receiver, 0)],
      1000,
      10000,
      100,
    ).unwrap()
    let stream = prepare_managed_output_values(
      receiver,
      Step(0),
      2,
      stream_value_limits(),
      100,
      {
        ..managed_test_measure_limits(),
        max_bytes: if mode == 4 {
          1
        } else {
          1000
        },
      },
    ).unwrap()
    let port = prepare_managed_view_output_port(plan, stream, (_ : Unit) => {
      if mode == 0 {
        return None
      }
      if mode == 1 {
        live.val = false
      }
      if mode == 2 {
        cancel_managed_output_values(stream) |> ignore
      }
      Some({
        rows: 2,
        columns: [
          {
            rows: 2,
            bytes: if mode == 3 {
              3
            } else {
              2
            },
            nodes: 2,
            max_value_bytes: 1,
            null_rows: 0,
            admitted_depth: 10,
          },
        ],
        admission_usage: { nodes: 0, text_bytes: 0, work: 0, },
      })
    }).unwrap()
    if mode == 5 {
      assert_true(cancel_managed_view_output_port(port))
      assert_false(cancel_managed_view_output_port(port))
    }
    let result = finish_managed_view_output(port, ())
    match mode {
      0 => assert_true(result is Err(Unverified))
      1 => assert_true(result is Err(ForeignBinding))
      2 | 5 => assert_true(result is Err(Closed))
      3 => assert_true(result is Err(InconsistentFacts))
      _ => assert_true(result is Err(OutputRepresentationRequired))
    }
    assert_false(stream.open)
    assert_eq(stream.measurement.bytes, stream.initial.max_bytes)
    assert_true(finish_managed_view_output(port, ()) is Err(Closed))
  }
}

///|
test "managed view issuer cancellation during verification prevents receipt resurrection" {
  let owner = capture_fixture()
  let source = managed_read_fixture(owner, Ref(true))
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let plan = prepare_managed_view_plan(
    input,
    [row_kernel(receiver, 0)],
    1000,
    10000,
    100,
  ).unwrap()
  let stream = prepare_managed_output_values(
    receiver,
    Step(0),
    2,
    stream_value_limits(),
    100,
    managed_test_measure_limits(),
  ).unwrap()
  let holder : Ref[ManagedViewOutputPort[Unit, Int]?] = Ref(None)
  let foreign = managed_retention_test_stream(owner)
  assert_true(
    prepare_managed_view_output_port(plan, foreign, (_ : Unit) => None)
    is Err(ForeignBinding),
  )
  assert_false(foreign.reading)
  let port = prepare_managed_view_output_port(plan, stream, (_ : Unit) => {
    let current = holder.val.unwrap()
    assert_true(finish_managed_view_output(current, ()) is Err(Closed)) catch {
      _ => abort("reentrant finish")
    }
    assert_true(cancel_managed_view_output_port(current)) catch {
      _ => abort("cancel verifier")
    }
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
  }).unwrap()
  holder.val = Some(port)
  assert_true(
    prepare_managed_view_output_port(plan, stream, (_ : Unit) => None)
    is Err(Closed),
  )
  assert_true(finish_managed_view_output(port, ()) is Err(Closed))
  assert_true(finish_managed_output_values(stream) is Err(Closed))
  assert_false(cancel_managed_view_output_port(port))
}

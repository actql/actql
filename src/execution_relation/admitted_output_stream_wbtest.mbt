///|
fn stream_value_limits() -> ValueLimits {
  { max_nodes: 10000, max_text_bytes: 100000, max_depth: 10, max_work: 200000, }
}

///|
test "output stream retains no rows and shares canonical encoding with ordered output" {
  let owner = capture_fixture()
  let stream = prepare_admitted_output_stream(
    owner,
    Step(1),
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  let text = StringBuilder()
  for row in 0..<2 {
    let supplied = output_fixture_row(owner, row)
    text.write_string(
      append_admitted_output_stream(stream, supplied.length(), column => {
        supplied.get(column)
      }).unwrap(),
    )
    assert_true(stream.buffer.rows.is_empty())
    supplied.clear()
  }
  let (receipt, tail) = finish_admitted_output_stream(stream).unwrap()
  text.write_string(tail)
  // Independent literal includes order, exact Unicode and whole-array framing.
  let expected = "[{\"n\":1,\"s\":\"é\"},{\"n\":2,\"s\":\"😀\"}]"
  assert_eq(text.to_string(), expected)
  let expected_writer = @encode.hashing_writer(1000, 100, 10)
  @encode.emit_json(@json.parse(expected), expected_writer)
  let (hash, bytes, nodes) = @encode.finish_hash_usage(expected_writer)
  assert_eq(
    output_stream_identity(receipt),
    ("sha256:" + hash, bytes, nodes, 2),
  )
  assert_true(physical_equal(output_stream_owner(receipt), owner))
  assert_eq(output_stream_target(receipt), Step(1))
  assert_eq(output_stream_value_usage(receipt), {
    nodes: 6,
    text_bytes: 10,
    work: 16,
  })
  assert_true(finish_admitted_output_stream(stream) is Err(Closed))
  assert_true(
    append_admitted_output_stream(stream, 0, _ => None) is Err(Closed),
  )
}

///|
test "output stream rejects foreign values and closes without publishing a receipt" {
  let owner = capture_fixture()
  let stream = prepare_admitted_output_stream(
    owner,
    Step(1),
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  let own = output_fixture_row(owner, 0)
  append_admitted_output_stream(stream, own.length(), column => own.get(column)).unwrap()
  |> ignore
  let foreign = output_fixture_row(capture_fixture(), 1)
  assert_true(
    append_admitted_output_stream(stream, foreign.length(), column => {
      foreign.get(column)
    })
    is Err(Admission(ForeignCheckedValue(1, _))),
  )
  assert_true(stream.buffer.rows.is_empty())
  assert_true(finish_admitted_output_stream(stream) is Err(Closed))
}

///|
test "output stream retains cumulative row value and encoding budgets across drains" {
  let owner = capture_fixture()
  for case_ in 0..<4 {
    let stream = prepare_admitted_output_stream(
      owner,
      Step(1),
      if case_ == 0 {
        1
      } else {
        2
      },
      {
        ..stream_value_limits(),
        max_nodes: if case_ == 1 {
          5
        } else {
          10000
        },
      },
      { ..row_wire_limits(), max_bytes: if case_ == 2 { 22 } else { 100000 }, },
      if case_ == 3 {
        8
      } else {
        64
      },
    ).unwrap()
    let own = output_fixture_row(owner, 0)
    let first = append_admitted_output_stream(stream, own.length(), column => {
      own.get(column)
    })
    if first is Ok(_) {
      let second = output_fixture_row(owner, 1)
      assert_true(
        append_admitted_output_stream(stream, second.length(), column => {
          second.get(column)
        })
        is Err(_),
      )
    }
    assert_true(stream.buffer.rows.is_empty())
    assert_true(finish_admitted_output_stream(stream) is Err(Closed))
  }
}

///|
test "stream reentrancy cancellation and empty output cannot manufacture completion" {
  let owner = capture_fixture()
  let stream = prepare_admitted_output_stream(
    owner,
    Step(1),
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  let supplied = output_fixture_row(owner, 0)
  append_admitted_output_stream(stream, supplied.length(), column => {
    assert_true(finish_admitted_output_stream(stream) is Err(Closed)) catch {
      _ => abort("reentrant seal")
    }
    supplied.get(column)
  }).unwrap()
  |> ignore
  assert_true(cancel_admitted_output_stream(stream))
  assert_false(cancel_admitted_output_stream(stream))
  assert_true(finish_admitted_output_stream(stream) is Err(Closed))
  let empty = prepare_admitted_output_stream(
    owner,
    Step(1),
    0,
    stream_value_limits(),
    row_wire_limits(),
    2,
  ).unwrap()
  let (receipt, text) = finish_admitted_output_stream(empty).unwrap()
  assert_eq(text, "[]")
  assert_eq(
    output_stream_identity(receipt),
    (
      "sha256:4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
      2, 1, 0,
    ),
  )
}

///|
test "take never reapplies historical completion after shadow rename projection or another take" {
  for
    (body, shadow, value, name) in [
      (
        "[{\"take\":3},{\"derive\":[{\"n\":\"0 - n\"}]},{\"take\":1}]", true, -1,
        "n",
      ),
      ("[{\"take\":3},{\"select\":[\"s\"]},{\"take\":1}]", false, 1, "s"),
      (
        "[{\"take\":3},{\"rename\":{\"n\":\"renamed\"}},{\"take\":1}]", false, 1,
        "renamed",
      ),
      ("[{\"take\":3},{\"drop\":[\"n\"]},{\"take\":1}]", false, 1, "s"),
      ("[{\"take\":3},{\"take\":1}]", false, 1, "n"),
      (
        "[{\"take\":3,\"as\":\"ordered\"},{\"derive\":[{\"n\":\"0 - n\"}]},{\"from\":\"ordered\",\"select\":[\"s\"]},{\"take\":1}]",
        true, 1, "s",
      ),
    ] {
    let owner = take_key_owner(body)
    let sequence = prepared_sequence(owner)
    let prepared = @lower.bound_preparation(owner)
    let last = @lower.node_count(prepared) - 1
    let last_node = @lower.node_at(prepared, last).unwrap()
    assert_eq(@lower.usage(prepared).nodes, last + 3)
    assert_true(@lower.order_node_id(last_node) is None)
    guard @lower.sequence_step(sequence, last) is Some(@lower.RowStep(kernel)) else {
      fail("take")
    }
    assert_eq(@lower.kernel_sort_term_count(kernel), 0)
    assert_true(@lower.kernel_sort_term_at(kernel, 0) is None)
    assert_true(
      @lower.prepare_kernel(owner, last, max_bindings=0, max_name_bytes=0, {
        max_nodes: 100,
        max_work: 1000,
        max_depth: 100,
        max_literal_nodes: 100,
        max_literal_text_bytes: 1000,
      })
      is Ok(_),
    )
    let contexts = if shadow {
      [
        ordered_sequence_fragment_context(
          sequence,
          100000L,
          limits=Some({
            max_input_rows: 3L,
            max_value_bytes: 1000L,
            max_live_value_bytes: 10000L,
            max_work: 100000L,
          }),
        ),
      ]
    } else {
      []
    }
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      sequence,
      contexts,
      [@lower.node_id(last_node)],
      100000,
      10000,
    ).unwrap()
    for empty in [false, true] {
      let raw = if empty {
        []
      } else {
        [
          input_cursor("{\"n\":3,\"s\":\"three\"}"),
          input_cursor("{\"n\":1,\"s\":\"one\"}"),
          input_cursor("{\"n\":2,\"s\":\"two\"}"),
        ]
      }
      let input = capture_input(
        owner,
        0,
        raw,
        max_rows=3,
        run_limits().input_values,
      ).unwrap()
      for _i = 0; _i < 2; _i = _i + 1 {
        let complete = execute_generated_sequence(generated, [input], {
          rows: run_limits(),
          max_work: 100000,
          max_frames: 100,
        }).unwrap()
        let output = completed_output(complete, Step(last)).unwrap()
        assert_eq(completed_column_name(output, 0), Some(name))
        if empty {
          assert_eq(completed_row_count(output), 0)
        } else {
          assert_eq(completed_row_count(output), 1)
          if name == "s" {
            assert_true(completed_cell(output, 0, 0) is Some(Text("one")))
          } else {
            assert_true(
              completed_cell(output, 0, 0) is Some(Number(n)) &&
              n == value.to_double(),
            )
          }
        }
      }
    }
  }
}

///|
test "producer completion transfers established take order without replaying its key" {
  let owner = take_key_owner("[{\"take\":3}]")
  let upstream = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["limit_0"],
    100000,
    10000,
  ).unwrap()
  let raw = [
    input_cursor("{\"n\":3,\"s\":\"three\"}"),
    input_cursor("{\"n\":1,\"s\":\"one\"}"),
    input_cursor("{\"n\":2,\"s\":\"two\"}"),
  ]
  let input = capture_input(
    owner,
    0,
    raw,
    max_rows=3,
    run_limits().input_values,
  ).unwrap()
  let limits : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }
  let complete = execute_generated_sequence(upstream, [input], limits).unwrap()
  let output = completed_output(complete, Step(0)).unwrap()
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(owner)),
    Step(0),
  ).unwrap()
  let receiver = sort_input_owner(
    @pipeline.ProducedInput(producer),
    "[{\"select\":[\"s\"]},{\"take\":1}]",
  )
  let sequence = prepared_sequence(receiver)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["limit_1"],
    100000,
    10000,
  ).unwrap()
  let bound = bind_completed_input(receiver, 0, owner, output).unwrap()
  let result = execute_generated_sequence(generated, [], limits, produced=[
    bound,
  ]).unwrap()
  assert_true(
    completed_cell(completed_output(result, Step(1)).unwrap(), 0, 0)
    is Some(Text("one")),
  )
}

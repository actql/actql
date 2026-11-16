///|
fn literal_values_capacity_fixture(
  contract : String,
  rows : String,
  id_nullable? : Bool = false,
) -> GeneratedSequence raise {
  prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(
      bound_pipeline(
        "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":" +
        (if id_nullable { "true" } else { "false" }) +
        "},\"tenant\":" +
        contract +
        ",\"rows\":" +
        rows +
        "},\"as\":\"out\"}]",
      ),
    ),
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
}

///|
fn literal_values_capacity_limits() -> SequenceExecutionLimits {
  let values : ValueLimits = {
    max_nodes: 300000,
    max_text_bytes: 20000000,
    max_depth: 100,
    max_work: 20000000,
  }
  {
    rows: {
      max_rows: 3,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: values,
      output_values: values,
    },
    max_work: 20000000,
    max_frames: 100,
  }
}

///|
test "flat literal Values quote follows original DATA while unused policy ceilings remain finite" {
  let generated = literal_values_capacity_fixture(
    "{\"type\":\"string\",\"nullable\":false}}", "[{\"id\":1,\"tenant\":\"a\"},{\"id\":2,\"tenant\":\"é😀\"}]",
  )
  let limits = literal_values_capacity_limits()
  let measurement : FixedInputGuardMeasureLimits = {
    max_nodes: 300000,
    max_bytes: 20000000,
    max_depth: 100,
    max_work: 20000000,
  }
  let quote = generated_bounded_sequence_capacity(
    generated, limits, measurement,
  ).unwrap()
  let larger = generated_bounded_sequence_capacity(
    generated,
    {
      ..limits,
      rows: {
        ..limits.rows,
        input_values: { ..limits.rows.input_values, max_text_bytes: 40000000, },
        output_values: {
          ..limits.rows.output_values,
          max_text_bytes: 40000000,
        },
      },
    },
    measurement,
  ).unwrap()
  assert_eq(quote.retained_bytes, larger.retained_bytes)
  assert_eq(quote.execution_bytes, larger.execution_bytes)
  // Even simultaneously funding the retained output and full task scratch
  // leaves the unchanged 512MiB Request room for its existing preparation.
  assert_true(quote.retained_bytes + quote.execution_bytes < 536870912L)
  let generic = generated_sequence_capacity(generated, limits, measurement).unwrap()
  assert_true(quote.execution_bytes < generic.execution_bytes)
  let active = start_bounded_values(
    @bounded.control(),
    generated,
    3,
    limits.rows.input_values,
    limits.rows.output_values,
    limits.max_work,
    limits.max_frames,
    limits.rows.operation_entries,
    1000,
  ).unwrap()
  let mut completed = false
  for _ in 0..<10000 {
    match advance_bounded_values(active, 1).unwrap() {
      BoundedValuesContinue(_) => ()
      BoundedValuesComplete(output, ..) => {
        assert_eq(completed_row_count(output), 2)
        assert_true(completed_cell(output, 0, 0) is Some(Number(1.0)))
        assert_true(completed_cell(output, 1, 1) is Some(Text("é😀")))
        completed = true
        break
      }
      _ => fail("same original literal Values did not complete")
    }
  }
  assert_true(completed)
  assert_true(cleanup_bounded_values(active).unwrap())
  assert_false(bounded_values_cleanup_pending(active))
}

///|
test "literal Values quotation does not weaken original input refusal or cancellation" {
  let generated = literal_values_capacity_fixture(
    "{\"type\":\"string\",\"nullable\":false}}", "[{\"id\":1,\"tenant\":\"a\"}]",
  )
  let limits = literal_values_capacity_limits()
  for cancel in [false, true] {
    let control = @bounded.control()
    let active = start_bounded_values(
      control,
      generated,
      3,
      if cancel {
        limits.rows.input_values
      } else {
        { ..limits.rows.input_values, max_text_bytes: 0, }
      },
      limits.rows.output_values,
      limits.max_work,
      limits.max_frames,
      limits.rows.operation_entries,
      1000,
    ).unwrap()
    if cancel {
      assert_true(@bounded.request_cancel(control))
    }
    let mut refused = false
    for _ in 0..<10000 {
      match advance_bounded_values(active, 1).unwrap() {
        BoundedValuesContinue(_) => ()
        BoundedValuesFailed(InputLimit, ..) if !cancel => {
          refused = true
          break
        }
        BoundedValuesStopped(@bounded.Cancelled, ..) if cancel => {
          refused = true
          break
        }
        _ => fail("literal policy/current refusal changed")
      }
    }
    assert_true(refused)
    assert_true(cleanup_bounded_values(active).unwrap())
    assert_false(bounded_values_cleanup_pending(active))
  }
}

///|
test "recursive Values retain their enclosing DATA capacity fallback" {
  let limits = literal_values_capacity_limits()
  let measurement : FixedInputGuardMeasureLimits = {
    max_nodes: 300000,
    max_bytes: 20000000,
    max_depth: 100,
    max_work: 20000000,
  }
  for
    (contract, rows) in [
      (
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}}",
        "[{\"id\":1,\"tenant\":[1]}]",
      ),
    ] {
    let generated = literal_values_capacity_fixture(contract, rows)
    let original = generated_bounded_sequence_capacity(
      generated, limits, measurement,
    ).unwrap()
    let more = generated_bounded_sequence_capacity(
      generated,
      {
        ..limits,
        rows: {
          ..limits.rows,
          output_values: {
            ..limits.rows.output_values,
            max_text_bytes: 40000000,
          },
        },
      },
      measurement,
    ).unwrap()
    assert_true(more.retained_bytes > original.retained_bytes)
    assert_true(more.execution_bytes > original.execution_bytes)
  }
}

///|
test "nullable literal scalar Values uses same-owner cached DATA and unchanged admission" {
  let generated = literal_values_capacity_fixture(
    "{\"type\":\"string\",\"nullable\":false}}",
    "[{\"id\":1,\"tenant\":\"x\"},{\"id\":1,\"tenant\":\"x\"},{\"id\":2,\"tenant\":\"y\"},{\"id\":null,\"tenant\":\"n\"}]",
    id_nullable=true,
  )
  let prepared = @lower.bound_preparation(generated_sequence_owner(generated))
  let node = @lower.node_at(prepared, 0).unwrap()
  assert_eq(@lower.node_values_row_count(node), Some(4))
  let cached_text = @lower.node_values_literal_text_bytes(node).unwrap()
  // Four independently authored payload bytes are included in the original
  // charged admission envelope; keep any schema/metadata allowance as well.
  assert_true(cached_text >= 4)
  let limits = {
    ..literal_values_capacity_limits(),
    rows: { ..literal_values_capacity_limits().rows, max_rows: 4, },
  }
  let measure : FixedInputGuardMeasureLimits = {
    max_nodes: 300000,
    max_bytes: 20000000,
    max_depth: 100,
    max_work: 20000000,
  }
  let quote = generated_bounded_sequence_capacity(generated, limits, measure).unwrap()
  let expected = execution_capacity_inventory_bytes([
    { unit: CursorRootSlots, count: 2L, copies: 1, },
    { unit: ValueNodeSlots, count: 4L * (2L + 1L), copies: 1, },
  ]).unwrap()
  let cached_text_cost = execution_capacity_inventory_bytes([
    { unit: DecodedTextBytes, count: cached_text.to_int64(), copies: 1, },
  ]).unwrap()
  assert_eq(quote.retained_bytes - cached_text_cost, expected)
  let inflated = generated_bounded_sequence_capacity(
    generated,
    {
      ..limits,
      rows: {
        ..limits.rows,
        output_values: {
          ..limits.rows.output_values,
          max_nodes: 600000,
          max_text_bytes: 40000000,
        },
      },
    },
    measure,
  ).unwrap()
  assert_eq(quote.retained_bytes, inflated.retained_bytes)
  assert_eq(quote.execution_bytes, inflated.execution_bytes)
  assert_true(
    quote.retained_bytes <
    generated_sequence_capacity(generated, limits, measure).unwrap().retained_bytes,
  )
  for refused in [false, true] {
    let control = @bounded.control()
    let active = start_bounded_values(
      control,
      generated,
      4,
      if refused {
        { ..limits.rows.input_values, max_text_bytes: 0, }
      } else {
        limits.rows.input_values
      },
      limits.rows.output_values,
      limits.max_work,
      limits.max_frames,
      limits.rows.operation_entries,
      1000,
    ).unwrap()
    let mut done = false
    for _ in 0..<10000 {
      match advance_bounded_values(active, 1).unwrap() {
        BoundedValuesContinue(..) => ()
        BoundedValuesFailed(InputLimit, ..) if refused => {
          done = true
          break
        }
        BoundedValuesComplete(output, ..) if !refused => {
          assert_eq(completed_row_count(output), 4)
          assert_true(completed_cell(output, 3, 0) is Some(Null))
          assert_true(completed_cell(output, 3, 1) is Some(Text("n")))
          done = true
          break
        }
        _ => fail("nullable literal admission changed")
      }
    }
    assert_true(done)
    assert_true(cleanup_bounded_values(active).unwrap())
    assert_false(bounded_values_cleanup_pending(active))
  }
}

///|
test "nullable Text literal keeps explicit NULL as same-owner scalar DATA" {
  let generated = literal_values_capacity_fixture(
    "{\"type\":\"string\",\"nullable\":true}}", "[{\"id\":1,\"tenant\":null}]",
  )
  let limits = literal_values_capacity_limits()
  let measure : FixedInputGuardMeasureLimits = {
    max_nodes: 300000,
    max_bytes: 20000000,
    max_depth: 100,
    max_work: 20000000,
  }
  let quote = generated_bounded_sequence_capacity(generated, limits, measure).unwrap()
  let inflated = generated_bounded_sequence_capacity(
    generated,
    {
      ..limits,
      rows: {
        ..limits.rows,
        output_values: {
          ..limits.rows.output_values,
          max_text_bytes: 40000000,
        },
      },
    },
    measure,
  ).unwrap()
  assert_eq(quote.retained_bytes, inflated.retained_bytes)
  assert_eq(quote.execution_bytes, inflated.execution_bytes)
  let active = start_bounded_values(
    @bounded.control(),
    generated,
    3,
    limits.rows.input_values,
    limits.rows.output_values,
    limits.max_work,
    limits.max_frames,
    limits.rows.operation_entries,
    1000,
  ).unwrap()
  let mut complete = false
  for _ in 0..<10000 {
    match advance_bounded_values(active, 1).unwrap() {
      BoundedValuesContinue(..) => ()
      BoundedValuesComplete(output, ..) => {
        assert_eq(completed_row_count(output), 1)
        assert_true(completed_cell(output, 0, 1) is Some(Null))
        complete = true
        break
      }
      _ => fail("nullable Text literal changed")
    }
  }
  assert_true(complete)
  assert_true(cleanup_bounded_values(active).unwrap())
}

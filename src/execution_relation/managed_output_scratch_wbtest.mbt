///|
fn metered_managed_scratch_stream(
  output : AdmittedOutput,
  growth : WorkspaceGrowth,
  count : Int,
) -> ManagedOutputValues raise {
  let stream = prepare_managed_output_values(
    output.owner,
    output.target,
    count,
    {
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 10,
      max_work: 100000,
    },
    100,
    { max_work: 100000, max_bytes: 100000, max_nodes: 100000, max_depth: 10, },
  ).unwrap()
  stream.buffer.budget.retention = Some(growth)
  assert_true(
    prepare_managed_output_scratch(stream.buffer.budget, stream.buffer.schema),
  )
  stream
}

///|
test "managed row scratch preserves original payload and cumulative work without historical payload copies" {
  let growth = {
    ..working_growth_fixture(_ => Ok(())),
    live_ceiling: 1048576L,
    retained_outputs: Some(0L),
  }
  let original = funded_row_output(growth)
  let cell = funded_row_number(original, 1.0)
  append_admitted_output(original, [cell]).unwrap()
  assert_eq(growth.retained_outputs, Some(528L))
  let stream = metered_managed_scratch_stream(original, growth, 1000)
  // Existing representation tariffs: fixed column/finish/row controls3528,
  // schema traversal192 execution bytes, TWO largest rows2*528 retained.
  assert_eq(growth.retained_outputs, Some(528L + 3528L))
  for _ in 0..<1000 {
    append_managed_output_values(stream, 1, _ => Some(cell)).unwrap()
  }
  assert_eq(growth.retained_outputs, Some(528L + 3528L + 1056L))
  assert_eq(stream.buffer.budget.nodes, 2000)
  assert_eq(stream.buffer.budget.text, 2000)
  assert_eq(stream.buffer.budget.work, 4000)
  let receipt = finish_managed_output_values(stream).unwrap()
  assert_eq(receipt.rows, 1000)
  assert_eq(receipt.usage, { nodes: 2000, text_bytes: 2000, work: 4000, })
  assert_eq(receipt.reference_rows.length(), 0)
  assert_eq(receipt.column_usage.length(), 1)
  let funded = growth.retained_outputs
  request_managed_output_values_disposal(stream)
  while !advance_managed_output_values_reclamation(stream, 1) {

  }
  assert_true(managed_output_values_scratch_released(stream))
  // No premature release credit, including Native stale backing. The same
  // original Task still owns original payload plus scratch/metadata funding.
  assert_eq(growth.retained_outputs, funded)
  assert_eq(original.buffer.rows.length(), 1)
}

///|
test "managed row scratch funds packed facts and refuses a truly occupied original budget" {
  for occupied in [false, true] {
    let growth = {
      ..working_growth_fixture(_ => Ok(())),
      live_ceiling: 1048576L,
      retained_outputs: Some(0L),
      reserve_retained: Some((_, retained) => {
        if occupied && retained > 5111L {
          Err(WorkspaceBudgetUnavailable)
        } else {
          Ok(())
        }
      }),
    }
    let original = funded_row_output(growth)
    let cell = funded_row_number(original, 1.0)
    append_admitted_output(original, [cell]).unwrap()
    let stream = metered_managed_scratch_stream(original, growth, 2)
    if occupied {
      assert_true(
        append_managed_output_values(stream, 1, _ => Some(cell))
        is Err(Admission(CaptureLimit)),
      )
      assert_true(finish_managed_output_values(stream) is Err(Closed))
      assert_eq(growth.retained_outputs, Some(4056L))
      assert_eq(original.buffer.rows.length(), 1)
    } else {
      enable_managed_row_measurements(stream, 2).unwrap()
      assert_eq(growth.retained_outputs, Some(4056L + 530L))
      append_managed_output_values(stream, 1, _ => Some(cell)).unwrap()
      append_managed_output_values(stream, 1, _ => Some(cell)).unwrap()
      let receipt = finish_managed_output_values(stream).unwrap()
      assert_eq(managed_output_measurement_index_cells(receipt), Some(2))
      assert_eq(growth.retained_outputs, Some(4056L + 530L + 1056L))
    }
    request_managed_output_values_disposal(stream)
    while !advance_managed_output_values_reclamation(stream, 1) {

    }
    assert_true(managed_output_values_scratch_released(stream))
  }
}

///|
test "managed packed scratch facts refuse capacity before allocation and retain original payload" {
  let growth = {
    ..working_growth_fixture(_ => Ok(())),
    live_ceiling: 1048576L,
    retained_outputs: Some(0L),
    reserve_retained: Some((_, retained) => {
      if retained > 5111L {
        Err(WorkspaceBudgetUnavailable)
      } else {
        Ok(())
      }
    }),
  }
  let original = funded_row_output(growth)
  append_admitted_output(original, [funded_row_number(original, 1.0)]).unwrap()
  let stream = metered_managed_scratch_stream(original, growth, 1000)
  assert_true(
    enable_managed_row_measurements(stream, 1000)
    is Err(Admission(CaptureLimit)),
  )
  assert_true(stream.row_measurements is None)
  assert_eq(growth.retained_outputs, Some(4056L))
  assert_eq(original.buffer.rows.length(), 1)
  request_managed_output_values_disposal(stream)
  while !advance_managed_output_values_reclamation(stream, 1) {

  }
  assert_true(managed_output_values_scratch_released(stream))
}

///|
test "nested schema scratch keeps one actual reservation and mandatory first refusal" {
  let owner = managed_nested_reference_owner()
  let output = prepare_admitted_output(owner, Step(0), 1, stream_value_limits()).unwrap()
  let pending_extents : Array[Int] = []
  assert_eq(
    managed_schema_reference_free(
      output.buffer.schema,
      100,
      reserve=Some(count => {
        pending_extents.push(count)
        true
      }),
    ),
    Some(false),
  )
  // The existing object/array/reference fixture visits three contracts while
  // the actual pending stack's extent remains one throughout.
  assert_eq(pending_extents, [1, 1, 1])
  for refuse in [false, true] {
    let calls = Ref(0)
    let growth = {
      ..working_growth_fixture(_ => {
        calls.val += 1
        if refuse {
          Err(WorkspaceUnavailable)
        } else {
          Ok(())
        }
      }),
      live_ceiling: 1048576L,
      retained_outputs: Some(0L),
    }
    let budget = value_budget(stream_value_limits()).unwrap()
    budget.retention = Some(growth)
    assert_eq(
      prepare_managed_output_scratch(budget, output.buffer.schema),
      !refuse,
    )
    assert_eq(calls.val, 1)
    assert_eq(growth.text, if refuse { 0L } else { 192L })
    // The nested reference still requires the complete original path. Neither
    // a funded proof stack nor its reuse establishes reference availability.
    assert_true(budget.row_scratch_start is None)
    assert_eq((budget.nodes, budget.text, budget.work), (0, 0, 0))
  }
}

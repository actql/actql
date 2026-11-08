///|
fn funded_row_output(
  growth : WorkspaceGrowth,
  rows? : Int = 10,
) -> AdmittedOutput {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"out\"}]",
  )
  let output = prepare_admitted_output(owner, @pipeline.Step(0), rows, {
    max_nodes: rows * 10,
    max_text_bytes: rows * 10,
    max_depth: 10,
    max_work: rows * 100,
  }).unwrap()
  output.buffer.budget.retention = Some(growth)
  output
}

///|
fn funded_row_number(
  output : AdmittedOutput,
  value : Double,
) -> @admitted.CheckedValue {
  @admitted.checked_number_value(
    value,
    @schema.field_at(output.buffer.schema, 0).unwrap().contract,
  ).unwrap()
}

///|
test "persistent output growth composes original buffers before every row commit" {
  let requests : Array[Int64] = []
  let growth = {
    ..working_growth_fixture(bytes => {
      requests.push(bytes)
      Ok(())
    }),
    live_ceiling: 1048576L,
  }
  growth.retained_outputs = Some(0L)
  let first = funded_row_output(growth)
  let second = funded_row_output(growth)
  append_admitted_output(first, [funded_row_number(first, 1.0)]).unwrap()
  // A row root, one number node, and its two-byte field name.
  assert_eq(requests, [16384L])
  append_admitted_output(second, [funded_row_number(second, 2.0)]).unwrap()
  assert_eq(requests, [16384L])
  append_admitted_output(first, [funded_row_number(first, 3.0)]).unwrap()
  assert_eq(requests, [16384L])
  assert_eq((growth.used, growth.funded), (1584L, 16384L))
  let earlier = finish_admitted_output(first).unwrap()
  assert_eq(admitted_output_row_count(earlier), 2)
  assert_eq(growth.retained_outputs, Some(1584L))
  assert_true(cancel_admitted_output(second))
  // Failed/cancelled buffers retain their actual charge until task cleanup.
  assert_eq(growth.retained_outputs, Some(1584L))
  assert_eq(requests, [16384L])
}

///|
test "output growth refusal cannot commit a row or discard an earlier output charge" {
  let calls = Ref(0)
  let growth = {
    ..working_growth_fixture(bytes => {
      calls.val += 1
      if bytes <= 528L {
        Ok(())
      } else {
        Err(WorkspaceBudgetUnavailable)
      }
    }),
    live_ceiling: 1048576L,
  }
  growth.retained_outputs = Some(0L)
  let first = funded_row_output(growth)
  append_admitted_output(first, [funded_row_number(first, 1.0)]).unwrap()
  let earlier = finish_admitted_output(first).unwrap()
  let second = funded_row_output(growth)
  assert_true(
    append_admitted_output(second, [funded_row_number(second, 2.0)])
    is Err(CaptureLimit),
  )
  assert_true(second.buffer.rows.is_empty())
  assert_false(second.buffer.open)
  assert_eq(admitted_output_row_count(earlier), 1)
  assert_eq(growth.retained_outputs, Some(528L))
  assert_eq(second.buffer.budget.retention_funded, 0L)
  assert_true(growth.failed)
  assert_eq(calls.val, 4)
}

///|
test "cancellation inside output funding prevents persistent row transfer" {
  let original : Ref[AdmittedOutput?] = Ref(None)
  let growth = {
    ..working_growth_fixture(_ => {
      cancel_admitted_output(original.val.unwrap()) |> ignore
      Ok(())
    }),
    live_ceiling: 1048576L,
  }
  growth.retained_outputs = Some(0L)
  let output = funded_row_output(growth)
  original.val = Some(output)
  assert_true(
    append_admitted_output(output, [funded_row_number(output, 1.0)])
    is Err(CaptureLimit),
  )
  assert_true(output.buffer.rows.is_empty())
  assert_false(output.buffer.open)
  assert_eq(growth.retained_outputs, Some(528L))
  assert_true(cancel_admitted_output(output) == false)
}

///|
test "many small retained rows use page funding and cheap counters" {
  let requests : Array[Int64] = []
  let growth = {
    ..working_growth_fixture(bytes => {
      requests.push(bytes)
      Ok(())
    }),
    live_ceiling: 1048576L,
  }
  growth.retained_outputs = Some(0L)
  let output = funded_row_output(growth, rows=500)
  for _ in 0..<500 {
    append_admitted_output(output, [funded_row_number(output, 1.0)]).unwrap()
  }
  assert_eq(
    admitted_output_row_count(finish_admitted_output(output).unwrap()),
    500,
  )
  assert_eq(growth.retained_outputs, Some(264000L))
  assert_eq(growth.used, 264000L)
  assert_eq(requests.length(), 17)
  assert_eq(growth.funded, 278528L)
  assert_true(growth.funded >= growth.used)
}

///|
test "tight output funding uses exact minimum only after pure budget refusal" {
  let requests : Array[Int64] = []
  let growth = {
    ..working_growth_fixture(bytes => {
      requests.push(bytes)
      if bytes <= 1056L {
        Ok(())
      } else {
        Err(WorkspaceBudgetUnavailable)
      }
    }),
    live_ceiling: 1048576L,
  }
  growth.retained_outputs = Some(0L)
  let output = funded_row_output(growth)
  append_admitted_output(output, [funded_row_number(output, 1.0)]).unwrap()
  append_admitted_output(output, [funded_row_number(output, 2.0)]).unwrap()
  assert_eq(requests, [16384L, 528L, 16384L, 1056L])
  assert_eq((growth.used, growth.funded), (1056L, 1056L))
  assert_eq(
    admitted_output_row_count(finish_admitted_output(output).unwrap()),
    2,
  )
}

///|
test "generic output funding failure never retries a smaller request" {
  let requests : Array[Int64] = []
  let growth = {
    ..working_growth_fixture(bytes => {
      requests.push(bytes)
      Err(WorkspaceUnavailable)
    }),
    live_ceiling: 1048576L,
  }
  growth.retained_outputs = Some(0L)
  let output = funded_row_output(growth)
  assert_true(
    append_admitted_output(output, [funded_row_number(output, 1.0)])
    is Err(CaptureLimit),
  )
  assert_eq(requests, [16384L])
  assert_true(output.buffer.rows.is_empty())
  assert_eq((growth.used, growth.funded), (0L, 0L))
}

///|
test "retained pages grow both original resource dimensions together" {
  let requests : Array[(Int64, Int64)] = []
  let unexpected = Ref(0)
  let growth = {
    ..working_growth_fixture(_ => {
      unexpected.val += 1
      Err(WorkspaceUnavailable)
    }),
    live_ceiling: 1048576L,
    retained_outputs: Some(0L),
    reserve_retained: Some((execution, retained) => {
      requests.push((execution, retained))
      Ok(())
    }),
  }
  let output = funded_row_output(growth, rows=500)
  for _ in 0..<500 {
    append_admitted_output(output, [funded_row_number(output, 1.0)]).unwrap()
  }
  assert_eq(growth.used, 264000L)
  assert_eq(growth.retained_outputs, Some(264000L))
  assert_eq((growth.funded, growth.retained_funded), (278528L, 278528L))
  assert_eq(requests.length(), 17)
  assert_eq(unexpected.val, 0)
  for (execution, retained) in requests {
    assert_eq(execution, retained)
  }
}

///|
test "reference revocation before row commit cannot request output funding" {
  let calls = Ref(0)
  let growth = {
    ..working_growth_fixture(_ => {
      calls.val += 1
      Ok(())
    }),
    live_ceiling: 1048576L,
    retained_outputs: Some(0L),
  }
  let output = prepare_admitted_output(managed_reference_owner(), Step(0), 1, {
    max_nodes: 100,
    max_text_bytes: 1000,
    max_depth: 10,
    max_work: 1000,
  }).unwrap()
  output.buffer.budget.retention = Some(growth)
  let armed = Ref(false)
  let observed = Ref(false)
  let wire = managed_reference_wire()
  let checked = @admitted.issue_reference(
    @admitted.bind_reference_issuer((_, candidate) => candidate == wire, _ => {
      if armed.val {
        observed.val = true
        cancel_admitted_output(output) |> ignore
      }
      true
    }),
    @schema.field_at(output.buffer.schema, 0).unwrap().contract,
    wire,
    { max_bytes: 1000, max_nodes: 100, max_depth: 10, max_text_units: 1000, },
  ).unwrap()
  armed.val = true
  let result = append_admitted_output(output, [checked])
  assert_true(observed.val)
  assert_eq(calls.val, 0)
  assert_true(result is Err(ClosedCapture))
  assert_eq((growth.used, growth.funded), (0L, 0L))
  assert_eq(growth.retained_outputs, Some(0L))
  assert_eq(output.buffer.budget.retention_funded, 0L)
  assert_true(output.buffer.rows.is_empty())
  assert_true(finish_admitted_output(output) is Err(ClosedCapture))
}

///|
test "completed value projection revocation cannot request output funding" {
  let owner = managed_reference_owner()
  let limits = {
    max_nodes: 100,
    max_text_bytes: 1000,
    max_depth: 10,
    max_work: 1000,
  }
  let stream = prepare_managed_output_values(
    owner,
    Step(0),
    1,
    limits,
    1000,
    managed_test_measure_limits(),
  ).unwrap()
  let calls = Ref(0)
  let growth = {
    ..working_growth_fixture(_ => {
      calls.val += 1
      Ok(())
    }),
    live_ceiling: 1048576L,
    retained_outputs: Some(0L),
  }
  stream.buffer.budget.retention = Some(growth)
  let armed = Ref(false)
  let observed = Ref(false)
  let released_during_callback = Ref(true)
  let wire = managed_reference_wire()
  let checked = @admitted.issue_reference(
    @admitted.bind_reference_issuer((_, candidate) => candidate == wire, _ => {
      if armed.val {
        observed.val = true
        dispose_managed_output_values_scratch(stream)
        released_during_callback.val = managed_output_values_scratch_released(
          stream,
        )
      }
      true
    }),
    @schema.field_at(stream.buffer.schema, 0).unwrap().contract,
    wire,
    { max_bytes: 1000, max_nodes: 100, max_depth: 10, max_text_units: 1000, },
  ).unwrap()
  let admitted = prepare_admitted_output(owner, Step(0), 1, limits).unwrap()
  append_admitted_output(admitted, [checked]).unwrap()
  let rows = finish_admitted_output(admitted).unwrap()
  let preparation = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(owner),
    ["select_0"],
    10000,
    1000,
  ).unwrap()
  let output = complete_trusted_output(
    prepare_trusted_output_port(preparation, Step(0), 1000, 10000, (_ : Unit) => {
      Some(rows)
    }).unwrap(),
    (),
  ).unwrap()
  armed.val = true
  let result = append_completed_projection_managed_values(stream, output, 0)
  assert_true(observed.val)
  assert_false(released_during_callback.val)
  assert_eq(calls.val, 0)
  assert_true(result is Err(Closed))
  assert_eq((growth.used, growth.funded), (0L, 0L))
  assert_eq(growth.retained_outputs, Some(0L))
  assert_true(managed_output_values_scratch_released(stream))
  assert_true(finish_managed_output_values(stream) is Err(Closed))
  assert_true(completed_output_available(output))
}

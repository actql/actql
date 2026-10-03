///|
fn managed_scratch_test_source(
  available? : () -> Bool = fn() { true },
) -> (@lower.BoundPrepared, @execution.ManagedCompletedOutput[Unit]) raise {
  let owner = remote_completion_owner()
  let values = remote_completion_values(owner)
  let retention = @execution.prepare_managed_output_retention_port(values, (
    receipt : @execution.ManagedOutputValueReceipt,
  ) => Some((receipt, (), 8L, available))).unwrap()
  let physical = @duckdb.prepare_managed_physical_output(
    values,
    [("n", @duckdb.Float64)],
    fixed_compute_attempt_limits().physical,
    100,
  ).unwrap()
  @duckdb.append_managed_physical_output(physical, 1, [
    input_cursor("[\"4008000000000000\"]"),
  ]).unwrap()
  let receipt = @duckdb.finish_managed_physical_output(physical).unwrap()
  let material = @execution.retain_managed_output(retention, receipt).unwrap()
  let completion = @execution.prepare_managed_completion_port(
    @execution.selected_managed_execution_profile(),
    task_test_completion(owner),
    @pipeline.Step(1),
    100,
    1000,
    (material : @execution.ManagedRetainedOutput[Unit]) => Some(material),
  ).unwrap()
  let output = @execution.complete_managed_output(completion, material).unwrap()
  @execution.dispose_managed_output_values_scratch(values)
  assert_true(@execution.managed_output_values_scratch_released(values))
  (owner, output)
}

///|
test "managed admission scratch disposal waits for active reads and preserves finished receipts" {
  let values = remote_completion_values(remote_completion_owner())
  let during_read = Ref(true)
  assert_true(
    @execution.append_managed_output_values(values, 1, fn(_) {
      @execution.dispose_managed_output_values_scratch(values)
      during_read.val = @execution.managed_output_values_scratch_released(
        values,
      )
      None
    })
    is Err(_),
  )
  assert_false(during_read.val)
  assert_true(@execution.managed_output_values_scratch_released(values))
  @execution.dispose_managed_output_values_scratch(values)
  assert_true(@execution.managed_output_values_scratch_released(values))

  let values = remote_completion_values(remote_completion_owner())
  @execution.enable_managed_row_measurements(values, 1).unwrap()
  let physical = @duckdb.prepare_managed_physical_output(
    values,
    [("n", @duckdb.Float64)],
    fixed_compute_attempt_limits().physical,
    100,
  ).unwrap()
  @duckdb.append_managed_physical_output(physical, 1, [
    input_cursor("[\"4008000000000000\"]"),
  ]).unwrap()
  let receipt = @duckdb.finish_managed_physical_output(physical).unwrap()
  assert_false(@execution.managed_output_values_scratch_released(values))
  assert_false(@execution.cancel_managed_output_values(values))
  @execution.dispose_managed_output_values_scratch(values)
  assert_true(@execution.managed_output_values_scratch_released(values))
  assert_eq(@execution.managed_output_measurement_index_cells(receipt), Some(1))
  assert_eq(@execution.managed_output_value_row_count(receipt), 1)
}

///|
test "DuckDB scratch disposal covers cancellation finished values and successful publication" {
  // Open cancellation, cancellation after finish, successful completion, and
  // reentrant cancellation while the verifier still owns an active frame.
  for mode in 0..<4 {
    let (source, output) = managed_scratch_test_source()
    let owner = typed_receiver(
      source, "[{\"filter\":\"n > 0\"},{\"select\":[\"n\"]}]",
    )
    let input = @execution.prepare_managed_producer_read(
      owner, 0, source, output, 100, 1000,
    ).unwrap()
    let query = @duckdb.prepare_managed_fixed_query(
      input,
      "held",
      native_compile_limits(),
    ).unwrap()
    let current : Ref[@duckdb_compute.ManagedInputDuckDBCompletion[Unit]?] = Ref(
      None,
    )
    let during_verification = Ref(true)
    let completion = @duckdb_compute.prepare_managed_input_duckdb_completion(
      query,
      task_test_completion(owner),
      @execution.selected_managed_execution_profile(),
      fixed_compute_attempt_limits(),
      2,
      100,
      fn() { true },
      fn(_) {
        if mode == 3 && current.val is Some(value) {
          @duckdb_compute.dispose_managed_input_duckdb_completion(value)
          during_verification.val = @duckdb_compute.managed_input_duckdb_scratch_released(
            value,
          )
        }
        true
      },
    ).unwrap()
    current.val = Some(completion)
    let values = @duckdb_compute.managed_input_duckdb_output_values(completion)
    assert_false(
      @duckdb_compute.managed_input_duckdb_scratch_released(completion),
    )
    @execution.enable_managed_row_measurements(values, 2).unwrap()
    if mode == 0 {
      assert_true(
        @duckdb_compute.cancel_managed_input_duckdb_completion(completion),
      )
      assert_false(
        @duckdb_compute.managed_input_duckdb_scratch_released(completion),
      )
      @duckdb_compute.dispose_managed_input_duckdb_completion(completion)
    } else {
      let retention = @execution.prepare_managed_output_retention_port(values, (
        receipt : @execution.ManagedOutputValueReceipt,
      ) => Some((receipt, (), 8L, fn() { true }))).unwrap()
      let physical = @duckdb.prepare_managed_physical_output(
        values,
        [("n", @duckdb.Float64)],
        fixed_compute_attempt_limits().physical,
        100,
      ).unwrap()
      @duckdb.append_managed_physical_output(physical, 1, [
        input_cursor("[\"4008000000000000\"]"),
      ]).unwrap()
      let receipt = @duckdb.finish_managed_physical_output(physical).unwrap()
      let material = @execution.retain_managed_output(retention, receipt).unwrap()
      if mode == 1 {
        assert_true(
          @duckdb_compute.cancel_managed_input_duckdb_completion(completion),
        )
        assert_false(
          @duckdb_compute.managed_input_duckdb_scratch_released(completion),
        )
        @duckdb_compute.dispose_managed_input_duckdb_completion(completion)
      } else {
        let completed = @duckdb_compute.complete_managed_input_duckdb(
          completion, receipt, material,
        )
        if mode == 3 {
          assert_true(completed is Err(_))
          assert_false(during_verification.val)
        } else {
          let completed = completed.unwrap()
          assert_false(
            @duckdb_compute.cancel_managed_input_duckdb_completion(completion),
          )
          assert_false(
            @duckdb_compute.managed_input_duckdb_scratch_released(completion),
          )
          let usage = @duckdb_compute.managed_input_duckdb_demand_usage(
            completion,
          )
          @duckdb_compute.dispose_managed_input_duckdb_completion(completion)
          assert_true(@execution.managed_completed_output_available(completed))
          assert_true(usage is Some(_))
          assert_true(
            @duckdb_compute.managed_input_duckdb_demand_usage(completion)
            is Some(_),
          )
        }
      }
      // Scratch disposal never destroys an index already owned by the receipt.
      assert_eq(
        @execution.managed_output_measurement_index_cells(receipt),
        Some(1),
      )
      assert_eq(@execution.managed_output_value_row_count(receipt), 1)
      assert_true(@execution.managed_retained_output_matches(material, receipt))
    }
    assert_true(
      @duckdb_compute.managed_input_duckdb_scratch_released(completion),
    )
    @duckdb_compute.dispose_managed_input_duckdb_completion(completion)
    assert_true(
      @duckdb_compute.managed_input_duckdb_scratch_released(completion),
    )
    assert_false(
      @duckdb_compute.bind_managed_input_duckdb_completion_attempt(
        completion,
        @execution.issue_managed_execution_attempt(),
      ),
    )
  }
}

///|
test "DuckDB scratch release waits for reentrant producer availability during value finish" {
  let current : Ref[@duckdb_compute.ManagedInputDuckDBCompletion[Unit]?] = Ref(
    None,
  )
  let observed = Ref(false)
  let released_during_finish = Ref(true)
  let (source, output) = managed_scratch_test_source(available=fn() {
    if current.val is Some(completion) {
      observed.val = true
      @duckdb_compute.dispose_managed_input_duckdb_completion(completion)
      released_during_finish.val = @duckdb_compute.managed_input_duckdb_scratch_released(
        completion,
      )
    }
    true
  })
  let owner = typed_receiver(
    source, "[{\"filter\":\"n > 0\"},{\"select\":[\"n\"]}]",
  )
  let input = @execution.prepare_managed_producer_read(
    owner, 0, source, output, 100, 1000,
  ).unwrap()
  let query = @duckdb.prepare_managed_fixed_query(
    input,
    "held",
    native_compile_limits(),
  ).unwrap()
  let completion = @duckdb_compute.prepare_managed_input_duckdb_completion(
    query,
    task_test_completion(owner),
    @execution.selected_managed_execution_profile(),
    fixed_compute_attempt_limits(),
    2,
    100,
    fn() { true },
    fn(_) { true },
  ).unwrap()
  let values = @duckdb_compute.managed_input_duckdb_output_values(completion)
  @execution.enable_managed_row_measurements(values, 2).unwrap()
  let physical = @duckdb.prepare_managed_physical_output(
    values,
    [("n", @duckdb.Float64)],
    fixed_compute_attempt_limits().physical,
    100,
  ).unwrap()
  @duckdb.append_managed_physical_output(physical, 1, [
    input_cursor("[\"4008000000000000\"]"),
  ]).unwrap()
  current.val = Some(completion)
  assert_true(@duckdb.finish_managed_physical_output(physical) is Err(_))
  assert_true(observed.val)
  assert_false(released_during_finish.val)
  assert_true(@duckdb_compute.managed_input_duckdb_scratch_released(completion))
  assert_true(@execution.finish_managed_output_values(values) is Err(Closed))
}

///|
test "managed reference callbacks cannot release active scratch or resurrect disposed rows" {
  for during_finish in [false, true] {
    let owner = managed_scratch_reference_owner()
    let values = @execution.prepare_managed_output_values(
      owner,
      @pipeline.Step(0),
      2,
      { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
      1000,
      { max_work: 1000, max_bytes: 1000, max_nodes: 100, max_depth: 10, },
    ).unwrap()
    @execution.enable_managed_row_measurements(values, 2).unwrap()
    let armed = Ref(false)
    let observed = Ref(false)
    let released_during_callback = Ref(true)
    let issuer = @admitted.bind_reference_issuer(fn(_, _) { true }, fn(_) {
      if armed.val {
        observed.val = true
        @execution.dispose_managed_output_values_scratch(values)
        released_during_callback.val = @execution.managed_output_values_scratch_released(
          values,
        )
      }
      true
    })
    let schema = @execution.managed_output_values_schema(values)
    let checked = @admitted.issue_reference(
      issuer,
      @schema.field_at(schema, 0).unwrap().contract,
      "{\"$actql_ref\":\"artifact\",\"artifact_ref_cid\":\"sha256:" +
      "a".repeat(64) +
      "\",\"media_type\":\"text/plain\",\"metadata\":{},\"version\":\"actql-artifact-ref/0.1\"}",
      { max_bytes: 1000, max_nodes: 100, max_depth: 10, max_text_units: 1000, },
    ).unwrap()
    if during_finish {
      for _ in 0..<2 {
        @execution.append_managed_output_values(values, 1, fn(_) {
          Some(checked)
        }).unwrap()
      }
      armed.val = true
      assert_true(
        @execution.finish_managed_output_values(values) is Err(Closed),
      )
    } else {
      armed.val = true
      assert_true(
        @execution.append_managed_output_values(values, 1, fn(_) {
          Some(checked)
        })
        is Err(Closed),
      )
    }
    assert_true(observed.val)
    assert_false(released_during_callback.val)
    assert_true(@execution.managed_output_values_scratch_released(values))
    assert_true(@execution.finish_managed_output_values(values) is Err(Closed))
  }
}

///|
fn managed_scratch_reference_owner() -> @lower.BoundPrepared {
  let contract = @value_contract.read_checked(
    input_cursor("{\"type\":\"artifact_ref\",\"nullable\":false}"),
    { max_nodes: 10, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let schema = @schema.from_fields(
    [(@schema.Unqualified("ref"), contract)],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let checked = @pipeline.check(
    input_cursor("[{\"select\":[\"ref\"]}]"),
    [("fixed", schema)],
    None,
    None,
    {
      max_steps: 2,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "managed direct and wire projections hold scratch through liveness callbacks" {
  for mode in 0..<4 {
    let wire_projection = mode >= 2
    let reentrant = mode % 2 == 1
    let owner = remote_completion_owner()
    let values = remote_completion_values(owner)
    let schema = @execution.managed_output_values_schema(values)
    let admitted = @execution.prepare_admitted_output(
      owner,
      @pipeline.Step(1),
      2,
      { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    ).unwrap()
    @execution.append_admitted_output(admitted, [
      @admitted.checked_number_value(
        3.0,
        @schema.field_at(schema, 0).unwrap().contract,
      ).unwrap(),
    ]).unwrap()
    let rows = @execution.finish_admitted_output(admitted).unwrap()
    let armed = Ref(false)
    let observed = Ref(false)
    let released_during_callback = Ref(true)
    let port = @execution.prepare_trusted_output_port(
      task_test_completion(owner),
      @pipeline.Step(1),
      100,
      1000,
      fn(_ : Unit) {
        if armed.val {
          observed.val = true
          @execution.dispose_managed_output_values_scratch(values)
          released_during_callback.val = @execution.managed_output_values_scratch_released(
            values,
          )
        }
        Some(rows)
      },
    ).unwrap()
    let output = @execution.complete_trusted_output(port, ()).unwrap()
    armed.val = reentrant
    let result = if wire_projection {
      @execution.append_completed_projection_managed_wire(
        values,
        output,
        0,
        row_wire_limits(),
        {
          max_bytes: 1000,
          max_nodes: 100,
          max_depth: 10,
          max_text_bytes: 1000,
        },
      )
    } else {
      @execution.append_completed_projection_managed_values(values, output, 0)
    }
    if reentrant {
      assert_true(result is Err(_))
      assert_true(observed.val)
      assert_false(released_during_callback.val)
      assert_true(@execution.managed_output_values_scratch_released(values))
      assert_true(
        @execution.finish_managed_output_values(values) is Err(Closed),
      )
    } else {
      result.unwrap()
      let receipt = @execution.finish_managed_output_values(values).unwrap()
      assert_eq(@execution.managed_output_value_row_count(receipt), 1)
      @execution.dispose_managed_output_values_scratch(values)
      assert_true(@execution.managed_output_values_scratch_released(values))
      assert_eq(@execution.managed_output_value_row_count(receipt), 1)
    }
  }
}

///|
test "managed verified port reservation releases after cancel and reentrant verifier disposal" {
  for reentrant in [false, true] {
    let values = remote_completion_values(remote_completion_owner())
    let observed = Ref(false)
    let released_during_callback = Ref(true)
    let port = @execution.prepare_managed_verified_output_port(values, fn(
      _ : Unit,
    ) {
      observed.val = true
      @execution.dispose_managed_output_values_scratch(values)
      released_during_callback.val = @execution.managed_output_values_scratch_released(
        values,
      )
      None
    }).unwrap()
    assert_false(@execution.managed_output_values_scratch_released(values))
    if reentrant {
      assert_true(@execution.finish_managed_verified_output(port, ()) is Err(_))
      assert_true(observed.val)
      assert_false(released_during_callback.val)
    } else {
      assert_true(@execution.cancel_managed_verified_output_port(port))
      @execution.dispose_managed_output_values_scratch(values)
      assert_false(observed.val)
    }
    assert_true(@execution.managed_output_values_scratch_released(values))
    @execution.dispose_managed_output_values_scratch(values)
    assert_true(@execution.managed_output_values_scratch_released(values))
    assert_true(@execution.finish_managed_verified_output(port, ()) is Err(_))
  }
}

///|
test "managed view port reservation releases after cancel and reentrant verifier disposal" {
  for reentrant in [false, true] {
    let (source, output) = managed_scratch_test_source()
    let owner = typed_receiver(source, "[{\"select\":[\"n\"]}]")
    let input = @execution.prepare_managed_producer_read(
      owner, 0, source, output, 100, 1000,
    ).unwrap()
    let kernel = @lower.prepare_kernel(
      owner,
      0,
      max_bindings=100,
      max_name_bytes=1000,
      native_compile_limits().expressions,
    ).unwrap()
    let plan = @execution.prepare_managed_view_plan(
      input,
      [kernel],
      1000,
      1000,
      10,
    ).unwrap()
    let values = @execution.prepare_managed_output_values(
      owner,
      @pipeline.Step(0),
      2,
      { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
      1000,
      { max_work: 1000, max_bytes: 1000, max_nodes: 100, max_depth: 10, },
    ).unwrap()
    let observed = Ref(false)
    let released_during_callback = Ref(true)
    let port = @execution.prepare_managed_view_output_port(plan, values, fn(
      _ : Unit,
    ) {
      observed.val = true
      @execution.dispose_managed_output_values_scratch(values)
      released_during_callback.val = @execution.managed_output_values_scratch_released(
        values,
      )
      None
    }).unwrap()
    assert_false(@execution.managed_output_values_scratch_released(values))
    if reentrant {
      assert_true(@execution.finish_managed_view_output(port, ()) is Err(_))
      assert_true(observed.val)
      assert_false(released_during_callback.val)
    } else {
      assert_true(@execution.cancel_managed_view_output_port(port))
      @execution.dispose_managed_output_values_scratch(values)
      assert_false(observed.val)
    }
    assert_true(@execution.managed_output_values_scratch_released(values))
    @execution.dispose_managed_output_values_scratch(values)
    assert_true(@execution.managed_output_values_scratch_released(values))
    assert_true(@execution.finish_managed_view_output(port, ()) is Err(_))
    assert_true(@execution.managed_completed_output_available(output))
  }
}

///|
test "successful managed view and verified receipts survive admission scratch disposal" {
  let (source, output) = managed_scratch_test_source()
  let owner = typed_receiver(source, "[{\"select\":[\"n\"]}]")
  let input = @execution.prepare_managed_producer_read(
    owner, 0, source, output, 100, 1000,
  ).unwrap()
  let column = @execution.managed_producer_read_column_measurement(input, 0).unwrap()
  let kernel = @lower.prepare_kernel(
    owner,
    0,
    max_bindings=100,
    max_name_bytes=1000,
    native_compile_limits().expressions,
  ).unwrap()
  let plan = @execution.prepare_managed_view_plan(
    input,
    [kernel],
    1000,
    1000,
    10,
  ).unwrap()
  let facts : @execution.ManagedViewOutputFacts = {
    rows: 1,
    columns: [column],
    admission_usage: { nodes: 2, text_bytes: 1, work: 2, },
  }
  for view in [false, true] {
    let values = @execution.prepare_managed_output_values(
      owner,
      @pipeline.Step(0),
      2,
      { max_nodes: 100, max_text_bytes: 1000, max_depth: 100, max_work: 1000, },
      1000,
      { max_work: 1000, max_bytes: 1000, max_nodes: 100, max_depth: 100, },
    ).unwrap()
    let receipt = if view {
      let port = @execution.prepare_managed_view_output_port(plan, values, fn(
        _ : Unit,
      ) {
        Some(facts)
      }).unwrap()
      @execution.finish_managed_view_output(port, ()).unwrap()
    } else {
      let port = @execution.prepare_managed_verified_output_port(values, fn(
        _ : Unit,
      ) {
        Some(facts)
      }).unwrap()
      @execution.finish_managed_verified_output(port, ()).unwrap()
    }
    assert_eq(@execution.managed_output_value_row_count(receipt), 1)
    let usage = @execution.managed_output_value_usage(receipt)
    assert_false(@execution.managed_output_values_scratch_released(values))
    @execution.dispose_managed_output_values_scratch(values)
    assert_true(@execution.managed_output_values_scratch_released(values))
    assert_eq(@execution.managed_output_value_row_count(receipt), 1)
    assert_eq(@execution.managed_output_value_usage(receipt), usage)
    assert_true(@execution.managed_completed_output_available(output))
  }
}

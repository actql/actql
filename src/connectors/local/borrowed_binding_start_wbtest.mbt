///|
test "singleton borrowed binding leaves meter output DATA without admitting constructors or injected providers" {
  for
    (expression, borrowed) in [
      ("{\"literal\":\"ÿ\"}", true),
      ("\"1 + 2\"", true),
      ("\"1 = 2\"", true),
      ("{\"field\":\"payload\"}", true),
      ("{\"literal\":[1,2]}", true),
      ("{\"literal\":{\"x\":1}}", true),
      ("{\"object\":{\"x\":{\"field\":\"payload\"}}}", false),
      ("{\"array\":[{\"field\":\"payload\"}]}", false),
    ] {
    let (chain, _, _) = chain_lifetime_fixture(
      "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"payload\":\"é\"}]},\"as\":\"value\"},{\"from\":\"value\",\"derive\":{\"result\":" +
      expression +
      "}}]",
    )
    let selected = @execution.select_generated_sequence_step(
      chain,
      @execution.generated_sequence_step_index_at(chain, 1).unwrap(),
    ).unwrap()
    guard @execution.generated_sequence_step_at(selected, 0)
      is Some(@lower.RowStep(kernel)) else {
      fail("original binding kernel")
    }
    assert_eq(selected_binding_outputs_borrowed(kernel), borrowed)
    let registry = @connector.prepare_capability_registry(
      [
        {
          name: "local",
          acquisition: false,
          fixed_compute: true,
          effect: false,
        },
      ],
      1,
      100,
    ).unwrap()
    let registration = @connector.capability_registration_at(registry, 0).unwrap()
    let original = prepare_local_compute_module(
      registry,
      registration,
      [selected],
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
    ).unwrap()
    let full = local_module_capacity_for_sequence(original, 0, selected).unwrap()
    let metered = local_module_metered_output_start_capacity(
      original, 0, selected,
    ).unwrap()
    if borrowed {
      assert_true(metered.retained_bytes < full.retained_bytes)
    } else {
      assert_eq(metered.retained_bytes, full.retained_bytes)
    }
    // The logical constructor and traversal recipe itself stays unchanged;
    // this selection defers only persistent output to the existing growth link.
    let more_output = @execution.generated_bounded_sequence_capacity(
      selected,
      {
        ..chain_lifetime_limits(),
        rows: {
          ..chain_lifetime_limits().rows,
          output_values: {
            ..chain_lifetime_limits().rows.output_values,
            max_nodes: chain_lifetime_limits().rows.output_values.max_nodes + 1,
          },
        },
      },
      chain_lifetime_measurement(),
    ).unwrap()
    assert_eq(more_output.retained_bytes - full.retained_bytes, 256L)
    assert_eq(more_output.execution_bytes - full.execution_bytes, 256L)
    let replacement = managed_provider(_ => true, _ => Some(full), (
      _,
      _,
      _,
      _,
      _,
    ) => Err(@connector.InvalidLimits))
    let injected = prepare_local_compute_module(
      registry,
      registration,
      [selected],
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
      managed_providers=[replacement],
    ).unwrap()
    assert_true(
      local_module_metered_output_start_capacity(injected, 0, selected) is None,
    )
    assert_eq(
      local_module_capacity_for_sequence(injected, 0, selected).map(value => {
        (value.retained_bytes, value.execution_bytes)
      }),
      Some((full.retained_bytes, full.execution_bytes)),
    )
    @connector.close_capability_registry(registry)
  }
}

///|
test "ordered borrowed bindings retain repeated original prior-slot occurrences" {
  let owner = chain_lifetime_bind(
    @pipeline.check(
      chain_lifetime_cursor(
        "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"payload\":\"é\"}]},\"as\":\"value\"},{\"derive\":[{\"first\":\"payload\"},{\"second\":\"first\"},{\"again\":\"first\"}]}]",
      ),
      [],
      None,
      None,
      {
        max_steps: 100,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
  let kernel = @lower.prepare_kernel(
    owner,
    1,
    max_bindings=100,
    max_name_bytes=10000,
    {
      max_nodes: 10000,
      max_work: 100000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 10000,
    },
  ).unwrap()
  guard @lower.kernel_bindings(kernel) is Some(bindings) else {
    fail("original ordered binding kernel")
  }
  assert_true(@lower.bindings_ordered(bindings))
  assert_eq(@lower.bindings_count(bindings), 3)
  for index in 1..<3 {
    guard @lower.binding_at(bindings, index) is Some((_, expression)) else {
      fail("original prior-slot binding")
    }
    assert_true(
      @lower.expression_body(expression)
      is @lower.Field(_, @relation.PriorSlot(0)),
    )
  }
  assert_true(selected_binding_outputs_borrowed(kernel))
}

///|
test "constructed Text row chain keeps final holding prepaid and reclaims child scratch" {
  let check : @pipeline.Limits = {
    max_steps: 100,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_depth: 100,
  }
  let source_owner = chain_lifetime_bind(
    @pipeline.check(
      chain_lifetime_cursor(
        (
          #|[{"values":{"schema":{"id":{"type":"string","nullable":false},"key":{"type":"string","nullable":false}},"rows":[{"id":"second","key":"é😀"},{"id":"first","key":"key-1"}]},"as":"seed"}]
        ),
      ),
      [],
      None,
      None,
      check,
    ).unwrap(),
  )
  let source = @execution.completed_output(
    @execution.execute_generated_sequence(
      chain_lifetime_generated(source_owner),
      [],
      chain_lifetime_limits(),
    ).unwrap(),
    @pipeline.Step(0),
  ).unwrap()
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(source_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let receiver = chain_lifetime_bind(
    @pipeline.check_with_evidence(
      chain_lifetime_cursor(
        (
          #|[{"from":"source","derive":{"next_name":{"concat":[{"field":"key"},{"literal":"-processed"}]}},"as":"derived"},{"from":"derived","select":["id","next_name"]}]
        ),
      ),
      [("source", @pipeline.ProducedInput(producer))],
      None,
      None,
      check,
    ).unwrap(),
  )
  let sequence = chain_lifetime_generated(receiver, fragment_work=20000000L)
  assert_eq(@execution.generated_sequence_step_count(sequence), 2)
  guard @execution.generated_sequence_step_at(sequence, 0)
    is Some(@lower.RowStep(kernel)) else {
    fail("original constructed binding kernel")
  }
  assert_false(selected_binding_outputs_borrowed(kernel))
  let values : @execution.ValueLimits = {
    max_nodes: 20000,
    max_text_bytes: 20000000,
    max_depth: 100,
    max_work: 20000000,
  }
  let limits = {
    ..chain_lifetime_limits(),
    rows: {
      ..chain_lifetime_limits().rows,
      input_values: values,
      output_values: values,
    },
    max_work: 20000000,
  }
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  let installed = prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [sequence],
    limits,
    chain_lifetime_measurement(),
    100000,
    1,
  ).unwrap()
  let full = local_module_capacity_for_sequence(installed, 0, sequence).unwrap()
  let startup = local_module_metered_output_start_capacity(
    installed, 0, sequence,
  ).unwrap()
  // New Text remains owned DATA. Only the legacy whole-sequence scratch
  // floor is absent: complete child Fragment/workspace and intermediate
  // output growth still belong to this same bounded chain.
  assert_eq(startup.retained_bytes, full.retained_bytes)
  assert_true(startup.execution_bytes < full.execution_bytes)
  assert_true(startup.retained_bytes + startup.execution_bytes < 536870912L)
  let read = @execution.prepare_producer_read(
    receiver,
    @execution.bind_completed_input(receiver, 0, source_owner, source).unwrap(),
    1000,
    10000,
  ).unwrap()
  for small in [false, true] {
    let selected_limits = if small {
      { ..limits, max_work: 1, }
    } else {
      limits
    }
    let (active, state) = bounded_relation_chain_execution_state(
      sequence,
      [managed_provider_relation_input(read)],
      selected_limits,
      chain_lifetime_measurement(),
      10000,
      None,
      [],
    ).unwrap()
    let mut output : @execution.CompletedOutput? = None
    let mut failed = false
    for _ in 0..<10000 {
      if output is Some(_) || failed {
        break
      }
      match advance_managed_provider(active, 1).unwrap() {
        Continue(..) => ()
        Complete(value, ..) => output = Some(value)
        Failed(issue, ..) => {
          assert_true(small)
          // The original shared chain refuses exhausted work before opening
          // another child, rather than reporting a row evaluator failure.
          assert_true(issue is @connector.Execution(@execution.InputLimit))
          failed = true
        }
        _ => fail("unexpected constructed Text chain outcome")
      }
    }
    if small {
      assert_true(failed)
      assert_true(output is None)
    } else {
      let output = output.unwrap()
      assert_eq(@execution.completed_row_count(output), 2)
      for
        row, (id, text) in [
          ("second", "é😀-processed"),
          ("first", "key-1-processed"),
        ] {
        assert_true(
          @execution.completed_cell(output, row, 0)
          is Some(@execution.Text(actual)) &&
          actual == id,
        )
        assert_true(
          @execution.completed_cell(output, row, 1)
          is Some(@execution.Text(actual)) &&
          actual == text,
        )
      }
    }
    assert_true(cleanup_managed_provider(active).unwrap())
    assert_true(state.current is None)
    assert_true(state.children.is_empty())
    assert_true(state.completed.is_empty())
    assert_true(@execution.producer_read_available(read))
    assert_true(@execution.completed_output_available(source))
  }
  @connector.close_capability_registry(registry)
}

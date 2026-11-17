///|
fn unpivot_label_chain_sequence(
  recursive_output? : Bool = false,
) -> @execution.GeneratedSequence raise {
  let binding = if recursive_output {
    "{\"array\":[{\"field\":\"private_name\"}]}"
  } else {
    "{\"if\":[{\"eq\":[{\"field\":\"private_name\"},{\"literal\":\"first_input\"}]},{\"literal\":\"first\"},{\"literal\":\"second\"}]}"
  }
  let prefix =
    #|[{"values":{"schema":{"id":{"type":"number","nullable":false},"jan":{"type":"number","nullable":true},"feb":{"type":"number","nullable":true}},"rows":[{"id":2,"jan":7,"feb":null},{"id":1,"jan":null,"feb":5},{"id":2,"jan":7,"feb":null}]},"as":"wide"},{"from":"wide","select":["id","feb",{"first_input":"jan"},{"second_input":"jan"}]},{"unpivot":{"columns":["first_input","second_input"],"keep":["id","feb"],"value_column":"amount","name_column":"private_name"}},{"derive":{"month":
  let suffix =
    #|}},{"sort":[{"field":"id","dir":"asc","nulls":"first"}]},{"select":["id","amount","month"]}]
  let owner = chain_lifetime_bind(
    @pipeline.check(
      chain_lifetime_cursor(prefix + binding + suffix),
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
  chain_lifetime_generated(owner, fragment_work=20000000L)
}

///|
test "literal UNPIVOT chain preserves full Text DATA and charges original output before transfer" {
  let sequence = unpivot_label_chain_sequence()
  assert_eq(@execution.generated_sequence_step_count(sequence), 6)
  assert_true(selected_literal_unpivot_chain(sequence))
  let recursive = unpivot_label_chain_sequence(recursive_output=true)
  assert_false(selected_literal_unpivot_chain(recursive))
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
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let installed = prepare_local_compute_module(
    registry,
    registration,
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
  assert_eq(startup.retained_bytes, full.retained_bytes)
  assert_true(startup.execution_bytes < full.execution_bytes)
  assert_true(startup.execution_bytes < 536870912L)
  assert_true(
    local_module_metered_output_start_capacity(
      installed,
      0,
      unpivot_label_chain_sequence(),
    )
    is None,
  )
  let replacement = managed_provider(_ => true, _ => Some(full), (_, _, _, _, _) => {
    Err(@connector.InvalidLimits)
  })
  let injected = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    limits,
    chain_lifetime_measurement(),
    100000,
    1,
    managed_providers=[replacement],
  ).unwrap()
  assert_true(
    local_module_metered_output_start_capacity(injected, 0, sequence) is None,
  )
  for mode in [0, 1, 2, 3] {
    let selected = if mode == 1 { { ..limits, max_work: 1, } } else { limits }
    let requests = []
    let funded = @execution.bind_generated_workspace_growth(
      sequence,
      selected,
      536870912L,
      bytes => {
        requests.push(bytes)
        if mode == 2 {
          Err(@execution.WorkspaceUnavailable)
        } else {
          Ok(())
        }
      },
      meter_retained_outputs=true,
    ).unwrap()
    let (active, state) = bounded_relation_chain_execution_state(
      funded,
      [],
      selected,
      chain_lifetime_measurement(),
      10000,
      None,
      [],
    ).unwrap()
    let mut output : @execution.CompletedOutput? = None
    let mut failed = false
    let mut stopped = false
    let mut cancelled = false
    for _ in 0..<100000 {
      if output is Some(_) || failed || stopped {
        break
      }
      match advance_managed_provider(active, 1).unwrap() {
        Continue(work~, ..) =>
          if mode == 3 &&
            !cancelled &&
            state.position == 2 &&
            state.current is Some(_) &&
            work > 0L {
            assert_true(cancel_managed_provider(active))
            cancelled = true
          }
        Waiting(..) => ()
        Complete(value, ..) => output = Some(value)
        Failed(_, ..) => {
          assert_true(mode != 0)
          failed = true
        }
        Stopped(..) => stopped = true
        _ => fail("unexpected UNPIVOT chain outcome")
      }
    }
    if mode == 0 {
      let output = output.unwrap()
      assert_eq(@execution.completed_row_count(output), 6)
      for
        row, expected in [
          "{\"id\":1,\"amount\":null,\"month\":\"first\"}", "{\"id\":1,\"amount\":null,\"month\":\"second\"}",
          "{\"id\":2,\"amount\":7,\"month\":\"first\"}", "{\"id\":2,\"amount\":7,\"month\":\"second\"}",
          "{\"id\":2,\"amount\":7,\"month\":\"first\"}", "{\"id\":2,\"amount\":7,\"month\":\"second\"}",
        ] {
        assert_eq(
          @json.parse(
            @execution.completed_output_row_wire(output, row, 1000, 100, 10).unwrap(),
          ),
          @json.parse(expected),
        )
      }
      assert_false(requests.is_empty())
      assert_true(requests.all(bytes => bytes >= 0L && bytes <= 536870912L))
    } else if mode == 3 {
      assert_true(cancelled && stopped && !failed && output is None)
    } else {
      assert_true(failed && output is None)
      if mode == 2 {
        assert_false(requests.is_empty())
      }
    }
    let mut clean = false
    for _ in 0..<10000 {
      if cleanup_managed_provider(active).unwrap() {
        clean = true
        break
      }
    }
    assert_true(clean)
    assert_true(
      state.current is None &&
      state.children.is_empty() &&
      state.completed.is_empty(),
    )
  }
  @connector.close_capability_registry(registry)
}

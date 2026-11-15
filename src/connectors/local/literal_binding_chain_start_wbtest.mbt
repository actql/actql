///|
fn literal_binding_chain_sequence(
  constructed_array? : Bool = false,
) -> @execution.GeneratedSequence raise {
  let binding = if constructed_array {
    "{\"array\":[{\"field\":\"payload\"}]}"
  } else {
    "{\"replace\":[{\"field\":\"payload\"},{\"literal\":\"ana\"},{\"literal\":\"X\"}]}"
  }
  let owner = chain_lifetime_bind(
    @pipeline.check(
      chain_lifetime_cursor(
        "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"payload\":{\"type\":\"string\",\"nullable\":true}},\"rows\":[{\"id\":3,\"payload\":null},{\"id\":1,\"payload\":\"banana\"},{\"id\":2,\"payload\":\"\"}]},\"as\":\"seed\"},{\"derive\":{\"replaced\":" +
        binding +
        ",\"length\":{\"len\":{\"field\":\"payload\"}}},\"as\":\"derived\"},{\"select\":[\"id\",\"replaced\",\"length\"]}]",
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
  chain_lifetime_generated(owner, fragment_work=20000000L)
}

///|
test "literal nullable Text chain retains full DATA and bounded child scratch while funding original output before transfer" {
  let sequence = literal_binding_chain_sequence()
  assert_eq(@execution.generated_sequence_step_count(sequence), 3)
  assert_true(selected_literal_binding_chain(sequence))
  assert_false(
    selected_literal_binding_chain(
      literal_binding_chain_sequence(constructed_array=true),
    ),
  )
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
  assert_true(startup.retained_bytes + startup.execution_bytes < 536870912L)
  let injected = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    limits,
    chain_lifetime_measurement(),
    100000,
    1,
    managed_providers=[],
  ).unwrap()
  // An empty provider set still selects the original default; a real
  // injected provider below cannot borrow this built-in constructor proof.
  assert_true(
    local_module_metered_output_start_capacity(injected, 0, sequence) is Some(_),
  )
  let replacement = managed_provider(_ => true, _ => Some(full), (_, _, _, _, _) => {
    Err(@connector.InvalidLimits)
  })
  let foreign = prepare_local_compute_module(
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
    local_module_metered_output_start_capacity(foreign, 0, sequence) is None,
  )
  for mode in [0, 1, 2] {
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
    for _ in 0..<100000 {
      if output is Some(_) || failed {
        break
      }
      match advance_managed_provider(active, 1).unwrap() {
        Continue(..) | Waiting(..) => ()
        Complete(value, ..) => output = Some(value)
        Failed(issue, ..) => {
          assert_true(mode != 0)
          if mode == 1 {
            assert_true(issue is @connector.Execution(@execution.InputLimit))
          }
          failed = true
        }
        _ => fail("unexpected original literal binding chain outcome")
      }
    }
    if mode == 0 {
      let output = output.unwrap()
      assert_eq(@execution.completed_row_count(output), 3)
      for
        row, expected in [
          "{\"id\":3,\"length\":null,\"replaced\":null}", "{\"id\":1,\"length\":6,\"replaced\":\"bXna\"}",
          "{\"id\":2,\"length\":0,\"replaced\":\"\"}",
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

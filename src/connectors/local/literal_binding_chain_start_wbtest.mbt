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

///|
fn literal_string_group_sequence(
  wider? : Bool = false,
  distinct? : Bool = false,
  literal_argument? : Bool = false,
) -> @execution.GeneratedSequence raise {
  let text = "[{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":true},\"b\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"a\":1,\"b\":\"x\"},{\"a\":1,\"b\":\"x\"},{\"a\":2,\"b\":\"y\"},{\"a\":null,\"b\":\"n\"}]},\"as\":\"seed\"},{\"group\":{\"by\":[],\"aggregates\":{\"labels\":{\"fn\":\"string_agg\",\"field\":\"b\",\"delimiter\":\"|\",\"max_bytes\":10000,\"order_by\":[{\"a\":\"desc\"}]" +
    (if distinct { ",\"distinct\":true" } else { "" }) +
    "}}},\"as\":\"grouped\"},{\"select\":[\"labels\"]}" +
    (if wider { ",{\"select\":[\"labels\"]}" } else { "" }) +
    "]"
  let text = if literal_argument {
    text.replace(old="\"field\":\"b\"", new="\"expr\":{\"literal\":\"x\"}")
  } else {
    text
  }
  chain_lifetime_generated(
    chain_lifetime_bind(
      @pipeline.check(chain_lifetime_cursor(text), [], None, None, {
        max_steps: 100,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      }).unwrap(),
    ),
  )
}

///|
test "literal StringAgg chain peak coholds prior output and active full constructor without changing whole retention" {
  let sequence = literal_string_group_sequence()
  assert_true(@execution.bounded_literal_string_group_chain(sequence))
  let values : @execution.ValueLimits = {
    max_nodes: 28,
    max_text_bytes: 20000000,
    max_depth: 100,
    max_work: 20000000,
  }
  let limits = {
    ..chain_lifetime_limits(),
    rows: {
      ..chain_lifetime_limits().rows,
      max_rows: 4,
      input_values: values,
      output_values: values,
    },
    max_work: 20000000,
  }
  let measurement = {
    ..chain_lifetime_measurement(),
    max_nodes: 20000,
    max_bytes: 120000845,
    max_depth: 100,
  }
  let full = @execution.generated_sequence_capacity(
    sequence, limits, measurement,
  ).unwrap()
  let quote = bounded_relation_chain_capacity(sequence, limits, measurement, []).unwrap()
  let mut prior = 0L
  let mut peak = 0L
  let mut largest_child = 0L
  for index in 0..<3 {
    let step = @execution.generated_sequence_step_index_at(sequence, index).unwrap()
    let selected = @execution.select_generated_sequence_step(sequence, step).unwrap()
    let child = chain_lifetime_child_capacity(selected, limits, measurement)
    peak = Int64::max(peak, prior + child.execution_bytes)
    largest_child = Int64::max(largest_child, child.execution_bytes)
    prior += child.retained_bytes
  }
  peak = Int64::max(peak, prior)
  let controls = 3L * 256L + 512L + local_provider_selection_recipe_field_bytes
  assert_eq(quote.retained_bytes, full.retained_bytes)
  assert_eq(
    quote.execution_bytes,
    Int64::max(full.retained_bytes, peak + controls),
  )
  assert_true(quote.execution_bytes < prior + largest_child + controls)
  // The existing driver also retains its independent checked output copy.
  // Keep that entire outer holding alongside the actual chain peak.
  assert_true(quote.execution_bytes + full.retained_bytes < 536870912L)
  let (active, state) = bounded_relation_chain_execution_state(
    sequence,
    [],
    limits,
    measurement,
    10000,
    None,
    [],
  ).unwrap()
  let mut completed = false
  for _ in 0..<100000 {
    match advance_managed_provider(active, 1).unwrap() {
      Continue(..) | Waiting(..) => ()
      Complete(output, ..) => {
        assert_eq(@execution.completed_row_count(output), 1)
        assert_true(
          @execution.completed_cell(output, 0, 0)
          is Some(@execution.Text("y|x|x|n")),
        )
        completed = true
        break
      }
      _ => fail("original literal StringAgg chain did not complete")
    }
  }
  assert_true(completed)
  assert_true(state.completed[0] is Some(_))
  assert_true(state.completed[1] is Some(_))
  let literal = state.completed[0].unwrap()
  let grouped = state.completed[1].unwrap()
  assert_eq(@execution.completed_row_count(literal), 4)
  assert_true(@execution.completed_cell(literal, 3, 0) is Some(@execution.Null))
  assert_true(
    @execution.completed_cell(grouped, 0, 0) is Some(@execution.Text("y|x|x|n")),
  )
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_true(state.completed.is_empty())
  assert_true(@execution.completed_output_available(literal))
  assert_true(@execution.completed_output_available(grouped))
}

///|
test "literal StringAgg chain proof excludes wider distinct and injected provider recipes" {
  assert_false(
    @execution.bounded_literal_string_group_chain(
      literal_string_group_sequence(wider=true),
    ),
  )
  assert_false(
    @execution.bounded_literal_string_group_chain(
      literal_string_group_sequence(distinct=true),
    ),
  )
  assert_false(
    @execution.bounded_literal_string_group_chain(
      literal_string_group_sequence(literal_argument=true),
    ),
  )
  let sequence = literal_string_group_sequence()
  let limits = chain_lifetime_limits()
  let measurement = chain_lifetime_measurement()
  let original = @execution.execution_capacity(4000000L, 7000000L).unwrap()
  let replacement = managed_provider(_ => true, _ => Some(original), (
    _,
    _,
    _,
    _,
    _,
  ) => Err(@connector.InvalidLimits))
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
    measurement,
    100000,
    1,
    managed_providers=[replacement],
  ).unwrap()
  let selected = local_module_capacity(installed, 0).unwrap()
  assert_eq(selected.retained_bytes, original.retained_bytes)
  assert_eq(selected.execution_bytes, original.execution_bytes)
  assert_true(
    physical_equal(
      local_module_managed_provider(installed, 0, sequence).unwrap(),
      replacement,
    ),
  )
  assert_true(
    local_module_metered_output_start_capacity(installed, 0, sequence) is None,
  )
  @connector.close_capability_registry(registry)
}

///|
fn source_string_group_chain_fixture(
  distinct? : Bool = false,
) -> (
  @execution.GeneratedSequence,
  @execution.ProducerRead,
  @execution.CompletedOutput,
) raise {
  chain_lifetime_fixture(
    "[{\"from\":\"source\",\"derive\":{\"name\":{\"case\":{\"when\":[{\"when\":{\"eq\":[{\"field\":\"id\"},{\"literal\":1}]},\"then\":{\"literal\":\"z\"}}],\"else\":{\"literal\":\"a\"}}}}},{\"select\":[\"id\",\"name\"]},{\"derive\":{\"key\":{\"literal\":7}}},{\"group\":{\"by\":[],\"aggregates\":{\"names\":{\"fn\":\"string_agg\",\"field\":\"name\",\"order_by\":[{\"key\":\"desc\"},{\"id\":\"asc\"}],\"delimiter\":\"|\",\"max_bytes\":65536" +
    (if distinct { ",\"distinct\":true" } else { "" }) +
    "}}}}]",
  )
}

///|
test "Source ordered StringAgg chain keeps full retention and funds bounded children without a legacy table" {
  let (sequence, read, source) = source_string_group_chain_fixture()
  let values : @execution.ValueLimits = {
    max_nodes: 2800,
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
  let measurement = {
    ..chain_lifetime_measurement(),
    max_bytes: 120040633,
    max_nodes: 20000,
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
    measurement,
    100000,
    1,
  ).unwrap()
  let full = local_module_capacity(installed, 0).unwrap()
  let startup = local_module_metered_output_start_capacity(
    installed, 0, sequence,
  ).unwrap()
  assert_eq(startup.retained_bytes, full.retained_bytes)
  assert_true(startup.execution_bytes < full.execution_bytes)
  assert_true(startup.retained_bytes + startup.execution_bytes < 536870912L)
  let reserve_calls = Ref(0)
  let sequence = @execution.bind_generated_workspace_growth(
    sequence,
    limits,
    536870912L,
    _ => {
      reserve_calls.val += 1
      Ok(())
    },
    meter_retained_outputs=true,
  ).unwrap()
  let (active, state) = bounded_relation_chain_execution_state(
    sequence,
    [managed_provider_relation_input(read)],
    limits,
    measurement,
    120040633,
    None,
    [],
  ).unwrap()
  let mut complete = false
  for _ in 0..<100000 {
    match advance_managed_provider(active, 1).unwrap() {
      Continue(..) | Waiting(..) => ()
      Complete(output, ..) => {
        assert_eq(@execution.completed_row_count(output), 1)
        assert_true(
          @execution.completed_cell(output, 0, 0)
          is Some(@execution.Text("z|a|a")),
        )
        complete = true
        break
      }
      _ => fail("original Source StringAgg chain did not complete")
    }
  }
  assert_true(complete)
  assert_true(reserve_calls.val > 0)
  assert_true(state.completed[0] is Some(_))
  assert_true(state.completed[1] is Some(_))
  assert_true(state.completed[2] is Some(_))
  assert_true(@execution.completed_output_available(source))
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_true(state.completed.is_empty())
  assert_true(@execution.completed_output_available(source))
  @connector.close_capability_registry(registry)
}

///|
test "Source StringAgg startup preserves full DISTINCT DATA and injected constructor fallback" {
  let (sequence, _, _) = source_string_group_chain_fixture(distinct=true)
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let original = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    100000,
    1,
  ).unwrap()
  // DISTINCT now uses its actual charged bounded sorter/index constructor,
  // while the original standing output DATA remains completely prepaid.
  assert_false(@execution.bounded_literal_string_group_chain(sequence))
  let distinct = local_module_metered_output_start_capacity(
    original, 0, sequence,
  ).unwrap()
  let distinct_full = local_module_capacity(original, 0).unwrap()
  assert_eq(distinct.retained_bytes, distinct_full.retained_bytes)
  assert_true(distinct.execution_bytes <= distinct_full.execution_bytes)
  let (sequence, _, _) = source_string_group_chain_fixture()
  let original = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    100000,
    1,
  ).unwrap()
  let full = local_module_capacity(original, 0).unwrap()
  let injected = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    100000,
    1,
    managed_providers=[
      managed_provider(_ => true, _ => Some(full), (_, _, _, _, _) => {
        Err(@connector.InvalidLimits)
      }),
    ],
  ).unwrap()
  assert_true(
    local_module_metered_output_start_capacity(injected, 0, sequence) is None,
  )
  let unchanged = local_module_capacity(injected, 0).unwrap()
  assert_eq(unchanged.retained_bytes, full.retained_bytes)
  assert_eq(unchanged.execution_bytes, full.execution_bytes)
  @connector.close_capability_registry(registry)
}

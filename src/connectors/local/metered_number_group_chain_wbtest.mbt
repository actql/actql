///|
// A real completed producer supplies Text and Number cells to the same two
// children used by the wide Table program: LENGTH, then SUM/SUM/row COUNT.
fn metered_text_number_group_chain_fixture(
  count_field? : Bool = false,
) -> (
  @execution.GeneratedSequence,
  @execution.ProducerRead,
  @execution.CompletedOutput,
  @execution.NumericAggregateExecution,
) raise {
  let check_limits : @pipeline.Limits = {
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
          #|[{"values":{"schema":{"id":{"type":"number","nullable":false},"document":{"type":"string","nullable":false}},"rows":[{"id":0,"document":"abc"},{"id":1,"document":"é😀"},{"id":2,"document":"xxxxx"}]},"as":"seed"}]
        ),
      ),
      [],
      None,
      None,
      check_limits,
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
  let count = if count_field { ",\"field\":\"id\"" } else { "" }
  let receiver = chain_lifetime_bind(
    @pipeline.check_with_evidence(
      chain_lifetime_cursor(
        "[{\"from\":\"source\",\"derive\":{\"document_chars\":{\"len\":{\"field\":\"document\"}}},\"as\":\"measured\"},{\"from\":\"measured\",\"group\":{\"by\":[],\"aggregates\":{\"document_chars\":{\"fn\":\"sum\",\"field\":\"document_chars\"},\"id_sum\":{\"fn\":\"sum\",\"field\":\"id\"},\"row_count\":{\"fn\":\"count\"" +
        count +
        "}}},\"as\":\"summary\"}]",
      ),
      [("source", @pipeline.ProducedInput(producer))],
      None,
      None,
      check_limits,
    ).unwrap(),
  )
  let read = @execution.prepare_producer_read(
    receiver,
    @execution.bind_completed_input(receiver, 0, source_owner, source).unwrap(),
    1000,
    10000,
  ).unwrap()
  let profile = @numeric.builtin_profile()
  let reduction = @numeric.select(
    profile,
    @numeric.member_cid_at(profile, 0).unwrap(),
  ).unwrap()
  let numeric = @execution.numeric_aggregate_execution((
    _,
    name,
    _,
    contributors,
    count,
    work,
  ) => {
    match name {
      "document_chars" | "id_sum" =>
        Some(
          @numeric.execute(reduction, @numeric.Sum, contributors, count, work),
        )
      _ => None
    }
  })
  // SUM uses the same real common numeric executor as managed dispatch. The
  // general lifetime helper intentionally supplies none for nonnumeric cases.
  (
    @execution.bind_generated_numeric_execution(
      chain_lifetime_generated(receiver),
      numeric,
    ),
    read,
    source,
    numeric,
  )
}

///|
test "original LENGTH and mixed Number group chain select the same metered constructor" {
  let (sequence, read, source, numeric) = metered_text_number_group_chain_fixture()
  assert_eq(@execution.generated_sequence_step_count(sequence), 2)
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
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    100000,
    1,
  ).unwrap()
  let full = local_module_capacity_for_sequence(installed, 0, sequence).unwrap()
  let startup = local_module_metered_output_start_capacity(
    installed, 0, sequence,
  ).unwrap()
  assert_true(startup.execution_bytes < full.execution_bytes)
  assert_true(startup.retained_bytes < full.retained_bytes)
  // Constructor credit belongs to this same built-in. An injected provider
  // keeps the original full quote and cannot execute during quote selection.
  let starts = Ref(0)
  let replacement = managed_provider(_ => true, _ => Some(full), (_, _, _, _, _) => {
    starts.val += 1
    Err(@connector.InvalidLimits)
  })
  let injected = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    100000,
    1,
    managed_providers=[replacement],
  ).unwrap()
  assert_true(
    local_module_metered_output_start_capacity(injected, 0, sequence) is None,
  )
  assert_eq(starts.val, 0)
  let (active, state) = bounded_relation_chain_execution_state(
    sequence,
    [managed_provider_relation_input(read)],
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    10000,
    Some(numeric),
    [],
  ).unwrap()
  let cleanups = Array::make(2, 0)
  let mut watched = -1
  let mut result : @execution.CompletedOutput? = None
  for _ in 0..<100000 {
    if result is Some(_) {
      break
    }
    if !state.pending && watched != state.position {
      chain_lifetime_watch_child(state, cleanups)
      watched = state.position
    }
    match advance_managed_provider(active, 1).unwrap() {
      Continue(..) => ()
      Complete(output, ..) => result = Some(output)
      _ => fail("actual LENGTH/group chain did not complete")
    }
  }
  let output = result.unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  for column, expected in [10.0, 3.0, 3.0] {
    assert_true(
      @execution.completed_cell(output, 0, column)
      is Some(@execution.Number(actual)) &&
      actual == expected,
    )
  }
  assert_eq(cleanups, [1, 0])
  assert_true(@execution.producer_read_available(read))
  assert_true(@execution.completed_output_available(source))
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_eq(cleanups, [1, 1])
  assert_true(state.current is None)
  assert_true(state.children.is_empty())
  assert_true(state.completed.is_empty())
  assert_true(@execution.completed_output_available(output))
  @connector.close_capability_registry(registry)
}

///|
test "nullable Text choice LENGTH COUNT and arithmetic retain their original borrowed cells" {
  let check_limits : @pipeline.Limits = {
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
          #|[{"values":{"schema":{"id":{"type":"number","nullable":false},"amount":{"type":"number","nullable":true}},"rows":[{"id":3,"amount":30},{"id":1,"amount":null},{"id":2,"amount":20},{"id":3,"amount":30}]},"as":"seed"}]
        ),
      ),
      [],
      None,
      None,
      check_limits,
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
          #|[{"from":"source","derive":{"name":{"if":[{"eq":[{"field":"id"},{"literal":1}]},{"literal":null},{"if":[{"eq":[{"field":"id"},{"literal":2}]},{"literal":"e\u0301"},{"literal":"😀"}]}]}}},{"derive":{"key":{"len":{"field":"name"}}}},{"group":{"by":["key"],"aggregates":{"n":{"fn":"count"}}}},{"derive":{"total":{"add":[{"field":"n"},{"field":"key"}]}}},{"select":[{"width":"key"},"total"]},{"sort":[{"field":"width","dir":"asc","nulls":"last"}],"as":"ordered"}]
        ),
      ),
      [("source", @pipeline.ProducedInput(producer))],
      None,
      None,
      check_limits,
    ).unwrap(),
  )
  let read = @execution.prepare_producer_read(
    receiver,
    @execution.bind_completed_input(receiver, 0, source_owner, source).unwrap(),
    1000,
    10000,
  ).unwrap()
  let sequence = chain_lifetime_generated(receiver)
  let count = @execution.select_generated_sequence_step(sequence, 2).unwrap()
  let original_limits = chain_lifetime_limits()
  let quote = fn(limits, measurement) {
    managed_provider_capacity(
      local_bounded_relation_provider(limits, measurement, count).unwrap(),
      count,
    ).unwrap()
  }
  let before = quote(original_limits, chain_lifetime_measurement())
  // This exact CountGroups constructor charges every cell with its stepped
  // measuring cursor. Unused input/measurement codec maxima do not allocate
  // another forest or wire. Actual limits and independent workspace remain.
  let after = quote(
    {
      ..original_limits,
      rows: {
        ..original_limits.rows,
        input_values: {
          ..original_limits.rows.input_values,
          max_nodes: 1000000,
          max_text_bytes: 20000000,
        },
      },
    },
    { ..chain_lifetime_measurement(), max_nodes: 1000000, max_bytes: 20000000, },
  )
  assert_eq(before.retained_bytes, after.retained_bytes)
  assert_eq(before.execution_bytes, after.execution_bytes)
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  let installed = prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [sequence],
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    100000,
    1,
  ).unwrap()
  let full = local_module_capacity_for_sequence(installed, 0, sequence).unwrap()
  let startup = local_module_metered_output_start_capacity(
    installed, 0, sequence,
  ).unwrap()
  assert_true(startup.execution_bytes < full.execution_bytes)
  let (active, state) = bounded_relation_chain_execution_state(
    sequence,
    [managed_provider_relation_input(read)],
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    10000,
    None,
    [],
  ).unwrap()
  let mut result : @execution.CompletedOutput? = None
  for _ in 0..<100000 {
    match advance_managed_provider(active, 1).unwrap() {
      Continue(..) => ()
      Complete(output, ..) => {
        result = Some(output)
        break
      }
      _ => fail("the same nullable scalar chain must finish")
    }
  }
  let output = result.unwrap()
  assert_eq(@execution.completed_row_count(output), 3)
  assert_eq(@execution.completed_column_count(output), 2)
  for column in 0..<2 {
    let name = @execution.completed_column_name(output, column).unwrap()
    assert_true(name == "width" || name == "total")
    for row in 0..<3 {
      if row == 2 {
        assert_true(
          @execution.completed_cell(output, row, column)
          is Some(@execution.Null),
        )
      } else {
        let expected = if name == "total" {
          3.0
        } else if row == 0 {
          1.0
        } else {
          2.0
        }
        assert_true(
          @execution.completed_cell(output, row, column)
          is Some(@execution.Number(actual)) &&
          actual == expected,
        )
      }
    }
  }
  assert_true(@execution.producer_read_available(read))
  assert_true(@execution.completed_output_available(source))
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_true(state.current is None)
  assert_true(state.children.is_empty())
  assert_true(state.completed.is_empty())
  assert_true(@execution.completed_output_available(output))
  @connector.close_capability_registry(registry)
}

///|
test "mixed Number chain preserves field COUNT fallback and cancellation between children" {
  let (unsupported, _, _, _) = metered_text_number_group_chain_fixture(
    count_field=true,
  )
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let installed = prepare_local_compute_module(
    registry,
    registration,
    [unsupported],
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    100000,
    1,
  ).unwrap()
  assert_true(
    local_module_metered_output_start_capacity(installed, 0, unsupported)
    is None,
  )
  let (sequence, read, source, numeric) = metered_text_number_group_chain_fixture()
  let (active, state) = bounded_relation_chain_execution_state(
    sequence,
    [managed_provider_relation_input(read)],
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    10000,
    Some(numeric),
    [],
  ).unwrap()
  let cleanups = Array::make(2, 0)
  chain_lifetime_watch_child(state, cleanups)
  for _ in 0..<100000 {
    if state.pending {
      break
    }
    assert_true(advance_managed_provider(active, 1).unwrap() is Continue(..))
  }
  assert_true(state.pending)
  assert_eq(state.position, 1)
  assert_eq(cleanups, [1, 0])
  assert_true(cancel_managed_provider(active))
  assert_true(
    advance_managed_provider(active, 1).unwrap() is Stopped(work=0L, ..),
  )
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_eq(cleanups, [1, 0])
  assert_true(state.current is None)
  assert_true(state.children.is_empty())
  assert_true(state.completed.is_empty())
  assert_true(@execution.producer_read_available(read))
  assert_true(@execution.completed_output_available(source))
  @connector.close_capability_registry(registry)
}

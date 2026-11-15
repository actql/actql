///|
fn metered_number_append_chain_fixture() -> (
  @execution.GeneratedSequence,
  Array[@execution.ProducerRead],
  Array[@execution.CompletedOutput],
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
  let owners = []
  let sources = []
  let inputs = []
  for
    index, (name, chars, id) in [
      ("first", 12, 2),
      ("second", 12, 2),
      ("third", 21, 5),
    ] {
    let owner = chain_lifetime_bind(
      @pipeline.check(
        chain_lifetime_cursor(
          "[{\"values\":{\"schema\":{\"document_chars\":{\"type\":\"number\",\"nullable\":false},\"id_sum\":{\"type\":\"number\",\"nullable\":false},\"row_count\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"document_chars\":" +
          chars.to_string() +
          ",\"id_sum\":" +
          id.to_string() +
          ",\"row_count\":1}]},\"as\":\"seed\"}]",
        ),
        [],
        None,
        None,
        check_limits,
      ).unwrap(),
    )
    let source = @execution.completed_output(
      @execution.execute_generated_sequence(
        chain_lifetime_generated(owner),
        [],
        chain_lifetime_limits(),
      ).unwrap(),
      @pipeline.Step(0),
    ).unwrap()
    let produced = @pipeline.produced_input(
      @lower.pipeline(@lower.bound_preparation(owner)),
      @pipeline.Step(0),
    ).unwrap()
    owners.push(owner)
    sources.push(source)
    inputs.push((name, @pipeline.ProducedInput(produced)))
    assert_eq(sources.length(), index + 1)
  }
  // Equal values come from two distinct completed originals. Each input
  // occurrence must contribute, even when its content identity is equal.
  assert_false(physical_equal(sources[0], sources[1]))
  let receiver = chain_lifetime_bind(
    @pipeline.check_with_evidence(
      chain_lifetime_cursor(
        (
          #|[{"from":"first","append":{"with":"second"},"as":"paired"},{"from":"paired","append":{"with":"third"},"as":"combined"},{"from":"combined","group":{"by":[],"aggregates":{"document_chars":{"fn":"sum","field":"document_chars"},"id_sum":{"fn":"sum","field":"id_sum"},"row_count":{"fn":"sum","field":"row_count"}}},"as":"summary"}]
        ),
      ),
      inputs,
      None,
      None,
      check_limits,
    ).unwrap(),
  )
  let reads = []
  for index, source in sources {
    reads.push(
      @execution.prepare_producer_read(
        receiver,
        @execution.bind_completed_input(receiver, index, owners[index], source).unwrap(),
        1000,
        10000,
      ).unwrap(),
    )
  }
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
      "document_chars" | "id_sum" | "row_count" =>
        Some(
          @numeric.execute(reduction, @numeric.Sum, contributors, count, work),
        )
      _ => None
    }
  })
  (
    @execution.bind_generated_numeric_execution(
      chain_lifetime_generated(receiver),
      numeric,
    ),
    reads,
    sources,
    numeric,
  )
}

///|
test "original non-JOIN Append chain retains every input before its numeric reduction" {
  let (sequence, reads, sources, numeric) = metered_number_append_chain_fixture()
  assert_eq(@execution.generated_sequence_step_count(sequence), 3)
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
  let (active, state) = bounded_relation_chain_execution_state(
    sequence,
    reads.map(managed_provider_relation_input),
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    10000,
    Some(numeric),
    [],
  ).unwrap()
  let cleanups = Array::make(3, 0)
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
      _ => fail("actual Append/reduction chain did not complete")
    }
  }
  let combined = state.completed[1].unwrap()
  assert_eq(@execution.completed_row_count(combined), 3)
  for row, expected in [[12.0, 2.0, 1.0], [12.0, 2.0, 1.0], [21.0, 5.0, 1.0]] {
    for column, number in expected {
      assert_true(
        @execution.completed_cell(combined, row, column)
        is Some(@execution.Number(actual)) &&
        actual == number,
      )
    }
  }
  let output = result.unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  for column, expected in [45.0, 9.0, 3.0] {
    assert_true(
      @execution.completed_cell(output, 0, column)
      is Some(@execution.Number(actual)) &&
      actual == expected,
    )
  }
  assert_eq(cleanups, [1, 1, 0])
  for index, source in sources {
    assert_true(@execution.producer_read_available(reads[index]))
    assert_true(@execution.completed_output_available(source))
  }
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_eq(cleanups, [1, 1, 1])
  assert_true(state.current is None)
  assert_true(state.children.is_empty())
  assert_true(state.completed.is_empty())
  assert_true(@execution.completed_output_available(output))
  @connector.close_capability_registry(registry)
}

///|
test "cancel between original Append children retains originals and starts no successor" {
  let (sequence, reads, sources, numeric) = metered_number_append_chain_fixture()
  let (active, state) = bounded_relation_chain_execution_state(
    sequence,
    reads.map(managed_provider_relation_input),
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    10000,
    Some(numeric),
    [],
  ).unwrap()
  let cleanups = Array::make(3, 0)
  chain_lifetime_watch_child(state, cleanups)
  for _ in 0..<100000 {
    if state.pending {
      break
    }
    assert_true(advance_managed_provider(active, 1).unwrap() is Continue(..))
  }
  assert_true(state.pending)
  assert_eq(state.position, 1)
  assert_eq(@execution.completed_row_count(state.completed[0].unwrap()), 2)
  assert_eq(cleanups, [1, 0, 0])
  assert_true(cancel_managed_provider(active))
  assert_true(
    advance_managed_provider(active, 1).unwrap() is Stopped(work=0L, ..),
  )
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_eq(cleanups, [1, 0, 0])
  assert_true(state.current is None)
  assert_true(state.children.is_empty())
  assert_true(state.completed.is_empty())
  for index, source in sources {
    assert_true(@execution.producer_read_available(reads[index]))
    assert_true(@execution.completed_output_available(source))
  }
}

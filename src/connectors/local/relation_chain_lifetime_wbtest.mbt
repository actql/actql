///|
// Compose the exact installed child constructors: selected rows/Values/Append
// have bounded metadata, while Set/analytic/UNNEST retain their original recipe.
fn chain_lifetime_child_capacity(
  selected : @execution.GeneratedSequence,
  limits : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> @execution.ExecutionCapacity {
  let provider = bounded_relation_step_provider(selected, limits, measurement, family=[]).unwrap()
  managed_provider_capacity(provider, selected).unwrap()
}

///|
fn relation_chain_reclaims_completed_scratch(
  sequence : @execution.GeneratedSequence,
) -> Bool {
  relation_chain_reclaimed_prefix(sequence) ==
  @execution.generated_sequence_step_count(sequence)
}

///|
fn chain_lifetime_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="chain-lifetime.json",
    ).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn chain_lifetime_registry_limits() -> @execution.RegistryLimits {
  { max_body_bytes: 100000, max_body_nodes: 10000, max_body_depth: 100, }
}

///|
fn chain_lifetime_contracts() -> @execution.RegisteredRelationContracts raise {
  @execution.admit_relation_registry(
    chain_lifetime_registered_body(),
    chain_lifetime_registered_values(),
    chain_lifetime_registry_limits(),
  ).unwrap()
}

///|
fn chain_lifetime_limits() -> @execution.SequenceExecutionLimits {
  let values : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  {
    rows: {
      max_rows: 100,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: values,
      output_values: values,
    },
    max_work: 100000,
    max_frames: 100,
  }
}

///|
fn chain_lifetime_measurement() -> @execution.FixedInputGuardMeasureLimits {
  { max_work: 10000, max_bytes: 10000, max_nodes: 10000, max_depth: 100, }
}

///|
fn chain_lifetime_bind(
  checked : @pipeline.CheckedPipeline,
) -> @lower.BoundPrepared {
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
fn chain_lifetime_generated(
  owner : @lower.BoundPrepared,
) -> @execution.GeneratedSequence raise {
  let sequence = @lower.prepare_sequence(owner, {
    max_steps: 100,
    max_rows: 100,
    max_cells: 10000,
    max_bindings: 100,
    max_name_bytes: 10000,
    expressions: {
      max_nodes: 10000,
      max_work: 100000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 10000,
    },
  }).unwrap()
  let contracts = chain_lifetime_contracts()
  let contexts = []
  for step in 0..<@lower.sequence_count(sequence) {
    if @lower.sequence_step(sequence, step) is Some(@lower.RowStep(kernel)) &&
      @lower.kernel_body(kernel) is @lower.Filter(_) {
      let fragment = @lower.prepare_fragment_pipeline(sequence, step, {
        max_roots: 100,
        max_pointer_bytes: 10000,
        max_work: 100000,
      }).unwrap()
      let request = @lower.prepare_fragment_request(fragment, 10L, 1000L).unwrap()
      contexts.push(
        @execution.prepare_runtime_fragment(
          request,
          @execution.admit_fragment_contract(
            contracts,
            chain_lifetime_registered_fragment(),
            chain_lifetime_registry_limits(),
          ).unwrap(),
          {
            max_roots: 100,
            max_nodes: 1000,
            max_work: 100000,
            max_text_bytes: 100000,
            max_links: 10000,
          },
          chain_lifetime_registry_limits(),
          {
            max_input_rows: 10L,
            max_value_bytes: 1000L,
            max_live_value_bytes: 10000L,
            max_work: 100000L,
          },
        ).unwrap(),
      )
    }
  }
  let last = @lower.node_at(
    @lower.bound_preparation(owner),
    @lower.sequence_count(sequence) - 1,
  ).unwrap()
  @execution.prepare_generated_sequence(
    contracts,
    sequence,
    contexts,
    [@lower.node_id(last)],
    100000,
    10000,
  ).unwrap()
}

///|
/// The Values source is completed independently. The chain receives one exact
/// ProducerRead. Separate source-free cases below audit Values and UNNEST.
fn chain_lifetime_fixture(
  body : String,
  source_name? : String = "id",
) -> (
  @execution.GeneratedSequence,
  @execution.ProducerRead,
  @execution.CompletedOutput,
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
        "[{\"values\":{\"schema\":{\"" +
        source_name +
        "\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"" +
        source_name +
        "\":2},{\"" +
        source_name +
        "\":1},{\"" +
        source_name +
        "\":2}]},\"as\":\"seed\"}]",
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
      chain_lifetime_cursor(body),
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
  (chain_lifetime_generated(receiver), read, source)
}

///|
fn chain_lifetime_start(
  sequence : @execution.GeneratedSequence,
  read : @execution.ProducerRead,
) -> (ManagedProviderExecution, RelationChainExecutionState) {
  bounded_relation_chain_execution_state(
    sequence,
    [managed_provider_relation_input(read)],
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    10000,
    None,
    [],
  ).unwrap()
}

///|
/// Wrap the actual current built-in, retaining the same polls and cleanup.
/// Root inspection alone would miss a mutation that simply drops uncleaned
/// executions; this probe also requires the real cleanup callback to run.
fn chain_lifetime_watch_child(
  state : RelationChainExecutionState,
  cleanups : Array[Int],
) -> Unit {
  let child = state.current.unwrap()
  let position = state.position
  let watched = managed_provider_execution(
    q => advance_managed_provider(child, q),
    () => cancel_managed_provider(child),
    () => managed_provider_stopped(child),
    () => {
      cleanups[position] += 1
      cleanup_managed_provider(child)
    },
  )
  state.current = Some(watched)
  state.children = [watched]
}

///|
fn chain_lifetime_select_body() -> String {
  "[{\"from\":\"source\",\"filter\":\"true\",\"as\":\"kept\"},{\"from\":\"kept\",\"select\":[\"id\"],\"as\":\"selected\"},{\"from\":\"selected\",\"select\":[\"id\"]}]"
}

///|
fn chain_lifetime_append_body() -> String {
  "[{\"from\":\"source\",\"append\":{\"with\":\"source\"},\"as\":\"doubled\"},{\"from\":\"doubled\",\"select\":[\"id\"],\"as\":\"selected\"},{\"from\":\"selected\",\"append\":{\"with\":\"doubled\"}}]"
}

///|
test "bounded chains execute and charge an unconsumed checked branch" {
  let (sequence, read, source) = chain_lifetime_fixture(
    "[{\"from\":\"source\",\"select\":[\"id\"],\"as\":\"seed\"},{\"from\":\"seed\",\"select\":[\"id\"],\"as\":\"unused\"},{\"from\":\"seed\",\"select\":[\"id\"]}]",
  )
  let limits = chain_lifetime_limits()
  let measure = chain_lifetime_measurement()
  let provider = selected_relation_provider(limits, measure)
  assert_true(managed_provider_accepts(provider, sequence))
  let capacity = managed_provider_capacity(provider, sequence).unwrap()
  let count = @execution.generated_sequence_step_count(sequence)
  assert_eq(count, 3)
  let mut retained = 0L
  let mut peak = 0L
  for step in 0..<count {
    let selected = @execution.select_generated_sequence_step(sequence, step).unwrap()
    let child = chain_lifetime_child_capacity(selected, limits, measure)
    retained += child.retained_bytes
    peak = Int64::max(peak, child.execution_bytes)
  }
  let base = @execution.generated_sequence_capacity(sequence, limits, measure).unwrap()
  assert_eq(
    capacity.execution_bytes,
    Int64::max(
      base.execution_bytes,
      retained + peak + count.to_int64() * 256L + 512L,
    ),
  )
  let (active, state) = chain_lifetime_start(sequence, read)
  let cleanups = Array::make(count, 0)
  let mut watched = -1
  let mut output = None
  let mut work = 0L
  for _ in 0..<100000 {
    if output is Some(_) {
      break
    }
    if !state.pending && watched != state.position {
      chain_lifetime_watch_child(state, cleanups)
      watched = state.position
    }
    match advance_managed_provider(active, 1).unwrap() {
      Continue(work=delta, ..) => work += delta
      Complete(result, work=delta, ..) => {
        work += delta
        output = Some(result)
      }
      _ => fail("the original branch chain must complete")
    }
  }
  assert_eq(state.position, 2)
  assert_true(state.completed[1] is Some(_))
  assert_eq(@execution.completed_row_count(output.unwrap()), 3)
  assert_eq(cleanups, [1, 1, 0])
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_eq(cleanups, [1, 1, 1])
  assert_true(state.completed.is_empty())
  assert_eq(managed_provider_cumulative_work(active), Ok(work))
  assert_true(@execution.producer_read_available(read))
  assert_true(@execution.completed_output_available(source))
}

///|
test "an unconsumed checked branch still fails before the terminal step" {
  let (sequence, read, source) = chain_lifetime_fixture(
    "[{\"from\":\"source\",\"select\":[\"id\"],\"as\":\"seed\"},{\"from\":\"seed\",\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"unused\"},{\"from\":\"seed\",\"select\":[\"id\"]}]",
  )
  let provider = selected_relation_provider(
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
  )
  assert_true(managed_provider_accepts(provider, sequence))
  assert_true(managed_provider_capacity(provider, sequence) is Some(_))
  let (active, state) = chain_lifetime_start(sequence, read)
  let mut failed = false
  for _ in 0..<100000 {
    if failed {
      break
    }
    match advance_managed_provider(active, 1).unwrap() {
      Continue(..) => ()
      Failed(_, ..) => failed = true
      _ => fail("the unconsumed duplicate assertion must not be skipped")
    }
  }
  assert_true(failed)
  assert_eq(state.position, 1)
  assert_true(state.completed[1] is None)
  assert_true(state.completed[2] is None)
  assert_true(managed_provider_stopped(active))
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_true(state.completed.is_empty())
  assert_true(@execution.producer_read_available(read))
  assert_true(@execution.completed_output_available(source))
}

///|
test "built-in chains reclaim each intermediate execution and preserve exact outputs" {
  for
    (body, expected_rows) in [
      (chain_lifetime_select_body(), 3),
      (chain_lifetime_append_body(), 12),
      (
        "[{\"from\":\"source\",\"group\":{\"by\":[\"id\"],\"aggregates\":{\"n\":{\"fn\":\"count\"}}},\"as\":\"grouped\"},{\"from\":\"grouped\",\"filter\":\"true\",\"as\":\"kept\"},{\"from\":\"kept\",\"select\":[\"id\",\"n\"]}]",
        2,
      ),
      (
        "[{\"from\":\"source\",\"group\":{\"by\":[\"id\"],\"aggregates\":{\"m\":{\"fn\":\"max\",\"field\":\"id\"}}},\"as\":\"grouped\"},{\"from\":\"grouped\",\"filter\":\"true\",\"as\":\"kept\"},{\"from\":\"kept\",\"select\":[\"id\",\"m\"]}]",
        2,
      ),
      (
        "[{\"from\":\"source\",\"select\":[\"id\"],\"as\":\"earlier\"},{\"from\":\"earlier\",\"select\":[\"id\"],\"as\":\"later\"},{\"from\":\"earlier\",\"join\":{\"with\":\"later\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"left.id\"}},\"as\":\"joined\"},{\"from\":\"joined\",\"select\":[\"id\"]}]",
        5,
      ),
    ] {
    let (sequence, read, source) = chain_lifetime_fixture(body)
    assert_true(relation_chain_reclaims_completed_scratch(sequence))
    if expected_rows == 12 {
      let limits = chain_lifetime_limits()
      let measurement = chain_lifetime_measurement()
      let count = @execution.generated_sequence_step_count(sequence)
      let mut retained = 0L
      let mut peak = 0L
      let mut conservative = 0L
      for index in 0..<count {
        let step = @execution.generated_sequence_step_index_at(sequence, index).unwrap()
        let selected = @execution.select_generated_sequence_step(sequence, step).unwrap()
        let child = chain_lifetime_child_capacity(selected, limits, measurement)
        retained += child.retained_bytes
        peak = Int64::max(peak, child.execution_bytes)
        conservative += child.execution_bytes
      }
      let base = @execution.generated_sequence_capacity(
        sequence, limits, measurement,
      ).unwrap()
      let capacity = bounded_relation_chain_capacity(
        sequence,
        limits,
        measurement,
        [],
      ).unwrap()
      let handles = count.to_int64() * 256L + 512L
      assert_eq(
        capacity.execution_bytes,
        Int64::max(base.execution_bytes, retained + peak + handles),
      )
      assert_true(capacity.execution_bytes < retained + conservative + handles)
    }
    let (active, state) = chain_lifetime_start(sequence, read)
    let count = @execution.generated_sequence_step_count(sequence)
    let cleanups = Array::make(count, 0)
    let saved : Array[@execution.CompletedOutput] = []
    let mut watched = -1
    let mut charged = 0L
    let mut result : @execution.CompletedOutput? = None
    for _ in 0..<100000 {
      if result is Some(_) {
        break
      }
      if !state.pending && watched != state.position {
        chain_lifetime_watch_child(state, cleanups)
        watched = state.position
      }
      let before = state.position
      match advance_managed_provider(active, 1).unwrap() {
        Continue(work~, ..) => {
          assert_eq(work, 1L)
          charged += work
        }
        Complete(output, work~, ..) => {
          charged += work
          result = Some(output)
        }
        _ => fail("real built-in lifetime chain did not complete")
      }
      if state.position != before {
        assert_eq(state.position, before + 1)
        assert_true(state.pending)
        assert_false(state.reclaiming)
        assert_true(state.current is None)
        assert_true(state.children.is_empty())
        assert_eq(cleanups[before], 1)
        saved.push(state.completed[before].unwrap())
      }
      for output in saved {
        assert_true(@execution.completed_output_available(output))
        assert_true(@execution.completed_cell(output, 0, 0) is Some(_))
      }
      assert_true(@execution.producer_read_available(read))
      assert_true(@execution.completed_output_available(source))
    }
    let output = result.unwrap()
    assert_eq(@execution.completed_row_count(output), expected_rows)
    assert_eq(saved.length(), count - 1)
    assert_true(state.current is Some(_))
    assert_eq(state.children.length(), 1)
    assert_eq(cleanups[count - 1], 0)
    assert_eq(managed_provider_cumulative_work(active), Ok(charged))
    assert_true(cleanup_managed_provider(active).unwrap())
    assert_true(cleanup_managed_provider(active).unwrap())
    assert_true(state.current is None)
    assert_true(state.children.is_empty())
    assert_true(state.completed.is_empty())
    assert_eq(cleanups, Array::make(count, 1))
    assert_eq(managed_provider_cumulative_work(active), Ok(charged))
    // Neither final cleanup nor loss of execution ownership revokes successful
    // output evidence, including the earlier output used on both JOIN edges.
    for completed in saved {
      assert_true(@execution.completed_output_available(completed))
      assert_true(@execution.completed_cell(completed, 0, 0) is Some(_))
    }
    assert_true(@execution.completed_output_available(output))
    assert_eq(@execution.completed_row_count(output), expected_rows)
    if expected_rows == 12 {
      // Both append occurrences retain all source occurrences in order. The
      // first completion is read twice after its child has been reclaimed.
      let expected = [
        2.0, 1.0, 2.0, 2.0, 1.0, 2.0, 2.0, 1.0, 2.0, 2.0, 1.0, 2.0,
      ]
      for row in 0..<expected.length() {
        match @execution.completed_cell(output, row, 0) {
          Some(@execution.Number(value)) => assert_eq(value, expected[row])
          _ => fail("append lost an ordered number occurrence")
        }
      }
    }
    assert_true(@execution.completed_output_available(source))
  }
}

///|
test "chain cancellation between reclaimed children does not start the next child" {
  let (sequence, read, source) = chain_lifetime_fixture(
    chain_lifetime_select_body(),
  )
  let (active, state) = chain_lifetime_start(sequence, read)
  let cleanups = Array::make(3, 0)
  chain_lifetime_watch_child(state, cleanups)
  for _ in 0..<10000 {
    if state.pending {
      break
    }
    assert_true(advance_managed_provider(active, 1).unwrap() is Continue(..))
  }
  assert_true(state.pending)
  assert_eq(state.position, 1)
  assert_eq(cleanups, [1, 0, 0])
  let output = state.completed[0].unwrap()
  let work = managed_provider_cumulative_work(active)
  assert_true(state.children.is_empty())
  assert_true(state.current is None)
  assert_true(cancel_managed_provider(active))
  assert_true(
    advance_managed_provider(active, 1).unwrap() is Stopped(work=0L, ..),
  )
  assert_eq(state.position, 1)
  assert_true(state.children.is_empty())
  assert_true(state.current is None)
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_true(state.completed.is_empty())
  assert_eq(managed_provider_cumulative_work(active), work)
  assert_eq(cleanups, [1, 0, 0])
  assert_true(@execution.completed_output_available(output))
  assert_true(@execution.producer_read_available(read))
  assert_true(@execution.completed_output_available(source))
}

///|
test "intermediate cleanup false and error preserve child custody until parent retry" {
  for body in [chain_lifetime_select_body(), chain_lifetime_append_body()] {
    let (sequence, read, source) = chain_lifetime_fixture(body)
    let (active, state) = chain_lifetime_start(sequence, read)
    let child = state.current.unwrap()
    let calls = Ref(0)
    let advances = Ref(0)
    let watched = managed_provider_execution(
      q => {
        advances.val += 1
        advance_managed_provider(child, q)
      },
      () => cancel_managed_provider(child),
      () => managed_provider_stopped(child),
      () => {
        calls.val += 1
        match calls.val {
          1 | 2 => Ok(false)
          3 => Err(@connector.InvalidLimits)
          _ => cleanup_managed_provider(child)
        }
      },
    )
    state.current = Some(watched)
    state.children = [watched]
    for _ in 0..<10000 {
      if state.pending {
        break
      }
      assert_true(advance_managed_provider(active, 1).unwrap() is Continue(..))
    }
    assert_true(state.pending)
    assert_true(state.reclaiming)
    assert_eq(calls.val, 1)
    let output = state.completed[0].unwrap()
    let work = managed_provider_cumulative_work(active)
    let polls = advances.val
    assert_true(physical_equal(state.current.unwrap(), watched))
    assert_true(physical_equal(state.children[0], watched))
    assert_true(
      advance_managed_provider(active, 1).unwrap() is Waiting(work=0L, ..),
    )
    assert_eq(calls.val, 2)
    assert_false(managed_provider_stopped(active))
    assert_true(physical_equal(state.current.unwrap(), watched))
    assert_true(physical_equal(state.children[0], watched))
    assert_true(
      advance_managed_provider(active, 1).unwrap() is Failed(_, work=0L, ..),
    )
    assert_true(managed_provider_stopped(active))
    assert_eq(calls.val, 3)
    assert_eq(state.position, 1)
    assert_true(physical_equal(state.current.unwrap(), watched))
    assert_true(physical_equal(state.children[0], watched))
    assert_true(@execution.completed_output_available(output))
    assert_true(cleanup_managed_provider(active).unwrap())
    assert_true(cleanup_managed_provider(active).unwrap())
    assert_eq(calls.val, 4)
    assert_eq(advances.val, polls)
    assert_eq(managed_provider_cumulative_work(active), work)
    assert_true(state.current is None)
    assert_true(state.children.is_empty())
    assert_true(state.completed.is_empty())
    assert_true(@execution.completed_output_available(output))
    assert_true(@execution.producer_read_available(read))
    assert_true(@execution.completed_output_available(source))
  }
}

///|
test "cancelling pending intermediate cleanup preserves reclamation custody" {
  for body in [chain_lifetime_select_body(), chain_lifetime_append_body()] {
    let (sequence, read, source) = chain_lifetime_fixture(body)
    let (active, state) = chain_lifetime_start(sequence, read)
    let child = state.current.unwrap()
    let calls = Ref(0)
    let watched = managed_provider_execution(
      q => advance_managed_provider(child, q),
      () => cancel_managed_provider(child),
      () => managed_provider_stopped(child),
      () => {
        calls.val += 1
        if calls.val == 1 {
          Ok(false)
        } else {
          cleanup_managed_provider(child)
        }
      },
    )
    state.current = Some(watched)
    state.children = [watched]
    for _ in 0..<10000 {
      if state.pending {
        break
      }
      assert_true(advance_managed_provider(active, 1).unwrap() is Continue(..))
    }
    assert_true(state.pending)
    assert_true(state.reclaiming)
    let output = state.completed[0].unwrap()
    let work = managed_provider_cumulative_work(active)
    assert_eq(calls.val, 1)
    assert_true(cancel_managed_provider(active))
    assert_true(
      advance_managed_provider(active, 1).unwrap() is Stopped(work=0L, ..),
    )
    assert_eq(state.position, 1)
    assert_true(physical_equal(state.current.unwrap(), watched))
    assert_true(physical_equal(state.children[0], watched))
    assert_true(cleanup_managed_provider(active).unwrap())
    assert_true(cleanup_managed_provider(active).unwrap())
    assert_eq(calls.val, 2)
    assert_true(state.current is None)
    assert_true(state.children.is_empty())
    assert_true(state.completed.is_empty())
    assert_eq(managed_provider_cumulative_work(active), work)
    assert_true(@execution.completed_output_available(output))
    assert_true(@execution.producer_read_available(read))
    assert_true(@execution.completed_output_available(source))
  }
}

///|
test "audited prefix releases scratch before conservative child custody" {
  let (sequence, read, source) = chain_lifetime_fixture(
    "[{\"from\":\"source\",\"select\":[\"id\"],\"as\":\"first\"},{\"from\":\"first\",\"intersect\":{\"with\":\"first\",\"duplicates\":\"all\"},\"as\":\"out\"}]",
  )
  assert_false(relation_chain_reclaims_completed_scratch(sequence))
  let limits = chain_lifetime_limits()
  let measure = chain_lifetime_measurement()
  let capacity = bounded_relation_chain_capacity(sequence, limits, measure, []).unwrap()
  let count = @execution.generated_sequence_step_count(sequence)
  assert_eq(relation_chain_reclaimed_prefix(sequence), 1)
  // The first SELECT is reclaimed before the unaudited Set starts. Both
  // accepted outputs remain retained; only one execution scratch is live.
  let mut overlap = count.to_int64() * 256L + 512L
  let mut peak = 0L
  for index in 0..<count {
    let step = @execution.generated_sequence_step_index_at(sequence, index).unwrap()
    let selected = @execution.select_generated_sequence_step(sequence, step).unwrap()
    let child = chain_lifetime_child_capacity(selected, limits, measure)
    overlap += child.retained_bytes
    peak = Int64::max(peak, child.execution_bytes)
  }
  assert_eq(capacity.execution_bytes, overlap + peak)
  let (active, state) = chain_lifetime_start(sequence, read)
  let mut result = None
  for _ in 0..<100000 {
    if result is Some(_) {
      break
    }
    match advance_managed_provider(active, 1).unwrap() {
      Continue(..) => ()
      Complete(output, ..) => result = Some(output)
      _ => fail("conservative set chain did not complete")
    }
    if state.pending {
      assert_eq(state.children.length(), 0)
      assert_false(state.reclaiming)
    }
  }
  assert_eq(@execution.completed_row_count(result.unwrap()), 3)
  assert_eq(state.children.length(), count - 1)
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_true(state.children.is_empty())
  assert_true(@execution.completed_output_available(source))
}

///|
fn expansion_lifetime_sequence() -> @execution.GeneratedSequence raise {
  chain_lifetime_generated(
    chain_lifetime_bind(
      @pipeline.check(
        chain_lifetime_cursor(
          "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"number\",\"nullable\":true}}},\"rows\":[{\"id\":2,\"items\":[2,null,2]},{\"id\":1,\"items\":[1]},{\"id\":3,\"items\":[]},{\"id\":4,\"items\":null}]},\"as\":\"parents\"},{\"unnest\":{\"column\":\"items\",\"as\":\"element\",\"with_index\":\"position\"}},{\"filter\":{\"not\":{\"is_null\":{\"field\":\"element\"}}}},{\"sort\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"field\":\"position\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[\"id\",\"element\",\"position\"]},{\"take\":{\"count\":2,\"offset\":0}}]",
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
    ),
  )
}

///|
fn expansion_lifetime_start(
  sequence : @execution.GeneratedSequence,
) -> (ManagedProviderExecution, RelationChainExecutionState) {
  bounded_relation_chain_execution_state(
    sequence,
    [],
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    10000,
    None,
    [],
  ).unwrap()
}

///|
test "Values and UNNEST chains reclaim scratch and preserve accepted output generations" {
  let sequence = expansion_lifetime_sequence()
  assert_true(relation_chain_reclaims_completed_scratch(sequence))
  let count = @execution.generated_sequence_step_count(sequence)
  let limits = chain_lifetime_limits()
  let measure = chain_lifetime_measurement()
  let base = @execution.generated_sequence_capacity(sequence, limits, measure).unwrap()
  let mut retained = 0L
  let mut peak = 0L
  let mut conservative = 0L
  for index in 0..<count {
    let step = @execution.generated_sequence_step_index_at(sequence, index).unwrap()
    let selected = @execution.select_generated_sequence_step(sequence, step).unwrap()
    let child = chain_lifetime_child_capacity(selected, limits, measure)
    retained += child.retained_bytes
    peak = Int64::max(peak, child.execution_bytes)
    conservative += child.execution_bytes
  }
  let handles = count.to_int64() * 256L + 512L
  let required = bounded_relation_chain_capacity(sequence, limits, measure, []).unwrap()
  assert_eq(
    required.execution_bytes,
    Int64::max(base.execution_bytes, retained + peak + handles),
  )
  assert_true(required.execution_bytes < retained + conservative + handles)
  let (active, state) = expansion_lifetime_start(sequence)
  let cleanups = Array::make(count, 0)
  let saved : Array[@execution.CompletedOutput] = []
  let mut watched = -1
  let mut charged = 0L
  let mut result = None
  for _ in 0..<100000 {
    if result is Some(_) {
      break
    }
    if !state.pending && watched != state.position {
      chain_lifetime_watch_child(state, cleanups)
      watched = state.position
    }
    let before = state.position
    match advance_managed_provider(active, 1).unwrap() {
      Continue(work~, ..) => charged += work
      Complete(output, work~, ..) => {
        charged += work
        result = Some(output)
      }
      _ => fail("expanded lifetime chain did not complete")
    }
    if state.position != before {
      assert_eq(cleanups[before], 1)
      assert_true(state.current is None)
      assert_true(state.children.is_empty())
      saved.push(state.completed[before].unwrap())
    }
    for output in saved {
      assert_true(@execution.completed_output_available(output))
    }
  }
  let output = result.unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  for
    (name, expected) in [
      ("id", [1.0, 2.0]),
      ("element", [1.0, 2.0]),
      ("position", [0.0, 0.0]),
    ] {
    let mut column = -1
    for index in 0..<@execution.completed_column_count(output) {
      if @execution.completed_column_name(output, index) == Some(name) {
        column = index
      }
    }
    assert_true(column >= 0)
    for row in 0..<2 {
      assert_true(
        @execution.completed_cell(output, row, column)
        is Some(@execution.Number(actual)) &&
        actual == expected[row],
      )
    }
  }
  assert_eq(managed_provider_cumulative_work(active), Ok(charged))
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_eq(cleanups, Array::make(count, 1))
  for earlier in saved {
    assert_true(@execution.completed_output_available(earlier))
  }
  assert_true(@execution.completed_output_available(output))
}

///|
test "Values and UNNEST cleanup failures retain child custody and retry exactly once" {
  for injected in [0, 1] {
    let (active, state) = expansion_lifetime_start(
      expansion_lifetime_sequence(),
    )
    for _ in 0..<100000 {
      if state.position == injected && !state.pending {
        break
      }
      assert_true(advance_managed_provider(active, 1).unwrap() is Continue(..))
    }
    assert_eq(state.position, injected)
    let child = state.current.unwrap()
    let calls = Ref(0)
    let watched = managed_provider_execution(
      q => advance_managed_provider(child, q),
      () => cancel_managed_provider(child),
      () => managed_provider_stopped(child),
      () => {
        calls.val += 1
        match calls.val {
          1 | 2 => Ok(false)
          3 => Err(@connector.InvalidLimits)
          _ => cleanup_managed_provider(child)
        }
      },
    )
    state.current = Some(watched)
    state.children = [watched]
    for _ in 0..<100000 {
      if state.pending {
        break
      }
      assert_true(advance_managed_provider(active, 1).unwrap() is Continue(..))
    }
    assert_true(state.reclaiming)
    let output = state.completed[injected].unwrap()
    assert_eq(calls.val, 1)
    assert_true(
      advance_managed_provider(active, 1).unwrap() is Waiting(work=0L, ..),
    )
    assert_eq(state.position, injected + 1)
    assert_true(physical_equal(state.current.unwrap(), watched))
    assert_true(
      advance_managed_provider(active, 1).unwrap() is Failed(_, work=0L, ..),
    )
    assert_true(physical_equal(state.children[0], watched))
    assert_true(@execution.completed_output_available(output))
    assert_true(cleanup_managed_provider(active).unwrap())
    assert_true(cleanup_managed_provider(active).unwrap())
    assert_eq(calls.val, 4)
    assert_true(state.children.is_empty())
    assert_true(@execution.completed_output_available(output))
  }
}

///|
test "cancellation after reclaimed Values does not start UNNEST or publish unfinished output" {
  let (active, state) = expansion_lifetime_start(expansion_lifetime_sequence())
  for _ in 0..<100000 {
    if state.pending {
      break
    }
    assert_true(advance_managed_provider(active, 1).unwrap() is Continue(..))
  }
  assert_eq(state.position, 1)
  assert_true(state.current is None)
  assert_true(state.children.is_empty())
  let accepted = state.completed[0].unwrap()
  assert_true(cancel_managed_provider(active))
  assert_true(advance_managed_provider(active, 1).unwrap() is Stopped(..))
  assert_eq(state.position, 1)
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_true(state.children.is_empty())
  assert_true(@execution.completed_output_available(accepted))
}

///|
test "an unaudited first child keeps the complete conservative suffix" {
  let (sequence, read, source) = chain_lifetime_fixture(
    "[{\"from\":\"source\",\"intersect\":{\"with\":\"source\",\"duplicates\":\"all\"},\"as\":\"first\"},{\"from\":\"first\",\"select\":[\"id\"],\"as\":\"out\"}]",
  )
  assert_eq(relation_chain_reclaimed_prefix(sequence), 0)
  let limits = chain_lifetime_limits()
  let measure = chain_lifetime_measurement()
  let count = @execution.generated_sequence_step_count(sequence)
  let mut overlap = count.to_int64() * 256L + 512L
  for index in 0..<count {
    let step = @execution.generated_sequence_step_index_at(sequence, index).unwrap()
    let selected = @execution.select_generated_sequence_step(sequence, step).unwrap()
    let child = chain_lifetime_child_capacity(selected, limits, measure)
    overlap += child.retained_bytes + child.execution_bytes
  }
  let capacity = bounded_relation_chain_capacity(sequence, limits, measure, []).unwrap()
  assert_eq(capacity.execution_bytes, overlap)
  let (active, state) = chain_lifetime_start(sequence, read)
  let mut output = None
  for _ in 0..<100000 {
    if output is Some(_) {
      break
    }
    match advance_managed_provider(active, 1).unwrap() {
      Continue(..) => ()
      Complete(result, ..) => output = Some(result)
      _ => fail("unaudited-first chain must complete")
    }
    if state.pending {
      assert_eq(state.children.length(), state.position)
      assert_false(state.reclaiming)
    }
  }
  assert_eq(@execution.completed_row_count(output.unwrap()), 3)
  assert_eq(state.children.length(), count)
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_true(state.children.is_empty())
  assert_true(@execution.completed_output_available(source))
}

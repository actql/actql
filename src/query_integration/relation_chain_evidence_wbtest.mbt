///|
/// Independent checked linear fixture. Extending the suffix changes local
/// semantic obligations, not the common lifecycle oracle.
fn chain_evidence_sequence(
  count : Int,
  select_last? : Bool = false,
) -> @execution.GeneratedSequence raise {
  let steps = [
    "{\"time_series\":{\"start\":\"1969-12-31T23:59:59.999Z\",\"end\":\"1970-01-01T00:00:00.004Z\",\"step\":2},\"as\":\"s0\"}",
  ]
  for i in 1..<count {
    let op = if select_last && i == count - 1 {
      "\"select\":[\"time\"]"
    } else {
      "\"filter\":\"true\""
    }
    steps.push(
      "{\"from\":\"s" +
      (i - 1).to_string() +
      "\"," +
      op +
      ",\"as\":\"s" +
      i.to_string() +
      "\"}",
    )
  }
  let checked = @pipeline.check(
    input_cursor("[" + steps.join(",") + "]"),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  task_test_generated(owner)
}

///|
struct ChainEvidenceProbe {
  mut starts : Int
  mut advances : Int
  mut cleanup_calls : Int
  mut work : Int64
  mut output : @execution.CompletedOutput?
  delay_cleanup : Bool
}

///|
fn chain_evidence_probe(delay_cleanup? : Bool = false) -> ChainEvidenceProbe {
  {
    starts: 0,
    advances: 0,
    cleanup_calls: 0,
    work: 0L,
    output: None,
    delay_cleanup,
  }
}

///|
fn chain_evidence_family(
  sequence : @execution.GeneratedSequence,
  probe : ChainEvidenceProbe,
) -> @local_connector.ManagedProvider {
  let actual = local_time_series_provider(sequence)
  @local_connector.managed_provider(
    s => @local_connector.managed_provider_accepts(actual, s),
    s => @local_connector.managed_provider_capacity(actual, s),
    fn(s, inputs, rows, bytes, limits) {
      probe.starts += 1
      let active = match
        @local_connector.start_managed_provider_with_execution(
          actual, s, inputs, rows, bytes, limits,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      Ok(
        @local_connector.managed_provider_execution(
          q => {
            probe.advances += 1
            let poll = @local_connector.advance_managed_provider(active, q)
            match poll {
              Ok(@local_connector.Continue(work~, ..))
              | Ok(@local_connector.Failed(_, work~, ..))
              | Ok(@local_connector.Stopped(work~, ..)) => probe.work += work
              Ok(@local_connector.Complete(output, work~, ..)) => {
                probe.work += work
                probe.output = Some(output)
              }
              _ => ()
            }
            poll
          },
          fn() { @local_connector.cancel_managed_provider(active) },
          fn() { @local_connector.managed_provider_stopped(active) },
          fn() {
            probe.cleanup_calls += 1
            if probe.delay_cleanup && probe.cleanup_calls == 1 {
              Ok(false)
            } else if probe.delay_cleanup && probe.cleanup_calls == 2 {
              Err(@connector.Execution(@execution.InputSet))
            } else {
              @local_connector.cleanup_managed_provider(active)
            }
          },
        ),
      )
    },
  )
}

///|
fn chain_evidence_provider(
  sequence : @execution.GeneratedSequence,
  family : @local_connector.ManagedProvider,
) -> @local_connector.ManagedProvider {
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let implementation = @local_connector.prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [sequence],
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
    1,
    managed_providers=[family],
  ).unwrap()
  @local_connector.local_module_managed_provider(implementation, sequence).unwrap()
}

///|
fn chain_evidence_inputs(
  sequence : @execution.GeneratedSequence,
  index : Int,
  previous : @execution.CompletedOutput?,
) -> Array[@execution.ProducerRead] {
  if index == 0 {
    return []
  }
  let owner = @execution.generated_sequence_owner(sequence)
  let step = @execution.generated_sequence_step_index_at(sequence, index).unwrap()
  let bound = @execution.bind_completed_operation_input(
    owner,
    step,
    0,
    owner,
    previous.unwrap(),
  ).unwrap()
  [@execution.prepare_producer_read(owner, bound, 10000, 10000).unwrap()]
}

///|
/// Drain individual registered children without the chain owner. Their work
/// sum plus one handoff per edge is the independent completed-chain oracle.
fn chain_evidence_reference(
  sequence : @execution.GeneratedSequence,
  stop_at? : Int? = None,
  prework? : Bool = false,
) -> Int64 raise {
  let probe = chain_evidence_probe()
  let family = chain_evidence_family(sequence, probe)
  let children = []
  let mut previous = None
  let mut work = 0L
  for index in 0..<@execution.generated_sequence_step_count(sequence) {
    let selected = @execution.select_generated_sequence_step(
      sequence,
      @execution.generated_sequence_step_index_at(sequence, index).unwrap(),
    ).unwrap()
    let provider = chain_evidence_provider(selected, family)
    let active = @local_connector.start_managed_provider_with_execution(
      provider,
      selected,
      chain_evidence_inputs(sequence, index, previous),
      100,
      10000,
      dispatch_test_limits().local_execution,
    ).unwrap()
    children.push(active)
    if stop_at == Some(index) {
      if prework {
        assert_true(
          @local_connector.advance_managed_provider(active, 1).unwrap()
          is @local_connector.Continue(_),
        )
      }
      assert_true(@local_connector.cancel_managed_provider(active))
      assert_true(
        @local_connector.advance_managed_provider(active, 1).unwrap()
        is @local_connector.Stopped(progress=_, work=0L),
      )
      assert_true(@local_connector.managed_provider_stopped(active))
      assert_true(
        @local_connector.advance_managed_provider(active, 1) is Err(_),
      )
      break
    }
    let mut complete = false
    while !complete {
      match @local_connector.advance_managed_provider(active, 1).unwrap() {
        @local_connector.Continue(work=charged, ..) => work += charged
        @local_connector.Complete(output, work=charged, ..) => {
          work += charged
          previous = Some(output)
          complete = true
        }
        _ => fail("reference child failed")
      }
    }
  }
  let mut index = children.length() - 1
  while index >= 0 {
    assert_true(
      @local_connector.cleanup_managed_provider(children[index]).unwrap(),
    )
    index -= 1
  }
  work
}

///|
/// Execute children independently using the contract's remaining budget. This
/// oracle preserves each kernel's logical limits, without using the chain
/// owner's state fields or advance/cleanup implementation.
fn chain_evidence_limited_reference(
  sequence : @execution.GeneratedSequence,
  budget : Int,
  quantum : Int,
) -> (Bool, Int64) raise {
  let probe = chain_evidence_probe()
  let family = chain_evidence_family(sequence, probe)
  let children = []
  let mut previous = None
  let mut charged = 0L
  let mut completed = false
  for index in 0..<@execution.generated_sequence_step_count(sequence) {
    if index > 0 {
      if charged == budget.to_int64() {
        break
      }
      charged += 1L
    }
    let remaining = budget.to_int64() - charged
    if remaining == 0L {
      break
    }
    let selected = @execution.select_generated_sequence_step(
      sequence,
      @execution.generated_sequence_step_index_at(sequence, index).unwrap(),
    ).unwrap()
    let provider = chain_evidence_provider(selected, family)
    let limits = {
      ..dispatch_test_limits().local_execution,
      max_work: remaining.to_int(),
    }
    let active = match
      @local_connector.start_managed_provider_with_execution(
        provider,
        selected,
        chain_evidence_inputs(sequence, index, previous),
        100,
        10000,
        limits,
      ) {
      Ok(value) => value
      Err(_) => break
    }
    children.push(active)
    let mut child_completed = false
    let mut terminal = false
    while !terminal {
      if charged == budget.to_int64() {
        @local_connector.cancel_managed_provider(active) |> ignore
        assert_true(
          @local_connector.advance_managed_provider(active, 1).unwrap()
          is @local_connector.Stopped(work=0L, ..),
        )
        terminal = true
      } else {
        let q = Int::min(quantum, (budget.to_int64() - charged).to_int())
        match @local_connector.advance_managed_provider(active, q).unwrap() {
          @local_connector.Continue(work~, ..) => charged += work
          @local_connector.Complete(output, work~, ..) => {
            charged += work
            previous = Some(output)
            child_completed = true
            terminal = true
          }
          @local_connector.Failed(_, work~, ..) => {
            charged += work
            terminal = true
          }
          _ => fail("unexpected independent child outcome")
        }
      }
    }
    if !child_completed {
      break
    }
    completed = index == @execution.generated_sequence_step_count(sequence) - 1
  }
  let mut index = children.length() - 1
  while index >= 0 {
    assert_true(
      @local_connector.cleanup_managed_provider(children[index]).unwrap(),
    )
    index -= 1
  }
  (completed, charged)
}

///|
test "chain evidence real children stop on the next advance without Compute work" {
  for count in [2, 3, 4] {
    let sequence = chain_evidence_sequence(count, select_last=count > 2)
    for index in 0..<count {
      for prework in [false, true] {
        chain_evidence_reference(sequence, stop_at=Some(index), prework~)
        |> ignore
      }
    }
  }
}

///|
test "chain evidence work composes across child boundaries with remaining budgets" {
  for count in [2, 3, 4] {
    let sequence = chain_evidence_sequence(count, select_last=count > 2)
    let expected = chain_evidence_reference(sequence) + (count - 1).to_int64()
    for quantum in [1, 2, 7] {
      for
        budget in [
          4,
          5,
          6,
          expected.to_int() - 1,
          expected.to_int(),
          expected.to_int() + 1,
          10000,
        ] {
        let reference = chain_evidence_limited_reference(
          sequence, budget, quantum,
        )
        let probe = chain_evidence_probe()
        let provider = chain_evidence_provider(
          sequence,
          chain_evidence_family(sequence, probe),
        )
        let limits = {
          ..dispatch_test_limits().local_execution,
          max_work: budget,
        }
        let active = @local_connector.start_managed_provider_with_execution(
          provider,
          sequence,
          [],
          100,
          10000,
          limits,
        ).unwrap()
        let mut total = 0L
        let mut terminal = false
        let mut completed = false
        for _ in 0..<1000 {
          if !terminal {
            match
              @local_connector.advance_managed_provider(active, quantum).unwrap() {
              @local_connector.Continue(work~, ..) => {
                assert_true(work > 0L && work <= quantum.to_int64())
                total += work
              }
              @local_connector.Complete(output, work~, ..) => {
                total += work
                assert_eq(@execution.completed_row_count(output), 3)
                terminal = true
                completed = true
              }
              @local_connector.Failed(_, work~, ..) => {
                total += work
                terminal = true
              }
              _ => fail("unexpected chain observation")
            }
            assert_true(total <= budget.to_int64())
          }
        }
        assert_true(terminal)
        assert_eq((completed, total), reference)
        // Physical work bounds are necessary, not sufficient: each child also
        // checks its own logical work charges against the remaining limit.
        if budget.to_int64() < expected {
          assert_false(completed)
        }
        if budget == 10000 {
          assert_true(completed)
        }
        if completed {
          assert_eq(total, expected)
          assert_eq(probe.work, 4L)
        }
        let advances = probe.advances
        assert_true(
          @local_connector.advance_managed_provider(active, 1) is Err(_),
        )
        assert_eq(probe.advances, advances)
        assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
        assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
        assert_eq(probe.starts, 1)
        assert_eq(probe.cleanup_calls, 1)
      }
    }
  }
}

///|
test "chain evidence handoff failure retains output and retryable cleanup responsibility" {
  let sequence = chain_evidence_sequence(3, select_last=true)
  let probe = chain_evidence_probe(delay_cleanup=true)
  let provider = chain_evidence_provider(
    sequence,
    chain_evidence_family(sequence, probe),
  )
  let active = @local_connector.start_managed_provider_with_execution(
    provider,
    sequence,
    [],
    100,
    10000,
    { ..dispatch_test_limits().local_execution, max_work: 5, },
  ).unwrap()
  for _ in 0..<4 {
    assert_true(
      @local_connector.advance_managed_provider(active, 1).unwrap()
      is @local_connector.Continue(_),
    )
  }
  let output = probe.output.unwrap()
  assert_eq(probe.work, 4L)
  assert_true(@execution.completed_output_available(output))
  assert_true(
    @local_connector.cleanup_managed_provider(active).unwrap() == false,
  )
  assert_eq(probe.cleanup_calls, 0)
  assert_true(
    @local_connector.advance_managed_provider(active, 1).unwrap()
    is @local_connector.Failed(_, work=1L, ..),
  )
  let advances = probe.advances
  assert_true(@local_connector.managed_provider_stopped(active))
  assert_false(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_true(@execution.completed_output_available(output))
  assert_true(@local_connector.cleanup_managed_provider(active) is Err(_))
  assert_true(@execution.completed_output_available(output))
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_eq(probe.cleanup_calls, 3)
  assert_eq(probe.advances, advances)
  assert_eq(probe.starts, 1)
}

///|
test "chain evidence cancel across real handoffs seals Compute and preserves cleanup" {
  for count in [2, 3, 4] {
    let sequence = chain_evidence_sequence(count, select_last=count > 2)
    let expected = chain_evidence_reference(sequence) + (count - 1).to_int64()
    // Every prefix in this fixture reaches either a child poll or a pending
    // handoff. The next advance must confirm stop without Compute work.
    for prefix in 0..<expected.to_int() {
      let probe = chain_evidence_probe()
      let provider = chain_evidence_provider(
        sequence,
        chain_evidence_family(sequence, probe),
      )
      let active = @local_connector.start_managed_provider_with_execution(
        provider,
        sequence,
        [],
        100,
        10000,
        dispatch_test_limits().local_execution,
      ).unwrap()
      for _ in 0..<prefix {
        assert_true(
          @local_connector.advance_managed_provider(active, 1).unwrap()
          is @local_connector.Continue(_),
        )
      }
      assert_true(@local_connector.cancel_managed_provider(active))
      assert_false(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_true(
        @local_connector.advance_managed_provider(active, 1).unwrap()
        is @local_connector.Stopped(work=0L, ..),
      )
      let work = probe.work
      let advances = probe.advances
      assert_true(@local_connector.managed_provider_stopped(active))
      assert_true(
        @local_connector.advance_managed_provider(active, 1) is Err(_),
      )
      assert_eq(probe.work, work)
      assert_eq(probe.advances, advances)
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_eq(probe.advances, advances)
      assert_eq(probe.starts, 1)
      assert_eq(probe.cleanup_calls, 1)
    }
  }
}

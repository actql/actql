///|
fn compute_test_sequence(
  owner : @lower.BoundPrepared,
) -> GeneratedSequence raise {
  let sequence = prepared_sequence(owner)
  let contexts = if @pipeline.step_count(
      @lower.pipeline(@lower.bound_preparation(owner)),
    ) ==
    3 {
    [sequence_fragment_context(sequence, 1, 2L)]
  } else {
    []
  }
  let last = @pipeline.step_count(
      @lower.pipeline(@lower.bound_preparation(owner)),
    ) -
    1
  let node = @lower.node_at(@lower.bound_preparation(owner), last).unwrap()
  prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    contexts,
    [@lower.node_id(node)],
    100000,
    10000,
  ).unwrap()
}

///|
fn compute_test_limits() -> SequenceExecutionLimits {
  { rows: run_limits(), max_work: 100000, max_frames: 100, }
}

///|
test "local compute rejects an uncompleted input instead of reading its source" {
  let generated = compute_test_sequence(keyed_owner("[\"n\"]"))
  assert_true(
    prepare_local_compute_attempt(generated, [], 1)
    is Err(RequiresCompletedProducer(0)),
  )
}

///|
test "local compute accepts typed completed storage without row conversion" {
  let (prepared, declarations) = ordered_parameter_preparation()
  let owner = bind_number(prepared, declarations, 3)
  let other = bind_number(prepared, declarations, 4)
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [
      ordered_sequence_fragment_context(sequence, 10000L),
      sequence_fragment_context(sequence, 2, 1L),
    ],
    ["derive_1", "select_3"],
    100000,
    10000,
  ).unwrap()
  let completion = test_typed_completion(generated, 1)
  let source = completed_output(completion, Step(1)).unwrap()
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  assert_true(
    bind_completed_input(receiver, 0, other, source)
    is Err(ProducerBindingMismatch),
  )
  assert_true(
    bind_completed_input(
      receiver,
      0,
      owner,
      completed_output(completion, Step(3)).unwrap(),
    )
    is Err(ProducerTargetMismatch),
  )
  let binding = bind_completed_input(receiver, 0, owner, source).unwrap()
  let consumer = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["select_0"],
    100000,
    10000,
  ).unwrap()
  let task = prepare_local_compute_attempt(consumer, [binding], 3).unwrap()
  let result = execute_local_compute_attempt(task, compute_test_limits()).unwrap()
  let output = completed_output(result, Step(0)).unwrap()
  assert_true(output.table is Some(NumberTable(_)))
  assert_true(completed_cell(output, 0, 0) is Some(Number(5)))
  assert_true(physical_equal(result._producer_inputs[0].output, source))
}

///|
test "local compute only publishes after sole driver success and runs once" {
  let generated = compute_test_sequence(
    row_owner(",{\"filter\":\"a > 0\"},{\"select\":[\"a\"]}"),
  )
  let attempt = prepare_local_compute_attempt(generated, [], 0).unwrap()
  assert_true(local_compute_result(attempt) is Err(NotComplete))
  let completed = execute_local_compute_attempt(attempt, compute_test_limits()).unwrap()
  let output = completed_output(completed, Step(2)).unwrap()
  assert_eq(completed_row_count(output), 1)
  assert_true(completed_cell(output, 0, 0) is Some(Number(1.0)))
  assert_true(physical_equal(local_compute_result(attempt).unwrap(), completed))
  assert_true(
    execute_local_compute_attempt(attempt, compute_test_limits())
    is Err(AlreadyStarted),
  )
  assert_true(!cancel_local_compute_attempt(attempt))
}

///|
test "failed compute retains diagnostics not successful partial output" {
  let generated = compute_test_sequence(
    row_owner(",{\"filter\":\"1 / a > 0\"},{\"select\":[\"a\"]}"),
  )
  let attempt = prepare_local_compute_attempt(generated, [], 0).unwrap()
  assert_true(
    execute_local_compute_attempt(attempt, compute_test_limits())
    is Err(Execution(Rows(_, _))),
  )
  assert_true(local_compute_result(attempt) is Err(Execution(Rows(_, _))))
  assert_true(
    execute_local_compute_attempt(attempt, compute_test_limits())
    is Err(AlreadyStarted),
  )
  let fresh = prepare_local_compute_attempt(generated, [], 0).unwrap()
  assert_true(
    execute_local_compute_attempt(fresh, compute_test_limits())
    is Err(Execution(Rows(_, _))),
  )
}

///|
test "cancelled attempt cannot dispatch but does not poison prepared compute" {
  let generated = compute_test_sequence(row_owner(",{\"select\":[\"a\"]}"))
  assert_true(
    prepare_local_compute_attempt(generated, [], -1) is Err(InvalidInputLimit),
  )
  let attempt = prepare_local_compute_attempt(generated, [], 0).unwrap()
  assert_true(cancel_local_compute_attempt(attempt))
  assert_true(!cancel_local_compute_attempt(attempt))
  assert_true(local_compute_result(attempt) is Err(Cancelled))
  assert_true(
    execute_local_compute_attempt(attempt, compute_test_limits())
    is Err(Cancelled),
  )
  let failed = prepare_local_compute_attempt(generated, [], 0).unwrap()
  assert_true(
    execute_local_compute_attempt(failed, {
      ..compute_test_limits(),
      max_work: 0,
    })
    is Err(Execution(_)),
  )
  let fresh = prepare_local_compute_attempt(generated, [], 0).unwrap()
  assert_true(
    execute_local_compute_attempt(fresh, compute_test_limits()) is Ok(_),
  )
}

///|
test "completed input ownership budgets and two consumers use existing producer admission" {
  let owner = row_owner(",{\"select\":[\"a\",\"b\"]}")
  let producer = prepare_local_compute_attempt(
    compute_test_sequence(owner),
    [],
    0,
  ).unwrap()
  let result = execute_local_compute_attempt(producer, compute_test_limits()).unwrap()
  let output = completed_output(result, Step(1)).unwrap()
  let receiver = producer_consumer(owner, Step(1))
  let generated = compute_test_sequence(receiver)
  let bound = bind_completed_input(receiver, 0, owner, output).unwrap()
  assert_true(
    prepare_local_compute_attempt(generated, [], 1) is Err(MissingInput(0)),
  )
  assert_true(
    prepare_local_compute_attempt(generated, [bound], 2) is Err(InputLimit),
  )
  assert_true(
    prepare_local_compute_attempt(generated, [bound, bound], 5)
    is Err(DuplicateInput(0)),
  )
  let inputs = [bound]
  let first = prepare_local_compute_attempt(generated, inputs, 3).unwrap()
  let second = prepare_local_compute_attempt(generated, inputs, 3).unwrap()
  inputs.clear()
  assert_true(cancel_local_compute_attempt(first))
  let completed = execute_local_compute_attempt(second, compute_test_limits()).unwrap()
  let delivered = completed_output(completed, Step(0)).unwrap()
  assert_eq(completed_row_count(delivered), 2)
  assert_eq(completed_column_count(delivered), 1)
  assert_true(completed_cell(delivered, 0, 0) is Some(Number(1.0)))
  assert_true(completed_cell(delivered, 1, 0) is Some(Number(0.0)))
  let failure = prepare_local_compute_attempt(generated, [bound], 3).unwrap()
  let limits = compute_test_limits()
  assert_true(
    execute_local_compute_attempt(failure, {
      ..limits,
      rows: { ..limits.rows, max_rows: 1, },
    })
    is Err(Execution(_)),
  )
  let retry = prepare_local_compute_attempt(generated, [bound], 3).unwrap()
  assert_true(execute_local_compute_attempt(retry, limits) is Ok(_))
  assert_eq(completed_row_count(output), 2)
  let foreign = producer_consumer(owner, Step(1))
  assert_true(
    prepare_local_compute_attempt(compute_test_sequence(foreign), [bound], 3)
    is Err(ForeignInput(0)),
  )
}

///|
test "live producer binding only narrows original liveness and shares storage" {
  let owner = row_owner("")
  let completion = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let source = completed_output(completion, Step(0)).unwrap()
  let receiver = producer_consumer(owner, Step(0))
  let original_live = Ref(true)
  let additional_live = Ref(true)
  let output : CompletedOutput = {
    ..source,
    completion: { ..completion, live: Some(fn() { original_live.val }), },
  }
  let bound = bind_live_completed_input(receiver, 0, owner, output, fn() {
    additional_live.val
  }).unwrap()
  assert_true(physical_equal(bound.output.table, source.table))
  assert_true(physical_equal(bound.output.completion.store, completion.store))
  assert_true(completion_is_live(bound.output.completion))
  assert_true(completed_output_matches_port(bound.output, owner, Step(0)))
  additional_live.val = false
  assert_false(completion_is_live(bound.output.completion))
  assert_false(completed_output_matches_port(bound.output, owner, Step(0)))
  assert_true(completion_is_live(output.completion))
  additional_live.val = true
  original_live.val = false
  assert_false(completion_is_live(bound.output.completion))
  assert_true(
    bind_live_completed_input(receiver, 0, owner, output, fn() { true })
    is Err(ProducerUnavailable),
  )
}

///|
fn producer_consumer(
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  extra_input? : Bool = false,
) -> @lower.BoundPrepared {
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(owner)),
    target,
  ).unwrap()
  let inputs = [("prior", @pipeline.ProducedInput(producer))]
  if extra_input {
    inputs.push(
      (
        "plain",
        @pipeline.CarrierInput(
          @carrier.relation(
            @carrier.typed_rows(
              @pipeline.schema_at(
                @lower.pipeline(@lower.bound_preparation(owner)),
                target,
              ).unwrap(),
            ),
          ),
        ),
      ),
    )
  }
  let p = @pipeline.check_with_evidence(
    input_cursor("[{\"select\":[\"a\"]}]"),
    inputs,
    None,
    Some(input_cursor("\"prior\"")),
    {
      max_steps: 100,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(p, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "producer binding keeps exact receiver producer and target" {
  let owner = row_owner(",{\"select\":[\"a\",\"b\"]}")
  let completion = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0", "select_1"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let receiver = producer_consumer(owner, Step(1))
  let output = completed_output(completion, Step(1)).unwrap()
  assert_true(completed_output_matches_port(output, owner, Step(1)))
  assert_false(completed_output_matches_port(output, owner, Step(0)))
  let bound = bind_completed_input(receiver, 0, owner, output).unwrap()
  assert_true(physical_equal(bound.receiver, receiver))
  assert_true(physical_equal(bound.output, output))
  assert_eq(bound.input_index, 0)
  assert_true(
    bind_completed_input(
      receiver,
      0,
      owner,
      completed_output(completion, Step(0)).unwrap(),
    )
    is Err(ProducerTargetMismatch),
  )
  assert_true(
    bind_completed_input(receiver, 1, owner, output) is Err(NotProducedInput),
  )
  assert_true(
    bind_completed_input(input_owner(), 0, owner, output)
    is Err(NotProducedInput),
  )
  let foreign = row_owner(",{\"select\":[\"a\",\"b\"]}")
  assert_false(completed_output_matches_port(output, foreign, Step(1)))
  assert_true(
    bind_completed_input(receiver, 0, foreign, output)
    is Err(ProducerOwnerMismatch),
  )
  // A second binding of the same checked pipeline is still not the selected
  // bound producer. This remains true even when no Parameters were needed.
  let rebound = @lower.bind_parameters(
    @lower.bound_preparation(owner),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  assert_true(
    bind_completed_input(receiver, 0, rebound, output)
    is Err(ProducerBindingMismatch),
  )
  assert_false(completed_output_matches_port(output, rebound, Step(1)))
}

///|
fn fixture_owner() -> @lower.BoundPrepared {
  let tree = @decode.admit(
    @source.parse_json(
      "[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":1}]},\"as\":\"v\"},{\"select\":[\"x\"]}]",
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="managed-carrier-test.aql",
    ).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
  let checked = @pipeline.check(tree, [], None, None, {
    max_steps: 10,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_depth: 100,
  }).unwrap()
  let prepared = @lower.prepare(checked, {
    max_nodes: 100,
    max_references: 100,
    max_work: 1000,
    max_identifier_bytes: 1000,
  }).unwrap()
  let owner = @lower.bind_parameters(
    prepared,
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  owner
}

///|
fn fixture_binding() -> Binding {
  prepare_binding(fixture_owner(), @pipeline.Step(1)).unwrap()
}

///|
fn fixture_receiver(
  owner : @lower.BoundPrepared,
  target? : @pipeline.Target = @pipeline.Step(1),
) -> @lower.BoundPrepared {
  let pipeline = @pipeline.check_with_evidence(
    @decode.admit(
      @source.parse_json(
        "[{\"select\":[\"x\"]}]",
        { max_input_bytes: 1000, max_nodes: 100, max_depth: 20, },
        source_path="managed-carrier-consumer.aql",
      ).unwrap(),
      {
        max_nodes: 100,
        max_depth: 20,
        max_string_bytes: 1000,
        max_total_string_bytes: 1000,
      },
    ).unwrap(),
    [
      (
        "prior",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(owner)),
            target,
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(
      @decode.admit(
        @source.parse_json(
          "\"prior\"",
          { max_input_bytes: 100, max_nodes: 10, max_depth: 10, },
          source_path="managed-carrier-input.aql",
        ).unwrap(),
        {
          max_nodes: 10,
          max_depth: 10,
          max_string_bytes: 100,
          max_total_string_bytes: 100,
        },
      ).unwrap(),
    ),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(pipeline, {
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
test "carrier lifecycle retains one exact immutable generation" {
  let binding = fixture_binding()
  assert_eq(binding_kind(binding), @carrier.RelationKind)
  let receipt = complete_receipt(binding, RelationMeasure(rows=1, columns=1)).unwrap()
  let live = Ref(true)
  let port = prepare_retention_port(binding, (proof : Int) => {
    if proof == 7 {
      Some((receipt, "rows", 42, 16L, fn() { live.val }))
    } else {
      None
    }
  })
  let retained = retain(port, 7).unwrap()
  assert_eq(retained_evidence(retained), "rows")
  assert_eq(retained_payload(retained), Some(42))
  assert_eq(retained_storage_bytes(retained), Some(16L))
  let completed = complete(retained).unwrap()
  let reference = completion_reference(completed)
  assert_true(completion_reference_matches(reference, completed))
  live.val = false
  assert_false(completion_reference_available(reference))
  assert_eq(retained_payload(retained), None)
  assert_eq(retained_storage_bytes(retained), None)
  assert_true(retain(port, 7) is Err(Closed))
}

///|
test "carrier lifecycle rejects kind mismatch and foreign receipt" {
  let binding = fixture_binding()
  assert_true(
    complete_receipt(binding, GraphMeasure(nodes=1, edges=0))
    is Err(WrongCarrier),
  )
  let other = fixture_binding()
  let receipt = complete_receipt(other, RelationMeasure(rows=0, columns=1)).unwrap()
  let port = prepare_retention_port(binding, (_ : Unit) => {
    Some((receipt, (), 1, 0L, fn() { true }))
  })
  assert_true(retain(port, ()) is Err(ForeignReceipt))
}

///|
test "carrier lifecycle binds independent exact producer use sites" {
  let owner = fixture_owner()
  let binding = prepare_binding(owner, @pipeline.Step(1)).unwrap()
  let receipt = complete_receipt(binding, RelationMeasure(rows=1, columns=1)).unwrap()
  let live = Ref(true)
  let retained = retain(
    prepare_retention_port(binding, (_ : Unit) => {
      Some((receipt, "rows", 42, 16L, fn() { live.val }))
    }),
    (),
  ).unwrap()
  let completed = complete(retained).unwrap()
  let receiver = fixture_receiver(owner)
  let first = prepare_producer_read(receiver, 0, owner, completed).unwrap()
  let second = prepare_producer_read(receiver, 0, owner, completed).unwrap()
  assert_false(producer_read_same(first, second))
  assert_true(physical_equal(producer_read_receiver(first), receiver))
  assert_eq(producer_read_input_index(first), 0)
  assert_eq(producer_read_payload(first), Some(42))
  let reference = completion_reference(completed)
  assert_true(producer_read_matches_reference(first, reference))
  assert_true(producer_read_matches_reference(second, reference))
  assert_true(
    prepare_producer_read(receiver, 1, owner, completed) is Err(InvalidInput),
  )
  assert_true(
    prepare_producer_read(receiver, 0, fixture_owner(), completed)
    is Err(ProducerOwnerMismatch),
  )
  let other_binding = @lower.bind_parameters(
    @lower.bound_preparation(owner),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  assert_true(
    prepare_producer_read(receiver, 0, other_binding, completed)
    is Err(ProducerBindingMismatch),
  )
  assert_true(
    prepare_producer_read(
      fixture_receiver(owner, target=@pipeline.Step(0)),
      0,
      owner,
      completed,
    )
    is Err(ProducerTargetMismatch),
  )
  live.val = false
  assert_false(producer_read_available(first))
  assert_eq(producer_read_payload(second), None)
  assert_true(
    prepare_producer_read(receiver, 0, owner, completed)
    is Err(ProducerUnavailable),
  )
}

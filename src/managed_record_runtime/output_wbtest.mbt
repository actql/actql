///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="managed-record-runtime.aql",
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
fn relation_contract() -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Unqualified("id"),
          Some(@contract.primitive(@contract.NumberType, nullable=false)),
        ),
        (
          @schema.Unqualified("embedding"),
          Some(@contract.vector_contract(2.0, nullable=false).unwrap()),
        ),
      ],
      field_set=@carrier.Closed,
      max_fields=2,
      max_name_bytes=11,
    ).unwrap(),
  )
}

///|
fn producer_owner() -> @lower.BoundPrepared {
  let checked = @pipeline.check_carriers(
    cursor(
      "[{\"from\":\"rows\",\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"}}]",
    ),
    [("rows", relation_contract())],
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
  @lower.bind_parameters(
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
}

///|
fn consumer_owner(producer : @lower.BoundPrepared) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    cursor("[{\"normalize_vectors\":true}]"),
    [
      (
        "prior",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(producer)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(cursor("\"prior\"")),
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
}

///|
fn event_relation_contract() -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Unqualified("event_id"),
          Some(@contract.primitive(@contract.NumberType, nullable=false)),
        ),
        (
          @schema.Unqualified("occurred_at"),
          Some(@contract.primitive(@contract.NumberType, nullable=false)),
        ),
      ],
      field_set=@carrier.Closed,
      max_fields=2,
      max_name_bytes=19,
    ).unwrap(),
  )
}

///|
fn event_producer_owner() -> @lower.BoundPrepared {
  let checked = @pipeline.check_carriers(
    cursor(
      "[{\"from\":\"rows\",\"to_events\":{\"id\":\"event_id\",\"time\":\"occurred_at\"}}]",
    ),
    [("rows", event_relation_contract())],
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
  @lower.bind_parameters(
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
}

///|
fn event_consumer_owner(
  producer : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    cursor("[{\"watermark_events\":{\"watermark_ms\":0,\"policy\":\"mark\"}}]"),
    [
      (
        "prior",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(producer)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(cursor("\"prior\"")),
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
}

///|
fn limits() -> @storage.Limits {
  {
    max_input_records: 10,
    max_records: 10,
    max_fields_per_record: 10,
    max_value_bytes: 1000,
    max_total_value_bytes: 10000,
    max_retained_value_bytes: 10000,
    max_value_nodes: 100,
    max_value_depth: 10,
    max_contract_work: 1000,
    max_work: 1000,
    max_workspace_slots: 1000,
  }
}

///|
fn number(value : Double) -> @value.CheckedValue {
  @value.admit(
    @contract.primitive(@contract.NumberType, nullable=false),
    cursor(value.to_string()),
    { max_nodes: 1, max_depth: 1, max_text_bytes: 0, },
  ).unwrap()
}

///|
fn vector(text : String) -> @value.CheckedValue {
  @value.admit(
    @contract.vector_contract(2.0, nullable=false).unwrap(),
    cursor(text),
    { max_nodes: 3, max_depth: 2, max_text_bytes: 0, },
  ).unwrap()
}

///|
test "managed Vectors support two exact downstream consumers" {
  let owner = producer_owner()
  let live = Ref(true)
  let output = prepare_output(owner, @pipeline.Step(0), limits(), 2048L, fn() {
    live.val
  }).unwrap()
  append_record(output, [
    (@schema.Unqualified("id"), number(1.0)),
    (@schema.Unqualified("embedding"), vector("[3,4]")),
  ]).unwrap()
  let completed = finish_output(output).unwrap()
  assert_eq(
    completed_measure(completed),
    @lifecycle.VectorsMeasure(records=1, dimensions=2),
  )
  assert_eq(completed_storage_bytes(completed), Some(2048L))
  let evidence = completed_evidence(completed).unwrap()
  assert_eq(evidence_carrier(evidence), @carrier.VectorsKind)
  assert_eq(evidence_records(evidence), 1)
  assert_eq(evidence_identity_count(evidence), 1)
  assert_true(
    evidence_measured_value_bytes(evidence) >=
    evidence_retained_value_bytes(evidence),
  )
  let receiver = consumer_owner(owner)
  let first = prepare_producer_read(receiver, 0, owner, completed).unwrap()
  let second = prepare_producer_read(receiver, 0, owner, completed).unwrap()
  assert_false(producer_read_same(first, second))
  assert_eq(@storage.record_count(producer_read_storage(first).unwrap()), 1)
  assert_eq(@storage.record_count(producer_read_storage(second).unwrap()), 1)
  let reference = completed_reference(completed)
  assert_true(producer_read_matches_reference(first, reference))
  assert_true(producer_read_matches_reference(second, reference))
  live.val = false
  assert_false(completed_available(completed))
  assert_false(completed_reference_available(reference))
  assert_true(producer_read_storage(first) is None)
  assert_true(producer_read_storage(second) is None)
}

///|
test "managed Events support two exact downstream consumers" {
  let owner = event_producer_owner()
  let live = Ref(true)
  let output = prepare_output(owner, @pipeline.Step(0), limits(), 1024L, fn() {
    live.val
  }).unwrap()
  append_record(output, [
    (@schema.Unqualified("event_id"), number(7.0)),
    (@schema.Unqualified("occurred_at"), number(12.0)),
  ]).unwrap()
  let completed = finish_output(output).unwrap()
  assert_eq(completed_measure(completed), @lifecycle.EventsMeasure(records=1))
  let evidence = completed_evidence(completed).unwrap()
  assert_eq(evidence_carrier(evidence), @carrier.EventsKind)
  assert_eq(evidence_records(evidence), 1)
  let receiver = event_consumer_owner(owner)
  let first = prepare_producer_read(receiver, 0, owner, completed).unwrap()
  let second = prepare_producer_read(receiver, 0, owner, completed).unwrap()
  assert_false(producer_read_same(first, second))
  assert_eq(@storage.record_count(producer_read_storage(first).unwrap()), 1)
  assert_eq(@storage.record_count(producer_read_storage(second).unwrap()), 1)
  let reference = completed_reference(completed)
  assert_true(producer_read_matches_reference(first, reference))
  assert_true(producer_read_matches_reference(second, reference))
  live.val = false
  assert_false(completed_available(completed))
  assert_true(producer_read_storage(first) is None)
  assert_true(producer_read_storage(second) is None)
}

///|
test "managed record output cancels before publishing partial material" {
  let owner = producer_owner()
  let output = prepare_output(owner, @pipeline.Step(0), limits(), 2048L, fn() {
    true
  }).unwrap()
  append_record(output, [
    (@schema.Unqualified("id"), number(1.0)),
    (@schema.Unqualified("embedding"), vector("[3,4]")),
  ]).unwrap()
  assert_true(cancel_output(output))
  assert_false(cancel_output(output))
  assert_true(finish_output(output) is Err(Closed))
  assert_true(
    prepare_output(owner, @pipeline.Step(0), limits(), -1L, fn() { true })
    is Err(InvalidStorageBytes),
  )
}

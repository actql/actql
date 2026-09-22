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
fn event_sequence_owner() -> @lower.BoundPrepared {
  let checked = @pipeline.check_carriers(
    cursor(
      "[{\"from\":\"rows\",\"to_events\":{\"id\":\"event_id\",\"time\":\"occurred_at\"}},{\"watermark_events\":{\"watermark_ms\":0,\"policy\":\"mark\"}}]",
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
  let view = producer_read_view(first).unwrap()
  assert_eq(@lifecycle.producer_view_kind(view), @carrier.VectorsKind)
  assert_eq(@lifecycle.producer_view_record_count(view), Some(1))
  assert_eq(@lifecycle.producer_view_record_field_count(view, 0), Ok(2))
  assert_eq(
    @lifecycle.producer_view_record_field(view, 0, 0).unwrap().0,
    @schema.Unqualified("id"),
  )
  assert_true(
    @lifecycle.producer_view_matches_read(
      view,
      producer_read_carrier_reference(first),
    ),
  )
  let reference = completed_reference(completed)
  assert_true(producer_read_matches_reference(first, reference))
  assert_true(producer_read_matches_reference(second, reference))
  let material = completed_material(completed).unwrap()
  assert_eq(@lifecycle.material_kind(material), @carrier.VectorsKind)
  assert_eq(@lifecycle.material_storage_bytes(material), Some(2048L))
  let material_view = @lifecycle.material_prepare_view(
    material, receiver, 0, owner,
  ).unwrap()
  assert_eq(@lifecycle.producer_view_record_count(material_view), Some(1))
  live.val = false
  assert_false(completed_available(completed))
  assert_false(completed_reference_available(reference))
  assert_eq(
    @lifecycle.producer_view_record_field_count(view, 0),
    Err(@lifecycle.Unavailable),
  )
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
test "managed Events bind an exact internal sequence edge" {
  let owner = event_sequence_owner()
  let output = prepare_output(owner, @pipeline.Step(0), limits(), 1024L, fn() {
    true
  }).unwrap()
  append_record(output, [
    (@schema.Unqualified("event_id"), number(7.0)),
    (@schema.Unqualified("occurred_at"), number(12.0)),
  ]).unwrap()
  let completed = finish_output(output).unwrap()
  let read = prepare_step_read(owner, 1, 0, completed).unwrap()
  assert_true(producer_read_matches_step(read, owner, 1, 0))
  assert_true(producer_read_matches_operation_input(read, owner, 1, 0))
  assert_true(prepare_step_read(owner, 0, 0, completed) is Err(Producer(_)))
}

///|
test "managed Events material issues exact internal operation views" {
  let owner = event_sequence_owner()
  let output = prepare_output(owner, @pipeline.Step(0), limits(), 1024L, fn() {
    true
  }).unwrap()
  append_record(output, [
    (@schema.Unqualified("event_id"), number(7.0)),
    (@schema.Unqualified("occurred_at"), number(12.0)),
  ]).unwrap()
  let completed = finish_output(output).unwrap()
  let material = completed_material(completed).unwrap()
  let first = @lifecycle.material_prepare_operation_view(
    material, owner, 1, 0, owner,
  ).unwrap()
  let second = @lifecycle.material_prepare_operation_view(
    material, owner, 1, 0, owner,
  ).unwrap()
  assert_false(
    @lifecycle.producer_view_matches_read(
      first,
      @lifecycle.producer_view_read_reference(second),
    ),
  )
  assert_true(
    @lifecycle.material_prepare_operation_view(material, owner, 0, 0, owner)
    is Err(@lifecycle.Unverified),
  )
  assert_true(
    @lifecycle.material_prepare_operation_view(material, owner, 1, 1, owner)
    is Err(@lifecycle.Unverified),
  )
  let foreign = event_producer_owner()
  assert_true(
    @lifecycle.material_prepare_operation_view(material, owner, 1, 0, foreign)
    is Err(@lifecycle.Unverified),
  )
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

///|
test "failed managed record output remains reclaimable" {
  let owner = event_producer_owner()
  let output = prepare_output(owner, @pipeline.Step(0), limits(), 1024L, fn() {
    true
  }).unwrap()
  let record = [
    (@schema.Unqualified("event_id"), number(7.0)),
    (@schema.Unqualified("occurred_at"), number(12.0)),
  ]
  append_record(output, record).unwrap()
  assert_true(append_record(output, record) is Err(Storage(DuplicateIdentity)))
  assert_eq(@storage.builder_record_count(output.records), 1)
  assert_true(cancel_output(output))
  assert_eq(@storage.builder_record_count(output.records), 0)
  assert_eq(@storage.builder_retained_value_bytes(output.records), 0)
  assert_eq(@storage.builder_workspace_slots(output.records), 0)
  assert_false(cancel_output(output))
  assert_true(finish_output(output) is Err(Closed))
}

///|
test "unpublished completed record output can be revoked and discarded" {
  let owner = event_producer_owner()
  let output = prepare_output(owner, @pipeline.Step(0), limits(), 1024L, fn() {
    true
  }).unwrap()
  append_record(output, [
    (@schema.Unqualified("event_id"), number(7.0)),
    (@schema.Unqualified("occurred_at"), number(12.0)),
  ]).unwrap()
  let completed = finish_output(output).unwrap()
  let storage = completed_storage(completed).unwrap()
  assert_eq(@storage.record_count(storage), 1)
  assert_true(discard_completed(completed))
  assert_eq(@storage.record_count(storage), 0)
  assert_false(completed_available(completed))
  assert_true(completed_storage(completed) is None)
  assert_false(discard_completed(completed))
}

///|
test "unavailable unpublished record output remains reclaimable" {
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
  let storage = completed_storage(completed).unwrap()
  live.val = false
  assert_false(completed_available(completed))
  assert_true(discard_completed(completed))
  assert_eq(@storage.record_count(storage), 0)
  assert_false(discard_completed(completed))
}

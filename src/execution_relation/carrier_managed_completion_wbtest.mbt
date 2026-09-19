///|
fn carrier_completion_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="carrier-managed-completion.aql",
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
fn carrier_completion_relation() -> @carrier.Carrier {
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
fn carrier_completion_bind(
  checked : @pipeline.CheckedPipeline,
) -> @lower.BoundPrepared {
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
fn carrier_completion_producer() -> @lower.BoundPrepared {
  carrier_completion_bind(
    @pipeline.check_carriers(
      carrier_completion_cursor(
        "[{\"from\":\"rows\",\"to_events\":{\"id\":\"event_id\",\"time\":\"occurred_at\"}}]",
      ),
      [("rows", carrier_completion_relation())],
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
    ).unwrap(),
  )
}

///|
fn carrier_completion_consumer(
  producer : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  carrier_completion_bind(
    @pipeline.check_with_evidence(
      carrier_completion_cursor(
        "[{\"watermark_events\":{\"watermark_ms\":0,\"policy\":\"mark\"}}]",
      ),
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
      Some(carrier_completion_cursor("\"prior\"")),
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn carrier_completion_preparation(
  owner : @lower.BoundPrepared,
  retained : String,
) -> CompletionPreparation raise {
  let sequence = @lower.prepare_sequence(owner, {
    max_steps: 10,
    max_rows: 100,
    max_cells: 1000,
    max_bindings: 100,
    max_name_bytes: 1000,
    expressions: {
      max_nodes: 100,
      max_work: 1000,
      max_depth: 100,
      max_literal_nodes: 100,
      max_literal_text_bytes: 1000,
    },
  }).unwrap()
  prepare_completion(
    registered_relation_contracts(),
    sequence,
    [retained],
    10000,
    1000,
  ).unwrap()
}

///|
fn raw_event_completion(
  owner : @lower.BoundPrepared,
  live : Ref[Bool],
  storage_bytes : Int64,
) -> @managed_carrier.Completed[String, Int] {
  let binding = @managed_carrier.prepare_binding(owner, @pipeline.Step(0)).unwrap()
  let receipt = @managed_carrier.complete_receipt(
    binding,
    @managed_carrier.EventsMeasure(records=1),
  ).unwrap()
  let retained = @managed_carrier.retain(
    @managed_carrier.prepare_retention_port(binding, (_ : Unit) => {
      Some((receipt, "events", 7, storage_bytes, fn() { live.val }))
    }),
    (),
  ).unwrap()
  @managed_carrier.complete(retained).unwrap()
}

///|
fn carrier_envelope(
  owner : @lower.BoundPrepared,
  retained : String,
  raw : @managed_carrier.Completed[String, Int],
  inputs? : Array[CarrierManagedProducerRead],
  attempt? : ManagedExecutionAttempt = issue_managed_execution_attempt(),
) -> CarrierManagedCompletedOutput raise {
  let reference = @managed_carrier.completion_reference(raw)
  let port = prepare_carrier_managed_completion_port(
    selected_managed_execution_profile(),
    carrier_completion_preparation(owner, retained),
    @pipeline.Step(0),
    10,
    100,
    (_ : Unit) => Some(reference),
    inputs?,
    attempt~,
  )
  complete_carrier_managed_output(port.unwrap(), ()).unwrap()
}

///|
test "carrier completion seals exact event attempt and input use site" {
  let producer = carrier_completion_producer()
  let producer_live = Ref(true)
  let producer_raw = raw_event_completion(producer, producer_live, 16L)
  let producer_attempt = issue_managed_execution_attempt()
  let producer_output = carrier_envelope(
    producer,
    "to_events_0",
    producer_raw,
    attempt=producer_attempt,
  )
  assert_eq(
    carrier_managed_completed_output_kind(producer_output),
    @carrier.EventsKind,
  )
  assert_eq(
    carrier_managed_completed_output_storage_bytes(producer_output),
    Some(16L),
  )
  assert_true(
    carrier_managed_completed_output_matches_attempt(
      producer_output, producer_attempt,
    ),
  )

  let consumer = carrier_completion_consumer(producer)
  let raw_read = @managed_carrier.prepare_producer_read(
    consumer, 0, producer, producer_raw,
  ).unwrap()
  let input = prepare_carrier_managed_producer_read(
    consumer,
    0,
    producer,
    producer_output,
    @managed_carrier.producer_read_reference(raw_read),
  ).unwrap()
  let consumer_live = Ref(true)
  let consumer_raw = raw_event_completion(consumer, consumer_live, 32L)
  let consumer_reference = @managed_carrier.completion_reference(consumer_raw)
  assert_true(
    prepare_carrier_managed_completion_port(
      selected_managed_execution_profile(),
      carrier_completion_preparation(consumer, "watermark_events_0"),
      @pipeline.Step(0),
      10,
      100,
      (_ : Unit) => Some(consumer_reference),
    )
    is Err(ForeignInputs),
  )
  assert_true(
    prepare_carrier_managed_completion_port(
      selected_managed_execution_profile(),
      carrier_completion_preparation(consumer, "watermark_events_0"),
      @pipeline.Step(0),
      10,
      100,
      (_ : Unit) => Some(consumer_reference),
      inputs=[],
    )
    is Err(ForeignInputs),
  )
  let consumer_attempt = issue_managed_execution_attempt()
  let output = carrier_envelope(
    consumer,
    "watermark_events_0",
    consumer_raw,
    inputs=[input],
    attempt=consumer_attempt,
  )
  assert_true(carrier_managed_completed_output_available(output))
  assert_true(
    carrier_managed_completed_output_matches_port(
      output,
      consumer,
      @pipeline.Step(0),
    ),
  )
  assert_true(carrier_managed_completed_output_matches_inputs(output, [input]))
  assert_false(
    managed_obligations_require_logical_identity(
      carrier_managed_completed_output_obligations(output),
    ),
  )
  let reference = carrier_managed_completed_reference(output)
  assert_true(carrier_managed_completed_reference_matches(reference, output))
  consumer_live.val = false
  assert_false(carrier_managed_completed_output_available(output))
  assert_false(carrier_managed_completed_reference_available(reference))
  assert_true(carrier_managed_completed_output_storage_bytes(output) is None)
}

///|
test "carrier completion rejects foreign, revoked, and identity-required use" {
  let owner = carrier_completion_producer()
  let raw = raw_event_completion(owner, Ref(true), 8L)
  let reference = @managed_carrier.completion_reference(raw)
  let preparation = carrier_completion_preparation(owner, "to_events_0")
  let prepared_port = prepare_carrier_managed_completion_port(
    selected_managed_execution_profile(),
    preparation,
    @pipeline.Step(0),
    10,
    100,
    (_ : Unit) => Some(reference),
  )
  let port = prepared_port.unwrap()
  assert_true(cancel_carrier_managed_completion_port(port))
  assert_true(complete_carrier_managed_output(port, ()) is Err(Unverified))
  assert_true(
    prepare_carrier_managed_completion_port(
      selected_managed_execution_profile(),
      preparation,
      @pipeline.Step(0),
      10,
      100,
      (_ : Unit) => Some(reference),
      obligations=prepare_managed_obligations(
        owner,
        [
          {
            domain: OrderedRows,
            subject: TaskOutput,
            occurrence: None,
            need: EstablishedBy(BeforeDiscard),
          },
        ],
        ManagedUse,
        MaterialBinding,
        1,
      ).unwrap(),
    )
    is Err(ForeignOutput),
  )
}

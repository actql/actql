///|
priv enum EventsBridgeExpected {
  Number(Double)
  Timestamp(String)
  Text(String)
  Null
}

///|
test "compositional Events bridge preserves independent ordered nullable rows and checked schema" {
  // Inputs and expected observations are authored independently of lowering,
  // storage output and the Lean model. The two bridges share no watermark step.
  let cases : Array[(String, String, Array[Array[EventsBridgeExpected]])] = [
    ("number", "[]", []),
    (
      "number",
      "[{\"event_id\":2,\"occurred_at\":10,\"payload\":null}," +
      "{\"event_id\":1,\"occurred_at\":1,\"payload\":null}]",
      [[Number(2.0), Number(10.0), Null], [Number(1.0), Number(1.0), Null]],
    ),
    (
      "number",
      "[{\"event_id\":2,\"occurred_at\":10,\"payload\":\"same\"}," +
      "{\"event_id\":1,\"occurred_at\":1,\"payload\":\"same\"}]",
      [
        [Number(2.0), Number(10.0), Text("same")],
        [Number(1.0), Number(1.0), Text("same")],
      ],
    ),
    (
      "timestamp",
      "[{\"event_id\":1,\"occurred_at\":\"1969-12-31T23:59:59.999Z\"," +
      "\"payload\":\"é\\r\\n\"}]",
      [[Number(1.0), Timestamp("1969-12-31T23:59:59.999Z"), Text("é\r\n")]],
    ),
  ]
  for (clock, input, expected) in cases {
    let source_owner = carrier_events_source_owner_with(
      clock,
      input,
      payload_nullable=true,
    )
    let source = carrier_events_source_output(source_owner)
    let events_owner = carrier_events_output_owner(source_owner)
    let input_read = @execution.prepare_producer_read(
      events_owner,
      @execution.bind_completed_input(events_owner, 0, source_owner, source).unwrap(),
      100,
      1000,
    ).unwrap()
    let encoding = @local_bridge.start_rows_to_events(
      @bounded.control(),
      prepared_sequence(events_owner),
      0,
      input_read,
      carrier_events_storage_limits(),
      4096L,
      fn() { true },
    ).unwrap()
    let events = finish_rows_to_events(encoding)
    assert_eq(@local_bridge.cleanup_rows_to_events(encoding), Ok(true))
    // Observe the intermediate carrier before projection; two faulty bridges
    // must not conceal each other's identity, clock or payload mistakes.
    let storage = @records.completed_storage(events).unwrap()
    guard @record_storage.carrier(storage)
      is @carrier_contract.EventValue(event_contract) else {
      fail("intermediate Events carrier")
    }
    assert_eq(
      @schema.reference_name(
        @carrier_contract.event_identity(event_contract).name,
      ),
      "event_id",
    )
    assert_eq(
      @schema.reference_name(@carrier_contract.event_time(event_contract).name),
      "occurred_at",
    )
    assert_eq(
      @carrier_contract.event_clock_encoding(event_contract),
      if clock == "number" {
        @carrier_contract.Milliseconds
      } else {
        @carrier_contract.UtcTimestamp
      },
    )
    assert_eq(@record_storage.identity_count(storage), 1)
    assert_eq(@record_storage.identity_name_at(storage, 0), Some("event_id"))
    assert_eq(@record_storage.record_count(storage), expected.length())
    for row, cells in expected {
      assert_eq(@record_storage.record_field_count(storage, row), Some(3))
      for column, value in cells {
        let (name, actual) = @record_storage.record_field_at(
          storage, row, column,
        ).unwrap()
        assert_eq(
          @schema.reference_name(name),
          ["event_id", "occurred_at", "payload"][column],
        )
        match value {
          Number(expected) => {
            guard actual.value is @admitted.Number(value) else {
              fail("intermediate Events number")
            }
            assert_eq(value, expected)
          }
          Timestamp(expected) => {
            guard actual.value is @admitted.Timestamp(value) else {
              fail("intermediate Events timestamp")
            }
            assert_eq(value, expected)
          }
          Text(expected) => {
            guard actual.value is @admitted.Text(value) else {
              fail("intermediate Events text")
            }
            assert_eq(value, expected)
          }
          Null => assert_true(actual.value is @admitted.Null)
        }
      }
    }
    let projection_owner = carrier_events_projection_owner(events_owner)
    let record_read = @records.prepare_producer_read(
      projection_owner, 0, events_owner, events,
    ).unwrap()
    assert_true(
      @records.producer_read_matches_operation_input(
        record_read, projection_owner, 0, 0,
      ),
    )
    let sequence = prepared_sequence(projection_owner)
    assert_true(
      @lower.sequence_step(sequence, 0) is Some(@lower.CarrierProjectionStep(_)),
    )
    let checked_schema = @pipeline.schema_at(
      @lower.pipeline(@lower.bound_preparation(projection_owner)),
      @pipeline.Step(0),
    ).unwrap()
    // Empty/all-NULL types are contracts, not inferred runtime types. The
    // material's public schema and the same checked projection are compared
    // separately against independent expectations.
    let material_schema = @carrier_contract.complete_schema(
      @carrier_contract.event_records(event_contract),
    ).unwrap()
    for actual_schema in [material_schema, checked_schema] {
      assert_eq(@schema.field_count(actual_schema), 3)
      for index, name in ["event_id", "occurred_at", "payload"] {
        let field = @schema.field_at(actual_schema, index).unwrap()
        assert_eq(@schema.field_reference_name(field), name)
        assert_eq(field.contract.nullable, index == 2)
        if index == 0 {
          assert_true(field.contract.shape is @value_contract.Number)
        } else if index == 1 {
          assert_true(
            (
              clock == "number" &&
              field.contract.shape is @value_contract.Number
            ) ||
            (
              clock == "timestamp" &&
              field.contract.shape is @value_contract.Timestamp
            ),
          )
        } else {
          assert_true(field.contract.shape is @value_contract.Text(_))
        }
      }
    }
    let projection = @local_bridge.start_events_view_to_rows(
      @bounded.control(),
      task_test_completion(projection_owner),
      sequence,
      0,
      @records.producer_read_view(record_read).unwrap(),
      10,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      100,
      1000,
    ).unwrap()
    let rows = finish_events_to_rows(projection)
    assert_eq(@local_bridge.cleanup_events_to_rows(projection), Ok(true))
    assert_true(
      @execution.completed_output_matches_port(
        rows,
        projection_owner,
        @pipeline.Step(0),
      ),
    )
    assert_eq(@execution.completed_column_count(rows), 3)
    for index, name in ["event_id", "occurred_at", "payload"] {
      assert_eq(@execution.completed_column_name(rows, index), Some(name))
    }
    assert_eq(@execution.completed_row_count(rows), expected.length())
    for row, cells in expected {
      for column, value in cells {
        let actual = @execution.completed_cell(rows, row, column)
        match value {
          Number(expected) => {
            guard actual is Some(@execution.Number(value)) else {
              fail("number observation")
            }
            assert_eq(value, expected)
          }
          Timestamp(expected) => {
            guard actual
              is Some(@execution.Captured(@admitted.Timestamp(value))) else {
              fail("authored timestamp observation")
            }
            assert_eq(value, expected)
          }
          Text(expected) => {
            guard actual is Some(@execution.Text(value)) else {
              fail("text observation")
            }
            assert_eq(value, expected)
          }
          Null => assert_true(actual is Some(@execution.Null))
        }
      }
    }
    assert_true(@records.completed_available(events))
    assert_true(@records.discard_completed(events))
    assert_false(@records.discard_completed(events))
  }
}

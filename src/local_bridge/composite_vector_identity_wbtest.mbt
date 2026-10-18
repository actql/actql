///|
fn composite_vector_bridge_receiver(
  source : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    graph_order_input_cursor(
      "[{\"from\":\"rows\",\"to_vectors\":{\"id\":[\"id\",\"tenant\"],\"vector\":\"embedding\"}}]",
    ),
    [
      (
        "rows",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(source)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 100000,
      max_identifier_bytes: 100000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn composite_vector_bridge_storage_limits() -> @storage.Limits {
  {
    max_input_records: 10,
    max_records: 10,
    max_fields_per_record: 3,
    max_value_bytes: 1000,
    max_total_value_bytes: 10000,
    max_retained_value_bytes: 10000,
    max_value_nodes: 1000,
    max_value_depth: 10,
    max_contract_work: 10000,
    max_work: 10000,
    max_workspace_slots: 1000,
  }
}

///|
test "composite rows Bridge uses complete original identity tuples for uniqueness" {
  for (tenant, duplicate) in [("two", false), ("one", true)] {
    let source_owner = graph_order_keyed_source_owner(
      "{\"tenant\":{\"type\":\"string\",\"nullable\":false},\"id\":{\"type\":\"number\",\"nullable\":false},\"embedding\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}}",
      "[{\"id\":1,\"tenant\":\"one\",\"embedding\":[1,0]},{\"id\":1,\"tenant\":\"" +
      tenant +
      "\",\"embedding\":[0,1]}]",
    )
    let source = graph_order_carrier_events_source_output(source_owner)
    let owner = composite_vector_bridge_receiver(source_owner)
    let input = @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
      100,
      1000,
    ).unwrap()
    let active = start_rows_to_vectors(
      @bounded.control(),
      graph_order_prepared_sequence(owner),
      0,
      input,
      composite_vector_bridge_storage_limits(),
      4096L,
      () => true,
    ).unwrap()
    let mut terminal = false
    for _ in 0..<1000 {
      match advance_rows_to_vectors(active, 1).unwrap() {
        Continue(..) => ()
        Complete(output, ..) => {
          assert_true(!duplicate)
          let storage = @records.completed_storage(output).unwrap()
          assert_eq(@storage.record_count(storage), 2)
          guard @storage.carrier(storage) is @carrier.VectorValue(vectors) else {
            fail("Original Vectors carrier")
          }
          assert_eq(
            @carrier.vector_identity_at(vectors, 0).unwrap().name,
            @schema.Unqualified("id"),
          )
          assert_eq(
            @carrier.vector_identity_at(vectors, 1).unwrap().name,
            @schema.Unqualified("tenant"),
          )
          for index, expected in ["one", "two"] {
            let mut found = false
            for field in 0..<3 {
              if @storage.record_field_at(storage, index, field)
                is Some((@schema.Unqualified("tenant"), checked)) {
                assert_true(
                  checked.value is @value.Text(actual) && actual == expected,
                )
                found = true
              }
            }
            assert_true(found)
          }
          assert_true(@records.discard_completed(output))
          terminal = true
          break
        }
        Failed(Output(@records.Storage(@storage.DuplicateIdentity)), ..) => {
          assert_true(duplicate)
          terminal = true
          break
        }
        _ => fail("Unexpected composite Bridge terminal")
      }
    }
    assert_true(terminal)
    assert_eq(cleanup_rows_to_vectors(active), Ok(true))
    assert_eq(cleanup_rows_to_vectors(active), Ok(false))
    assert_true(@execution.completed_output_available(source))
  }
}

///|
test "composite rows Bridge retains source through original current refusal and cancellation" {
  let source_owner = graph_order_keyed_source_owner(
    "{\"tenant\":{\"type\":\"string\",\"nullable\":false},\"id\":{\"type\":\"number\",\"nullable\":false},\"embedding\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}}",
    "[{\"id\":1,\"tenant\":\"one\",\"embedding\":[1,0]}]",
  )
  let source = graph_order_carrier_events_source_output(source_owner)
  let owner = composite_vector_bridge_receiver(source_owner)
  for cancel in [true, false] {
    let current = Ref(true)
    // Restrict the same completion through its existing original-liveness port.
    // The output retention predicate is not an input-currentness callback.
    let selected = @execution.restrict_completed_output(source, () => {
      current.val
    })
    let input = @execution.prepare_producer_read(
      owner,
      @execution.bind_completed_input(owner, 0, source_owner, selected).unwrap(),
      100,
      1000,
    ).unwrap()
    let control = @bounded.control()
    let active = start_rows_to_vectors(
      control,
      graph_order_prepared_sequence(owner),
      0,
      input,
      composite_vector_bridge_storage_limits(),
      4096L,
      () => true,
    ).unwrap()
    assert_true(advance_rows_to_vectors(active, 1).unwrap() is Continue(..))
    if cancel {
      assert_true(@bounded.request_cancel(control))
    } else {
      current.val = false
    }
    match advance_rows_to_vectors(active, 1).unwrap() {
      Stopped(_, ..) => assert_true(cancel)
      Failed(InputUnavailable, ..) => assert_true(!cancel)
      _ => fail("Original current/stop boundary must refuse before publication")
    }
    assert_eq(cleanup_rows_to_vectors(active), Ok(true))
    assert_true(@execution.completed_output_available(source))
  }
}

// Synthetic expectations are authored independently of execution output.

///|
fn composition_receiver(
  source : @lower.BoundPrepared,
  source_step : Int,
  vectors : Bool,
) -> @lower.BoundPrepared {
  let body = if vectors {
    "[{\"from\":\"rows\",\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"}},{\"vectors\":true}]"
  } else {
    "[{\"from\":\"rows\",\"to_events\":{\"id\":\"id\",\"time\":\"occurred_at\"}},{\"events\":true}]"
  }
  let checked = @pipeline.check_with_evidence(
    graph_order_input_cursor(body),
    [
      (
        "rows",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(source)),
            @pipeline.Step(source_step),
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
fn composition_storage_limits() -> @storage.Limits {
  {
    max_input_records: 10,
    max_records: 10,
    max_fields_per_record: 4,
    max_value_bytes: 1000,
    max_total_value_bytes: 10000,
    max_retained_value_bytes: 10000,
    max_value_nodes: 1000,
    max_value_depth: 10,
    max_contract_work: 100000,
    max_work: 100000,
    max_workspace_slots: 10000,
  }
}

///|
fn composition_roundtrip(
  source_owner : @lower.BoundPrepared,
  source : @execution.CompletedOutput,
  source_step : Int,
  vectors : Bool,
  quantum : Int,
) -> (@lower.BoundPrepared, @execution.CompletedOutput) raise {
  let owner = composition_receiver(source_owner, source_step, vectors)
  let sequence = graph_order_prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    1000,
    10000,
  ).unwrap()
  let mut completed : @records.Completed? = None
  if vectors {
    let active = start_rows_to_vectors(
      @bounded.control(),
      sequence,
      0,
      external,
      composition_storage_limits(),
      65536L,
      () => true,
    ).unwrap()
    for _ in 0..<10000 {
      match advance_rows_to_vectors(active, quantum).unwrap() {
        Continue(..) => ()
        Complete(output, ..) => {
          completed = Some(output)
          break
        }
        _ => fail("Vectors construction did not complete")
      }
    }
    assert_true(completed is Some(_))
    assert_eq(cleanup_rows_to_vectors(active), Ok(true))
  } else {
    let active = start_rows_to_events(
      @bounded.control(),
      sequence,
      0,
      external,
      composition_storage_limits(),
      65536L,
      () => true,
    ).unwrap()
    for _ in 0..<10000 {
      match advance_rows_to_events(active, quantum).unwrap() {
        Continue(..) => ()
        Complete(output, ..) => {
          completed = Some(output)
          break
        }
        _ => fail("Events construction did not complete")
      }
    }
    assert_true(completed is Some(_))
    assert_eq(cleanup_rows_to_events(active), Ok(true))
  }
  let completed = completed.unwrap()
  let input = @records.prepare_step_read(owner, 1, 0, completed).unwrap()
  let limits : @execution.ValueLimits = {
    max_nodes: 1000,
    max_text_bytes: 10000,
    max_depth: 20,
    max_work: 100000,
  }
  let mut projected : @execution.CompletedOutput? = None
  if vectors {
    let active = start_vectors_to_rows(
      @bounded.control(),
      graph_order_task_test_completion(owner),
      sequence,
      1,
      input,
      10,
      limits,
      1000,
      10000,
      [external],
    ).unwrap()
    for _ in 0..<10000 {
      match advance_vectors_to_rows(active, quantum).unwrap() {
        Continue(..) => ()
        Complete(output, ..) => {
          projected = Some(output)
          break
        }
        _ => fail("Vectors projection did not complete")
      }
    }
    assert_true(projected is Some(_))
    assert_eq(cleanup_vectors_to_rows(active), Ok(true))
  } else {
    let active = start_events_to_rows(
      @bounded.control(),
      graph_order_task_test_completion(owner),
      sequence,
      1,
      input,
      10,
      limits,
      1000,
      10000,
      [external],
    ).unwrap()
    for _ in 0..<10000 {
      match advance_events_to_rows(active, quantum).unwrap() {
        Continue(..) => ()
        Complete(output, ..) => {
          projected = Some(output)
          break
        }
        _ => fail("Events projection did not complete")
      }
    }
    assert_true(projected is Some(_))
    assert_eq(cleanup_events_to_rows(active), Ok(true))
  }
  assert_true(@execution.completed_output_available(source))
  (owner, projected.unwrap())
}

///|
fn composition_assert_rows(
  output : @execution.CompletedOutput,
  empty : Bool,
) -> Unit raise {
  assert_eq(@execution.completed_row_count(output), if empty { 0 } else { 3 })
  assert_eq(@execution.completed_column_count(output), 4)
  // Check the schema even for empty input. Counting columns alone would let
  // one expected field disappear behind a duplicated known field name.
  for expected in ["id", "occurred_at", "embedding", "payload"] {
    let mut occurrences = 0
    for column in 0..<4 {
      if @execution.completed_column_name(output, column) == Some(expected) {
        occurrences += 1
      }
    }
    assert_eq(occurrences, 1)
  }
  if empty {
    return
  }
  let ids = [10.0, 2.0, 31.0]
  let clocks = [200.0, -10.0, 0.0]
  let embeddings = [[1.0, 0.0], [0.0, 2.0], [-3.0, 4.0]]
  for row in 0..<3 {
    for col in 0..<4 {
      let name = @execution.completed_column_name(output, col).unwrap()
      let cell = @execution.completed_cell(output, row, col).unwrap()
      match name {
        "id" => {
          guard cell is @execution.Number(n) else { fail("ID changed type") }
          assert_eq(n, ids[row])
        }
        "occurred_at" => {
          guard cell is @execution.Number(n) else { fail("Clock changed type") }
          assert_eq(n, clocks[row])
        }
        "embedding" => {
          guard cell is @execution.Captured(@value.Vector(v)) else {
            fail("Vector changed type")
          }
          assert_eq(@value.element_count(v), 2)
          assert_eq(@value.element_at(v, 0).unwrap(), embeddings[row][0])
          assert_eq(@value.element_at(v, 1).unwrap(), embeddings[row][1])
        }
        "payload" =>
          if row == 1 {
            assert_true(cell is @execution.Null)
          } else {
            guard cell is @execution.Text(s) else {
              fail("Payload changed type")
            }
            assert_eq(s, if row == 0 { "first😀" } else { "third" })
          }
        _ => fail("Unexpected projected field")
      }
    }
  }
}

///|
test "mixed Vectors Relation Events Relation Vectors chain retains typed values and occurrence order" {
  for quantum in [1, 64] {
    for empty in [false, true] {
      let source_owner = graph_order_keyed_source_owner(
        "{\"id\":{\"type\":\"number\",\"nullable\":false},\"occurred_at\":{\"type\":\"number\",\"nullable\":false},\"embedding\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false},\"payload\":{\"type\":\"string\",\"nullable\":true}}",
        if empty {
          "[]"
        } else {
          "[{\"id\":10,\"occurred_at\":200,\"embedding\":[1,0],\"payload\":\"first😀\"},{\"id\":2,\"occurred_at\":-10,\"embedding\":[0,2],\"payload\":null},{\"id\":31,\"occurred_at\":0,\"embedding\":[-3,4],\"payload\":\"third\"}]"
        },
      )
      let source = graph_order_carrier_events_source_output(source_owner)
      composition_assert_rows(source, empty)
      let (vectors_owner, vectors) = composition_roundtrip(
        source_owner, source, 0, true, quantum,
      )
      composition_assert_rows(vectors, empty)
      let (events_owner, events) = composition_roundtrip(
        vectors_owner, vectors, 1, false, quantum,
      )
      composition_assert_rows(events, empty)
      let (_, final_rows) = composition_roundtrip(
        events_owner, events, 1, true, quantum,
      )
      composition_assert_rows(final_rows, empty)
      composition_assert_rows(source, empty)
      composition_assert_rows(vectors, empty)
    }
  }
}

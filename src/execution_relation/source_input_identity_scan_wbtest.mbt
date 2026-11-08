///|
test "original Source input identity scan retains exact bodies without becoming a completed task" {
  for presence in [false, true] {
    let input = ordered_input_fixture(presence)
    let rows = finish_admitted_input(input).unwrap()
    let read = prepare_supplied_relation_read(input.owner, 0, rows, () => true).unwrap()
    let output = capture_supplied_source_input(
      registered_relation_contracts(),
      prepared_sequence(input.owner),
      read,
      10,
      100,
    ).unwrap()
    assert_true(
      start_completed_relation_identity_scan(
        output,
        3,
        stream_value_limits(),
        row_wire_limits(),
        row_wire_limits(),
        publication_schema_limits(),
        100000,
        100000,
        incremental_metadata=true,
        retain_body=true,
      )
      is Err(InvalidTarget),
    )
    let replacement = prepare_supplied_relation_read(input.owner, 0, rows, () => {
      true
    }).unwrap()
    assert_true(
      start_completed_relation_identity_scan(
        output,
        3,
        stream_value_limits(),
        row_wire_limits(),
        row_wire_limits(),
        publication_schema_limits(),
        100000,
        100000,
        incremental_metadata=true,
        retain_body=true,
        source_input=Some(replacement),
      )
      is Err(Unavailable),
    )
    let scan = start_completed_relation_identity_scan(
      output,
      3,
      stream_value_limits(),
      row_wire_limits(),
      row_wire_limits(),
      publication_schema_limits(),
      100000,
      100000,
      incremental_metadata=true,
      retain_body=true,
      source_input=Some(read),
    ).unwrap()
    let mut done = false
    for _ in 0..<100000 {
      let next = completed_relation_identity_scan_next_construction_capacity(
        scan,
      ).unwrap()
      if advance_completed_relation_identity_scan(
          scan,
          7,
          construction_capacity=Some(next),
        ).unwrap().0 {
        done = true
        break
      }
    }
    assert_true(done)
    let receipt = finish_completed_relation_identity_scan(scan).unwrap()
    let expected = if presence {
      "{\"sort\":\"relation\",\"value\":[{\"id\":1,\"p\":7},{\"id\":2,\"p\":null},{\"id\":3}]}"
    } else {
      "{\"sort\":\"relation\",\"value\":[{\"n\":1,\"s\":\"é😀\"},{\"n\":2,\"s\":\"é😀\"},{\"n\":3,\"s\":\"é😀\"}]}"
    }
    assert_eq(
      completed_relation_identity_scan_body(scan, receipt),
      Some(expected),
    )
    assert_eq(output.target, @pipeline.Input(0))
    assert_true(output.completion.readmitted)
    assert_true(completed_source_input_matches_read(output, read))
    cancel_completed_relation_identity_scan(scan) |> ignore
    assert_true(completed_relation_identity_scan_body(scan, receipt) is None)
    assert_true(supplied_relation_read_available(read))
  }
}

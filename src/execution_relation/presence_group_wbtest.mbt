///|
fn presence_group_input(
  owner : @lower.BoundPrepared,
  empty : Bool,
  nullable_key? : Bool = false,
) -> CapturedRows {
  let input = prepare_admitted_input(owner, 0, 4, stream_value_limits()).unwrap()
  if !empty {
    for
      wire in (if nullable_key {
        [
          "{\"id\":null,\"p\":7}", "{\"id\":null,\"p\":null}", "{\"id\":null}", "{\"id\":1,\"p\":8}",
        ]
      } else {
        [
          "{\"id\":2,\"p\":7}", "{\"id\":2,\"p\":null}", "{\"id\":2}", "{\"id\":1,\"p\":8}",
        ]
      }) {
      append_admitted_input_presence(
        input,
        read_retained_relation_row(
          input.buffer.schema,
          wire,
          retained_row_test_limits(),
          stream_value_limits(),
        ).unwrap(),
      ).unwrap()
    }
  }
  finish_admitted_input(input).unwrap()
}

///|
fn presence_group_fixture(
  empty? : Bool = false,
  dynamic? : Bool = false,
  nullable_key? : Bool = false,
  input_limits? : ValueLimits = run_limits().input_values,
  workspace_limit? : Int = 10000,
) -> (
  @lower.BoundPrepared,
  @bounded.Control,
  BoundedGroupExecution,
  CapturedRows,
) raise {
  let owner = sort_input_owner(
    @pipeline.CarrierInput(
      @carrier.relation(
        @carrier.typed_rows(
          if nullable_key {
            @schema.from_presence_fields(
              [
                (
                  Unqualified("id"),
                  @contract.primitive(NumberType, nullable=true),
                  Required,
                ),
                (
                  Unqualified("p"),
                  @contract.primitive(NumberType, nullable=true),
                  Conditional,
                ),
              ],
              max_fields=2,
              max_name_bytes=3,
            ).unwrap()
          } else {
            presence_test_schema()
          },
        ),
      ),
    ),
    if dynamic {
      "[{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"m\":{\"fn\":\"max\",\"expr\":\"id\",\"filter\":\"id > 0\"}}}}]"
    } else {
      "[{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"m\":{\"fn\":\"max\",\"field\":\"id\"}}}}]"
    },
  )
  let captured = presence_group_input(owner, empty, nullable_key~)
  let read = prepare_supplied_relation_read(owner, 0, captured, () => true).unwrap()
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    if dynamic {
      [sequence_fragment_context(sequence, 0, 4L)]
    } else {
      []
    },
    ["group_0"],
    100000,
    10000,
  ).unwrap()
  let control = @bounded.control()
  let active = start_bounded_group_execution_supplied(
    control,
    generated,
    read,
    4,
    input_limits,
    run_limits().output_values,
    run_limits().input_values,
    100000,
    100,
    workspace_limit,
    10000,
  ).unwrap()
  (owner, control, active, captured)
}

///|
test "presence group aggregates guaranteed fields independently of unused omission NULL and values" {
  for dynamic in [false, true] {
    let (owner, _, active, source) = presence_group_fixture(dynamic~)
    guard drive_bounded_group(active) is BoundedGroupComplete(output, ..) else {
      fail("sparse group failed")
    }
    assert_eq(completed_row_count(output), 2)
    assert_eq(
      completed_output_row_wire(output, 0, 10000, 10000, 50).unwrap(),
      "{\"id\":1,\"m\":1}",
    )
    assert_eq(
      completed_output_row_wire(output, 1, 10000, 10000, 50).unwrap(),
      "{\"id\":2,\"m\":2}",
    )
    assert_true(
      captured_presence_cell(source, 0, 1) is Ok(Present(@admitted.Number(7))),
    )
    assert_true(
      captured_presence_cell(source, 1, 1) is Ok(Present(@admitted.Null)),
    )
    assert_true(captured_presence_cell(source, 2, 1) is Ok(Absent))
    assert_true(cleanup_bounded_group_execution(active).unwrap())
    let sequence = prepared_sequence(owner)
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      sequence,
      if dynamic {
        [sequence_fragment_context(sequence, 0, 4L)]
      } else {
        []
      },
      ["group_0"],
      100000,
      10000,
    ).unwrap()
    let completed = execute_generated_sequence(
      generated,
      [source],
      compute_test_limits(),
    ).unwrap()
    let synchronous = completed_output(completed, Step(0)).unwrap()
    for row in 0..<2 {
      assert_eq(
        completed_output_row_wire(synchronous, row, 10000, 10000, 50).unwrap(),
        completed_output_row_wire(output, row, 10000, 10000, 50).unwrap(),
      )
    }
  }
}

///|
test "presence group empty input retains dense output schema and aggregate nullability" {
  let (owner, _, active, source) = presence_group_fixture(empty=true)
  guard drive_bounded_group(active) is BoundedGroupComplete(output, ..) else {
    fail("empty group failed")
  }
  assert_eq(completed_row_count(output), 0)
  assert_eq(completed_column_name(output, 0), Some("id"))
  assert_eq(completed_column_name(output, 1), Some("m"))
  assert_eq(completed_column_name(output, 2), None)
  let schema = @lower.preparation_schema_at(
    @lower.bound_preparation(owner),
    Step(0),
  ).unwrap()
  assert_true(@schema.all_fields_required(schema))
  assert_false(@schema.field_at(schema, 0).unwrap().contract.nullable)
  assert_true(@schema.field_at(schema, 1).unwrap().contract.nullable)
  assert_true(cleanup_bounded_group_execution(active).unwrap())
  assert_eq(captured_row_count(source), 0)
}

///|
test "presence group Required nullable keys retain NULL grouping independently of omission" {
  let (owner, _, active, source) = presence_group_fixture(nullable_key=true)
  guard drive_bounded_group(active) is BoundedGroupComplete(output, ..) else {
    fail("nullable guaranteed key group failed")
  }
  // Existing GROUP order is NULLS FIRST, not omission-first or input order.
  assert_eq(completed_row_count(output), 2)
  assert_eq(
    completed_output_row_wire(output, 0, 10000, 10000, 50).unwrap(),
    "{\"id\":null,\"m\":null}",
  )
  assert_eq(
    completed_output_row_wire(output, 1, 10000, 10000, 50).unwrap(),
    "{\"id\":1,\"m\":1}",
  )
  let schema = @lower.preparation_schema_at(
    @lower.bound_preparation(owner),
    Step(0),
  ).unwrap()
  assert_true(@schema.all_fields_required(schema))
  assert_true(@schema.field_at(schema, 0).unwrap().contract.nullable)
  assert_true(
    captured_presence_cell(source, 2, 0) is Ok(Present(@admitted.Null)),
  )
  assert_true(captured_presence_cell(source, 2, 1) is Ok(Absent))
  assert_true(cleanup_bounded_group_execution(active).unwrap())
}

///|
test "presence group charges unused sparse cells and retains cancellation cleanup custody" {
  // Four row nodes plus eight declared cell/presence slots: the absent p
  // still owns one slot, just as its NULL and scalar siblings do.
  let (_, _, exact, _) = presence_group_fixture(input_limits={
    ..run_limits().input_values,
    max_nodes: 12,
  })
  assert_true(drive_bounded_group(exact) is BoundedGroupComplete(_, ..))
  assert_true(cleanup_bounded_group_execution(exact).unwrap())
  let (_, _, limited, source) = presence_group_fixture(input_limits={
    ..run_limits().input_values,
    max_nodes: 11,
  })
  assert_true(
    drive_bounded_group(limited) is BoundedGroupFailed(InputLimit, ..),
  )
  assert_true(@bounded.cleanup_pending(limited.session))
  assert_true(captured_presence_cell(source, 2, 1) is Ok(Absent))
  assert_true(cleanup_bounded_group_execution(limited).unwrap())
  assert_false(@bounded.cleanup_pending(limited.session))
  let (_, _, short, _) = presence_group_fixture(workspace_limit=10)
  assert_true(
    drive_bounded_group(short) is BoundedGroupFailed(Rows(RowLimit), ..),
  )
  assert_true(cleanup_bounded_group_execution(short).unwrap())
  let (_, control, active, source) = presence_group_fixture(dynamic=true)
  assert_true(
    advance_bounded_group_execution(active, 1).unwrap()
    is BoundedGroupContinue(..),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_group_execution(active, 1).unwrap()
    is BoundedGroupStopped(_, ..),
  )
  assert_true(@bounded.cleanup_pending(active.session))
  assert_true(
    captured_presence_cell(source, 0, 1) is Ok(Present(@admitted.Number(7))),
  )
  assert_true(cleanup_bounded_group_execution(active).unwrap())
  // The existing owner reports whether this call changed reclamation state.
  // Repeated cleanup does not release a second time.
  assert_false(cleanup_bounded_group_execution(active).unwrap())
  assert_false(@bounded.cleanup_pending(active.session))
}

///|
test "presence group exact aggregate stream survives Store reload without source access" {
  let (_, _, active, _) = presence_group_fixture()
  guard drive_bounded_group(active) is BoundedGroupComplete(output, ..) else {
    fail("group failed")
  }
  let stream = prepare_completed_output_export(
    output,
    4,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  let saved = StringBuilder()
  while next_completed_output_export(stream).unwrap() is Some(part) {
    saved.write_string(part)
  }
  let (receipt, tail) = finish_completed_output_export(stream).unwrap()
  saved.write_string(tail)
  let bytes = saved.to_string()
  assert_eq(bytes, "[{\"id\":1,\"m\":1},{\"id\":2,\"m\":2}]")
  let (cid, _, _, _) = output_stream_identity(completed_export_content(receipt))
  assert_eq(
    cid, "sha256:ac9089f4ea4eb4948fb51c0b1f2e72ca01b9b9d7b72e1ab5519371795bbb72b6",
  )
  let retained = retain_admitted_output_stream(
    completed_export_content(receipt),
    bytes,
    () => true,
  )
  let stored = bind_completed_output_export(
    receipt,
    retained_output_material(retained),
  ).unwrap()
  assert_true(completed_cell(stored, 0, 0) is None)
  let importing = prepare_completed_output_import(
    stored,
    4,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for wire in ["{\"id\":1,\"m\":1}", "{\"id\":2,\"m\":2}"] {
    append_completed_output_import_wire(
      importing,
      wire,
      retained_row_test_limits(),
    ).unwrap()
  }
  let reloaded = finish_completed_output_import(importing).unwrap()
  assert_true(completed_output_same_occurrence(output, reloaded))
  assert_eq(
    completed_output_row_wire(reloaded, 1, 10000, 10000, 50).unwrap(),
    "{\"id\":2,\"m\":2}",
  )
  assert_true(cleanup_bounded_group_execution(active).unwrap())
}

///|
test "presence group optimized global count admits and charges every sparse input cell" {
  for empty in [false, true] {
    let owner = sort_input_owner(
      @pipeline.CarrierInput(
        @carrier.relation(@carrier.typed_rows(presence_test_schema())),
      ),
      "[{\"group\":{\"by\":[],\"aggregates\":{\"all\":{\"fn\":\"count\"},\"ids\":{\"fn\":\"count\",\"field\":\"id\"}}}}]",
    )
    let source = presence_group_input(owner, empty)
    let sequence = prepared_sequence(owner)
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      sequence,
      [],
      ["group_0"],
      100000,
      10000,
    ).unwrap()
    let read = prepare_supplied_relation_read(owner, 0, source, () => true).unwrap()
    let active = start_bounded_global_count_supplied(
      @bounded.control(),
      generated,
      read,
      4,
      // Four row nodes and eight cell/presence slots, or zero for no rows.
      { ..run_limits().input_values, max_nodes: if empty { 0 } else { 12 }, },
      run_limits().output_values,
      100000,
      100,
      10000,
      10000,
    ).unwrap()
    let mut output = None
    for _ in 0..<10000 {
      match advance_bounded_global_count(active, 1).unwrap() {
        BoundedGlobalCountContinue(..) => ()
        BoundedGlobalCountComplete(value, ..) => {
          output = Some(value)
          break
        }
        _ => fail("sparse global count failed")
      }
    }
    let expected = if empty {
      "{\"all\":0,\"ids\":0}"
    } else {
      "{\"all\":4,\"ids\":4}"
    }
    assert_eq(completed_row_count(output.unwrap()), 1)
    assert_eq(
      completed_output_row_wire(output.unwrap(), 0, 10000, 10000, 50).unwrap(),
      expected,
    )
    let synchronous = execute_generated_sequence(
      generated,
      [source],
      compute_test_limits(),
    ).unwrap()
    assert_eq(
      completed_output_row_wire(
        completed_output(synchronous, Step(0)).unwrap(),
        0,
        10000,
        10000,
        50,
      ).unwrap(),
      expected,
    )
    assert_true(cleanup_bounded_global_count(active).unwrap())
    if !empty {
      assert_true(captured_presence_cell(source, 2, 1) is Ok(Absent))
      let limited = start_bounded_global_count_supplied(
        @bounded.control(),
        generated,
        read,
        4,
        { ..run_limits().input_values, max_nodes: 11, },
        run_limits().output_values,
        100000,
        100,
        10000,
        10000,
      ).unwrap()
      let mut refused = false
      for _ in 0..<10000 {
        match advance_bounded_global_count(limited, 1).unwrap() {
          BoundedGlobalCountContinue(..) => ()
          BoundedGlobalCountFailed(InputLimit, ..) => {
            refused = true
            break
          }
          _ => fail("sparse count input budget bypassed")
        }
      }
      assert_true(refused)
      assert_true(cleanup_bounded_global_count(limited).unwrap())
    }
  }
}

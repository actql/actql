///|
fn presence_test_schema() -> @schema.Schema {
  @schema.from_presence_fields(
    [
      (
        Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
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
}

///|
test "presence rows retain values NULL omission and independent canonical identities" {
  let schema = presence_test_schema()
  let limits = stream_value_limits()
  let fixtures = [
    (
      "{\"id\":1,\"p\":7}", "6efc7523b91119584facb56616152e5d19ad376d635e65d04349d64577d8f470",
    ),
    (
      "{\"id\":2,\"p\":null}", "c95a4e042c2d0ac62fd007941137d6b624306948cf1257b5f135e9c1296f93c1",
    ),
    (
      "{\"id\":3}", "a22883e93273fa52419f3f34bb7e1125f2cd14a1f32561e419adc15324916c4b",
    ),
    (
      "{\"id\":3,\"p\":null}", "cef86126ac3076dd66cc79909a6dafa6e52e7c45b1152f9ea6a300386b813aae",
    ),
  ]
  for index, (wire, hash) in fixtures {
    // Independent literal preimages hashed by Node crypto, not product output.
    let row = read_retained_relation_row(
      schema,
      wire,
      retained_row_test_limits(),
      limits,
    ).unwrap()
    let copied = copy_relation_row(row, limits).unwrap()
    assert_true(physical_equal(relation_row_schema(copied), schema))
    assert_eq(relation_row_usage(copied), relation_row_usage(row))
    assert_true(relation_row_required_value(row, 0) is Ok(@admitted.Number(_)))
    assert_true(
      relation_row_required_value(row, 1) is Err(PresenceNotGuaranteed(1)),
    )
    assert_true(relation_row_cell(row, 2) is Err(InvalidLayout))
    match index {
      0 =>
        assert_true(
          relation_row_cell(copied, 1) is Ok(Present(@admitted.Number(7))),
        )
      2 => assert_true(relation_row_cell(copied, 1) is Ok(Absent))
      _ =>
        assert_true(relation_row_cell(copied, 1) is Ok(Present(@admitted.Null)))
    }
    let writer = @encode.writer(4096, 100, 10)
    emit_relation_row(copied, writer)
    let saved = @encode.finish(writer)
    assert_eq(saved, wire)
    assert_eq(@sha.hex(@utf8.encode(saved)), hash)
    let reloaded = read_retained_relation_row(
      schema,
      saved,
      retained_row_test_limits(),
      limits,
    ).unwrap()
    let writer = @encode.writer(4096, 100, 10)
    emit_relation_row(reloaded, writer)
    assert_eq(@encode.finish(writer), wire)
    let usage = relation_row_usage(row)
    assert_true(
      copy_relation_row(row, { ..limits, max_nodes: usage.nodes - 1, })
      is Err(Limit),
    )
    assert_true(
      copy_relation_row(row, { ..limits, max_work: usage.work - 1, })
      is Err(Limit),
    )
  }
}

///|
test "presence row admission never changes ordinary object or value-type rules" {
  let schema = presence_test_schema()
  for
    wire in [
      "{\"p\":7}", "{\"id\":null}", "{\"id\":1,\"p\":\"7\"}", "{\"id\":1,\"extra\":1}",
    ] {
    assert_true(
      read_retained_relation_row(
        schema,
        wire,
        retained_row_test_limits(),
        stream_value_limits(),
      )
      is Err(_),
    )
  }
  let conditional_nonnullable = @schema.from_presence_fields(
    [
      (
        Unqualified("p"),
        @contract.primitive(NumberType, nullable=false),
        Conditional,
      ),
    ],
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  assert_true(
    read_retained_relation_row(
      conditional_nonnullable,
      "{}",
      retained_row_test_limits(),
      stream_value_limits(),
    )
    is Ok(_),
  )
  assert_true(
    read_retained_relation_row(
      conditional_nonnullable,
      "{\"p\":null}",
      retained_row_test_limits(),
      stream_value_limits(),
    )
    is Err(Value(_, _)),
  )
  // The dense decoder cannot reinterpret omission or bypass presence checking.
  assert_true(
    decode_retained_row(
      schema,
      "{\"id\":1,\"p\":7}",
      retained_row_test_limits(),
    )
    is Err(InvalidShape),
  )
  let nullable = @contract.primitive(NumberType, nullable=true)
  let object = @contract.object_contract(
    [("p", nullable)],
    nullable=false,
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  assert_true(
    @admitted.admit(object, input_cursor("{}"), {
      max_nodes: 100,
      max_text_bytes: 100,
      max_depth: 10,
    })
    is Err(_),
  )
  let supplied = [
    Some(
      @admitted.admit(
        @contract.primitive(NumberType, nullable=false),
        input_cursor("1"),
        { max_nodes: 10, max_text_bytes: 10, max_depth: 2, },
      ).unwrap(),
    ),
    None,
  ]
  assert_true(
    admit_relation_row(schema, supplied, stream_value_limits())
    is Err(ForeignContract(0)),
  )
  assert_true(
    admit_relation_row(schema, [None, None], stream_value_limits())
    is Err(RequiredFieldMissing(0)),
  )
}

///|
test "presence schema identity binds guarantees separately from nullability" {
  let conditional = presence_test_schema()
  let required = @schema.from_fields(
    @schema.fields(conditional).map(f => (f.name, f.contract)),
    max_fields=2,
    max_name_bytes=3,
  ).unwrap()
  let sparse = identify_relation_schema(conditional, schema_identity_limits()).unwrap()
  let dense = identify_relation_schema(required, schema_identity_limits()).unwrap()
  assert_eq(
    relation_schema_wire(sparse),
    "{\"id\":{\"nullable\":false,\"type\":\"number\"},\"p\":{\"contract\":{\"nullable\":true,\"type\":\"number\"},\"presence\":\"conditional\"}}",
  )
  assert_eq(
    relation_schema_cid(sparse),
    "sha256:10ce8369a6cadfefd6e712b9af9320c69915df75a0a9654c7d69788ef23a437c",
  )
  assert_eq(
    relation_schema_cid(dense),
    "sha256:f514059d2843e24fdebe1c68934d9912b90f0d24283f6f23d9e6cb34eb307de5",
  )
}

///|
fn presence_input_owner() -> @lower.BoundPrepared {
  let pipeline = @pipeline.check(
    input_cursor("[{\"select\":[\"id\"]}]"),
    [("input_0", presence_test_schema())],
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
test "presence input reaches the existing retained Store and guaranteed projection" {
  let owner = presence_input_owner()
  let input = prepare_admitted_input(owner, 0, 3, stream_value_limits()).unwrap()
  let schema = input.buffer.schema
  for wire in ["{\"id\":1,\"p\":7}", "{\"id\":2,\"p\":null}", "{\"id\":3}"] {
    let row = read_retained_relation_row(
      schema,
      wire,
      retained_row_test_limits(),
      stream_value_limits(),
    ).unwrap()
    append_admitted_input_presence(input, row).unwrap()
  }
  let captured = finish_admitted_input(input).unwrap()
  assert_eq(captured_row_count(captured), 3)
  assert_true(captured_cell(captured, 0, 1) is None)
  assert_true(
    captured_presence_cell(captured, 0, 1) is Ok(Present(@admitted.Number(7))),
  )
  assert_true(
    captured_presence_cell(captured, 1, 1) is Ok(Present(@admitted.Null)),
  )
  assert_true(captured_presence_cell(captured, 2, 1) is Ok(Absent))
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["select_0"],
    10000,
    1000,
  ).unwrap()
  for record_values in [false, true] {
    let (guarded, _) = execute_fixed_input_guarded(
      generated,
      captured,
      Step(0),
      { rows: run_limits(), max_work: 10000, max_frames: 100, },
      max_output_rows=3,
      max_value_bytes=100,
      record_values~,
      { max_work: 10000, max_bytes: 10000, max_nodes: 1000, max_depth: 100, },
    ).unwrap()
    assert_eq(
      completed_row_count(completed_output(guarded, Step(0)).unwrap()),
      3,
    )
  }
  let completion = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [captured],
    ["input_0", "select_0"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let source = completed_output(completion, Input(0)).unwrap()
  assert_true(source.table is Some(PresenceTable(_)))
  assert_true(completed_cell(source, 0, 1) is None)
  assert_true(completed_presence_cell(source, 2, 1) is Ok(Absent))
  let selected = completed_output(completion, Step(0)).unwrap()
  for row in 0..<3 {
    assert_true(completed_cell(selected, row, 0) is Some(Number(_)))
  }
  let copied = copy_completed_output_independent(source, 3, 2).unwrap()
  assert_true(
    completed_presence_cell(copied, 1, 1) is Ok(Present(@admitted.Null)),
  )
  assert_true(completed_presence_cell(copied, 2, 1) is Ok(Absent))
  let copying = start_bounded_independent_row_copy(
    @bounded.control(),
    source,
    3,
    2,
    20,
  ).unwrap()
  let mut bounded = None
  for _ in 0..<100 {
    match advance_bounded_independent_row_copy(copying, 1).unwrap() {
      RowCopyContinue(..) => ()
      RowCopyComplete(output, ..) => {
        bounded = Some(output)
        break
      }
      _ => fail("presence copy failed")
    }
  }
  let bounded = bounded.unwrap()
  assert_true(
    completed_presence_cell(bounded, 1, 1) is Ok(Present(@admitted.Null)),
  )
  assert_true(completed_presence_cell(bounded, 2, 1) is Ok(Absent))
  assert_eq(
    row_wire_cid(identify_completed_rows(source, row_wire_limits()).unwrap()),
    row_wire_cid(identify_completed_rows(bounded, row_wire_limits()).unwrap()),
  )
  assert_true(cleanup_bounded_independent_row_copy(copying).unwrap())
  let cancelled_copy = start_bounded_independent_row_copy(
    @bounded.control(),
    source,
    3,
    2,
    20,
  ).unwrap()
  assert_true(
    advance_bounded_independent_row_copy(cancelled_copy, 4).unwrap()
    is RowCopyContinue(..),
  )
  assert_true(request_bounded_independent_row_copy_cancel(cancelled_copy))
  assert_true(
    advance_bounded_independent_row_copy(cancelled_copy, 1).unwrap()
    is RowCopyStopped(_, ..),
  )
  assert_true(cleanup_bounded_independent_row_copy(cancelled_copy).unwrap())
  assert_false(bounded_independent_row_copy_cleanup_pending(cancelled_copy))
  assert_eq(
    row_wire_cid(identify_completed_rows(source, row_wire_limits()).unwrap()),
    row_wire_cid(identify_completed_rows(copied, row_wire_limits()).unwrap()),
  )
  guard completion.store is PhysicalStore(store) else {
    fail("not the common Store")
  }
  assert_true(store.workspace.live > store.wiring.ids.length())
  clear_table_store(store)
  assert_eq(store.workspace.live, store.wiring.ids.length())
  clear_table_store(store)
  assert_eq(store.workspace.live, store.wiring.ids.length())
  assert_true(completed_output(completion, Input(0)) is None)
  assert_true(completed_output(completion, Step(0)) is None)
}

///|
test "presence input cancellation and cumulative limits release the same buffer" {
  let owner = presence_input_owner()
  let schema = @lower.preparation_input_schema(
    @lower.bound_preparation(owner),
    0,
  ).unwrap()
  let row = read_retained_relation_row(
    schema,
    "{\"id\":3}",
    retained_row_test_limits(),
    stream_value_limits(),
  ).unwrap()
  let usage = relation_row_usage(row)
  let limits = {
    ..stream_value_limits(),
    max_nodes: usage.nodes,
    max_text_bytes: usage.text_bytes,
    max_work: usage.work,
  }
  let input = prepare_admitted_input(owner, 0, 2, limits).unwrap()
  append_admitted_input_presence(input, row).unwrap()
  assert_true(append_admitted_input_presence(input, row) is Err(CaptureLimit))
  assert_true(input.buffer.presence_rows.is_empty())
  assert_true(finish_admitted_input(input) is Err(ClosedCapture))
  let cancelled = prepare_admitted_input(owner, 0, 1, stream_value_limits()).unwrap()
  append_admitted_input_presence(cancelled, row).unwrap()
  assert_true(cancel_admitted_input(cancelled))
  assert_false(cancel_admitted_input(cancelled))
  assert_true(cancelled.buffer.presence_rows.is_empty())
  assert_true(finish_admitted_input(cancelled) is Err(ClosedCapture))
}

///|
fn presence_output_owner(
  schema? : @schema.Schema = presence_test_schema(),
) -> @lower.BoundPrepared {
  // The existing Carrier projection supplies a genuine checked conditional
  // Step port. This fixture tests common retention, not a new Graph executor.
  let events = @carrier.events(
    @carrier.typed_rows(schema),
    id=Unqualified("id"),
    time=Unqualified("id"),
  ).unwrap()
  let pipeline = @pipeline.check_carriers(
    input_cursor("[{\"events\":true,\"as\":\"rows\"}]"),
    [("events", events)],
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
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 10000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "presence output stream retains exact bytes and reloads through the existing completion owner" {
  let owner = presence_output_owner()
  let stream = prepare_admitted_output_stream(
    owner,
    Step(0),
    3,
    stream_value_limits(),
    row_wire_limits(),
    4096,
  ).unwrap()
  let schema = stream.buffer.schema
  let wires = ["{\"id\":1,\"p\":7}", "{\"id\":2,\"p\":null}", "{\"id\":3}"]
  let chunks = []
  for wire in wires {
    let row = read_retained_relation_row(
      schema,
      wire,
      retained_row_test_limits(),
      stream_value_limits(),
    ).unwrap()
    chunks.push(append_admitted_output_stream_presence(stream, row).unwrap())
  }
  let (receipt, tail) = finish_admitted_output_stream(stream).unwrap()
  chunks.push(tail)
  let saved = chunks.join("")
  assert_eq(saved, "[" + wires.join(",") + "]")
  let live = Ref(true)
  let retained = retain_admitted_output_stream(receipt, saved, fn() { live.val })
  let material = retained_output_material(retained)
  let id = @lower.node_id(
    @lower.node_at(@lower.bound_preparation(owner), 0).unwrap(),
  )
  let preparation = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [id],
    10000,
    1000,
  ).unwrap()
  // The trusted test verifier binds one exact receipt/storage pair. Raw rows
  // cannot produce a completed output through the import path below.
  let port = prepare_trusted_retained_output_port(
    preparation,
    Step(0),
    1000,
    10000,
    fn(proof : RetainedOutputMaterial) {
      if physical_equal(proof, material) && live.val {
        Some(material)
      } else {
        None
      }
    },
  ).unwrap()
  let source = complete_trusted_retained_output(port, material).unwrap()
  let conversion = prepare_completed_output_import(
    source,
    3,
    stream_value_limits(),
    row_wire_limits(),
    4096,
  ).unwrap()
  for wire in wires {
    append_completed_output_import_wire(
      conversion,
      wire,
      retained_row_test_limits(),
    ).unwrap()
  }
  let reloaded = finish_completed_output_import(conversion).unwrap()
  for index, wire in wires {
    assert_eq(
      completed_output_row_wire(reloaded, index, 4096, 100, 10).unwrap(),
      wire,
    )
  }
  let exporting = prepare_completed_output_export(
    reloaded,
    3,
    stream_value_limits(),
    row_wire_limits(),
    4096,
  ).unwrap()
  let exported = StringBuilder()
  while next_completed_output_export(exporting).unwrap() is Some(part) {
    exported.write_string(part)
  }
  let (_, export_tail) = finish_completed_output_export(exporting).unwrap()
  exported.write_string(export_tail)
  assert_eq(exported.to_string(), saved)
  assert_true(completed_output_same_occurrence(source, reloaded))
  assert_true(completed_cell(reloaded, 0, 1) is None)
  assert_true(
    completed_presence_cell(reloaded, 0, 1) is Ok(Present(@admitted.Number(7))),
  )
  assert_true(
    completed_presence_cell(reloaded, 1, 1) is Ok(Present(@admitted.Null)),
  )
  assert_true(completed_presence_cell(reloaded, 2, 1) is Ok(Absent))
  assert_eq(
    row_wire_cid(identify_completed_rows(source, row_wire_limits()).unwrap()),
    row_wire_cid(identify_completed_rows(reloaded, row_wire_limits()).unwrap()),
  )
  let wrong = prepare_completed_output_import(
    source,
    3,
    stream_value_limits(),
    row_wire_limits(),
    4096,
  ).unwrap()
  for wire in [wires[0], wires[1], "{\"id\":3,\"p\":null}"] {
    append_completed_output_import_wire(wrong, wire, retained_row_test_limits()).unwrap()
  }
  assert_true(finish_completed_output_import(wrong) is Err(IdentityMismatch))
  let interrupted = prepare_completed_output_import(
    source,
    3,
    stream_value_limits(),
    row_wire_limits(),
    4096,
  ).unwrap()
  append_completed_output_import_wire(
    interrupted,
    wires[0],
    retained_row_test_limits(),
  ).unwrap()
  live.val = false
  assert_true(
    append_completed_output_import_wire(
      interrupted,
      wires[1],
      retained_row_test_limits(),
    )
    is Err(Unavailable),
  )
  assert_true(interrupted.admitted.buffer.presence_rows.is_empty())
  assert_true(completed_presence_cell(source, 2, 1) is Err(Unavailable))
  // The verified independent representation survives release of old payload.
  assert_true(completed_presence_cell(reloaded, 2, 1) is Ok(Absent))
}

///|
fn export_fixture(owner : @lower.BoundPrepared) -> CompletedOutput raise {
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["select_1"],
    100000,
    10000,
  ).unwrap()
  completed_output(
    execute_generated_sequence(generated, [], compute_test_limits()).unwrap(),
    Step(1),
  ).unwrap()
}

///|
fn publication_schema_limits() -> RelationSchemaIdentityLimits {
  { max_fields: 100, max_bytes: 10000, max_nodes: 1000, max_depth: 20, }
}

///|
fn result_export_owner() -> @lower.BoundPrepared {
  bound_pipeline(
    "[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":false},\"s\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"n\":1,\"s\":\"é\"},{\"n\":2,\"s\":\"😀\"}]},\"as\":\"v\"},{\"select\":[\"s\",\"n\"],\"as\":\"selected\"}]",
  )
}

///|
fn result_export_occurrence(
  owner : @lower.BoundPrepared,
  name : String,
  body : String,
) -> ManagedResultOccurrence {
  let checked = @results.check(
    @lower.pipeline(@lower.bound_preparation(owner)),
    input_cursor(body),
    {
      max_results: 10,
      max_work: 100000,
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 100,
    },
  ).unwrap()
  let orders = @results.resolve_all_orders(checked, {
    max_steps: 10,
    max_results: 10,
    max_work: 100000,
    max_text_bytes: 100000,
  }).unwrap()
  let ports = @results.prepare_ports(orders, {
    max_results: 10,
    max_work: 200000,
    max_nodes: 20000,
    max_text_bytes: 200000,
    max_depth: 100,
  }).unwrap()
  bind_managed_result_occurrence(
    owner,
    name,
    @results.lookup_port(ports, name).unwrap(),
  ).unwrap()
}

///|
fn result_view_limits() -> CompletedResultViewLimits {
  {
    max_fields: 10,
    max_mapping_work: 100,
    max_order_work: 1000,
    max_workspace_entries: 20,
  }
}

///|
fn export_all(
  source : CompletedOutput,
) -> (CompletedOutputExportReceipt, String) raise {
  let stream = prepare_completed_output_export(
    source,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  let text = StringBuilder()
  while next_completed_output_export(stream).unwrap() is Some(part) {
    text.write_string(part)
  }
  let (receipt, tail) = finish_completed_output_export(stream).unwrap()
  text.write_string(tail)
  assert_true(stream.source is None)
  (receipt, text.to_string())
}

///|
fn export_relation_all(
  source : CompletedOutput,
) -> (CompletedRelationExportReceipt, String) {
  let stream = prepare_completed_relation_export(
    source,
    2,
    stream_value_limits(),
    row_wire_limits(),
    { ..row_wire_limits(), max_bytes: 1000, max_nodes: 100, max_depth: 20, },
    publication_schema_limits(),
    64,
  ).unwrap()
  let text = StringBuilder()
  while next_completed_output_export(stream).unwrap() is Some(part) {
    text.write_string(part)
  }
  let (receipt, tail) = finish_completed_relation_export(stream).unwrap()
  text.write_string(tail)
  (receipt, text.to_string())
}

///|
test "publication export separates ordered rows from logical Relation identity" {
  let source = export_fixture(capture_fixture())
  let (receipt, text) = export_relation_all(source)
  assert_eq(text, "[{\"n\":1,\"s\":\"é\"},{\"n\":2,\"s\":\"😀\"}]")
  let content = completed_relation_export_content(receipt)
  let relation = completed_relation_export_identity(receipt)
  assert_eq(
    content.cid,
    "sha256:1f3a78f3ede9a4385bbcbf098a3f0fdb9b16dc3e0e8d78f05255682d9c25f3e0",
  )
  // Independent SHA-256 of the canonical preimage
  // {"sort":"relation","value":<the ordered rows above>}.
  assert_eq(
    logical_relation_cid(relation),
    "sha256:5f089a447a51c56f479c2c6258d8c3b687ec1368bf8e0bc28eda2d53efa0e5b8",
  )
  assert_eq(logical_relation_usage(relation), (65, 9, 2))
  assert_true(logical_relation_cid(relation) != content.cid)
  let schema = completed_relation_export_schema_identity(receipt)
  assert_eq(
    relation_schema_cid(schema),
    "sha256:91f065fb2cd5d7dce27dbd0e5d1e17644e21e521ec989fa9be93b52787b305b2",
  )
  assert_eq(relation_schema_usage(schema), (79, 7, 2))
  assert_true(relation_schema_cid(schema) != logical_relation_cid(relation))
  let measurement = completed_relation_export_measurement(receipt)
  assert_eq(measurement.row_count, 2)
  assert_eq(measurement.admission_nodes, 6)
  assert_eq(measurement.admission_text_bytes, 10)
  assert_eq(measurement.admission_work, 16)
  assert_eq(measurement.column_rows, [2, 2])
  assert_eq(measurement.column_bytes, [2, 10])
  assert_eq(measurement.column_nodes, [2, 2])
  assert_eq(measurement.column_max_value_bytes, [1, 6])
  assert_eq(measurement.column_null_rows, [0, 0])
  assert_eq(measurement.column_admitted_depths, [0, 0])
  measurement.column_rows[0] = 0
  assert_eq(completed_relation_export_measurement(receipt).column_rows, [2, 2])
  cancel_completed_relation_export_receipt(receipt)
}

///|
test "finished publication export replays the exact immutable view in bounded batches" {
  let source = export_fixture(capture_fixture())
  let stream = prepare_completed_relation_export(
    source,
    2,
    stream_value_limits(),
    row_wire_limits(),
    { ..row_wire_limits(), max_bytes: 1000, max_nodes: 100, max_depth: 20, },
    publication_schema_limits(),
    64,
  ).unwrap()
  let first = StringBuilder()
  while next_completed_output_export(stream).unwrap() is Some(part) {
    first.write_string(part)
  }
  let (receipt, tail) = finish_completed_relation_export(stream).unwrap()
  first.write_string(tail)
  let replay = replay_completed_relation_export(
    stream,
    receipt,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  let second = StringBuilder()
  while next_completed_output_export(replay).unwrap() is Some(part) {
    second.write_string(part)
  }
  let (replayed, replay_tail) = finish_completed_output_export(replay).unwrap()
  second.write_string(replay_tail)
  assert_eq(first.to_string(), second.to_string())
  assert_eq(
    output_stream_identity(completed_relation_export_content(receipt)),
    output_stream_identity(completed_export_content(replayed)),
  )
  cancel_completed_export_receipt(replayed)
  cancel_completed_relation_export_receipt(receipt)
}

///|
test "publication replay rejects a foreign finished receipt" {
  let source = export_fixture(capture_fixture())
  let prepare = fn() {
    prepare_completed_relation_export(
      source,
      2,
      stream_value_limits(),
      row_wire_limits(),
      { ..row_wire_limits(), max_bytes: 1000, max_nodes: 100, max_depth: 20, },
      publication_schema_limits(),
      64,
    ).unwrap()
  }
  let first = prepare()
  let second = prepare()
  for stream in [first, second] {
    while next_completed_output_export(stream).unwrap() is Some(_) {

    }
  }
  let (first_receipt, _) = finish_completed_relation_export(first).unwrap()
  let (second_receipt, _) = finish_completed_relation_export(second).unwrap()
  assert_true(
    replay_completed_relation_export(
      first,
      second_receipt,
      stream_value_limits(),
      row_wire_limits(),
      64,
    )
    is Err(NotFinished),
  )
  cancel_completed_relation_export_receipt(first_receipt)
  cancel_completed_relation_export_receipt(second_receipt)
}

///|
test "publication export independently bounds the logical Relation preimage" {
  let source = export_fixture(capture_fixture())
  let stream = prepare_completed_relation_export(
    source,
    2,
    stream_value_limits(),
    row_wire_limits(),
    { ..row_wire_limits(), max_bytes: 64, max_nodes: 100, max_depth: 20, },
    publication_schema_limits(),
    64,
  ).unwrap()
  assert_true(next_completed_output_export(stream) is Ok(Some(_)))
  assert_true(next_completed_output_export(stream) is Ok(Some(_)))
  assert_true(next_completed_output_export(stream) is Ok(None))
  assert_true(
    finish_completed_relation_export(stream) is Err(Wire(Encoding(_))),
  )
  assert_true(completed_output_available(source))
}

///|
test "Named Result export applies its exact projection and total order as views" {
  let owner = result_export_owner()
  let source = export_fixture(owner)
  let occurrence = result_export_occurrence(
    owner, "answer", "{\"answer\":{\"from\":\"selected\",\"fields\":[\"s\"],\"order_by\":[{\"n\":\"desc\"}]}}",
  )
  let stream = prepare_completed_result_relation_export(
    source,
    occurrence,
    result_view_limits(),
    2,
    stream_value_limits(),
    row_wire_limits(),
    { ..row_wire_limits(), max_bytes: 1000, max_nodes: 100, max_depth: 20, },
    publication_schema_limits(),
    64,
  ).unwrap()
  let text = StringBuilder()
  while next_completed_output_export(stream).unwrap() is Some(part) {
    text.write_string(part)
  }
  let (receipt, tail) = finish_completed_relation_export(stream).unwrap()
  text.write_string(tail)
  assert_eq(text.to_string(), "[{\"s\":\"😀\"},{\"s\":\"é\"}]")
  let content = completed_relation_export_content(receipt)
  assert_eq(
    content.cid,
    "sha256:b02d1ca0bcef117894d3a35792bce4057604d152c60c7719a222833466811088",
  )
  assert_eq(
    logical_relation_cid(completed_relation_export_identity(receipt)),
    "sha256:f690ca53202a4e4fd0736d14fb759522c904e416982f72d2dbbdbb7a63332fbb",
  )
  assert_eq(
    relation_schema_cid(completed_relation_export_schema_identity(receipt)),
    "sha256:572f534f7825ac4eb8718cc624861dc01efecd8307333cf7639ec5ed312df476",
  )
  assert_eq(@schema.field_count(content.schema), 1)
  assert_eq(
    @schema.reference_name(@schema.field_at(content.schema, 0).unwrap().name),
    "s",
  )
  assert_true(completed_output_available(source))
  cancel_completed_relation_export_receipt(receipt)
}

///|
test "Named Result export rejects foreign occurrence and exact view limits" {
  let owner = result_export_owner()
  let source = export_fixture(owner)
  let occurrence = result_export_occurrence(
    owner, "answer", "{\"answer\":{\"from\":\"selected\",\"fields\":[\"s\"],\"order_by\":[{\"n\":\"desc\"}]}}",
  )
  let foreign_owner = result_export_owner()
  let foreign = result_export_occurrence(
    foreign_owner, "answer", "{\"answer\":{\"from\":\"selected\",\"fields\":[\"s\"],\"order_by\":[{\"n\":\"desc\"}]}}",
  )
  let prepare = fn(
    selected : ManagedResultOccurrence,
    view : CompletedResultViewLimits,
  ) {
    prepare_completed_result_relation_export(
      source,
      selected,
      view,
      2,
      stream_value_limits(),
      row_wire_limits(),
      row_wire_limits(),
      publication_schema_limits(),
      64,
    )
  }
  assert_true(
    prepare(foreign, result_view_limits()) is Err(ResultView(ForeignOccurrence)),
  )
  for
    view in [
      { ..result_view_limits(), max_fields: 0, },
      { ..result_view_limits(), max_mapping_work: 0, },
      { ..result_view_limits(), max_order_work: 0, },
      { ..result_view_limits(), max_workspace_entries: 1, },
    ] {
    assert_true(prepare(occurrence, view) is Err(ResultView(Limit)))
  }
  assert_true(completed_output_available(source))
}

///|
test "Local completion exports bounded canonical batches into the same logical result" {
  let owner = capture_fixture()
  let source = export_fixture(owner)
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  let read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, owner, source).unwrap(),
    1000,
    10000,
  ).unwrap()
  let (receipt, text) = export_all(source)
  assert_eq(text, "[{\"n\":1,\"s\":\"é\"},{\"n\":2,\"s\":\"😀\"}]")
  let content = completed_export_content(receipt)
  // Independent SHA-256 of the literal canonical UTF-8 text above.
  assert_eq(
    content.cid,
    "sha256:1f3a78f3ede9a4385bbcbf098a3f0fdb9b16dc3e0e8d78f05255682d9c25f3e0",
  )
  assert_eq(
    content.cid,
    row_wire_cid(identify_completed_rows(source, row_wire_limits()).unwrap()),
  )
  assert_eq(content.usage, { nodes: 6, text_bytes: 10, work: 16, })
  let live = Ref(true)
  let handle = retain_admitted_output_stream(content, text, fn() { live.val })
  let result = bind_completed_output_export(
    receipt,
    retained_output_material(handle),
  ).unwrap()
  assert_true(receipt.source is None)
  assert_false(completed_has_cell_access(result))
  assert_true(
    physical_equal(
      source.completion.result_identity,
      result.completion.result_identity,
    ),
  )
  assert_true(result.completion._producer_inputs.is_empty())
  let rebound = rebind_producer_representation(read, result).unwrap()
  assert_eq(retained_producer_payload(handle, rebound), Some(text))
  assert_true(physical_equal(rebound.bound.identity, read.bound.identity))
  assert_true(
    bind_completed_output_export(receipt, retained_output_material(handle))
    is Err(Closed),
  )
  let conversion = prepare_completed_output_import(
    result,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for row in 0..<2 {
    append_completed_output_import(conversion, output_fixture_row(owner, row)).unwrap()
  }
  let memory = finish_completed_output_import(conversion).unwrap()
  live.val = false
  assert_false(producer_read_available(rebound))
  assert_true(producer_read_available(read))
  assert_true(completed_output_available(source))
  let imported_read = rebind_producer_representation(rebound, memory).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["select_0"],
    10000,
    1000,
  ).unwrap()
  let downstream = completed_output(
    execute_fixed_producer_input(
      generated,
      imported_read,
      compute_test_limits(),
    ).unwrap(),
    Step(0),
  ).unwrap()
  assert_true(completed_output_matches_inputs(downstream, [read]))
  assert_true(completed_cell(downstream, 0, 0) is Some(Number(1)))
  assert_true(completed_cell(downstream, 1, 0) is Some(Number(2)))
}

///|
test "export handles empty and nullable numeric column storage without materializing rows" {
  for rows in ["[]", "[{\"a\":null,\"b\":7},{\"a\":0,\"b\":8}]"] {
    let owner = bound_pipeline(
      "[{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":true},\"b\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
      rows +
      "},\"as\":\"seed\"},{\"derive\":[{\"a\":\"a + 1\"}]}]",
    )
    let sequence = prepared_sequence(owner)
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      sequence,
      [ordered_sequence_fragment_context(sequence, 1000L)],
      ["derive_1"],
      100000,
      10000,
    ).unwrap()
    let output = completed_output(test_typed_completion(generated, 7), Step(1)).unwrap()
    assert_true(output.table is Some(NumberTable(_)))
    let (receipt, text) = export_all(output)
    assert_eq(
      text,
      if rows == "[]" {
        "[]"
      } else {
        "[{\"a\":null,\"b\":7},{\"a\":1,\"b\":8}]"
      },
    )
    assert_eq(
      receipt.content.cid,
      row_wire_cid(identify_completed_rows(output, row_wire_limits()).unwrap()),
    )
    let material = retain_admitted_output_stream(receipt.content, (), fn() {
      true
    })
    let copy = bind_completed_output_export(receipt, material.material).unwrap()
    assert_false(completed_has_cell_access(copy))
    assert_eq(completed_row_count(copy), if rows == "[]" { 0 } else { 2 })
  }
}

///|
test "export callbacks cannot finish twice or publish after cancelling the receipt" {
  let source = export_fixture(capture_fixture())
  let (receipt, _) = export_all(source)
  let called = Ref(false)
  let material = retain_admitted_output_stream(receipt.content, (), fn() {
    called.val = true
    cancel_completed_export_receipt(receipt)
    true
  })
  assert_true(
    bind_completed_output_export(receipt, material.material) is Err(Closed),
  )
  assert_true(called.val)
  assert_true(receipt.source is None)
  let stream_ref : Ref[CompletedOutputExport?] = Ref(None)
  let restricted = restrict_completed_output(source, fn() {
    if stream_ref.val is Some(stream) {
      cancel_completed_output_export(stream)
    }
    true
  })
  let stream = prepare_completed_output_export(
    restricted,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  stream_ref.val = Some(stream)
  assert_true(next_completed_output_export(stream) is Err(Closed))
  assert_true(finish_completed_output_export(stream) is Err(Closed))
}

///|
test "export rejects equal content from a different receipt or completion" {
  let owner = capture_fixture()
  let source = export_fixture(owner)
  let (first, _) = export_all(source)
  let (second, _) = export_all(source)
  let other = retain_admitted_output_stream(second.content, (), fn() { true })
  assert_eq(first.content.cid, second.content.cid)
  assert_true(
    bind_completed_output_export(first, other.material) is Err(ForeignMaterial),
  )
  let own = retain_admitted_output_stream(first.content, (), fn() { true })
  let copy = bind_completed_output_export(first, own.material).unwrap()
  let unrelated = export_fixture(owner)
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  let unrelated_read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, owner, unrelated).unwrap(),
    1000,
    10000,
  ).unwrap()
  assert_true(rebind_producer_representation(unrelated_read, copy) is Err(_))
  cancel_completed_export_receipt(second)
  assert_true(
    bind_completed_output_export(second, other.material) is Err(Closed),
  )
}

///|
test "export observes cancellation incomplete streams and original logical revocation" {
  for phase in 0..<4 {
    let source = export_fixture(capture_fixture())
    let permission = Ref(true)
    let restricted = restrict_completed_output(source, fn() { permission.val })
    let stream = prepare_completed_output_export(
      restricted,
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    assert_true(finish_completed_output_export(stream) is Err(NotFinished))
    next_completed_output_export(stream).unwrap() |> ignore
    if phase == 0 {
      cancel_completed_output_export(stream)
      assert_true(next_completed_output_export(stream) is Err(Closed))
      assert_true(finish_completed_output_export(stream) is Err(Closed))
    } else if phase == 1 {
      permission.val = false
      assert_true(next_completed_output_export(stream) is Err(Unavailable))
      assert_true(stream.source is None)
    } else {
      next_completed_output_export(stream).unwrap() |> ignore
      let (receipt, _) = finish_completed_output_export(stream).unwrap()
      let handle = retain_admitted_output_stream(receipt.content, (), fn() {
        true
      })
      if phase == 3 {
        permission.val = false
        assert_true(
          bind_completed_output_export(receipt, handle.material)
          is Err(Unavailable),
        )
        assert_true(receipt.source is None)
      } else {
        let copy = bind_completed_output_export(receipt, handle.material).unwrap()
        permission.val = false
        assert_false(completed_output_available(copy))
      }
    }
    assert_true(completed_output_available(source))
  }
}

///|
test "export enforces cumulative value wire and physical frame limits before sealing" {
  let source = export_fixture(capture_fixture())
  for mode in 0..<3 {
    let stream = prepare_completed_output_export(
      source,
      2,
      if mode == 0 {
        { ..stream_value_limits(), max_nodes: 5, }
      } else {
        stream_value_limits()
      },
      if mode == 1 {
        { ..row_wire_limits(), max_bytes: 20, }
      } else {
        row_wire_limits()
      },
      if mode == 2 {
        1
      } else {
        64
      },
    ).unwrap()
    let mut failed = false
    for _ in 0..<2 {
      if next_completed_output_export(stream) is Err(_) {
        failed = true
        break
      }
    }
    assert_true(failed)
    assert_true(finish_completed_output_export(stream) is Err(Closed))
    assert_true(stream.source is None)
    assert_true(completed_output_available(source))
  }
}

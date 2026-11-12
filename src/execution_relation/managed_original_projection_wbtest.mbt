///|
test "managed full completed projection preserves original output through publication bridge" {
  let owner = row_owner("")
  let raw = completed_output(
    evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [],
      ["values_0"],
      run_limits(),
      { remaining: 10000, max_frames: 100, },
    ).unwrap(),
    Step(0),
  ).unwrap()
  let original_live = Ref(true)
  let original = restrict_completed_output(raw, () => original_live.val)
  let values = prepare_managed_output_values(
    owner,
    Step(0),
    2,
    stream_value_limits(),
    4096,
    managed_test_measure_limits(),
  ).unwrap()
  let live = Ref(true)
  let retention = prepare_managed_output_retention_port(values, (
    receipt : ManagedOutputValueReceipt,
  ) => Some((receipt, 7, 128L, () => live.val))).unwrap()
  for row in 0..<2 {
    match append_completed_projection_managed_values(values, original, row) {
      Ok(_) => ()
      Err(Admission(InvalidCheckedRow)) =>
        append_completed_projection_managed_wire(
          values,
          original,
          row,
          {
            max_columns: 2,
            max_order_work: 100,
            max_bytes: 4096,
            max_nodes: 100,
            max_depth: 10,
          },
          retained_row_test_limits(),
        ).unwrap()
      Err(_) => abort("the original completed projection must copy")
    }
  }
  let material = retain_managed_output(
    retention,
    finish_managed_output_values(values).unwrap(),
  ).unwrap()
  let prepared = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(owner),
    ["values_0"],
    10000,
    1000,
  ).unwrap()
  let port = prepare_managed_completion_port(
    selected_managed_execution_profile(),
    prepared,
    Step(0),
    1000,
    10000,
    (_ : Unit) => Some(material),
  ).unwrap()
  let completed = complete_managed_output(port, ()).unwrap()
  let geometry = managed_publication_bridge_import_geometry(
    completed, material, 1000, 10000,
  ).unwrap()
  assert_eq(geometry.max_rows, 2)
  assert_true(geometry.values.max_nodes < stream_value_limits().max_nodes)
  assert_true(geometry.row.max_bytes < 10000)
  assert_true(
    managed_publication_bridge_import_geometry(completed, material, 1, 10000)
    is None,
  )
  let bridge = prepare_managed_publication_bridge(
    completed,
    material,
    2,
    stream_value_limits(),
    1000,
    10000,
  ).unwrap()
  for wire in ["{\"a\":1,\"b\":0}", "{\"a\":0,\"b\":1}"] {
    append_managed_publication_bridge_wire(
      bridge,
      wire,
      retained_row_test_limits(),
    ).unwrap()
  }
  let converted = finish_managed_publication_bridge(bridge).unwrap()
  assert_eq(completed_row_count(converted), 2)
  assert_false(converted.completion.readmitted)
  assert_true(completed_output_same_occurrence(original, converted))
  original_live.val = false
  assert_false(completed_output_same_occurrence(original, converted))
  assert_true(completed_output_available(converted))
  original_live.val = true
  live.val = false
  assert_false(completed_output_available(converted))
  assert_false(completed_output_same_occurrence(original, converted))
  live.val = true
  close_managed_publication_bridge(bridge)
  assert_false(completed_output_available(converted))
  assert_true(completed_output_available(original))
}

///|
fn managed_projection_original(
  owner : @lower.BoundPrepared,
) -> CompletedOutput raise {
  completed_output(
    evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [],
      ["values_0"],
      run_limits(),
      { remaining: 10000, max_frames: 100, },
    ).unwrap(),
    Step(0),
  ).unwrap()
}

///|
fn managed_projection_stream(
  owner : @lower.BoundPrepared,
  original : CompletedOutput,
) -> ManagedOutputValues {
  prepare_managed_output_values(
    owner,
    Step(0),
    2,
    stream_value_limits(),
    4096,
    managed_test_measure_limits(),
    completed_projection=Some(original),
  ).unwrap()
}

///|
fn managed_projection_copy(
  values : ManagedOutputValues,
  original : CompletedOutput,
  row : Int,
) -> Result[Unit, ManagedOutputValueIssue] {
  append_completed_projection_managed_wire(
    values,
    original,
    row,
    {
      max_columns: 2,
      max_order_work: 100,
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 10,
    },
    retained_row_test_limits(),
  )
}

///|
test "managed completed projection refuses partial and reordered copy provenance" {
  let owner = row_owner("")
  let original = managed_projection_original(owner)
  let partial = managed_projection_stream(owner, original)
  managed_projection_copy(partial, original, 0).unwrap()
  assert_true(
    finish_managed_output_values(partial).unwrap().completed_projection is None,
  )
  let reordered = managed_projection_stream(owner, original)
  managed_projection_copy(reordered, original, 1).unwrap()
  managed_projection_copy(reordered, original, 0).unwrap()
  assert_true(
    finish_managed_output_values(reordered).unwrap().completed_projection
    is None,
  )
}

///|
test "managed completed projection refuses equal-valued foreign source mixing" {
  let owner = row_owner("")
  let original = managed_projection_original(owner)
  let foreign = managed_projection_original(owner)
  assert_false(completed_output_same_occurrence(original, foreign))
  let mixed = managed_projection_stream(owner, original)
  managed_projection_copy(mixed, original, 0).unwrap()
  managed_projection_copy(mixed, foreign, 1).unwrap()
  assert_true(
    finish_managed_output_values(mixed).unwrap().completed_projection is None,
  )
  let other = managed_projection_stream(owner, original)
  managed_projection_copy(other, foreign, 0).unwrap()
  managed_projection_copy(other, foreign, 1).unwrap()
  assert_true(
    finish_managed_output_values(other).unwrap().completed_projection is None,
  )
}

///|
test "managed completed projection does not authenticate manual equal row admission" {
  let owner = row_owner("")
  let original = managed_projection_original(owner)
  let values = managed_projection_stream(owner, original)
  for wire in ["{\"a\":1,\"b\":0}", "{\"a\":0,\"b\":1}"] {
    let cells = decode_retained_row(
      values.buffer.schema,
      wire,
      retained_row_test_limits(),
    ).unwrap()
    append_managed_output_values(values, cells.length(), column => {
      cells.get(column)
    }).unwrap()
  }
  assert_true(
    finish_managed_output_values(values).unwrap().completed_projection is None,
  )
}

///|
test "managed completed projection rejects a foreign receiving owner" {
  let owner = row_owner("")
  let foreign = row_owner("")
  let original = managed_projection_original(owner)
  assert_true(
    prepare_managed_output_values(
      foreign,
      Step(0),
      2,
      stream_value_limits(),
      4096,
      managed_test_measure_limits(),
      completed_projection=Some(original),
    )
    is Err(Admission(InvalidCheckedRow)),
  )
}

///|
test "managed completed projection cancellation and expired source cannot seal a copy" {
  let owner = row_owner("")
  let original = managed_projection_original(owner)
  let cancelled = managed_projection_stream(owner, original)
  managed_projection_copy(cancelled, original, 0).unwrap()
  assert_true(cancel_managed_output_values(cancelled))
  assert_true(finish_managed_output_values(cancelled) is Err(Closed))
  assert_true(cancelled.completed_projection is None)
  let live = Ref(true)
  let restricted = restrict_completed_output(original, () => live.val)
  let expired = managed_projection_stream(owner, restricted)
  live.val = false
  assert_true(managed_projection_copy(expired, restricted, 0) is Err(_))
  match finish_managed_output_values(expired) {
    Ok(receipt) => assert_true(receipt.completed_projection is None)
    Err(_) => ()
  }
}

///|
test "managed completed projection keeps dense checked value conversion provenance" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let importing = prepare_completed_output_import(
    source,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for row in 0..<2 {
    append_completed_output_import(importing, output_fixture_row(owner, row)).unwrap()
  }
  let original = finish_completed_output_import(importing).unwrap()
  let values = prepare_managed_output_values(
    owner,
    Step(1),
    2,
    stream_value_limits(),
    4096,
    managed_test_measure_limits(),
    completed_projection=Some(original),
  ).unwrap()
  for row in 0..<2 {
    append_completed_projection_managed_values(values, original, row).unwrap()
  }
  let receipt = finish_managed_output_values(values).unwrap()
  guard receipt.completed_projection is Some((identity, target)) else {
    abort("the complete dense copy must preserve its original occurrence")
  }
  assert_true(physical_equal(identity, original.completion.result_identity))
  assert_eq(target, Step(1))
}

///|
test "managed completed projection preserves an exact empty original without row work" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":false},\"b\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"}]",
  )
  let original = managed_projection_original(owner)
  assert_eq(completed_row_count(original), 0)
  let values = managed_projection_stream(owner, original)
  let receipt = finish_managed_output_values(values).unwrap()
  guard receipt.completed_projection is Some((identity, target)) else {
    abort("the exact completed empty copy has no missing rows")
  }
  assert_eq(receipt.rows, 0)
  assert_true(physical_equal(identity, original.completion.result_identity))
  assert_eq(target, original.target)
}

///|
test "managed completed projection retains the original output row refusal boundary" {
  let owner = row_owner("")
  let original = managed_projection_original(owner)
  let values = prepare_managed_output_values(
    owner,
    Step(0),
    1,
    stream_value_limits(),
    4096,
    managed_test_measure_limits(),
    completed_projection=Some(original),
  ).unwrap()
  managed_projection_copy(values, original, 0).unwrap()
  assert_true(
    managed_projection_copy(values, original, 1) is Err(Admission(CaptureLimit)),
  )
  assert_true(finish_managed_output_values(values) is Err(Closed))
  assert_true(values.completed_projection is None)
}

///|
test "managed publication import quotes actual long text separately from syntax nodes" {
  let owner = capture_fixture()
  let generated = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(owner),
    ["select_1"],
    10000,
    1000,
  ).unwrap()
  let values = prepare_managed_output_values(
    owner,
    Step(1),
    2,
    stream_value_limits(),
    5000,
    { max_work: 20000, max_bytes: 20000, max_nodes: 1000, max_depth: 10, },
  ).unwrap()
  let retention = prepare_managed_output_retention_port(values, (
    receipt : ManagedOutputValueReceipt,
  ) => Some((receipt, 7, 9000L, () => true))).unwrap()
  for row in 0..<2 {
    let schema = @pipeline.schema_at(
      @lower.pipeline(@lower.bound_preparation(owner)),
      Step(1),
    ).unwrap()
    let cells = Array::makei(@schema.field_count(schema), column => {
      let field = @schema.field_at(schema, column).unwrap()
      let text = if @schema.reference_name(field.name) == "n" {
        (row + 1).to_string()
      } else {
        "\"" + "x".repeat(4096) + "\""
      }
      @admitted.admit(field.contract, input_cursor(text), {
        max_nodes: 10,
        max_text_bytes: 5000,
        max_depth: 2,
      }).unwrap()
    })
    append_managed_output_values(values, cells.length(), column => {
      cells.get(column)
    }).unwrap()
  }
  let receipt = finish_managed_output_values(values).unwrap()
  let material = retain_managed_output(retention, receipt).unwrap()
  let port = prepare_managed_completion_port(
    managed_test_profile(),
    generated,
    Step(1),
    1000,
    10000,
    (_ : Unit) => Some(material),
  ).unwrap()
  let output = complete_managed_output(port, ()).unwrap()
  let geometry = managed_publication_bridge_import_geometry(
    output, material, 2, 20000,
  ).unwrap()
  assert_eq(geometry.max_rows, 2)
  assert_eq(geometry.values.max_nodes, receipt.usage.nodes)
  assert_true(geometry.row.max_bytes > 4096)
  assert_true(geometry.row.max_nodes < 100)
  assert_true(geometry.row.max_nodes < geometry.row.max_bytes)
}

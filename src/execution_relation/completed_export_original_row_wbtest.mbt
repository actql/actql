///|
fn original_export_row_owner() -> @lower.BoundPrepared {
  bound_pipeline(
    (
      #|[{"values":{"schema":{"id":{"type":"number","nullable":false},"day":{"type":"date","nullable":false},"plain":{"type":"string","nullable":false},"whole":{"type":"int64","nullable":false},"amount":{"type":"decimal","precision":20,"scale":2,"nullable":false}},"rows":[{"id":1,"day":"2026-10-20","plain":"2026-10-20","whole":"9223372036854775807","amount":"9007199254740993.01"},{"id":2,"day":"2026-10-21","plain":"2026-10-21","whole":"-9223372036854775808","amount":"-9007199254740993.01"}]},"as":"v"},{"select":["plain","day","whole","amount","id"],"as":"selected"}]
    ),
  )
}

///|
fn original_export_row_preparation(
  source : CompletedOutput,
  occurrence : ManagedResultOccurrence,
) -> (CompletedResultRelationExportPreparation, CompletedOutputExport) {
  let preparation = start_completed_result_relation_export(
    source,
    occurrence,
    result_view_limits(),
    2,
    stream_value_limits(),
    row_wire_limits(),
    row_wire_limits(),
    publication_schema_limits(),
    4096,
  ).unwrap()
  while !advance_completed_result_relation_export(preparation, 100).unwrap().0 {
    ()
  }
  (
    preparation,
    finish_completed_result_relation_export_preparation(preparation).unwrap(),
  )
}

///|
fn original_export_row_field(
  row : CompletedOutputExportOriginalRow,
  name : String,
) -> @admitted.CheckedValue {
  completed_output_export_original_row_checked_field(row, name, 10, 1000, {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }).unwrap()
}

///|
test "original export row keeps typed cells and exact selected projection order" {
  let owner = original_export_row_owner()
  let source = export_fixture(owner)
  let occurrence = result_export_occurrence(
    owner,
    "answer",
    (
      #|{"answer":{"from":"selected","fields":["plain","day","whole","amount"],"order_by":[{"id":"desc"}]}}
    ),
  )
  let (preparation, stream) = original_export_row_preparation(
    source, occurrence,
  )
  let (_, foreign_stream) = original_export_row_preparation(source, occurrence)
  let (_, row) = next_completed_output_export_original_row(
      stream, 100, 10, 4096,
    )
    .unwrap()
    .unwrap()
  assert_eq(completed_output_export_original_row_index(row), 0)
  assert_true(
    completed_result_export_preparation_matches_original_row(preparation, row),
  )
  let (_, foreign) = next_completed_output_export_original_row(
      foreign_stream, 100, 10, 4096,
    )
    .unwrap()
    .unwrap()
  assert_false(
    completed_result_export_preparation_matches_original_row(
      preparation, foreign,
    ),
  )
  let day = original_export_row_field(row, "day")
  let plain = original_export_row_field(row, "plain")
  assert_true(day.value is @admitted.Date("2026-10-21"))
  assert_true(plain.value is @admitted.Text("2026-10-21"))
  assert_true(
    original_export_row_field(row, "whole").value
    is @admitted.Signed64(-9223372036854775808L),
  )
  assert_eq(
    @admitted.canonical_scalar_text(
      original_export_row_field(row, "amount"),
      1000,
    ),
    Some("-9007199254740993.01"),
  )
  assert_true(
    physical_equal(
      day.contract,
      @schema.lookup_reference(stream.rows.schema, "day").unwrap().contract,
    ),
  )
  let canonical = completed_output_export_original_row_canonical(row).unwrap()
  assert_eq(
    @identity.stringify_value(
      @identity.object_field(canonical, "day").unwrap(),
      100,
      10,
      3,
    ),
    @identity.stringify_value(
      @identity.object_field(canonical, "plain").unwrap(),
      100,
      10,
      3,
    ),
  )
  // Equal JSON strings never replace the two distinct checked domains.
  cancel_completed_output_export(stream)
  cancel_completed_output_export(foreign_stream)
  retire_completed_output_export_original_row(row)
  retire_completed_output_export_original_row(foreign)
}

///|
test "original export row refuses a progressed closed or explicitly retired traversal" {
  let source = export_fixture(result_export_owner())
  let stream = prepare_completed_output_export(
    source,
    2,
    stream_value_limits(),
    row_wire_limits(),
    4096,
  ).unwrap()
  let (_, row) = next_completed_output_export_original_row(
      stream, 100, 10, 4096,
    )
    .unwrap()
    .unwrap()
  assert_true(completed_output_export_original_row_available(row))
  let slots = completed_output_export_workspace_slots(
    stream_value_limits(),
    row_wire_limits(),
  ).unwrap()
  advance_completed_output_export(stream, 1, slots).unwrap() |> ignore
  assert_false(completed_output_export_original_row_available(row))
  assert_true(
    completed_output_export_original_row_checked_field(row, "s", 10, 1000, {
      max_nodes: 10,
      max_depth: 10,
      max_text_bytes: 100,
    })
    is Err(Unavailable),
  )
  cancel_completed_output_export(stream)
  retire_completed_output_export_original_row(row)
  assert_true(row.stream is None)
  assert_true(row.canonical is None)
}

///|
test "original export row preserves missing field and independent limits without NULL fallback" {
  let stream = prepare_completed_output_export(
    export_fixture(result_export_owner()),
    2,
    stream_value_limits(),
    row_wire_limits(),
    4096,
  ).unwrap()
  let (_, row) = next_completed_output_export_original_row(
      stream, 100, 10, 4096,
    )
    .unwrap()
    .unwrap()
  let limits : @admitted.Limits = {
    max_nodes: 10,
    max_depth: 10,
    max_text_bytes: 100,
  }
  assert_true(
    completed_output_export_original_row_checked_field(
      row, "absent", 10, 1000, limits,
    )
    is Err(MissingField),
  )
  assert_true(
    completed_output_export_original_row_checked_field(
      row, "s", 0, 1000, limits,
    )
    is Err(FieldLimit),
  )
  assert_true(
    completed_output_export_original_row_checked_field(row, "s", 10, 0, limits)
    is Err(WorkLimit),
  )
  assert_true(
    completed_output_export_original_row_checked_field(row, "s", 10, 1000, {
      ..limits,
      max_text_bytes: 0,
    })
    is Err(InvalidValue),
  )
  assert_true(
    completed_output_export_original_row_checked_field(row, "s", 10, 1000, {
      ..limits,
      max_nodes: 0,
    })
    is Err(InvalidLimits),
  )
  cancel_completed_output_export(stream)
  retire_completed_output_export_original_row(row)
}

///|
test "original export row fences cancellation performed by physical availability" {
  let armed = Ref(false)
  let stream_ref : Ref[CompletedOutputExport?] = Ref(None)
  let source = restrict_completed_output(
    export_fixture(result_export_owner()),
    fn() {
      if armed.val && stream_ref.val is Some(stream) {
        cancel_completed_output_export(stream)
      }
      true
    },
  )
  let stream = prepare_completed_output_export(
    source,
    2,
    stream_value_limits(),
    row_wire_limits(),
    4096,
  ).unwrap()
  stream_ref.val = Some(stream)
  let (_, row) = next_completed_output_export_original_row(
      stream, 100, 10, 4096,
    )
    .unwrap()
    .unwrap()
  armed.val = true
  assert_true(
    completed_output_export_original_row_checked_field(row, "s", 10, 1000, {
      max_nodes: 10,
      max_depth: 10,
      max_text_bytes: 100,
    })
    is Err(Unavailable),
  )
  assert_false(completed_output_export_original_row_available(row))
  retire_completed_output_export_original_row(row)
}

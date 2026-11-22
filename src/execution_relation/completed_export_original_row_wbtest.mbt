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
    max_text_bytes: 100,
  }).unwrap()
}

///|
test "Result export funds metadata before creation and preserves the captured row" {
  let owner = original_export_row_owner()
  let source = export_fixture(owner)
  let occurrence = result_export_occurrence(
    owner,
    "answer",
    (
      #|{"answer":{"from":"selected","fields":["plain","day","whole","amount"],"order_by":[{"id":"desc"}]}}
    ),
  )
  for accept in [false, true] {
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
    let mut visits = 0
    let mut saw_schema = false
    let mut saw_stream_start = false
    let mut valid_quote = true
    let fund = fn(capacity) {
      let size = execution_capacity_execution_bytes(capacity)
      visits += 1
      if visits == 1 {
        valid_quote = preparation.metadata is None && preparation.stream is None
        // Initial 55H/108R/155W plus three slots for each co-held name.
        let expected = 2984L +
          24L * preparation.rows.names.capacity().to_int64()
        valid_quote = valid_quote && size == expected
        return size <= expected - (if accept { 0L } else { 1L })
      }
      let metadata = preparation.metadata.unwrap()
      if metadata.phase == 3 {
        saw_schema = true
      }
      if metadata.phase == 4 {
        saw_stream_start = true
        valid_quote = valid_quote && metadata.stream is None
      }
      valid_quote = valid_quote && size > 0L
      true
    }
    let finished = while true {
      match
        advance_completed_result_relation_export(
          preparation,
          31,
          before_metadata=Some(fund),
        ) {
        Ok((false, _)) => continue
        value => break value
      }
    } nobreak {
      Err(Closed)
    }
    assert_true(valid_quote)
    if accept {
      assert_true(finished is Ok((true, _)) && saw_schema && saw_stream_start)
      let stream = finish_completed_result_relation_export_preparation(
        preparation,
      ).unwrap()
      let (_, row) = next_completed_output_export_original_row(
          stream, 100, 10, 4096,
        )
        .unwrap()
        .unwrap()
      assert_true(
        completed_result_export_preparation_matches_original_row(
          preparation, row,
        ),
      )
      assert_true(
        original_export_row_field(row, "whole").value
        is @admitted.Signed64(-9223372036854775808L),
      )
      retire_completed_output_export_original_row(row)
      cancel_completed_output_export(stream)
    } else {
      assert_true(
        finished is Err(Admission(CaptureLimit)) && preparation.closed,
      )
      assert_eq(visits, 1)
      assert_true(preparation.metadata is None && preparation.stream is None)
    }
    assert_true(completed_output_available(source))
  }
}

///|
test "Result export metadata cancellation cannot publish an open stream" {
  let owner = original_export_row_owner()
  let source = export_fixture(owner)
  let occurrence = result_export_occurrence(
    owner,
    "answer",
    (
      #|{"answer":{"from":"selected","fields":["day","whole"]}}
    ),
  )
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
  let mut cancelled = false
  let mut reentry_refused = true
  let mut schema_was_owned = false
  let fund = fn(_) {
    reentry_refused = reentry_refused &&
      advance_completed_result_relation_export(preparation, 1) is Err(Closed)
    if preparation.metadata is Some(metadata) && metadata.phase == 3 {
      schema_was_owned = metadata.schema_cursor is Some(_)
      cancelled = cancel_completed_result_relation_export(preparation)
    }
    true
  }
  let finished = while true {
    match
      advance_completed_result_relation_export(
        preparation,
        31,
        before_metadata=Some(fund),
      ) {
      Ok((false, _)) => continue
      value => break value
    }
  } nobreak {
    Ok((false, 0))
  }
  assert_true(finished is Err(Closed) && reentry_refused && schema_was_owned)
  assert_true(cancelled && preparation.closed && preparation.stream is None)
  assert_true(
    finish_completed_result_relation_export_preparation(preparation)
    is Err(Closed),
  )
  assert_true(completed_output_available(source))
}

///|
test "Result export retains the original receipt and closed stream metadata once" {
  let owner = original_export_row_owner()
  let source = export_fixture(owner)
  let occurrence = result_export_occurrence(
    owner,
    "answer",
    (
      #|{"answer":{"from":"selected","fields":["plain","day","whole","amount"],"order_by":[{"id":"desc"}]}}
    ),
  )
  let finish = fn(stream : CompletedOutputExport) {
    while next_completed_output_export_canonical_row(stream, 100, 10, 4096).unwrap()
          is Some(_) {
      ()
    }
    finish_completed_relation_export(stream).unwrap().0
  }
  let (original, stream) = original_export_row_preparation(source, occurrence)
  let (_, other_stream) = original_export_row_preparation(source, occurrence)
  let receipt = finish(stream)
  let other = finish(other_stream)
  assert_eq(receipt.rows.content.cid, other.rows.content.cid)
  assert_true(receipt.rows.references is None)
  assert_true(
    completed_result_export_retained_metadata_capacity(original, other) is None,
  )
  let retained = completed_result_export_retained_metadata_capacity(
    original, receipt,
  ).unwrap()
  let receipt_only = completed_relation_export_retained_capacity(receipt).unwrap()
  // Fixed controls 24H/72R/80W, 15 current array wrappers at 56B each,
  // four 32B order tuples, and the actual order/projection backing slots.
  // The existing receipt quote already counts both shared name arrays.
  let extra = 2568L +
    8L *
    (
      stream.order.columns.capacity().to_int64() +
      stream.rows.columns.unwrap().capacity().to_int64()
    )
  let bytes = execution_capacity_retained_bytes(receipt_only) + extra
  assert_eq(execution_capacity_retained_bytes(retained), bytes)
  assert_eq(execution_capacity_execution_bytes(retained), bytes)
  cancel_completed_relation_export_receipt(receipt)
  assert_true(
    completed_result_export_retained_metadata_capacity(original, receipt)
    is None,
  )
  cancel_completed_relation_export_receipt(other)
  assert_true(completed_output_available(source))
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

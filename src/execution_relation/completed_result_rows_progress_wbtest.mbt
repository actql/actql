///|
fn long_result_text_fixture() -> (CompletedOutput, ManagedResultOccurrence) raise {
  let prefix = "x".repeat(1024) + "😀"
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":false},\"s\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"n\":1,\"s\":\"" +
    prefix +
    "b\"},{\"n\":2,\"s\":\"" +
    prefix +
    "a\"}]},\"as\":\"v\"},{\"select\":[\"s\",\"n\"],\"as\":\"selected\"}]",
  )
  (
    export_fixture(owner),
    result_export_occurrence(
      owner, "answer", "{\"answer\":{\"from\":\"selected\",\"fields\":[\"s\"],\"order_by\":[{\"s\":\"asc\"}]}}",
    ),
  )
}

///|
fn long_result_view_limits() -> CompletedResultViewLimits {
  // Source fields are s,n. One projected s: 1 search + 1 binding + 1 column.
  // One order s: 1 term + 1 column. Merge: 2 row indices + 2 scratch indices
  // + 4 emitted indices (width-one and final width-two passes) + 1 comparison
  // + twice 1029 UTF-8 bytes = 2067. Preserve that existing final-copy pass.
  {
    max_fields: 1,
    max_mapping_work: 5,
    max_order_work: 2067,
    max_workspace_entries: 5,
  }
}

///|
test "Named Result row preparation splits long Text comparison without changing logical work" {
  for quantum in [1, 7, 64] {
    let (source, occurrence) = long_result_text_fixture()
    assert_eq(RelationRows::field_names(source.table.unwrap()), ["s", "n"])
    let cursor = start_completed_result_rows(
      source,
      occurrence,
      long_result_view_limits(),
    ).unwrap()
    let mut steps = 0
    let mut done = false
    for _ in 0..<5000 {
      let (finished, used) = advance_completed_result_rows(cursor, quantum).unwrap()
      assert_true(used >= 0 && used <= quantum)
      steps += used
      if finished {
        done = true
        break
      }
      assert_true(used > 0)
    }
    assert_true(done && steps > 3000)
    assert_eq(cursor.mapping_work.val, 0)
    assert_eq(cursor.order_work.remaining, 0)
    let rows = finish_completed_result_rows(cursor).unwrap()
    assert_eq(rows.names, ["s"])
    assert_eq(rows.columns, Some([0]))
    assert_eq(rows.rows, Some([1, 0]))
    assert_true(
      IndexedRows::read_cell(rows, 0, 0) is Text(text) &&
      text == "x".repeat(1024) + "😀a",
    )
    assert_true(
      IndexedRows::read_cell(rows, 1, 0) is Text(text) &&
      text == "x".repeat(1024) + "😀b",
    )
    assert_true(cursor.rows.is_empty() && cursor.scratch.is_empty())
    assert_true(cursor.columns.is_empty() && cursor.names.is_empty())
    assert_true(cursor.terms.is_empty() && completed_output_available(source))
  }
}

///|
test "Named Result lookup preserves typed roles when flattened spellings agree" {
  assert_false(
    result_reference_roles_match(
      @schema.Unqualified("left.s"),
      @schema.Qualified(@schema.Left, "s"),
    ),
  )
  assert_false(
    result_reference_roles_match(
      @schema.Qualified(@schema.Left, "s"),
      @schema.Qualified(@schema.Right, "s"),
    ),
  )
  assert_true(
    result_reference_roles_match(
      @schema.Qualified(@schema.Left, "x".repeat(1024)),
      @schema.Qualified(@schema.Left, "different"),
    ),
  )
  assert_true(
    result_reference_roles_match(
      @schema.Unqualified("x".repeat(1024)),
      @schema.Unqualified("different"),
    ),
  )
}

///|
test "Named Result row preparation rejects independently one-short work and workspace" {
  for
    limits in [
      { ..long_result_view_limits(), max_mapping_work: 4, },
      { ..long_result_view_limits(), max_order_work: 2066, },
      { ..long_result_view_limits(), max_workspace_entries: 4, },
    ] {
    let (source, occurrence) = long_result_text_fixture()
    let cursor = start_completed_result_rows(source, occurrence, limits).unwrap()
    let mut refused = false
    for _ in 0..<5000 {
      match advance_completed_result_rows(cursor, 1) {
        Err(Limit) => {
          refused = true
          break
        }
        Ok((false, 1)) => ()
        _ => fail("wrong Result preparation boundary")
      }
    }
    assert_true(refused && cursor.closed)
    assert_true(cursor.rows.is_empty() && cursor.scratch.is_empty())
    assert_true(cursor.columns.is_empty() && cursor.names.is_empty())
    assert_true(cursor.terms.is_empty() && cursor.mapping_input is None)
    assert_true(completed_output_available(source))
  }
}

///|
test "Named Result cancellation inside Text charging retains producer and prevents transfer" {
  for comparison_phase in [1, 2, 3] {
    let (source, occurrence) = long_result_text_fixture()
    let cursor = start_completed_result_rows(
      source,
      occurrence,
      long_result_view_limits(),
    ).unwrap()
    let mut observed = false
    for _ in 0..<5000 {
      advance_completed_result_rows(cursor, 1).unwrap() |> ignore
      if cursor.comparison.phase == comparison_phase &&
        (cursor.comparison.offset > 20 || cursor.comparison.charge.offset > 20) {
        observed = true
        break
      }
    }
    assert_true(observed)
    let work = cursor.order_work.remaining
    assert_true(cancel_completed_result_rows(cursor))
    assert_false(cancel_completed_result_rows(cursor))
    assert_true(finish_completed_result_rows(cursor) is Err(Unavailable))
    assert_true(advance_completed_result_rows(cursor, 1) is Err(Unavailable))
    assert_eq(cursor.order_work.remaining, work)
    assert_true(cursor.rows.is_empty() && cursor.columns.is_empty())
    assert_true(cursor.names.is_empty() && cursor.terms.is_empty())
    assert_true(completed_output_available(source))
  }
}

///|
test "Named Result projection lookup yields within long reference spellings" {
  let prefix = "x".repeat(1024) + "😀"
  let a = prefix + "a"
  let b = prefix + "b"
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"" +
    a +
    "\":{\"type\":\"number\",\"nullable\":false},\"" +
    b +
    "\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"" +
    a +
    "\":2,\"" +
    b +
    "\":1}]},\"as\":\"v\"},{\"select\":[\"" +
    b +
    "\",\"" +
    a +
    "\"],\"as\":\"selected\"}]",
  )
  let source = export_fixture(owner)
  let occurrence = result_export_occurrence(
    owner,
    "answer",
    "{\"answer\":{\"from\":\"selected\",\"fields\":[\"" +
    a +
    "\"],\"order_by\":[{\"" +
    a +
    "\":\"asc\"}]}}",
  )
  assert_eq(RelationRows::field_names(source.table.unwrap()), [b, a])
  // Projection: 1 search + 1 binding + 2 columns; order: 1 term + 2 columns.
  let limits : CompletedResultViewLimits = {
    max_fields: 1,
    max_mapping_work: 7,
    max_order_work: 1,
    max_workspace_entries: 2,
  }
  let cursor = start_completed_result_rows(source, occurrence, limits).unwrap()
  for _ in 0..<40 {
    assert_eq(advance_completed_result_rows(cursor, 1).unwrap(), (false, 1))
  }
  assert_eq(cursor.mapping_phase, 1)
  assert_eq(cursor.mapping_offset, 39)
  assert_true(cursor.names.is_empty() && cursor.rows.is_empty())
  assert_true(cancel_completed_result_rows(cursor))
  for quantum in [1, 7, 64] {
    let cursor = start_completed_result_rows(source, occurrence, limits).unwrap()
    let mut steps = 0
    for _ in 0..<10000 {
      let (done, used) = advance_completed_result_rows(cursor, quantum).unwrap()
      assert_true(used <= quantum)
      steps += used
      if done {
        break
      }
    }
    assert_true(steps > 5000)
    assert_eq(cursor.mapping_work.val, 0)
    assert_eq(cursor.order_work.remaining, 0)
    let rows = finish_completed_result_rows(cursor).unwrap()
    assert_eq(rows.names, [a])
    assert_eq(rows.columns, Some([1]))
    assert_true(IndexedRows::read_cell(rows, 0, 0) is Number(2))
  }
}

///|
test "Named Result metadata handoff stays cancellable after private row-map transfer" {
  let owner = result_export_owner()
  let source = export_fixture(owner)
  let occurrence = result_export_occurrence(
    owner, "answer", "{\"answer\":{\"from\":\"selected\",\"fields\":[\"s\"],\"order_by\":[{\"n\":\"desc\"}]}}",
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
    64,
  ).unwrap()
  for _ in 0..<200 {
    assert_eq(
      advance_completed_result_relation_export(preparation, 1).unwrap(),
      (false, 1),
    )
    if preparation.metadata is Some(_) {
      break
    }
  }
  let metadata = preparation.metadata.unwrap()
  assert_true(preparation.rows.closed && preparation.stream is None)
  assert_true(
    preparation.rows.names.is_empty() && preparation.rows.columns.is_empty(),
  )
  assert_true(
    preparation.rows.rows.is_empty() && preparation.rows.scratch.is_empty(),
  )
  assert_eq(metadata.rows.unwrap().rows, Some([1, 0]))
  assert_true(cancel_completed_result_relation_export(preparation))
  assert_false(cancel_completed_result_relation_export(preparation))
  assert_true(
    metadata.closed && metadata.rows is None && metadata.stream is None,
  )
  assert_eq(metadata.workspace.live, 0)
  assert_true(
    finish_completed_result_relation_export_preparation(preparation)
    is Err(Closed),
  )
  assert_true(completed_output_available(source))
}

///|
test "Named Result preparation rejects availability reentry and revocation before final transfer" {
  let owner = result_export_owner()
  let holder : Ref[CompletedResultRelationExportPreparation?] = Ref(None)
  let permission = Ref(true)
  let reentries = Ref(0)
  let rejected_reentry = Ref(true)
  let source = restrict_completed_output(export_fixture(owner), fn() {
    if holder.val is Some(preparation) {
      rejected_reentry.val = rejected_reentry.val &&
        advance_completed_result_relation_export(preparation, 1) is Err(Closed) &&
        finish_completed_result_relation_export_preparation(preparation)
        is Err(Closed)
      reentries.val += 1
    }
    permission.val
  })
  let occurrence = result_export_occurrence(
    owner, "answer", "{\"answer\":{\"from\":\"selected\",\"fields\":[\"s\"],\"order_by\":[{\"n\":\"desc\"}]}}",
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
    64,
  ).unwrap()
  holder.val = Some(preparation)
  for _ in 0..<200 {
    if advance_completed_result_relation_export(preparation, 1).unwrap().0 {
      break
    }
  }
  assert_true(
    reentries.val > 0 && rejected_reentry.val && preparation.stream is Some(_),
  )
  permission.val = false
  assert_true(
    finish_completed_result_relation_export_preparation(preparation)
    is Err(ResultView(Unavailable)),
  )
  assert_true(preparation.closed && preparation.stream.unwrap().source is None)
  assert_true(preparation.metadata is None)
}

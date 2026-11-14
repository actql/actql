///|
fn completed_scalar_text_fixture(
  current : () -> Bool,
) -> (CompletedOutputImport, CompletedOutput) raise {
  let owner = capture_fixture()
  let (retained, _) = retained_fixture(owner, Ref(true))
  let source = restrict_completed_output(retained, current)
  let importing = prepare_completed_output_import(
    source,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  assert_true(physical_equal(importing.source, source))
  for row in 0..<2 {
    append_completed_output_import(importing, output_fixture_row(owner, row)).unwrap()
  }
  let output = finish_completed_output_import(importing).unwrap()
  (importing, output)
}

///|
test "closed scalar import reports only same original shared text DATA" {
  let (importing, output) = completed_scalar_text_fixture(() => true)
  assert_true(!importing.open && importing.completed && !importing.reading)
  assert_true(physical_equal(importing.source, output))
  assert_eq(importing.admitted.buffer.budget.text, 10)
  assert_eq(
    completed_output_import_shared_scalar_text_bytes(importing, output),
    Some(80L),
  )
  assert_eq(
    completed_output_import_shared_scalar_text_bytes(importing, { ..output, }),
    None,
  )
  let (foreign, other) = completed_scalar_text_fixture(() => true)
  assert_eq(
    completed_output_import_shared_scalar_text_bytes(importing, other),
    None,
  )
  assert_eq(
    completed_output_import_shared_scalar_text_bytes(foreign, output),
    None,
  )
  // Original decoded Text is still the exact admitted immutable Value. The
  // helper neither clears these rows nor acknowledges their original owner.
  guard output.table is Some(AdmittedTable(table)) else {
    abort("actual scalar import must retain its table")
  }
  assert_true(physical_equal(table.rows, importing.admitted.buffer.rows))
  assert_eq(table.rows.length(), 2)
  assert_eq(completed_output_import_cumulative_work(importing), 32L)
}

///|
test "scalar overlap refuses partial cancelled current-changed and nested use" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let partial = prepare_completed_output_import(
    source,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  assert_eq(
    completed_output_import_shared_scalar_text_bytes(partial, source),
    None,
  )
  append_completed_output_import(partial, output_fixture_row(owner, 0)).unwrap()
  assert_eq(
    completed_output_import_shared_scalar_text_bytes(partial, source),
    None,
  )
  cancel_completed_output_import(partial) |> ignore
  assert_eq(
    completed_output_import_shared_scalar_text_bytes(partial, source),
    None,
  )
  let live = Ref(true)
  let reenter = Ref(false)
  let nested : Ref[Int64?] = Ref(Some(-1L))
  let selected : Ref[(CompletedOutputImport, CompletedOutput)?] = Ref(None)
  let (importing, output) = completed_scalar_text_fixture(() => {
    if reenter.val {
      reenter.val = false
      let (original, result) = selected.val.unwrap()
      nested.val = completed_output_import_shared_scalar_text_bytes(
        original, result,
      )
    }
    live.val
  })
  selected.val = Some((importing, output))
  reenter.val = true
  assert_eq(
    completed_output_import_shared_scalar_text_bytes(importing, output),
    Some(80L),
  )
  assert_eq(nested.val, None)
  assert_false(importing.reading)
  live.val = false
  assert_eq(
    completed_output_import_shared_scalar_text_bytes(importing, output),
    None,
  )
  assert_false(importing.reading)
  let nested_owner = managed_nested_reference_owner()
  let nested_schema = @lower.preparation_schema_at(
    @lower.bound_preparation(nested_owner),
    Step(0),
  ).unwrap()
  assert_false(completed_import_plain_scalar_schema(nested_schema))
}

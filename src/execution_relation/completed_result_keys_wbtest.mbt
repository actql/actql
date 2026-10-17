///|
fn result_key_fixture(
  rows : String,
  nullable? : Bool = false,
) -> (CompletedResultRelationExportPreparation, @schema.Field) raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":false},\"s\":{\"type\":\"string\",\"nullable\":" +
    nullable.to_string() +
    "}},\"rows\":" +
    rows +
    "},\"as\":\"v\"},{\"select\":[\"s\",\"n\"],\"as\":\"selected\"}]",
  )
  let source = export_fixture(owner)
  let occurrence = result_export_occurrence(
    owner, "answer", "{\"answer\":{\"from\":\"selected\",\"fields\":[\"s\"]}}",
  )
  let preparation = start_completed_result_relation_export(
    source,
    occurrence,
    result_view_limits(),
    100,
    stream_value_limits(),
    row_wire_limits(),
    row_wire_limits(),
    publication_schema_limits(),
    64,
  ).unwrap()
  (preparation, @schema.field_at(preparation.rows.schema, 0).unwrap())
}

///|
fn result_key_cleanup(value : CompletedResultKeyValidation) -> Unit raise {
  let mut done = false
  for _ in 0..<10000 {
    if cleanup_completed_result_key_validation(value).unwrap() {
      done = true
      break
    }
  }
  assert_true(done && value.state.retired)
  assert_true(value.state.cursor is None && value.state.view is None)
}

///|
test "original Result key validation shares exact typed work and retires before nominal matching" {
  let totals : Array[Int64] = []
  for quantum in [1, 7, 64] {
    let (original, field) = result_key_fixture(
      "[{\"n\":1,\"s\":\"é\"},{\"n\":2,\"s\":\"😀\"}]",
    )
    // Key/field 2 + one schema candidate 3 + type transition 1 +
    // row/cell/text (1+1+2) + (1+1+4) = 16 original semantic units.
    let validation = start_completed_result_key_validation(
      @bounded.control(),
      original,
      field,
      16,
      1,
      5,
    ).unwrap()
    assert_false(
      completed_result_key_validation_matches(validation, original, field),
    )
    let mut complete = false
    let mut previous = 0L
    for _ in 0..<10000 {
      match
        advance_completed_result_key_validation(validation, quantum).unwrap() {
        @bounded.ContinueWith(_, work~, ..) => {
          assert_true(work > previous && work - previous <= quantum.to_int64())
          previous = work
          assert_false(
            completed_result_key_validation_matches(validation, original, field),
          )
        }
        @bounded.Completed(remaining, work~, ..) => {
          assert_eq(remaining, 0)
          assert_true(work > previous && work - previous <= quantum.to_int64())
          totals.push(work)
          complete = true
          break
        }
        _ => fail("original completed Result key validation failed")
      }
    }
    assert_true(complete)
    result_key_cleanup(validation)
    assert_true(
      completed_result_key_validation_matches(validation, original, field),
    )
    let copy = @schema.field_at(original.rows.schema, 0).unwrap()
    assert_false(physical_equal(field, copy))
    assert_false(
      completed_result_key_validation_matches(validation, original, copy),
    )
    let (other, _) = result_key_fixture(
      "[{\"n\":1,\"s\":\"é\"},{\"n\":2,\"s\":\"😀\"}]",
    )
    assert_false(
      completed_result_key_validation_matches(validation, other, field),
    )
    assert_true(completed_output_available(original.rows.source))
  }
  assert_eq(totals.length(), 3)
  assert_eq(totals[0], totals[1])
  assert_eq(totals[1], totals[2])
}

///|
test "original Result final duplicate cannot yield a partial key proof" {
  let (original, field) = result_key_fixture(
    "[{\"n\":1,\"s\":\"a\"},{\"n\":2,\"s\":\"b\"},{\"n\":3,\"s\":\"a\"}]",
  )
  let validation = start_completed_result_key_validation(
    @bounded.control(),
    original,
    field,
    100,
    1,
    20,
  ).unwrap()
  let mut duplicate = false
  for _ in 0..<10000 {
    match advance_completed_result_key_validation(validation, 1).unwrap() {
      @bounded.ContinueWith(_, ..) =>
        assert_false(
          completed_result_key_validation_matches(validation, original, field),
        )
      @bounded.FailedWith(Key(DuplicateKey(0, 2)), ..) => {
        duplicate = true
        break
      }
      _ => fail("late duplicate did not retain its original row coordinates")
    }
  }
  assert_true(duplicate)
  result_key_cleanup(validation)
  assert_false(
    completed_result_key_validation_matches(validation, original, field),
  )
  assert_true(
    validation.state.original is None && validation.state.field is None,
  )
  assert_true(completed_output_available(original.rows.source))
}

///|
test "original Result one-short key work entries and type frames refuse without leaked tuples" {
  for (work, frames, entries) in [(15, 1, 5), (16, 1, 4), (16, 0, 5)] {
    let (original, field) = result_key_fixture(
      "[{\"n\":1,\"s\":\"é\"},{\"n\":2,\"s\":\"😀\"}]",
    )
    let validation = start_completed_result_key_validation(
      @bounded.control(),
      original,
      field,
      work,
      frames,
      entries,
    ).unwrap()
    let mut failed = false
    for _ in 0..<10000 {
      match advance_completed_result_key_validation(validation, 1).unwrap() {
        @bounded.ContinueWith(_, ..) => ()
        @bounded.FailedWith(Key(Limit), ..) => {
          failed = true
          break
        }
        _ => fail("one-short original key bound accepted")
      }
    }
    assert_true(failed)
    result_key_cleanup(validation)
    assert_false(
      completed_result_key_validation_matches(validation, original, field),
    )
  }
}

///|
test "original Result cancellation retires retained key entries and never completes" {
  let (original, field) = result_key_fixture(
    "[{\"n\":1,\"s\":\"a\"},{\"n\":2,\"s\":\"b\"}]",
  )
  let engine = @bounded.control()
  let validation = start_completed_result_key_validation(
    engine, original, field, 100, 1, 20,
  ).unwrap()
  let mut held = false
  for _ in 0..<10000 {
    assert_true(
      advance_completed_result_key_validation(validation, 1).unwrap()
      is @bounded.ContinueWith(_, ..),
    )
    if validation.state.cursor
      .map(cursor => cursor.seen.length() > 0)
      .unwrap_or(false) {
      held = true
      break
    }
  }
  assert_true(held)
  @bounded.request_cancel(engine) |> ignore
  assert_true(
    advance_completed_result_key_validation(validation, 1).unwrap()
    is @bounded.StoppedWith(_, ..),
  )
  result_key_cleanup(validation)
  assert_false(
    completed_result_key_validation_matches(validation, original, field),
  )
}

///|
test "original Result retirement revokes partial and completed key validation" {
  for completed in [false, true] {
    let (original, field) = result_key_fixture("[{\"n\":1,\"s\":\"a\"}]")
    let live = Ref(true)
    let source = restrict_completed_output(original.rows.source, () => live.val)
    let restricted = start_completed_result_relation_export(
      source,
      original.rows.occurrence,
      result_view_limits(),
      100,
      stream_value_limits(),
      row_wire_limits(),
      row_wire_limits(),
      publication_schema_limits(),
      64,
    ).unwrap()
    let validation = start_completed_result_key_validation(
      @bounded.control(),
      restricted,
      field,
      100,
      1,
      20,
    ).unwrap()
    if completed {
      let mut done = false
      for _ in 0..<10000 {
        match advance_completed_result_key_validation(validation, 1).unwrap() {
          @bounded.ContinueWith(_, ..) => ()
          @bounded.Completed(_, ..) => {
            done = true
            break
          }
          _ => fail("live original did not complete")
        }
      }
      assert_true(done)
      result_key_cleanup(validation)
      assert_true(
        completed_result_key_validation_matches(validation, restricted, field),
      )
      live.val = false
    } else {
      assert_true(
        advance_completed_result_key_validation(validation, 1).unwrap()
        is @bounded.ContinueWith(_, ..),
      )
      live.val = false
      assert_true(
        advance_completed_result_key_validation(validation, 1).unwrap()
        is @bounded.FailedWith(Unavailable, ..),
      )
      result_key_cleanup(validation)
    }
    assert_false(
      completed_result_key_validation_matches(validation, restricted, field),
    )
  }
}

///|
test "empty original Result still checks selected key type and presence" {
  let (original, field) = result_key_fixture("[]")
  let validation = start_completed_result_key_validation(
    @bounded.control(),
    original,
    field,
    6,
    1,
    2,
  ).unwrap()
  let mut done = false
  for _ in 0..<10000 {
    match advance_completed_result_key_validation(validation, 1).unwrap() {
      @bounded.ContinueWith(_, ..) => ()
      @bounded.Completed(remaining, ..) => {
        assert_eq(remaining, 0)
        done = true
        break
      }
      _ => fail("valid empty original key input failed")
    }
  }
  assert_true(done)
  result_key_cleanup(validation)
  assert_true(
    completed_result_key_validation_matches(validation, original, field),
  )
  let (nullable, nullable_field) = result_key_fixture("[]", nullable=true)
  assert_true(
    start_completed_result_key_validation(
      @bounded.control(),
      nullable,
      nullable_field,
      100,
      1,
      20,
    )
    is Err(Key(NullableWitnessPending)),
  )
}

///|
test "independent managed copy outlives its exact scoped source" {
  let owner = capture_fixture()
  let generated = compute_test_sequence(owner)
  let completed = test_typed_completion(generated, 1)
  let permission = Ref(true)
  let source = restrict_completed_output(
    completed_output(completed, Step(1)).unwrap(),
    fn() { permission.val },
  )
  let copy = copy_completed_output_independent(source, 2, 2).unwrap()
  permission.val = false
  assert_false(completed_output_available(source))
  assert_true(completed_output_available(copy))
  assert_eq(completed_row_count(copy), 2)
  assert_true(completed_cell(copy, 1, 0) is Some(_))
  assert_true(copy_completed_output_independent(copy, 1, 2) is Err(Limit))
}

///|
test "bounded independent row copy respects quantum and source lifetime" {
  let owner = capture_fixture()
  let generated = compute_test_sequence(owner)
  let completed = test_typed_completion(generated, 1)
  let permission = Ref(true)
  let source = restrict_completed_output(
    completed_output(completed, Step(1)).unwrap(),
    fn() { permission.val },
  )
  let control = @bounded.control()
  let copy = start_bounded_independent_row_copy(control, source, 2, 2, 12).unwrap()
  let mut prior_work = 0L
  let mut steps = 0
  let mut result : CompletedOutput? = None
  while result is None && steps < 32 {
    match advance_bounded_independent_row_copy(copy, 1).unwrap() {
      RowCopyContinue(work~, ..) => {
        assert_eq(work - prior_work, 1L)
        prior_work = work
      }
      RowCopyComplete(output, work~, ..) => {
        assert_eq(work - prior_work, 1L)
        result = Some(output)
      }
      RowCopyFailed(_, ..) => abort("unexpected copy failure")
      RowCopyStopped(_, ..) => abort("unexpected copy stop")
    }
    steps += 1
  }
  assert_true(result is Some(_))
  permission.val = false
  assert_false(completed_output_available(source))
  assert_true(completed_output_available(result.unwrap()))
  assert_eq(completed_row_count(result.unwrap()), 2)
  assert_true(completed_cell(result.unwrap(), 1, 0) is Some(_))
  assert_true(cleanup_bounded_independent_row_copy(copy).unwrap())
  assert_false(bounded_independent_row_copy_cleanup_pending(copy))
}

///|
test "bounded independent row copy stops before partial output publication" {
  let owner = capture_fixture()
  let generated = compute_test_sequence(owner)
  let completed = test_typed_completion(generated, 1)
  let source = completed_output(completed, Step(1)).unwrap()
  let control = @bounded.control()
  let copy = start_bounded_independent_row_copy(control, source, 2, 2, 12).unwrap()
  assert_true(
    advance_bounded_independent_row_copy(copy, 1) is Ok(RowCopyContinue(..)),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_independent_row_copy(copy, 1) is Ok(RowCopyStopped(_, ..)),
  )
  assert_true(bounded_independent_row_copy_stopped(copy))
  assert_true(bounded_independent_row_copy_cleanup_pending(copy))
  assert_true(cleanup_bounded_independent_row_copy(copy).unwrap())
  assert_false(bounded_independent_row_copy_cleanup_pending(copy))
}

///|
test "bounded independent row copy admits exact dimensions before starting" {
  let owner = capture_fixture()
  let generated = compute_test_sequence(owner)
  let completed = test_typed_completion(generated, 1)
  let source = completed_output(completed, Step(1)).unwrap()
  let control = @bounded.control()
  assert_true(
    start_bounded_independent_row_copy(control, source, 1, 2, 12) is Err(Limit),
  )
  assert_true(
    start_bounded_independent_row_copy(control, source, 2, 1, 12) is Err(Limit),
  )
  assert_true(
    start_bounded_independent_row_copy(control, source, 2, 2, 1) is Err(Limit),
  )
  let copy = start_bounded_independent_row_copy(control, source, 2, 2, 12).unwrap()
  let mut total_work = 0L
  let mut output : CompletedOutput? = None
  while output is None && total_work < 20L {
    match advance_bounded_independent_row_copy(copy, 1).unwrap() {
      RowCopyContinue(work~, ..) => total_work = work
      RowCopyComplete(value, work~, ..) => {
        total_work = work
        output = Some(value)
      }
      RowCopyFailed(_, ..) | RowCopyStopped(_, ..) =>
        abort("exact bounded copy did not complete")
    }
  }
  assert_true(output is Some(_))
  assert_eq(total_work, 11L)
  assert_true(cleanup_bounded_independent_row_copy(copy).unwrap())

  let short = start_bounded_independent_row_copy(
    @bounded.control(),
    source,
    2,
    2,
    11,
  ).unwrap()
  let mut failed = false
  for _ in 0..<12 {
    match advance_bounded_independent_row_copy(short, 1).unwrap() {
      RowCopyContinue(..) => ()
      RowCopyFailed(Limit, ..) => {
        failed = true
        break
      }
      RowCopyFailed(_, ..) | RowCopyStopped(_, ..) | RowCopyComplete(_, ..) =>
        abort("one-short workspace did not fail at the copy boundary")
    }
  }
  assert_true(failed)
  assert_true(bounded_independent_row_copy_stopped(short))
  assert_true(cleanup_bounded_independent_row_copy(short).unwrap())
}

///|
test "bounded independent row copy rejects a source lost between resumes" {
  let owner = capture_fixture()
  let generated = compute_test_sequence(owner)
  let completed = test_typed_completion(generated, 1)
  let permission = Ref(true)
  let source = restrict_completed_output(
    completed_output(completed, Step(1)).unwrap(),
    fn() { permission.val },
  )
  let copy = start_bounded_independent_row_copy(
    @bounded.control(),
    source,
    2,
    2,
    12,
  ).unwrap()
  assert_true(
    advance_bounded_independent_row_copy(copy, 1) is Ok(RowCopyContinue(..)),
  )
  permission.val = false
  assert_true(
    advance_bounded_independent_row_copy(copy, 1)
    is Ok(RowCopyFailed(Unavailable, ..)),
  )
  assert_true(bounded_independent_row_copy_stopped(copy))
  assert_true(bounded_independent_row_copy_cleanup_pending(copy))
  assert_true(cleanup_bounded_independent_row_copy(copy).unwrap())
  assert_false(bounded_independent_row_copy_cleanup_pending(copy))
}

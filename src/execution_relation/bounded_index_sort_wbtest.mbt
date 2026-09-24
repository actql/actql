///|
test "bounded index sort is stable and observes cancellation" {
  let control = @bounded.control()
  let values = [3, 1, 2, 1]
  let execution = start_bounded_index_sort(control, values.length(), fn(a, b) {
    Ok(values[a] - values[b])
  }).unwrap()
  let mut sorted = None
  let mut advances = 0
  while sorted is None {
    advances += 1
    match advance_bounded_index_sort(execution, 1).unwrap() {
      BoundedIndexSortContinue => ()
      BoundedIndexSortComplete(value) => sorted = Some(value)
      BoundedIndexSortFailed(_) => fail("unexpected sort failure")
      BoundedIndexSortStopped(_) => fail("unexpected sort stop")
    }
  }
  assert_true(advances > values.length())
  assert_eq(sorted.unwrap(), [1, 3, 2, 0])
  assert_true(cleanup_bounded_index_sort(execution))

  let cancel_control = @bounded.control()
  let cancelled = start_bounded_index_sort(cancel_control, 100, fn(a, b) {
    Ok(a - b)
  }).unwrap()
  assert_true(
    advance_bounded_index_sort(cancelled, 1).unwrap()
    is BoundedIndexSortContinue,
  )
  assert_true(@bounded.request_cancel(cancel_control))
  assert_true(
    advance_bounded_index_sort(cancelled, 1).unwrap()
    is BoundedIndexSortStopped(@bounded.Cancelled),
  )
  assert_true(cleanup_bounded_index_sort(cancelled))
}

///|
test "bounded index sort keeps a pending comparison across resumes" {
  let values = [3, 1, 2, 1]
  let pair = Ref((-1, -1))
  let visits = Ref(0)
  let execution = start_bounded_index_sort_stepped(
    @bounded.control(),
    values.length(),
    (left, right) => {
      if visits.val == 0 {
        pair.val = (left, right)
      } else if pair.val != (left, right) {
        return Err(InvalidRows)
      }
      visits.val += 1
      if visits.val < 4 {
        Ok(None)
      } else {
        visits.val = 0
        Ok(Some(values[left] - values[right]))
      }
    },
  ).unwrap()
  let mut sorted = None
  let mut advances = 0
  while sorted is None && advances < 100 {
    advances += 1
    match advance_bounded_index_sort(execution, 1).unwrap() {
      BoundedIndexSortContinue => ()
      BoundedIndexSortComplete(value) => sorted = Some(value)
      BoundedIndexSortFailed(_) | BoundedIndexSortStopped(_) =>
        fail("stepped comparison did not complete")
    }
  }
  assert_eq(sorted.unwrap(), [1, 3, 2, 0])
  assert_true(advances > 15)
  assert_true(cleanup_bounded_index_sort(execution))
}

///|
test "bounded index sort can stop during a pending comparison" {
  let control = @bounded.control()
  let visits = Ref(0)
  let execution = start_bounded_index_sort_stepped(control, 2, (_, _) => {
    visits.val += 1
    Ok(None)
  }).unwrap()
  let mut polls = 0
  while visits.val == 0 && polls < 10 {
    polls += 1
    assert_true(
      advance_bounded_index_sort(execution, 1).unwrap()
      is BoundedIndexSortContinue,
    )
  }
  assert_eq(visits.val, 1)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_index_sort(execution, 1).unwrap()
    is BoundedIndexSortStopped(@bounded.Cancelled),
  )
  assert_eq(visits.val, 1)
  assert_true(cleanup_bounded_index_sort(execution))
}

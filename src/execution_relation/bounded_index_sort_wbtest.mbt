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

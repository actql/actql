///|
// Prepared Native inputs only. Reuse the original 64-page fixture; these are
// neither VM execution nor an installed product's adopted numerical limits.
test "original backing loan prevents physical close and preserves cleanup return" {
  let host = prepared_host(64L * page_bytes_ffi())
  host.acquire().unwrap()
  let allocation = host.allocate(1L).unwrap()
  let loan = host.borrow_backing().unwrap()
  host.require_backing_borrow_current(loan).unwrap()
  assert_true(host.retire(allocation) is Err(@bootstrap.ReadersPending))
  assert_true(host.try_close() is Err(@bootstrap.ReadersPending))
  assert_false(host.closed)
  assert_true(host.backing is Some(_))
  assert_true(
    host.require_backing_borrow_current(loan) is Err(@bootstrap.Closing),
  )
  assert_true(host.borrow_backing() is Err(@bootstrap.Closing))
  host.return_backing_borrow(loan).unwrap()
  // The original allocation was preserved by the pending backing reader.
  host.retire(allocation).unwrap()
  host.try_close().unwrap()
  assert_true(host.closed)
  assert_true(host.backing is None)
}

///|
test "equal metadata cannot return or observe another original backing loan" {
  let first = prepared_host(64L * page_bytes_ffi())
  let second = prepared_host(64L * page_bytes_ffi())
  first.acquire().unwrap()
  second.acquire().unwrap()
  let loan = first.borrow_backing().unwrap()
  assert_true(
    second.require_backing_borrow_current(loan)
    is Err(@bootstrap.ForeignOriginal),
  )
  assert_true(
    second.return_backing_borrow(loan) is Err(@bootstrap.ForeignOriginal),
  )
  first.require_backing_borrow_current(loan).unwrap()
  first.return_backing_borrow(loan).unwrap()
  first.try_close().unwrap()
  second.try_close().unwrap()
}

///|
test "returned original backing loan cannot acquire another use" {
  let host = prepared_host(64L * page_bytes_ffi())
  host.acquire().unwrap()
  let loan = host.borrow_backing().unwrap()
  host.return_backing_borrow(loan).unwrap()
  assert_true(
    host.require_backing_borrow_current(loan) is Err(@bootstrap.AlreadyConsumed),
  )
  assert_true(
    host.return_backing_borrow(loan) is Err(@bootstrap.AlreadyConsumed),
  )
  host.try_close().unwrap()
}

///|
test "unacquired original intent cannot lend physical backing" {
  let host = prepared_host(64L * page_bytes_ffi())
  assert_true(host.borrow_backing() is Err(@bootstrap.Unavailable))
  host.try_close().unwrap()
}

///|
// The existing 64-page arena fixture exercises physical scope, not VM funding.
test "active original scope prevents loan return and closes after same leave" {
  let host = prepared_host(64L * page_bytes_ffi())
  host.acquire().unwrap()
  let loan = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(loan).unwrap()
  assert_true(
    host.return_backing_borrow(loan) is Err(@bootstrap.ReadersPending),
  )
  assert_true(host.try_close() is Err(@bootstrap.ReadersPending))
  assert_true(host.enter_backing_borrow_scope(loan) is Err(@bootstrap.Closing))
  host.leave_backing_borrow_scope(loan).unwrap()
  host.return_backing_borrow(loan).unwrap()
  host.try_close().unwrap()
  assert_true(host.closed)
}

///|
test "nested original scopes require every physical leave before return" {
  let host = prepared_host(64L * page_bytes_ffi())
  host.acquire().unwrap()
  let loan = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(loan).unwrap()
  host.enter_backing_borrow_scope(loan).unwrap()
  host.leave_backing_borrow_scope(loan).unwrap()
  assert_true(
    host.return_backing_borrow(loan) is Err(@bootstrap.ReadersPending),
  )
  host.leave_backing_borrow_scope(loan).unwrap()
  assert_true(
    host.leave_backing_borrow_scope(loan) is Err(@bootstrap.AlreadyConsumed),
  )
  host.return_backing_borrow(loan).unwrap()
  assert_true(
    host.enter_backing_borrow_scope(loan) is Err(@bootstrap.AlreadyConsumed),
  )
  host.try_close().unwrap()
}

///|
test "foreign nominal loan cannot enter or leave original physical scope" {
  let first = prepared_host(64L * page_bytes_ffi())
  let second = prepared_host(64L * page_bytes_ffi())
  first.acquire().unwrap()
  second.acquire().unwrap()
  let loan = first.borrow_backing().unwrap()
  first.enter_backing_borrow_scope(loan).unwrap()
  assert_true(
    second.enter_backing_borrow_scope(loan) is Err(@bootstrap.ForeignOriginal),
  )
  assert_true(
    second.leave_backing_borrow_scope(loan) is Err(@bootstrap.ForeignOriginal),
  )
  first.leave_backing_borrow_scope(loan).unwrap()
  first.return_backing_borrow(loan).unwrap()
  first.try_close().unwrap()
  second.try_close().unwrap()
}

///|
test "foreign active allocator rejects scope without consuming the new loan" {
  let first = prepared_host(64L * page_bytes_ffi())
  let second = prepared_host(64L * page_bytes_ffi())
  first.acquire().unwrap()
  second.acquire().unwrap()
  let a = first.borrow_backing().unwrap()
  let b = second.borrow_backing().unwrap()
  first.enter_backing_borrow_scope(a).unwrap()
  assert_true(
    second.enter_backing_borrow_scope(b) is Err(@bootstrap.Physical(_)),
  )
  assert_true(
    second.leave_backing_borrow_scope(b) is Err(@bootstrap.AlreadyConsumed),
  )
  first.leave_backing_borrow_scope(a).unwrap()
  second.enter_backing_borrow_scope(b).unwrap()
  second.leave_backing_borrow_scope(b).unwrap()
  first.return_backing_borrow(a).unwrap()
  second.return_backing_borrow(b).unwrap()
  first.try_close().unwrap()
  second.try_close().unwrap()
}

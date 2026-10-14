///|
// Prepared matching Native cases. No C callback or installed VM is executed by
// merely recording these assertions; reuse the original 64-page fixture.
test "backing reply refuses unacquired intent without fabricating a loan" {
  let host = prepared_host(64L * page_bytes_ffi())
  let reply = borrow_installed_arena_backing_reply(host)
  assert_eq(reply.operation_tag(), 1)
  assert_eq(reply.issue_family(), 1)
  assert_true(reply.original_loan() is None)
  guard reply.original_host() is Some(same) else {
    abort("original intent custody is missing")
  }
  assert_true(physical_equal(same, host))
  host.try_close().unwrap()
}

///|
test "backing reply foreign refusal retains the true loan and original" {
  let first = prepared_host(64L * page_bytes_ffi())
  let second = prepared_host(64L * page_bytes_ffi())
  first.acquire().unwrap()
  second.acquire().unwrap()
  let acquired = borrow_installed_arena_backing_reply(first)
  assert_eq(acquired.issue_family(), 0)
  guard acquired.original_loan() is Some(loan) else {
    abort("original backing loan is missing")
  }
  let observed = current_installed_arena_backing_reply(second, loan)
  let returned = return_installed_arena_backing_reply(second, loan)
  assert_eq(observed.operation_tag(), 2)
  assert_eq(returned.operation_tag(), 3)
  for refused in [observed, returned] {
    assert_eq(refused.issue_family(), 2)
    guard refused.original_host() is Some(same) else {
      abort("foreign refusal lost original Host custody")
    }
    guard refused.original_loan() is Some(same_loan) else {
      abort("foreign refusal lost original loan custody")
    }
    assert_true(physical_equal(same, first))
    assert_true(physical_equal(same_loan, loan))
  }
  assert_eq(
    current_installed_arena_backing_reply(first, loan).issue_family(),
    0,
  )
  assert_eq(return_installed_arena_backing_reply(first, loan).issue_family(), 0)
  first.try_close().unwrap()
  second.try_close().unwrap()
}

///|
test "backing reply preserves pending close and the same cleanup return" {
  let host = prepared_host(64L * page_bytes_ffi())
  host.acquire().unwrap()
  let acquired = borrow_installed_arena_backing_reply(host)
  guard acquired.original_loan() is Some(loan) else {
    abort("original backing loan is missing")
  }
  assert_eq(close_installed_arena_reply(host).issue_family(), 5)
  assert_false(host.closed)
  assert_eq(current_installed_arena_backing_reply(host, loan).issue_family(), 4)
  let returned = return_installed_arena_backing_reply(host, loan)
  assert_eq(returned.issue_family(), 0)
  assert_false(host.closed)
  guard returned.original_loan() is Some(same) else {
    abort("return result lost its original loan identity")
  }
  assert_true(physical_equal(same, loan))
  assert_eq(return_installed_arena_backing_reply(host, loan).issue_family(), 3)
  assert_eq(close_installed_arena_reply(host).issue_family(), 0)
  assert_true(host.closed)
}

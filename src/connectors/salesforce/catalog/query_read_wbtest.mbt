///|
fn query_read_test() -> QueryRead {
  begin_query_read(query_test_plan(), "v62.0", query_test_limits(), 3, 4L).unwrap()
}

///|
test "query read follows only the locator chain of its initial query" {
  let read = query_read_test()
  let first = query_read_next_path(read).unwrap()
  assert_eq(first, "/services/data/v62.0/query?q=SELECT%20Id%20FROM%20Account")
  let first_body =
    #|{"totalSize":2,"done":false,"nextRecordsUrl":"/services/data/v62.0/query/01gABC-2000","records":[{"Id":"001A"}]}
  let first_page = query_read_accept_page(read, first, @utf8.encode(first_body)).unwrap()
  assert_eq(query_page_row_count(first_page), 1)
  assert_eq(query_read_next_path(read), None)
  assert_eq(query_read_page_count(read), 0)
  acknowledge_query_page(read, first_page).unwrap()
  assert_eq(query_read_page_count(read), 1)
  assert_eq(query_read_row_count(read), 1L)
  assert_false(query_read_complete(read))
  let second = query_read_next_path(read).unwrap()
  assert_eq(second, "/services/data/v62.0/query/01gABC-2000")
  let last_body =
    #|{"totalSize":2,"done":true,"records":[{"Id":"001B"}]}
  let last_page = query_read_accept_page(read, second, @utf8.encode(last_body)).unwrap()
  assert_false(query_read_complete(read))
  acknowledge_query_page(read, last_page).unwrap()
  assert_true(query_read_complete(read))
  assert_eq(query_read_page_count(read), 2)
  assert_eq(query_read_row_count(read), 2L)
  assert_eq(query_read_next_path(read), None)
  assert_true(
    query_read_accept_page(read, first, @utf8.encode(first_body))
    is Err(AlreadyFinished),
  )
}

///|
test "query read cannot replace a failed locator request with a new query" {
  let read = query_read_test()
  let initial = query_read_next_path(read).unwrap()
  let body =
    #|{"totalSize":2,"done":false,"nextRecordsUrl":"/services/data/v62.0/query/01gABC-2000","records":[{"Id":"001A"}]}
  let page = query_read_accept_page(read, initial, @utf8.encode(body)).unwrap()
  assert_true(
    query_read_accept_page(read, initial, @utf8.encode(body))
    is Err(PageAwaitingConsumption),
  )
  acknowledge_query_page(read, page).unwrap()
  assert_true(
    query_read_accept_page(read, initial, @utf8.encode(body))
    is Err(WrongRequest),
  )
  assert_eq(query_read_next_path(read), None)
  assert_false(query_read_complete(read))
  assert_true(
    query_read_accept_page(
      read,
      "/services/data/v62.0/query/01gABC-2000",
      @utf8.encode(body),
    )
    is Err(Interrupted),
  )
}

///|
test "query read enforces page and total row budgets before completion" {
  let read = begin_query_read(
    query_test_plan(),
    "v62.0",
    query_test_limits(),
    1,
    1L,
  ).unwrap()
  let initial = query_read_next_path(read).unwrap()
  let first_body =
    #|{"totalSize":2,"done":false,"nextRecordsUrl":"/services/data/v62.0/query/01gABC-2000","records":[{"Id":"001A"}]}
  let first_page = query_read_accept_page(
    read,
    initial,
    @utf8.encode(first_body),
  ).unwrap()
  acknowledge_query_page(read, first_page).unwrap()
  let locator = query_read_next_path(read).unwrap()
  let last_body =
    #|{"totalSize":2,"done":true,"records":[{"Id":"001B"}]}
  assert_true(
    query_read_accept_page(read, locator, @utf8.encode(last_body))
    is Err(PageLimit),
  )
  assert_false(query_read_complete(read))
  let row_limited = begin_query_read(
    query_test_plan(),
    "v62.0",
    query_test_limits(),
    2,
    0L,
  ).unwrap()
  assert_true(
    query_read_accept_page(
      row_limited,
      query_read_next_path(row_limited).unwrap(),
      @utf8.encode(last_body),
    )
    is Err(RowLimit),
  )
  assert_eq(query_read_row_count(row_limited), 0L)
  assert_false(query_read_complete(row_limited))
}

///|
test "query read interruption is terminal for this observation" {
  let read = query_read_test()
  assert_true(interrupt_query_read(read))
  assert_false(interrupt_query_read(read))
  assert_eq(query_read_next_path(read), None)
  assert_false(query_read_complete(read))
}

///|
test "terminal page is not complete until the consumer acknowledges it" {
  let read = query_read_test()
  let initial = query_read_next_path(read).unwrap()
  let body =
    #|{"totalSize":1,"done":true,"records":[{"Id":"001A"}]}
  let page = query_read_accept_page(read, initial, @utf8.encode(body)).unwrap()
  assert_false(query_read_complete(read))
  assert_eq(query_read_row_count(read), 0L)
  assert_true(
    query_read_accept_page(read, initial, @utf8.encode(body))
    is Err(PageAwaitingConsumption),
  )
  assert_true(interrupt_query_read(read))
  assert_false(query_read_complete(read))
  assert_true(acknowledge_query_page(read, page) is Err(Interrupted))
}

///|
test "query read rejects a page from another observation" {
  let first = query_read_test()
  let second = query_read_test()
  let body =
    #|{"totalSize":1,"done":true,"records":[{"Id":"001A"}]}
  let first_page = query_read_accept_page(
    first,
    query_read_next_path(first).unwrap(),
    @utf8.encode(body),
  ).unwrap()
  let second_page = query_read_accept_page(
    second,
    query_read_next_path(second).unwrap(),
    @utf8.encode(body),
  ).unwrap()
  assert_true(acknowledge_query_page(first, second_page) is Err(WrongPage))
  assert_false(query_read_complete(first))
  acknowledge_query_page(first, first_page).unwrap()
  assert_true(query_read_complete(first))
}

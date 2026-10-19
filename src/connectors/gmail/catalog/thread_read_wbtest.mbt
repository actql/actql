///|
fn thread_read() -> GmailThreadRead {
  prepare_gmail_thread_read(
    "original@example.com",
    thread_list_limits(),
    thread_limits(),
    3,
    10,
  ).unwrap()
}

///|
test "Gmail list continuation and dependent gets preserve exact nominal request occurrences" {
  let read = thread_read()
  let first = next_gmail_thread_request(read).unwrap().unwrap()
  assert_true(gmail_thread_request_is_list(first))
  assert_eq(gmail_thread_request_mailbox(first), "original@example.com")
  assert_eq(gmail_thread_request_ordinal(first), 0)
  assert_eq(gmail_thread_request_page_token(first), None)
  assert_true(next_gmail_thread_request(read) is Err(ForeignRequest))
  ignore(
    accept_gmail_thread_list(
      read, first, b"{\"nextPageToken\":\"opaque/+\",\"threads\":[]}",
    ).unwrap(),
  )
  assert_true(!gmail_thread_read_completed(read))
  let second = next_gmail_thread_request(read).unwrap().unwrap()
  assert_eq(gmail_thread_request_page_token(second), Some("opaque/+"))
  ignore(
    accept_gmail_thread_list(read, second, b"{\"threads\":[{\"id\":\"t/+\"}]}").unwrap(),
  )
  let get = next_gmail_thread_request(read).unwrap().unwrap()
  assert_true(!gmail_thread_request_is_list(get))
  assert_eq(gmail_thread_request_ordinal(get), 2)
  assert_eq(gmail_thread_request_target_id(get), Some("t/+"))
  let row = accept_gmail_thread(read, get, b"{\"id\":\"t/+\",\"messages\":[]}").unwrap()
  assert_true(gmail_thread_projection_matches_request(row, get))
  assert_true(!gmail_thread_projection_matches_request(row, first))
  assert_true(next_gmail_thread_request(read).unwrap() is None)
  assert_true(gmail_thread_read_completed(read))
  assert_true(next_gmail_thread_request(read) is Err(ForeignRequest))
}

///|
test "Gmail foreign equal requests cannot consume another read or replay response occurrences" {
  let a = thread_read()
  let b = thread_read()
  let ar = next_gmail_thread_request(a).unwrap().unwrap()
  let br = next_gmail_thread_request(b).unwrap().unwrap()
  assert_true(accept_gmail_thread_list(a, br, b"{}") is Err(ForeignRequest))
  assert_true(gmail_thread_request_matches(a, ar))
  ignore(accept_gmail_thread_list(a, ar, b"{}").unwrap())
  assert_true(accept_gmail_thread_list(a, ar, b"{}") is Err(ForeignRequest))
  assert_true(gmail_thread_request_matches(b, br))
  close_gmail_thread_read(b)
  assert_true(!gmail_thread_request_matches(b, br))
  assert_true(accept_gmail_thread_list(b, br, b"{}") is Err(ForeignRequest))
}

///|
test "Gmail repeated cross-page tokens and IDs consume the failed pending occurrence" {
  for
    body in [
      b"{\"nextPageToken\":\"next\"}", b"{\"threads\":[{\"id\":\"t/+\"}]}",
    ] {
    let read = thread_read()
    let first = next_gmail_thread_request(read).unwrap().unwrap()
    ignore(
      accept_gmail_thread_list(
        read, first, b"{\"threads\":[{\"id\":\"t/+\"}],\"nextPageToken\":\"next\"}",
      ).unwrap(),
    )
    let get = next_gmail_thread_request(read).unwrap().unwrap()
    ignore(
      accept_gmail_thread(read, get, b"{\"id\":\"t/+\",\"messages\":[]}").unwrap(),
    )
    let next = next_gmail_thread_request(read).unwrap().unwrap()
    assert_true(accept_gmail_thread_list(read, next, body) is Err(_))
    assert_true(!gmail_thread_request_matches(read, next))
    assert_true(next_gmail_thread_request(read) is Err(ForeignRequest))
  }
}

///|
test "Gmail malformed dependent get refuses without a replacement target or partial completion" {
  let read = thread_read()
  let list = next_gmail_thread_request(read).unwrap().unwrap()
  ignore(
    accept_gmail_thread_list(
      read, list, b"{\"threads\":[{\"id\":\"t/+\"},{\"id\":\"later\"}]}",
    ).unwrap(),
  )
  let get = next_gmail_thread_request(read).unwrap().unwrap()
  assert_true(
    accept_gmail_thread(read, get, b"{\"id\":\"t/+\"}")
    is Err(InvalidThread(InvalidCell("messages"))),
  )
  assert_true(
    accept_gmail_thread(read, get, b"{\"id\":\"t/+\",\"messages\":[]}")
    is Err(ForeignRequest),
  )
  assert_true(next_gmail_thread_request(read) is Err(ForeignRequest))
  assert_true(!gmail_thread_read_completed(read))
}

///|
test "Gmail list and dependent request bounds fail closed at the original finite extent" {
  let read = prepare_gmail_thread_read(
    "a@example.com",
    thread_list_limits(),
    thread_limits(),
    1,
    0,
  ).unwrap()
  let request = next_gmail_thread_request(read).unwrap().unwrap()
  ignore(
    accept_gmail_thread_list(read, request, b"{\"nextPageToken\":\"next\"}").unwrap(),
  )
  assert_true(next_gmail_thread_request(read) is Err(BudgetExceeded))
  let read = prepare_gmail_thread_read(
    "a@example.com",
    thread_list_limits(),
    thread_limits(),
    1,
    0,
  ).unwrap()
  let request = next_gmail_thread_request(read).unwrap().unwrap()
  assert_true(
    accept_gmail_thread_list(read, request, b"{\"threads\":[{\"id\":\"t\"}]}")
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_gmail_thread_read(
      "a@example.com",
      thread_list_limits(),
      { ..thread_limits(), max_value_nodes: 0, },
      1,
      0,
    )
    is Err(InvalidLimits),
  )
}

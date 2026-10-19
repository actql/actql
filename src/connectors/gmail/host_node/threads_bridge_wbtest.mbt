///|
test "Gmail bridge retains original Common list and get occurrences without raw fields" {
  let read = gmail_prepare_thread_read(
    "operator@example.com", 8192, 1024, 16, 100, 128, 128, 20, 100, 100, 1024, 8,
    100, 4096, 3, 20,
  ).unwrap()
  let list = gmail_next_thread_request(read).unwrap()[0]
  assert_true(gmail_thread_request_matches(read, list))
  assert_eq(
    gmail_thread_request_json(list),
    (
      #|{"mailbox":"operator@example.com","ordinal":0,"isList":true,"pageToken":null,"threadId":null}
    ),
  )
  ignore(
    gmail_accept_thread_list(
      read, list, b"{\"threads\":[{\"id\":\"exact/+\"}]}",
    ).unwrap(),
  )
  let get = gmail_next_thread_request(read).unwrap()[0]
  assert_eq(
    gmail_thread_request_json(get),
    (
      #|{"mailbox":"operator@example.com","ordinal":1,"isList":false,"pageToken":null,"threadId":"exact/+"}
    ),
  )
  let thread = gmail_accept_thread(
    read, get, b"{\"id\":\"exact/+\",\"messages\":[]}",
  ).unwrap()
  assert_true(gmail_thread_projection_matches_request(thread, get))
  assert_eq(
    gmail_thread_rows_wire(thread, ["subject", "message_count"], 1024, 20, 8).unwrap(),
    (
      #|[{"subject":null,"message_count":"0"}]
    ),
  )
  assert_eq(gmail_next_thread_request(read).unwrap().length(), 0)
  assert_true(gmail_thread_read_completed(read))
  gmail_close_thread_read(read)
  assert_true(!gmail_thread_request_matches(read, get))
}

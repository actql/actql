///|
test "outbound poll preserves the exact canonical dispatch request" {
  let request = coordinator_request("dispatch-poll", 31)
  let body = remote_poll_dispatch_json(request).unwrap()
  let admitted = admit_remote_poll_dispatch_json(body).unwrap()
  assert_eq(
    dispatch_request_identity(remote_poll_dispatch_request(admitted)),
    dispatch_request_identity(request),
  )
  assert_true(
    admit_remote_poll_dispatch_json(body.replace(old="site-a", new="site-b"))
    is Err(InvalidDispatch),
  )
}

///|
test "outbound query is distinct and not-seen binds the exact request" {
  let request = coordinator_request("dispatch-query", 33)
  let query = remote_poll_query_json(request).unwrap()
  let admitted = admit_remote_poll_operation_json(query).unwrap()
  assert_true(remote_poll_operation_is_query(admitted))
  assert_eq(
    dispatch_request_identity(remote_poll_operation_request(admitted)),
    dispatch_request_identity(request),
  )
  assert_true(admit_remote_poll_dispatch_json(query) is Err(InvalidDispatch))
  let not_seen = remote_poll_not_seen_json(request).unwrap()
  assert_eq(admit_remote_poll_not_seen_json(not_seen, request), Ok(()))
  assert_true(
    admit_remote_poll_not_seen_json(
      not_seen,
      coordinator_request("dispatch-other", 34),
    )
    is Err(InvalidDispatch),
  )
}

///|
test "Site reply is admitted as the same transport observation" {
  let request = coordinator_request("dispatch-reply", 32)
  let site = @site.create_site(
    "site-a",
    1,
    cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  let journal = create_site_dispatch_journal(site, "actql-remote-site/0.1").unwrap()
  let (_, record) = commit_dispatch_acceptance(
    prepare_dispatch_acceptance(journal, request).unwrap(),
    true,
  ).unwrap()
  let body = remote_dispatch_reply_json(record).unwrap()
  let response = admit_remote_dispatch_response_json(
    body,
    request,
    DispatchReply,
  ).unwrap()
  assert_eq(remote_dispatch_response_revision(response), 0)
}

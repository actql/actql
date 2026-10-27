///|
fn terminal_report_request(task : String, dispatch : String) -> DispatchRequest {
  let c = "sha256:" + "a".repeat(64)
  prepare_dispatch_request(
    "holder-test-coordinator", c, task, 1, dispatch, "holder-test-site", 1, c, "local",
    "local/1", "strategy/1", c, c, c, c, c,
  ).unwrap()
}

///|
test "terminal report preserves independently pinned whole inventory and bounded exact wire" {
  let root = terminal_report_request("task_0", "terminal-root")
  let child = terminal_report_request("task_1", "terminal-child")
  let report = prepare_remote_holder_terminal_report(root, [root, child], 20000).unwrap()
  assert_eq(
    remote_holder_terminal_report_identity(report),
    "sha256:a02a89b1f8f9b89752a23991ab2cd570b8a712ab1b76e35f606e4ee8d8ab18a9",
  )
  let body = remote_holder_terminal_report_json(report)
  assert_eq(@utf8.encode(body).length(), 2235)
  let restored = admit_remote_holder_terminal_report_json(body, 2235).unwrap()
  assert_eq(
    remote_holder_terminal_report_identity(restored),
    remote_holder_terminal_report_identity(report),
  )
  assert_true(admit_remote_holder_terminal_report_json(body, 2234) is Err(_))
  let copy = remote_holder_terminal_report_requests(restored)
  copy.clear()
  assert_eq(remote_holder_terminal_report_requests(restored).length(), 2)
  assert_eq(
    dispatch_request_identity(remote_holder_terminal_report_root(restored)),
    dispatch_request_identity(root),
  )
}

///|
test "terminal report refuses foreign duplicate replacement missing root and noncanonical wire" {
  let root = terminal_report_request("task_0", "terminal-root")
  let child = terminal_report_request("task_1", "terminal-child")
  assert_true(
    prepare_remote_holder_terminal_report(root, [child], 20000) is Err(_),
  )
  assert_true(
    prepare_remote_holder_terminal_report(root, [root, root], 20000) is Err(_),
  )
  assert_true(
    prepare_remote_holder_terminal_report(
      root,
      [root, terminal_report_request("task_0", "replacement")],
      20000,
    )
    is Err(_),
  )
  assert_true(
    prepare_remote_holder_terminal_report(
      root,
      [root, request("foreign", 1, 1, "sha256:" + "a".repeat(64))],
      20000,
    )
    is Err(_),
  )
  let body = remote_holder_terminal_report_json(
    prepare_remote_holder_terminal_report(root, [root, child], 20000).unwrap(),
  )
  assert_true(
    admit_remote_holder_terminal_report_json(" " + body, 20000) is Err(_),
  )
  assert_true(
    admit_remote_holder_terminal_report_json(
      body.replace(
        old="\"root_request_cid\":",
        new="\"extra\":true,\"root_request_cid\":",
      ),
      20000,
    )
    is Err(_),
  )
}

///|
test "terminal reply binds exact independently pinned report and root without granting whole Run stop" {
  let root = terminal_report_request("task_0", "terminal-root")
  let report = prepare_remote_holder_terminal_report(
    root,
    [root, terminal_report_request("task_1", "terminal-child")],
    20000,
  ).unwrap()
  let expected = "{\"report_cid\":\"sha256:a02a89b1f8f9b89752a23991ab2cd570b8a712ab1b76e35f606e4ee8d8ab18a9\",\"root_request_cid\":\"sha256:5f6d38607616ba225843f6994a784bed67088719de262294b1dc65e86d8fc594\",\"version\":\"actql-native-holder-terminal-ack/0.1\"}"
  let reply = prepare_remote_holder_terminal_reply(report).unwrap()
  assert_eq(remote_holder_terminal_reply_json(reply), expected)
  assert_true(
    remote_holder_terminal_reply_matches(
      admit_remote_holder_terminal_reply_json(expected, report).unwrap(),
      report,
    ),
  )
  let other = prepare_remote_holder_terminal_report(root, [root], 20000).unwrap()
  assert_false(remote_holder_terminal_reply_matches(reply, other))
  assert_true(
    admit_remote_holder_terminal_reply_json(expected, other) is Err(_),
  )
  assert_true(
    admit_remote_holder_terminal_reply_json(" " + expected, report) is Err(_),
  )
  assert_true(
    admit_remote_holder_terminal_reply_json(
      expected.replace(old="\"version\":", new="\"extra\":true,\"version\":"),
      report,
    )
    is Err(_),
  )
  assert_true(
    admit_remote_holder_terminal_reply_json(
      expected.replace(old="terminal-ack/0.1", new="terminal-ack/9.9"),
      report,
    )
    is Err(_),
  )
}

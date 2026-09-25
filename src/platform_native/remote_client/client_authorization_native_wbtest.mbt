///|
/// Push dispatches the test HTTPS server itself received: its
/// `/remote/received` reply is exactly `{"dispatch":N}`.
fn native_remote_received(client : @http.Client, origin : String) -> Int {
  let response = client.post_json(origin + "/remote/received", b"{}").unwrap()
  guard response.status == 200 else { abort("received count status") }
  let text = @utf8.decode(response.body) catch {
    _ => abort("received count encoding")
  }
  let prefix = "{\"dispatch\":"
  guard text.has_prefix(prefix) && text.has_suffix("}") else {
    abort("received count shape")
  }
  let mut count = 0
  for index in prefix.length()..<(text.length() - 1) {
    let digit = text[index].to_int() - '0'.to_int()
    guard digit >= 0 && digit <= 9 else { abort("received count digit") }
    count = count * 10 + digit
  }
  count
}

///|
/// The Run owner's evaluated authorization over a real HTTPS exchange: every
/// refusal records no intent and reaches no server; an allow sends one.
test "native run-owner gate: refusals reach no server; allow sends one" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(http_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL") is Some(origin) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT") is Some(cert) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY") is Some(key) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_JOURNAL")
    is Some(journal_path) else {
    return
  }
  let client = @http.load_library(http_path)
    .unwrap()
    .create_client(ca, cert, key, 524288L, 2000, 5000)
    .unwrap()
  let journal = @journal.open_coordinator_journal(
    @sqlite.load_library(sqlite_path).unwrap(),
    journal_path + ".authorization",
    1048576L,
    @remote.create_coordinator_dispatch_journal("native-coordinator").unwrap(),
  ).unwrap()
  let url = origin + "/remote/dispatch"
  let request = authorization_request("native-site")
  let other_site = authorization_request("other-site")
  let before = native_remote_received(client, origin)
  let denied = @authorization.runtime_action_for(
    @authorization.evaluate_account(
      authorization_configuration(Deny),
      remote_dispatch_access_tuple("run-owner", request),
    ),
  ).unwrap()
  let no_match = @authorization.runtime_action_for(
    @authorization.evaluate_account(
      authorization_configuration(Allow),
      remote_dispatch_access_tuple("run-owner", other_site),
    ),
  ).unwrap()
  let refusals : Array[(@remote.DispatchRequest, @authorization.RuntimeAction)] = [
    (request, denied),
    (other_site, no_match),
    (request, remote_dispatch_answer(request, Failure(Timeout))),
    // A permit for native-site does not dispatch to another Site.
    (other_site, remote_dispatch_permit(request)),
  ]
  for refusal in refusals {
    let (target, action) = refusal
    guard dispatch(journal, client, url, target, action) is Err(NotAuthorized) else {
      fail("an unauthorized remote dispatch was sent")
    }
    // No durable intent was recorded for the refused dispatch.
    assert_true(journal.require(target) is Err(_))
  }
  assert_eq(native_remote_received(client, origin), before)
  let accepted = dispatch(
    journal,
    client,
    url,
    request,
    remote_dispatch_allow_action(request),
  ).unwrap()
  assert_eq(@remote.remote_dispatch_response_revision(accepted), 0)
  assert_eq(native_remote_received(client, origin), before + 1)
  assert_true(journal.require(request) is Ok(_))
  assert_true(client.close())
  assert_true(journal.close())
}

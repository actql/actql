///|
fn native_remote_cid(fill : String) -> String {
  "sha256:" + fill
}

///|
fn native_remote_request() -> @remote.DispatchRequest {
  @remote.prepare_dispatch_request(
    "native-coordinator",
    native_remote_cid(
      "0000000000000000000000000000000000000000000000000000000000000000",
    ),
    "task-native-remote",
    1,
    "dispatch-native-remote",
    "native-site",
    1,
    native_remote_cid(
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ),
    "local",
    "local/1",
    "strategy/1",
    native_remote_cid(
      "1111111111111111111111111111111111111111111111111111111111111111",
    ),
    native_remote_cid(
      "2222222222222222222222222222222222222222222222222222222222222222",
    ),
    native_remote_cid(
      "3333333333333333333333333333333333333333333333333333333333333333",
    ),
    native_remote_cid(
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    ),
    native_remote_cid(
      "4444444444444444444444444444444444444444444444444444444444444444",
    ),
  ).unwrap()
}

///|
test "native Coordinator persists intent and admitted HTTPS observations" {
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
  let http_library = @http.load_library(http_path).unwrap()
  let client = http_library
    .create_client(ca, cert, key, 524288L, 2000, 5000)
    .unwrap()
  let sqlite_library = @sqlite.load_library(sqlite_path).unwrap()
  let journal = @journal.open_coordinator_journal(
    sqlite_library,
    journal_path,
    1048576L,
    @remote.create_coordinator_dispatch_journal("native-coordinator").unwrap(),
  ).unwrap()
  let request = native_remote_request()
  let accepted = dispatch(journal, client, origin + "/remote/dispatch", request).unwrap()
  assert_eq(@remote.remote_dispatch_response_revision(accepted), 0)
  let status = query(journal, client, origin + "/remote/query", request).unwrap()
  assert_eq(@remote.remote_dispatch_response_kind(status), @remote.StatusReply)
  guard query(journal, client, origin + "/remote/foreign", request)
    is Err(Protocol(_)) else {
    fail("foreign remote response was accepted")
  }
  let recovered = journal.recover_after("").unwrap().unwrap()
  let state = @remote.coordinator_dispatch_record_state_codes(
    @journal.recovered_coordinator_dispatch_record(recovered),
  )
  assert_eq(state[1], "1")
  let reconciled = query(journal, client, origin + "/remote/query", request).unwrap()
  assert_eq(@remote.remote_dispatch_response_revision(reconciled), 0)
  assert_true(client.close())
  assert_true(journal.close())
}

///|
test "native Site polls outbound and durably accepts before acknowledgement" {
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
  let http_library = @http.load_library(http_path).unwrap()
  let client = http_library
    .create_client(ca, cert, key, 131072L, 2000, 5000)
    .unwrap()
  let sqlite_library = @sqlite.load_library(sqlite_path).unwrap()
  let site = @site.create_site(
    "native-site",
    1,
    native_remote_cid(
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ),
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  let journal = @journal.open_journal(
    sqlite_library,
    journal_path + ".site",
    1048576L,
    @remote.create_site_dispatch_journal(site, "actql-remote-site/0.1").unwrap(),
  ).unwrap()
  let request = poll(client, origin + "/outbound/poll").unwrap().unwrap()
  assert_eq(
    @remote.dispatch_request_identity(request),
    @remote.dispatch_request_identity(native_remote_request()),
  )
  let record = acknowledge_acceptance(
    journal,
    client,
    origin + "/outbound/observation",
    request,
  ).unwrap()
  assert_eq(@remote.dispatch_record_revision(record), 0)
  assert_true(journal.close())
  assert_true(client.close())
}

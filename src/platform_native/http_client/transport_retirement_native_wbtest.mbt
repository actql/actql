///|
#borrow(client)
extern "C" fn retirement_fixture_dns_port(client : Client, port : Int) -> Unit = "actql_native_http_test_dns_port"

///|
#borrow(library)
extern "C" fn retirement_fixture_has_tls_cleanup(library : Library) -> Bool = "actql_native_http_test_has_tls_cleanup"

///|
test "completed original easy handles allow checked HTTP Library retirement" {
  let library = load_library_with_custody(
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(256),
  ).unwrap()
  let has_tls_cleanup = retirement_fixture_has_tls_cleanup(library)
  let original = library
    .create_authenticated_client_with_custody(
      @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA").unwrap(),
      MutualTls(
        @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT").unwrap(),
        @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY").unwrap(),
      ),
      64L,
      2000,
      5000,
    )
    .unwrap()
  let url = @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL").unwrap()
  let posted = original.post_json(url + "/probe", b"{}").unwrap()
  assert_eq(posted.status, 200)
  assert_eq(posted.body, b"{\"accepted\":true}")
  let fetched = original
    .request(
      Get,
      url + "/generic-get",
      [{ name: "accept", value: "application/octet-stream", }],
      b"",
    )
    .unwrap()
  assert_eq(fetched.status, 200)
  assert_eq(fetched.body, b"chunk-b")
  // Completion of transport is still not retirement of this Client holder.
  assert_true(library.close_checked() is Err(Transport(_)))
  original.close_checked().unwrap()
  // This waits for the same handles' cleanup, then balances the init and
  // loader references. It is not a whole Host or external resource ACK.
  if has_tls_cleanup {
    assert_true(library.close_checked() is Ok(_))
    library.close_checked().unwrap()
  } else {
    // The ordinary system libcurl has no same-image TLS retirement port.
    // Completed easy/Client cleanup must not fabricate its Library ACK.
    assert_true(library.close_checked() is Err(Transport(_)))
    assert_true(library.close_checked() is Err(Transport(_)))
  }
}

///|
test "TLS image preserves its other Library and reports only its actual cleanup capability" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY").unwrap()
  let first = load_library_with_custody(path, diagnostic_ceiling=Some(256)).unwrap()
  let second = load_library_with_custody(path, diagnostic_ceiling=Some(256)).unwrap()
  let has_tls_cleanup = retirement_fixture_has_tls_cleanup(first)
  assert_eq(retirement_fixture_has_tls_cleanup(second), has_tls_cleanup)
  let request = fn(library : Library, foreign : Library) -> Unit raise {
    let client = library
      .create_authenticated_client_with_custody(
        @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA").unwrap(),
        MutualTls(
          @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT").unwrap(),
          @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY").unwrap(),
        ),
        64L,
        2000,
        5000,
      )
      .unwrap()
    assert_true(client.uses_library(library))
    assert_false(client.uses_library(foreign))
    let response = client
      .post_json(
        @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL").unwrap() + "/probe",
        b"{}",
      )
      .unwrap()
    assert_eq(response.status, 200)
    assert_eq(response.body, b"{\"accepted\":true}")
    client.close_checked().unwrap()
  }
  request(first, second)
  if has_tls_cleanup {
    first.close_checked().unwrap()
  } else {
    assert_true(first.close_checked() is Err(Transport(_)))
  }
  assert_true(!second.version().is_empty())
  request(second, first)
  if has_tls_cleanup {
    second.close_checked().unwrap()
    // Use the actual loader after these original references retire. No flag
    // reset substitutes for an image that OPENSSL_cleanup has stopped.
    let replacement = load_library_with_custody(
      path,
      diagnostic_ceiling=Some(256),
    ).unwrap()
    request(replacement, second)
    replacement.close_checked().unwrap()
  } else {
    assert_true(second.close_checked() is Err(Transport(_)))
    assert_true(first.close_checked() is Err(Transport(_)))
    assert_true(second.close_checked() is Err(Transport(_)))
    assert_true(first.version().is_empty())
    assert_true(second.version().is_empty())
  }
}

///|
test "incremental bearer POST retains the original client until completion or physical cancellation" {
  let library = load_library_with_custody(
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(256),
  ).unwrap()
  let create = () => {
    library
    .create_authenticated_client_with_custody(
      @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA").unwrap(),
      MutualTls(
        @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT").unwrap(),
        @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY").unwrap(),
      ),
      64L,
      2000,
      5000,
    )
    .unwrap()
  }
  let url = @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL").unwrap()
  let secret = @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_SECRET").unwrap()
  println("Native incremental HTTPS image: " + library.version())
  let supported = library.incremental_bearer_post_supported()
  if @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_EXPECT_CARES") is Some(expected) {
    assert_eq(supported, expected == "1")
  }
  let ca = @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA").unwrap()
  if !supported {
    assert_true(
      library.create_projected_bearer_client_with_custody(ca, 64L, 2000, 5000)
      is Err(RefusedBeforeAcquisition(UnsupportedTarget)),
    )
    let original = create()
    // Missing credential would otherwise fail before transport. The resolver
    // refusal must precede acquisition, and leaves no physical child to drain.
    assert_true(
      original.start_bearer_post(
        url + "/incremental-complete",
        [],
        b"{}",
        secret + ".absent",
        9223372036854775807L,
      )
      is Err(UnsupportedTarget),
    )
    assert_true(original.poll_bearer_post() is Err(Closed))
    original.close_checked().unwrap()
    let has_tls_cleanup = retirement_fixture_has_tls_cleanup(library)
    assert_eq(library.close_checked() is Ok(_), has_tls_cleanup)
    return
  }
  // This injected allocation failure acquires the same Client before the
  // CA copy fails. Its first cleanup retry retains that physical original.
  fail_http_constructor_path(library, 1)
  guard library.create_projected_bearer_client_with_custody(ca, 64L, 2000, 5000)
    is Err(CleanupRequired(partial)) else {
    fail("the dedicated constructor lost its original failure custody")
    return
  }
  let partial_client = partial.client.unwrap()
  assert_true(partial_client.uses_library(library))
  fail_http_constructor_retirement(partial_client, 1, 0)
  assert_true(partial.retry_cleanup() is Err(Transport(_)))
  assert_true(
    partial.client is Some(held) && physical_equal(held, partial_client),
  )
  assert_true(physical_equal(partial.retry_cleanup().unwrap(), library))
  assert_true(partial.client is None)
  let create_projected = () => {
    library
    .create_projected_bearer_client_with_custody(ca, 64L, 2000, 5000)
    .unwrap()
  }
  let projected_url = @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_PROJECTED_URL").unwrap() +
    "/incremental-complete"
  let original = create_projected()
  let start = (client : Client, path : String) => {
    client.start_bearer_post(
      url + path,
      [{ name: "content-type", value: "application/json", }],
      b"{\"original\":true}",
      secret,
      9223372036854775807L,
    )
  }
  let fixture = @filesystem.open_root(
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_INCREMENTAL_ROOT").unwrap(),
  ).unwrap()
  let credential = fixture
    .adopt_private_file_projection("credential.secret")
    .unwrap()
  let write_fixture_key = (bytes : Bytes) => {
    let writer = fixture
      .create_writer("alternate.stage", bytes.length().to_int64())
      .unwrap()
    writer.append(bytes).unwrap()
    writer.seal("alternate.secret").unwrap()
  }
  let old = write_fixture_key(b"native-secret\n")
  let stale = fixture.adopt_private_file_projection("alternate.secret").unwrap()
  fixture.reclaim_generation("alternate.secret", old).unwrap()
  ignore(write_fixture_key(b"forged-secret\n"))
  let refused = create_projected()
  let payload = b"{\"original\":true}"
  assert_true(original.post_json(projected_url, payload) is Err(InvalidRequest))
  assert_true(
    original.request(Post, projected_url, [], payload) is Err(InvalidRequest),
  )
  assert_true(
    original.start_bearer_post(
      projected_url,
      [],
      payload,
      secret,
      9223372036854775807L,
    )
    is Err(InvalidRequest),
  )
  assert_true(
    refused.start_projected_bearer_post(
      projected_url, payload, stale, 9223372036854775807L,
    )
    is Err(CredentialUnavailable),
  )
  assert_true(refused.poll_bearer_post() is Err(Closed))
  refused.close_bearer_post_in_original_scope().unwrap()
  refused.close_bearer_post_in_original_scope().unwrap()
  original
  .start_projected_bearer_post(
    projected_url, payload, credential, 9223372036854775807L,
  )
  .unwrap()
  assert_true(
    original.start_projected_bearer_post(
      projected_url, payload, credential, 9223372036854775807L,
    )
    is Err(Closed),
  )
  assert_true(
    original.poll_bearer_post(wait_milliseconds=51) is Err(InvalidRequest),
  )
  let mut observed = None
  let sizes = FixedArray::make(2, -1L)
  for _ in 0..<100 {
    if original.poll_measured_bearer_post(sizes, wait_milliseconds=50).unwrap()
      is Some(value) {
      observed = Some(value)
      break
    }
    assert_eq((sizes[0], sizes[1]), (-1L, -1L))
  }
  assert_eq(observed.unwrap().status, 503)
  assert_eq(observed.unwrap().body, b"{\"unavailable\":true}")
  assert_eq((sizes[0], sizes[1]), (17L, 20L))
  assert_true(original.poll_measured_bearer_post(sizes) is Err(Closed))
  assert_eq((sizes[0], sizes[1]), (-1L, -1L))
  original.close_checked().unwrap()

  let interrupted = create()
  start(interrupted, "/incremental-stop").unwrap()
  for _ in 0..<100 {
    if fixture.observe_file("incremental-entered") is Ok(_) {
      break
    }
    assert_true(
      interrupted
      .poll_measured_bearer_post(sizes, wait_milliseconds=50)
      .unwrap()
      is None,
    )
    assert_eq((sizes[0], sizes[1]), (-1L, -1L))
  }
  assert_true(fixture.observe_file("incremental-entered") is Ok(_))
  fixture.close().unwrap()
  assert_true(interrupted.close_checked() is Err(Transport(_)))
  interrupted.close_bearer_post_in_original_scope().unwrap()
  interrupted.close_bearer_post_in_original_scope().unwrap()
  assert_true(interrupted.poll_bearer_post() is Err(Closed))
  assert_true(start(interrupted, "/incremental-stop") is Err(Closed))
  let has_tls_cleanup = retirement_fixture_has_tls_cleanup(library)
  assert_eq(library.close_checked() is Ok(_), has_tls_cleanup)
}

///|
test "incremental bearer POST retires its original on pending DNS cancellation and libcurl timeout" {
  let library = load_library_with_custody(
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(256),
  ).unwrap()
  let has_tls_cleanup = retirement_fixture_has_tls_cleanup(library)
  if library.incremental_bearer_post_supported() {
    retirement_fixture_check_dns(library, "cancel", 5000)
    retirement_fixture_check_dns(library, "timeout", 800)
  }
  assert_eq(library.close_checked() is Ok(_), has_tls_cleanup)
}

///|
fn retirement_fixture_check_dns(
  library : Library,
  scenario : String,
  timeout_ms : Int,
) -> Unit raise {
  let environment = name => {
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_" + name).unwrap()
  }
  let client = library
    .create_authenticated_client_with_custody(
      environment("CA"),
      MutualTls(environment("CERT"), environment("KEY")),
      64L,
      timeout_ms,
      timeout_ms,
    )
    .unwrap()
  let mut port = 0
  for ch in environment("DNS_PORT") {
    assert_true(ch >= '0' && ch <= '9' && port <= 6553)
    port = port * 10 + ch.to_int() - '0'.to_int()
  }
  retirement_fixture_dns_port(client, port)
  let url = "https://" +
    scenario +
    ".model.test:" +
    environment("TLS_PORT") +
    "/incremental-complete"
  let secret = environment("SECRET")
  let started = @env.now().reinterpret_as_int64()
  // The credential deadline is deliberately later than the libcurl timeout.
  // The timeout case must enter libcurl's own completion/teardown path.
  client
  .start_bearer_post(url, [], b"{}", secret, 9223372036854775807L)
  .unwrap()
  let root = @filesystem.open_root(environment("INCREMENTAL_ROOT")).unwrap()
  for _ in 0..<15 {
    if root.observe_file(scenario + "-dns") is Ok(_) {
      break
    }
    assert_true(client.poll_bearer_post(wait_milliseconds=40).unwrap() is None)
  }
  assert_true(root.observe_file(scenario + "-dns") is Ok(_))
  root.close().unwrap()
  if scenario == "cancel" {
    assert_true(client.cancel())
    assert_true(client.close_checked() is Err(Transport(_)))
    let pending = @env.now().reinterpret_as_int64()
    assert_true(client.poll_bearer_post() is Err(Cancelled))
    assert_true(@env.now().reinterpret_as_int64() - pending < 500L)
  } else {
    let mut timed_out = false
    for _ in 0..<40 {
      match client.poll_bearer_post(wait_milliseconds=50) {
        Ok(None) => ()
        Err(DeadlineExpired) => {
          timed_out = true
          break
        }
        _ => fail("pending DNS must reach the original libcurl deadline")
      }
    }
    assert_true(timed_out)
    assert_true(@env.now().reinterpret_as_int64() - started < 2000L)
  }
  client.close_checked().unwrap()
  assert_true(client.poll_bearer_post() is Err(Closed))
  assert_true(
    client.start_bearer_post(url, [], b"{}", secret, 9223372036854775807L)
    is Err(Closed),
  )
}

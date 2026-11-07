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
  let request = fn(library : Library) -> Unit raise {
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
  request(first)
  if has_tls_cleanup {
    first.close_checked().unwrap()
  } else {
    assert_true(first.close_checked() is Err(Transport(_)))
  }
  assert_true(!second.version().is_empty())
  request(second)
  if has_tls_cleanup {
    second.close_checked().unwrap()
    // Use the actual loader after these original references retire. No flag
    // reset substitutes for an image that OPENSSL_cleanup has stopped.
    let replacement = load_library_with_custody(
      path,
      diagnostic_ceiling=Some(256),
    ).unwrap()
    request(replacement)
    replacement.close_checked().unwrap()
  } else {
    assert_true(second.close_checked() is Err(Transport(_)))
    assert_true(first.close_checked() is Err(Transport(_)))
    assert_true(second.close_checked() is Err(Transport(_)))
    assert_true(first.version().is_empty())
    assert_true(second.version().is_empty())
  }
}

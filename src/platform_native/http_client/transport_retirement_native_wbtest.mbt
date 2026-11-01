///|
test "completed original easy handles allow checked HTTP Library retirement" {
  let library = load_library_with_custody(
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(256),
  ).unwrap()
  let original = library
    .create_authenticated_client_with_custody(
      @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA").unwrap(),
      Bearer(@env.get_env_var("ACTQL_TEST_NATIVE_HTTP_SECRET").unwrap()),
      64L,
      2000,
      5000,
    )
    .unwrap()
  let url = @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL").unwrap()
  let posted = original.post_json(url + "/probe", b"{}").unwrap()
  assert_eq(posted.status, 200)
  assert_eq(posted.body, b"{\"accepted\":true}")
  let fetched = original.request(Get, url + "/probe", [], b"").unwrap()
  assert_eq(fetched.status, 200)
  assert_eq(fetched.body, b"{\"accepted\":true}")
  // Completion of transport is still not retirement of this Client holder.
  assert_true(library.close_checked() is Err(Transport(_)))
  original.close_checked().unwrap()
  // This waits for the same handles' cleanup, then balances the init and
  // loader references. It is not a whole Host or external resource ACK.
  assert_true(library.close_checked() is Ok(_))
  library.close_checked().unwrap()
}

///|
test "TLS image remains current for its other Library and can reload after the final release" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY").unwrap()
  let first = load_library_with_custody(path, diagnostic_ceiling=Some(256)).unwrap()
  let second = load_library_with_custody(path, diagnostic_ceiling=Some(256)).unwrap()
  let request = fn(library : Library) -> Unit raise {
    let client = library
      .create_authenticated_client_with_custody(
        @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA").unwrap(),
        Bearer(@env.get_env_var("ACTQL_TEST_NATIVE_HTTP_SECRET").unwrap()),
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
  first.close_checked().unwrap()
  assert_true(!second.version().is_empty())
  request(second)
  second.close_checked().unwrap()
  // OPENSSL_cleanup cannot be undone by clearing a flag. This next acquisition
  // must use a genuinely reloaded image after both original references retire.
  let replacement = load_library_with_custody(
    path,
    diagnostic_ceiling=Some(256),
  ).unwrap()
  request(replacement)
  replacement.close_checked().unwrap()
}

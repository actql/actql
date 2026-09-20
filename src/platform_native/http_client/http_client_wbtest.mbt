///|
test "native HTTPS loader rejects a missing runtime library" {
  guard load_library("/actql/missing/libcurl") is Err(LibraryLoad(_)) else {
    fail("missing HTTPS runtime library was accepted")
  }
}

///|
test "native HTTPS client validates bounded configuration in MoonBit" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(path) else {
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
  let library = load_library(path).unwrap()
  guard library.create_client(ca, cert, key, 2147483648L, 2000, 5000)
    is Err(InvalidConfiguration) else {
    fail("unrepresentable HTTPS response bound was accepted")
  }
  guard library.create_client(ca, cert, key, 64L, 5000, 2000)
    is Err(InvalidConfiguration) else {
    fail("HTTP operation timeout shorter than connect timeout was accepted")
  }
}

///|
test "native HTTPS client verifies mTLS and bounds response bytes" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL") is Some(url) else {
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
  let library = load_library(path).unwrap()
  assert_true(!library.version().is_empty())
  let client = library.create_client(ca, cert, key, 64L, 2000, 5000).unwrap()
  let response = client.post_json(url + "/probe", b"{\"probe\":true}").unwrap()
  assert_eq(response.status, 200)
  assert_eq(response.body, b"{\"accepted\":true}")
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_SECRET") is Some(secret) else {
    return
  }
  let authorized = client.get_bearer_file(url + "/credential", secret).unwrap()
  assert_eq(authorized.status, 200)
  assert_eq(authorized.body, b"{\"authorized\":true}")
  assert_true(client.close())
  assert_true(!client.close())
  guard client.post_json(url + "/probe", b"{}") is Err(Closed) else {
    fail("closed HTTPS client accepted another request")
  }
  guard client.get_bearer_file(url + "/credential", secret) is Err(Closed) else {
    fail("closed HTTPS client accepted a credential request")
  }
  let bounded = library.create_client(ca, cert, key, 4L, 2000, 5000).unwrap()
  guard bounded.post_json(url + "/probe", b"{}") is Err(CapacityExceeded) else {
    fail("oversized HTTPS response was accepted")
  }
  ignore(bounded.close())
  let cancelled = library.create_client(ca, cert, key, 64L, 2000, 5000).unwrap()
  assert_true(cancelled.cancel())
  guard cancelled.post_json(url + "/probe", b"{}") is Err(Cancelled) else {
    fail("cancelled HTTPS client started a request")
  }
  ignore(cancelled.close())
  let disconnected = library
    .create_client(ca, cert, key, 64L, 2000, 5000)
    .unwrap()
  guard disconnected.post_json(url + "/disconnect", b"{}") is Err(Transport(_)) else {
    fail("disconnected HTTPS exchange was accepted")
  }
  ignore(disconnected.close())
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_BAD_CERT") is Some(bad_cert) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_BAD_KEY") is Some(bad_key) else {
    return
  }
  let untrusted = library
    .create_client(ca, bad_cert, bad_key, 64L, 2000, 5000)
    .unwrap()
  guard untrusted.post_json(url + "/probe", b"{}") is Err(Transport(_)) else {
    fail("untrusted client certificate was accepted")
  }
  ignore(untrusted.close())
}

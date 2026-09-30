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
  let uploaded = client
    .request(
      Put,
      url + "/generic-put",
      [
        { name: "content-type", value: "application/octet-stream", },
        { name: "x-actql-test", value: "bounded-chunk", },
      ],
      b"chunk-a",
    )
    .unwrap()
  assert_eq(uploaded.status, 200)
  assert_eq(uploaded.body, b"{\"stored\":7}")
  let downloaded = client
    .request(
      Get,
      url + "/generic-get",
      [{ name: "accept", value: "application/octet-stream", }],
      b"",
    )
    .unwrap()
  assert_eq(downloaded.status, 200)
  assert_eq(downloaded.body, b"chunk-b")
  let empty = client
    .request(
      Post,
      url + "/generic-post-empty",
      [{ name: "content-type", value: "application/json", }],
      b"",
    )
    .unwrap()
  assert_eq(empty.status, 200)
  assert_eq(empty.body, b"{\"empty\":true}")
  guard client.request(
      Put,
      url + "/generic-put",
      [{ name: "Invalid Header", value: "value", }],
      b"chunk-a",
    )
    is Err(InvalidRequest) else {
    fail("invalid physical header was accepted")
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_SECRET") is Some(secret) else {
    return
  }
  let authorized = client
    .get_bearer_file(url + "/credential", secret, 9223372036854775807L)
    .unwrap()
  assert_eq(authorized.status, 200)
  assert_eq(authorized.body, b"{\"authorized\":true}")
  guard client.get_bearer_file(url + "/credential", secret, 1L)
    is Err(DeadlineExpired) else {
    fail("expired credential deadline started an HTTPS request")
  }
  assert_true(client.close())
  assert_true(!client.close())
  guard client.post_json(url + "/probe", b"{}") is Err(Closed) else {
    fail("closed HTTPS client accepted another request")
  }
  guard client.get_bearer_file(
      url + "/credential",
      secret,
      9223372036854775807L,
    )
    is Err(Closed) else {
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

///|
test "native HTTPS client sends a per-request bearer credential file" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(path) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_BEARER_URL") is Some(url) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_BEARER_FOREIGN_URL")
    is Some(foreign) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_BEARER_ROOT") is Some(root) else {
    return
  }
  let library = load_library(path).unwrap()
  let bearer = fn(name : String) {
    library
    .create_authenticated_client(
      ca,
      Bearer(root + "/" + name),
      256L,
      2000,
      5000,
    )
    .unwrap()
  }
  let control = bearer("control")
  let probes = fn() -> String {
    @utf8.decode_lossy(
      control.post_json(url + "/bearer/probes", b"{}").unwrap().body,
    )
  }
  // Neither a client certificate nor a bearer file is not a configuration.
  guard library.create_authenticated_client(
      ca,
      MutualTls("", ""),
      64L,
      2000,
      5000,
    )
    is Err(InvalidConfiguration) else {
    fail("a client with no authentication was accepted")
  }
  let rotating = bearer("rotating")
  let first = rotating.post_json(url + "/bearer/probe", b"{}").unwrap()
  assert_eq(first.status, 200)
  let put = rotating
    .request(
      Put,
      url + "/bearer/put",
      [{ name: "content-type", value: "application/octet-stream", }],
      b"chunk",
    )
    .unwrap()
  assert_eq(put.status, 200)
  assert_eq(put.body, b"{\"stored\":5}")
  // The configured credential is the only Authorization header.
  guard rotating.request(
      Post,
      url + "/bearer/probe",
      [{ name: "authorization", value: "Bearer other", }],
      b"{}",
    )
    is Err(InvalidRequest) else {
    fail("a caller Authorization header replaced the bearer credential")
  }
  assert_eq(probes(), "{\"probes\":2}")
  // An atomic replacement is used by the very next request.
  assert_eq(
    control.post_json(url + "/bearer/rotate-to-b", b"{}").unwrap().status,
    200,
  )
  assert_eq(
    rotating.post_json(url + "/bearer/probe", b"{}").unwrap().status,
    200,
  )
  // A replacement that is readable by others stops the request; the earlier
  // credential is not reused and nothing is sent.
  assert_eq(
    control.post_json(url + "/bearer/rotate-to-shared-mode", b"{}").unwrap().status,
    200,
  )
  guard rotating.post_json(url + "/bearer/probe", b"{}")
    is Err(CredentialUnavailable) else {
    fail("a shared-mode bearer credential was sent")
  }
  guard rotating.request(Put, url + "/bearer/put", [], b"chunk")
    is Err(CredentialUnavailable) else {
    fail("a shared-mode bearer credential was sent by request")
  }
  assert_eq(probes(), "{\"probes\":3}")
  for
    name in [
      "group-readable", "empty", "oversized", "invalid-characters", "two-newlines",
      "symlink", "missing",
    ] {
    guard bearer(name).post_json(url + "/bearer/probe", b"{}")
      is Err(CredentialUnavailable) else {
      fail("bearer credential file \{name} was sent")
    }
  }
  assert_eq(probes(), "{\"probes\":3}")
  // The size bound admits exactly 4096 token bytes.
  assert_eq(
    bearer("max").post_json(url + "/bearer/max", b"{}").unwrap().status,
    200,
  )
  // Redirects are not followed, so no credential reaches another origin.
  let redirected = control.post_json(url + "/bearer/redirect", b"{}").unwrap()
  assert_eq(redirected.status, 307)
  assert_eq(
    control.post_json(foreign + "/foreign/landing-count", b"{}").unwrap().body,
    b"{\"requests\":0,\"authorized\":0}",
  )
  // A plain-HTTP origin is refused before any request.
  guard control.post_json("http://127.0.0.1:1/bearer/probe", b"{}")
    is Err(InvalidRequest) else {
    fail("a bearer credential was offered to a plain-HTTP origin")
  }
  ignore(control.close())
  ignore(rotating.close())
}

///|
test "native HTTPS client combines a client certificate and a bearer credential" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(path) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL") is Some(url) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT") is Some(cert) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY") is Some(key) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_BEARER_ROOT") is Some(root) else {
    return
  }
  let library = load_library(path).unwrap()
  let both = library
    .create_authenticated_client(
      ca,
      MutualTlsAndBearer(cert, key, root + "/control"),
      64L,
      2000,
      5000,
    )
    .unwrap()
  let response = both.post_json(url + "/both", b"{}").unwrap()
  assert_eq(response.status, 200)
  assert_eq(response.body, b"{\"both\":true}")
  ignore(both.close())
  // Without the client certificate the mutual TLS server refuses the
  // connection, even with a valid bearer credential.
  let bearer_only = library
    .create_authenticated_client(ca, Bearer(root + "/control"), 64L, 2000, 5000)
    .unwrap()
  guard bearer_only.post_json(url + "/both", b"{}") is Err(Transport(_)) else {
    fail("a bearer credential replaced the required client certificate")
  }
  ignore(bearer_only.close())
  let mutual_only = library
    .create_authenticated_client(ca, MutualTls(cert, key), 64L, 2000, 5000)
    .unwrap()
  assert_eq(mutual_only.post_json(url + "/both", b"{}").unwrap().status, 401)
  ignore(mutual_only.close())
}

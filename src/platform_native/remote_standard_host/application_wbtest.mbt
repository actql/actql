///|
fn payload_test_cid(label : String) -> String {
  "sha256:" + @sha.hex(@utf8.encode(label))
}

///|
fn payload_test_request(
  authority : String,
  token : String,
) -> @payload.PublicationPayloadRequest {
  @payload.prepare_publication_payload_request(
    authority,
    payload_test_cid(token + "-attempt"),
    payload_test_cid(token + "-material"),
    payload_test_cid(token + "-definition"),
    payload_test_cid(token + "-relation"),
    payload_test_cid(token + "-schema"),
    payload_test_cid(token + "-ordering"),
    payload_test_cid(token + "-codec"),
    32L,
    1L,
  ).unwrap()
}

///|
test "payload begin cleanup remains attached without a returned writer" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(library_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(parent) else {
    return
  }
  let token = "payload-begin-owner-" + @env.now().to_string()
  let authority = payload_test_cid(token + "-authority")
  let library = @sqlite.load_library(library_path).unwrap()
  let store = @publication_store.open_store(
    library,
    parent + "/" + token,
    authority,
    64L,
    2L,
    65536L,
  ).unwrap()
  let request = payload_test_request(authority, token)
  let writer = store.begin_payload(request).unwrap()
  writer.append(b"partial").unwrap()
  let failure = failed_payload_stream(
    Store(@publication_store.CleanupPending),
    None,
    None,
    Some(store),
    Some(request),
  )
  assert_true(native_remote_standard_payload_failure_cleanup_pending(failure))
  assert_false(retry_native_remote_standard_payload_failure_cleanup(failure))
  assert_true(native_remote_standard_payload_failure_cleanup_pending(failure))
  writer.cancel().unwrap()
  assert_true(retry_native_remote_standard_payload_failure_cleanup(failure))
  assert_false(native_remote_standard_payload_failure_cleanup_pending(failure))
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(store.close().unwrap())
}

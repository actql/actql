///|
fn holder_partial_root_fixture(
  label : String,
) -> (@filesystem.Root, String) raise {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(parent) else {
    fail("selected partial-holder cases require an owned isolated Root")
    abort("missing partial-holder Root")
  }
  let outer = @filesystem.open_root_with_custody(parent).unwrap()
  let name = label + "-" + @env.now().to_string()
  outer.create_directory(name).unwrap() |> ignore
  let path = parent + "/" + name
  let original = outer.open_child(name).unwrap()
  outer.close().unwrap()
  (original, path)
}

///|
test "invalid HTTP settings are Refused only before original output acquisition" {
  let settings : HolderHttpSettings = {
    library_path: "",
    ca_path: "unused-ca",
    authentication: Bearer("unused-token"),
    response_bytes: 1024L,
    connect_ms: 10,
    total_ms: 10,
  }
  assert_true(
    open_holder_partial_http_client(
      new_holder_partial_output_resources(),
      settings,
      true,
    )
    is Err(HolderOutputSetupRefused(_)),
  )
  let (root, _) = holder_partial_root_fixture("pre-http-holder-root")
  let original = new_holder_partial_output_resources()
  original.retained_root = Some(root)
  assert_true(
    open_holder_partial_http_client(original, settings, true)
    is Err(HolderOutputSetupPending(owner, _)) &&
    physical_equal(owner, original),
  )
  assert_true(
    original.retained_root is Some(owner) && physical_equal(owner, root),
  )
  assert_true(retry_partial_holder_output_resources(original))
}

///|
test "partial holder keeps the original failed Root until its checked cleanup" {
  let (outer, path) = holder_partial_root_fixture("failed-holder-root")
  let failure = match @filesystem.open_root_with_custody(path + "/missing") {
    Err(value) => value
    Ok(_) => {
      fail("missing Root admitted")
      abort("unexpected Root")
    }
  }
  let original = new_holder_partial_output_resources()
  original.retained_root = Some(outer)
  original.failed_root = Some(failure)
  assert_true(
    original.failed_root is Some(owner) && physical_equal(owner, failure),
  )
  assert_true(retry_partial_holder_output_resources(original))
  assert_true(original.failed_root is None)
  assert_true(original.retained_root is None)
  assert_true(failure.issue() is @filesystem.RootOpen(_))
  assert_true(retry_partial_holder_output_resources(original))
}

///|
test "partial holder rejects a competing Store without losing earlier Root custody" {
  let (outer, path) = holder_partial_root_fixture("failed-holder-store")
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    fail(
      "selected partial-holder Store case requires the pinned SQLite library",
    )
    abort("missing partial-holder SQLite")
  }
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let occupied = outer
    .acquire_lock_with_custody(".actql-publication.lock")
    .unwrap()
  let failure = match
    @publication_store.open_store_with_custody(
      sqlite,
      path,
      "sha256:" + "a".repeat(64),
      128L,
      4L,
      4096L,
      diagnostic_ceiling=Some(256),
    ) {
    Err(CleanupRequired(value)) => value
    _ => {
      fail("competing Store did not return original cleanup custody")
      abort("unexpected Store")
    }
  }
  let original = new_holder_partial_output_resources()
  original.retained_root = Some(outer)
  original.failed_store = Some(failure)
  assert_true(
    original.failed_store is Some(owner) && physical_equal(owner, failure),
  )
  assert_true(retry_partial_holder_output_resources(original))
  // Retiring the rejected constructor must not unlock the genuine owner.
  let observer = @filesystem.open_root_with_custody(path).unwrap()
  let still_occupied = match
    observer.acquire_lock_with_custody(".actql-publication.lock") {
    Err(value) => value
    Ok(_) => {
      fail("rejected cleanup released the genuine Lock")
      abort("unexpected Lock")
    }
  }
  still_occupied.retry_cleanup().unwrap()
  occupied.close_checked().unwrap()
  observer.close().unwrap()
  assert_true(original.failed_store is None)
  assert_true(original.retained_root is None)
  assert_true(retry_partial_holder_output_resources(original))
}

///|
test "partial holder returns its original Root only after checked HTTP constructor retirement" {
  let (outer, _) = holder_partial_root_fixture("partial-holder-library")
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIFETIME_LIBRARY")
    is Some(http_path) else {
    fail(
      "selected constructor-retirement case requires the pinned lifetime fixture library",
    )
    abort("missing partial-holder HTTP")
  }
  let library = @http.load_library_with_custody(
    http_path,
    diagnostic_ceiling=Some(256),
  ).unwrap()
  let client = library
    .create_authenticated_client_with_custody(
      "fixture-ca-not-read.pem",
      Bearer("fixture-token-not-read"),
      1024L,
      10,
      10,
    )
    .unwrap()
  // Construction performs no credential file read or Provider request.
  let original = new_holder_partial_output_resources()
  original.retained_root = Some(outer)
  original.control_library = Some(library)
  original.control = Some(client)
  // The pinned lifetime fixture advertises thread-safe cleanup and this
  // constructor never enters transport. This checks original loader/init
  // reference retirement only, not resolver exit or a whole Host ACK.
  assert_true(retry_partial_holder_output_resources(original))
  assert_true(original.control is None)
  assert_true(original.control_library is None)
  assert_true(original.retained_root is None)
  assert_true(retry_partial_holder_output_resources(original))
  assert_true(outer.create_directory("retired") is Err(_))
}

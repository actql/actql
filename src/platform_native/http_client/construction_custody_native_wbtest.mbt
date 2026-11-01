///|
#borrow(library)
extern "C" fn fail_http_constructor_path(
  library : Library,
  occurrence : Int,
) -> Unit = "actql_native_http_test_fail_constructor_path"

///|
#borrow(client)
extern "C" fn fail_http_constructor_retirement(
  client : Client,
  failures : Int,
  reply_losses : Int,
) -> Unit = "actql_native_http_test_fail_constructor_retirement"

///|
#borrow(client)
extern "C" fn http_constructor_path_count(client : Client) -> Int = "actql_native_http_test_constructor_path_count"

///|
#borrow(library)
extern "C" fn lose_failed_http_library_close(library : Library) -> Int = "actql_native_http_test_lose_failed_library_close"

///|
fn required_http_custody_library() -> Library {
  // Only construction/metadata are selected; no request, credential file,
  // Provider or replacement runtime is used. Missing required input fails.
  load_library_with_custody(
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(256),
  ).unwrap()
}

///|
fn failed_http_constructor(
  library : Library,
) -> NativeHttpClientCreateFailure raise {
  // Fail the second real path copy, after the actual CA allocation. This is
  // allocator fault injection, not an observed operating-system ENOMEM.
  fail_http_constructor_path(library, 2)
  match
    library.create_authenticated_client_with_custody(
      "/fixture/ca.pem",
      MutualTls("/fixture/cert.pem", "/fixture/key.pem"),
      32L,
      10,
      20,
    ) {
    Err(CleanupRequired(original)) => original
    _ => {
      fail("partial HTTP constructor lost original Client")
      abort("unreachable")
    }
  }
}

///|
test "HTTP construction distinguishes refusal from actual missing-library custody" {
  assert_true(
    load_library_with_custody("", diagnostic_ceiling=Some(256))
    is Err(RefusedBeforeAcquisition(InvalidConfiguration)),
  )
  let original = match
    load_library_with_custody(
      "/actql/missing/custody/libcurl",
      diagnostic_ceiling=Some(256),
    ) {
    Err(CleanupRequired(failure)) => failure
    _ => {
      fail("physical loader entry lost original Library")
      return
    }
  }
  assert_true(original.issue() is LibraryLoad(_))
  assert_true(original.library is Some(_))
  original.retry_cleanup().unwrap()
  assert_true(original.library is None)
  original.retry_cleanup().unwrap()
  assert_true(original.issue() is LibraryLoad(_))
}

///|
test "failed HTTP symbol load retains unknown unload without repeating a consumed handle" {
  // The exact pinned non-curl library is read-only: it lacks curl symbols.
  // The injected loss consumes the actual dlopen handle once, without claiming
  // a kernel dlclose failure or a successful runtime/global-init retirement.
  let original = match
    load_library_with_custody(
      @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_NON_CURL_LIBRARY").unwrap(),
      diagnostic_ceiling=Some(256),
    ) {
    Err(CleanupRequired(failure)) => failure
    _ => {
      fail("required symbol-refusal Library was not retained")
      return
    }
  }
  let library = original.library.unwrap()
  assert_eq(lose_failed_http_library_close(library), 0)
  assert_true(original.retry_cleanup() is Err(Transport(_)))
  assert_true(
    original.library is Some(retained) && physical_equal(retained, library),
  )
  assert_true(original.retry_cleanup() is Err(Transport(_)))
  assert_true(original.issue() is LibraryLoad(_))
}

///|
test "HTTP partial path acquisition retains original metadata through cleanup failure" {
  let library = required_http_custody_library()
  assert_true(
    library.create_authenticated_client_with_custody(
      "/fixture/ca.pem",
      Bearer("/fixture/token"),
      32L,
      20,
      10,
    )
    is Err(RefusedBeforeAcquisition(InvalidConfiguration)),
  )
  let original = failed_http_constructor(library)
  let client = original.client.unwrap()
  assert_eq(http_constructor_path_count(client), 2)
  assert_true(physical_equal(original.original_library, library))
  fail_http_constructor_retirement(client, 1, 0)
  assert_true(original.retry_cleanup() is Err(Transport(_)))
  assert_true(
    original.client is Some(retained) && physical_equal(retained, client),
  )
  assert_eq(http_constructor_path_count(client), 2)
  assert_true(
    client.post_json("https://example.invalid/unused", b"{}") is Err(Closed),
  )
  let retained_library = original.retry_cleanup().unwrap()
  assert_true(physical_equal(retained_library, library))
  assert_true(original.client is None)
  assert_eq(http_constructor_path_count(client), 0)
  ignore(original.retry_cleanup().unwrap())
  assert_true(original.issue() is ClientCreate(_))
  // Client metadata acknowledgement is not Library/global libcurl retirement.
  assert_true(physical_equal(original.original_library, library))
  assert_true(!library.version().is_empty())
  library.close_checked().unwrap()
  library.close_checked().unwrap()
  assert_true(library.version().is_empty())
}

///|
test "HTTP constructor cleanup reply loss observes the same retired metadata before acknowledgement" {
  let library = required_http_custody_library()
  let original = failed_http_constructor(library)
  let client = original.client.unwrap()
  fail_http_constructor_retirement(client, 0, 1)
  assert_true(original.retry_cleanup() is Err(Transport(_)))
  assert_true(original.client is Some(_))
  assert_eq(http_constructor_path_count(client), 0)
  assert_true(original.issue() is ClientCreate(_))
  let retained_library = original.retry_cleanup().unwrap()
  assert_true(physical_equal(retained_library, library))
  assert_true(original.client is None)
  ignore(original.retry_cleanup().unwrap())
  assert_true(original.issue() is ClientCreate(_))
  let positive = library
    .create_authenticated_client_with_custody(
      "/fixture/ca.pem",
      Bearer("/fixture/token"),
      32L,
      10,
      20,
    )
    .unwrap()
  assert_eq(positive.response_limit().unwrap(), 32L)
  positive.close_checked().unwrap()
  assert_false(positive.close())
  assert_true(positive.response_limit() is Err(Closed))
  library.close_checked().unwrap()
}

///|
test "ready HTTP Library retirement waits for its original Client and refuses new children" {
  let library = required_http_custody_library()
  let original = library
    .create_authenticated_client_with_custody(
      "/fixture/ca.pem",
      Bearer("/fixture/token"),
      32L,
      10,
      20,
    )
    .unwrap()
  assert_eq(original.response_limit().unwrap(), 32L)
  // A live original child prevents init/loader retirement. The pending parent
  // also stops new acquisition and request entry without reading credentials.
  assert_true(library.close_checked() is Err(Transport(_)))
  assert_true(library.close_checked() is Err(Transport(_)))
  assert_true(
    library.create_authenticated_client_with_custody(
      "/fixture/ca.pem",
      Bearer("/fixture/token"),
      32L,
      10,
      20,
    )
    is Err(RefusedBeforeAcquisition(Closed)),
  )
  assert_true(
    original.post_json("https://example.invalid/unused", b"{}") is Err(Closed),
  )
  original.close_checked().unwrap()
  original.close_checked().unwrap()
  assert_true(original.response_limit() is Err(Closed))
  library.close_checked().unwrap()
  library.close_checked().unwrap()
}

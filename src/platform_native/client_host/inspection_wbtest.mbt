///|
test "Native Client state inspection distinguishes absence from retained custody" {
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/client-inspection-retained.sqlite3"
  assert_true(
    inspect_native_client_state(library, path, 131072L, 1048576L, 8)
    is Ok(PhysicallyAbsent),
  )
  let database = library.open_database(path, 131072L).unwrap()
  initialize_native_client_epoch_authority(database, epoch_test_crypto()).unwrap()
  initialize_native_client_run_journal(database).unwrap()
  initialize_native_client_submitted_intents(database).unwrap()
  let epoch = database.read("client_submission_epoch", "authority").unwrap()
  let count = database.read("client_run_custody", "issued").unwrap()
  let submitted_count = database
    .read("client_submitted_intent_custody", "issued")
    .unwrap()
  assert_true(
    inspect_native_client_state(library, path, 131072L, 1048576L, 8)
    is Ok(Retained),
  )
  assert_true(
    inspect_native_client_state(library, path, 131072L, 1048576L, 1025)
    is Ok(Retained),
  )
  let after_epoch = database
    .read("client_submission_epoch", "authority")
    .unwrap()
  let after_count = database.read("client_run_custody", "issued").unwrap()
  assert_eq(after_epoch.body, epoch.body)
  assert_eq(after_epoch.revision, epoch.revision)
  assert_eq(after_count.body, count.body)
  assert_eq(after_count.revision, count.revision)
  let after_submitted_count = database
    .read("client_submitted_intent_custody", "issued")
    .unwrap()
  assert_eq(after_submitted_count.body, submitted_count.body)
  assert_eq(after_submitted_count.revision, submitted_count.revision)
  database.close_checked().unwrap()
  assert_true(
    inspect_native_client_state(library, path, 131072L, 1048576L, 8)
    is Ok(Retained),
  )
}

///|
test "Native Client state inspection refuses lost or corrupt custody without repair" {
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/client-inspection-refused.sqlite3"
  let database = library.open_database(path, 131072L).unwrap()
  assert_true(
    inspect_native_client_state(library, path, 131072L, 1048576L, 8)
    is Err(Custody(Epoch(CustodyLost))),
  )
  assert_true(
    database.read("client_submission_epoch", "authority")
    is Err(@sqlite.NotFound),
  )
  initialize_native_client_epoch_authority(database, epoch_test_crypto()).unwrap()
  assert_true(
    inspect_native_client_state(library, path, 131072L, 1048576L, 8)
    is Err(Custody(Run(CustodyLost))),
  )
  assert_true(
    database.read("client_run_custody", "issued") is Err(@sqlite.NotFound),
  )
  initialize_native_client_run_journal(database).unwrap()
  assert_true(
    inspect_native_client_state(library, path, 131072L, 1048576L, 8)
    is Err(Custody(Submission(CustodyLost))),
  )
  assert_true(
    database.read("client_submitted_intent_custody", "issued")
    is Err(@sqlite.NotFound),
  )
  initialize_native_client_submitted_intents(database).unwrap()
  let previous = database.read("client_run_custody", "issued").unwrap()
  database
  .compare_exchange("client_run_custody", "issued", previous.revision, b"1")
  .unwrap()
  |> ignore
  assert_true(
    inspect_native_client_state(library, path, 131072L, 1048576L, 8)
    is Err(Custody(Run(CustodyLost))),
  )
  assert_eq(database.read("client_run_custody", "issued").unwrap().body, b"1")
  database.close_checked().unwrap()
}

///|
test "Native Client state inspection rejects invalid limits before copying" {
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/client-inspection-limits.sqlite3"
  for limits in [(0L, 8), (1048577L, 8), (131072L, 0), (131072L, -1)] {
    assert_true(
      inspect_native_client_state(library, path, limits.0, 1048576L, limits.1)
      is Err(InvalidLimit),
    )
  }
  assert_true(
    inspect_native_client_state(library, path, 131072L, 1048576L, 8)
    is Ok(PhysicallyAbsent),
  )
}

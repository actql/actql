///|
fn original_claim_lookup_database(name : String) -> (Library, Database, String) {
  let library = load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(128),
  ).unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/" +
    name +
    ".sqlite3"
  (library, library.open_database(path, 64L).unwrap(), path)
}

///|
test "original claim lookup absence never consumes an ordinal or another namespace" {
  let (_, database, _) = original_claim_lookup_database("claim-lookup-absent")
  assert_eq(database.lookup_claim_ordinal("grant-a", "use-a").unwrap(), None)
  assert_eq(database.lookup_claim_ordinal("grant-a", "use-a").unwrap(), None)
  assert_true(
    database.claim_ordinal_action("grant-a", "use-a", 2L) is Ok(Fresh(1L)),
  )
  assert_eq(
    database.lookup_claim_ordinal("grant-a", "use-a").unwrap(),
    Some(1L),
  )
  assert_eq(database.lookup_claim_ordinal("grant-b", "use-a").unwrap(), None)
  assert_eq(database.lookup_claim_ordinal("grant-a", "use-b").unwrap(), None)
  assert_true(
    database.claim_ordinal_action("grant-a", "use-b", 2L) is Ok(Fresh(2L)),
  )
  assert_eq(
    database.lookup_claim_ordinal("grant-a", "use-b").unwrap(),
    Some(2L),
  )
  assert_true(
    database.claim_ordinal_action("grant-a", "use-c", 2L)
    is Err(CapacityExceeded),
  )
  assert_eq(database.lookup_claim_ordinal("grant-a", "use-c").unwrap(), None)
  assert_eq(database.capacity_usage("grant-a").unwrap().reserved_objects, 0L)
  database.close_checked().unwrap()
}

///|
test "original claim lookup survives reopen without changing use rows or claim limits" {
  let (library, first, path) = original_claim_lookup_database(
    "claim-lookup-reopen",
  )
  assert_eq(first.claim_ordinal("grant", "same-use", 1L).unwrap(), 1L)
  first.insert("grant", "same-use", b"exact original use bytes").unwrap()
  |> ignore
  let original = first.read("grant", "same-use").unwrap()
  first.close_checked().unwrap()
  let reopened = library.open_existing_database(path, 64L).unwrap()
  for _ in 0..<3 {
    assert_eq(
      reopened.lookup_claim_ordinal("grant", "same-use").unwrap(),
      Some(1L),
    )
    assert_eq(
      reopened.lookup_claim_ordinal("grant", "missing-use").unwrap(),
      None,
    )
  }
  let retained = reopened.read("grant", "same-use").unwrap()
  assert_eq(retained.body, original.body)
  assert_eq(retained.revision, original.revision)
  assert_true(
    reopened.claim_ordinal_action("grant", "same-use", 1L) is Ok(Retained(1L)),
  )
  assert_true(
    reopened.claim_ordinal_action("grant", "missing-use", 1L)
    is Err(CapacityExceeded),
  )
  reopened.close_checked().unwrap()
}

///|
test "original claim lookup preserves the caller transaction and rollback revision" {
  let (library, first, path) = original_claim_lookup_database(
    "claim-lookup-transaction",
  )
  first.claim_ordinal("grant", "original", 2L).unwrap() |> ignore
  first.insert("control", "run", b"original revision").unwrap() |> ignore
  let second = library.open_existing_database(path, 64L).unwrap()
  first.begin_immediate().unwrap()
  first.compare_exchange("control", "run", 0L, b"uncommitted").unwrap()
  |> ignore
  assert_eq(first.lookup_claim_ordinal("grant", "original").unwrap(), Some(1L))
  assert_eq(first.lookup_claim_ordinal("grant", "missing").unwrap(), None)
  assert_eq(second.lookup_claim_ordinal("grant", "original").unwrap(), Some(1L))
  assert_eq(second.read("control", "run").unwrap().body, b"original revision")
  first.rollback().unwrap()
  let original = first.read("control", "run").unwrap()
  assert_eq(original.revision, 0L)
  assert_eq(original.body, b"original revision")
  assert_eq(first.claim_ordinal("grant", "next", 2L).unwrap(), 2L)
  first.close_checked().unwrap()
  second.close_checked().unwrap()
}

///|
test "original claim lookup keeps existing name bounds and closed database refusal" {
  let (_, database, _) = original_claim_lookup_database("claim-lookup-bounds")
  for
    (scope, key) in [
      ("", "use"),
      ("grant", ""),
      ("g".repeat(513), "use"),
      ("grant", "\u00e9".repeat(257)),
    ] {
    assert_true(database.lookup_claim_ordinal(scope, key) is Err(InvalidName))
  }
  assert_eq(
    database
    .lookup_claim_ordinal("g".repeat(512), "\u00e9".repeat(256))
    .unwrap(),
    None,
  )
  assert_eq(database.claim_ordinal("grant", "original", 1L).unwrap(), 1L)
  database.close_checked().unwrap()
  assert_true(
    database.lookup_claim_ordinal("grant", "original") is Err(DatabaseClosed),
  )
}

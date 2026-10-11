///|
fn catalog_use_settled(
  journal : Journal,
  request : @remote.DispatchRequest,
) -> Unit {
  let (_, record) = journal.accept(request).unwrap()
  journal
  .commit_transition(
    @remote.prepare_begin_provisioning(record, test_capability(test_site())).unwrap(),
  )
  .unwrap()
  journal
  .commit_transition(@remote.prepare_begin_remote_execution(record).unwrap())
  .unwrap()
  journal
  .commit_transition(@remote.prepare_confirm_native_settled(record).unwrap())
  .unwrap()
}

///|
test "catalog use journal preserves the original nominal use across reopen and refuses replacements" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(library_path) else {
    fail("actual SQLite required")
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    fail("owned SQLite root required")
  }
  let library = @sqlite.load_library(library_path).unwrap()
  let path = root + "/catalog-use-" + @env.now().to_string() + ".sqlite3"
  let open = () => {
    open_journal(library, path, 262144L, test_control(test_site())).unwrap()
  }
  let journal = open()
  let request = test_request("original-catalog-use")
  let (grant, original) = catalog_use_fixture(request, "original-use")
  catalog_use_settled(journal, request)
  journal.retain_effect_catalog_use(request, grant, original).unwrap()
  journal.retain_effect_catalog_use(request, grant, original).unwrap()
  let (_, replacement) = catalog_use_fixture(request, "replacement-use")
  assert_true(
    journal.retain_effect_catalog_use(request, grant, replacement)
    is Err(StateCollision),
  )
  let foreign_request = test_request("foreign-catalog-use")
  let (foreign_grant, foreign_use) = catalog_use_fixture(
    foreign_request, "original-use",
  )
  assert_true(
    journal.retain_effect_catalog_use(request, foreign_grant, foreign_use)
    is Err(StateCollision),
  )
  assert_true(journal.close())
  let restored = open()
  assert_eq(
    @credential.credential_use_cid(
      restored.effect_catalog_use(request, grant, "original-use").unwrap(),
    ),
    @credential.credential_use_cid(original),
  )
  assert_true(
    restored.effect_catalog_use(request, foreign_grant, "original-use")
    is Err(StateCollision),
  )
  assert_true(
    restored.effect_catalog_use(request, grant, "replacement-use")
    is Err(StateCollision),
  )
  assert_true(restored.close())
}

///|
test "catalog use journal keeps missing and unconfirmed retention distinct from a fresh-read permit" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(library_path) else {
    fail("actual SQLite required")
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    fail("owned SQLite root required")
  }
  let library = @sqlite.load_library(library_path).unwrap()
  let path = root +
    "/catalog-use-failure-" +
    @env.now().to_string() +
    ".sqlite3"
  let journal = open_journal(library, path, 262144L, test_control(test_site())).unwrap()
  let request = test_request("catalog-use-failed-save")
  let (grant, original) = catalog_use_fixture(request, "original-use")
  journal.accept(request).unwrap() |> ignore
  assert_true(
    journal.retain_effect_catalog_use(request, grant, original)
    is Err(StateCollision),
  )
  catalog_use_settled(journal, request)
  assert_true(
    journal.effect_catalog_use(request, grant, "original-use")
    is Err(Physical(@sqlite.NotFound)),
  )
  let lock = library.open_database(path, 262144L).unwrap()
  lock.begin_immediate().unwrap()
  assert_true(
    journal.retain_effect_catalog_use(request, grant, original) is Err(_),
  )
  lock.rollback().unwrap()
  assert_true(
    journal.effect_catalog_use(request, grant, "original-use")
    is Err(Physical(@sqlite.NotFound)),
  )
  journal.retain_effect_catalog_use(request, grant, original).unwrap()
  lock.close()
  assert_true(journal.close())
}

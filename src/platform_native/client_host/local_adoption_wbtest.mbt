///|
let local_selected_account : Bytes = b"{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[]}\r\n"

///|
fn local_selected_source(
  name : String,
) -> (String, String, @filesystem.Root, @filesystem.NativeFileGeneration) {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = @filesystem.open_private_root(path).unwrap()
  let source_name = name + ".account.json"
  let writer = root.create_writer(name + ".account.stage", 4096L).unwrap()
  writer.append(local_selected_account).unwrap()
  let generation = writer.seal(source_name).unwrap()
  (path, source_name, root, generation)
}

///|
test "Native Local adoption retains the original intent and exact selected account after reopen" {
  let (path, source_name, parent, _) = local_selected_source(
    "local-adoption-reopen",
  )
  let crypto = epoch_test_crypto()
  let session = begin_native_local_host_adoption(
    path, "adopted-reopen", path, source_name, "operator", crypto,
  ).unwrap()
  let original = session.intent_cid()
  let original_configuration = session.configuration_cid()
  assert_eq(session.configuration.entry_count(), 0)
  assert_true(
    @authorization.evaluate_account(session.configuration, {
      principal: "operator",
      connection: "fixture",
      resource: "rows",
      operation: "read",
    })
    is Deny(NoMatch),
  )
  session.stage_configuration().unwrap()
  let root = parent.open_child("adopted-reopen").unwrap()
  let (body, generation) = local_adoption_read(root, "account.json", 1048576L).unwrap()
  assert_eq(body, local_selected_account)
  assert_true(session.close())
  assert_true(session.stage_configuration() is Err(Closed))
  let restored = begin_native_local_host_adoption(
    path, "adopted-reopen", path, source_name, "operator", crypto,
  ).unwrap()
  assert_eq(restored.intent_cid(), original)
  assert_eq(restored.configuration_cid(), original_configuration)
  restored.stage_configuration().unwrap()
  assert_eq(root.inspect_generation("account.json").unwrap(), Some(generation))
  assert_eq(
    local_adoption_read(root, "account.json", 1048576L).unwrap().0,
    local_selected_account,
  )
  assert_true(restored.close())
}

///|
test "Native Local adoption resumes a recorded intent before configuration creation" {
  let (path, source_name, parent, _) = local_selected_source(
    "local-adoption-intent",
  )
  let crypto = epoch_test_crypto()
  let session = begin_native_local_host_adoption(
    path, "adopted-intent", path, source_name, "operator", crypto,
  ).unwrap()
  let original = session.intent_cid()
  let root = parent.open_child("adopted-intent").unwrap()
  assert_eq(root.inspect_generation("account.json").unwrap(), None)
  assert_true(session.close())
  let restored = begin_native_local_host_adoption(
    path, "adopted-intent", path, source_name, "operator", crypto,
  ).unwrap()
  assert_eq(restored.intent_cid(), original)
  restored.stage_configuration().unwrap()
  assert_eq(
    local_adoption_read(root, "account.json", 1048576L).unwrap().0,
    local_selected_account,
  )
  assert_true(restored.close())
}

///|
test "Native Local adoption refuses existing private state with missing intent without repair" {
  let (path, source_name, parent, _) = local_selected_source(
    "local-adoption-missing",
  )
  parent.create_directory("adopted-missing").unwrap() |> ignore
  assert_true(
    begin_native_local_host_adoption(
      path,
      "adopted-missing",
      path,
      source_name,
      "operator",
      epoch_test_crypto(),
    )
    is Err(CustodyLost),
  )
  let root = parent.open_child("adopted-missing").unwrap()
  assert_eq(root.inspect_generation("initialization.json").unwrap(), None)
  assert_eq(root.inspect_generation("account.json").unwrap(), None)
}

///|
test "Native Local adoption rejects foreign account and containment escape before state creation" {
  let (path, source_name, parent, _) = local_selected_source(
    "local-adoption-foreign",
  )
  let crypto = epoch_test_crypto()
  assert_true(
    begin_native_local_host_adoption(
      path, "adopted-foreign", path, source_name, "other-account", crypto,
    )
    is Err(ForeignAccount),
  )
  assert_eq(parent.inspect_directory("adopted-foreign").unwrap(), None)
  for invalid in ["..", ".", "../outside", "child/nested", "a\u{0000}b"] {
    assert_true(
      begin_native_local_host_adoption(
        path, invalid, path, source_name, "operator", crypto,
      )
      is Err(InvalidInput),
    )
  }
}

///|
test "Native Local adoption fences concurrent initialization under the existing filesystem lock" {
  let (path, source_name, parent, _) = local_selected_source(
    "local-adoption-concurrent",
  )
  let crypto = epoch_test_crypto()
  let original = begin_native_local_host_adoption(
    path, "adopted-concurrent", path, source_name, "operator", crypto,
  ).unwrap()
  assert_true(
    begin_native_local_host_adoption(
      path, "adopted-concurrent", path, source_name, "operator", crypto,
    )
    is Err(Filesystem(@filesystem.Lock(_))),
  )
  assert_eq(
    parent
    .open_child("adopted-concurrent")
    .unwrap()
    .inspect_generation("account.json")
    .unwrap(),
    None,
  )
  original.stage_configuration().unwrap()
  assert_true(original.close())
}

///|
test "Native Local adoption rejects source replacement even when its bytes are identical" {
  let (path, source_name, parent, generation) = local_selected_source(
    "local-adoption-replaced",
  )
  let crypto = epoch_test_crypto()
  let original = begin_native_local_host_adoption(
    path, "adopted-replaced", path, source_name, "operator", crypto,
  ).unwrap()
  parent.reclaim_generation(source_name, generation).unwrap()
  let replacement = parent
    .create_writer("replaced-source.stage", 4096L)
    .unwrap()
  replacement.append(local_selected_account).unwrap()
  replacement.seal(source_name).unwrap() |> ignore
  assert_true(original.stage_configuration() is Err(SourceChanged))
  assert_eq(
    parent
    .open_child("adopted-replaced")
    .unwrap()
    .inspect_generation("account.json")
    .unwrap(),
    None,
  )
  assert_true(original.close())
  assert_true(
    begin_native_local_host_adoption(
      path, "adopted-replaced", path, source_name, "operator", crypto,
    )
    is Err(SourceChanged),
  )
}

///|
test "Native Local adoption never repairs a lost configuration creation witness" {
  let (path, source_name, parent, _) = local_selected_source(
    "local-adoption-custody",
  )
  let crypto = epoch_test_crypto()
  let original = begin_native_local_host_adoption(
    path, "adopted-custody", path, source_name, "operator", crypto,
  ).unwrap()
  original.stage_configuration().unwrap()
  let root = parent.open_child("adopted-custody").unwrap()
  let account = root.inspect_generation("account.json").unwrap()
  root
  .reclaim_generation(
    "configuration-custody.json",
    root.inspect_generation("configuration-custody.json").unwrap().unwrap(),
  )
  .unwrap()
  assert_true(original.stage_configuration() is Err(AmbiguousInitialization))
  assert_true(original.close())
  let restored = begin_native_local_host_adoption(
    path, "adopted-custody", path, source_name, "operator", crypto,
  ).unwrap()
  assert_true(restored.stage_configuration() is Err(AmbiguousInitialization))
  assert_eq(root.inspect_generation("account.json").unwrap(), account)
  assert_eq(
    root.inspect_generation("configuration-custody.json").unwrap(),
    None,
  )
  assert_true(restored.close())
}

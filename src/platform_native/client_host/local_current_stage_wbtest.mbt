///|
test "Native current staging preserves authentic original rows and current refusal after close" {
  let host = local_journal_test_connection("current-stage-original")
  let expected = [
    host.database.read("client_local_adoption", "adoption").unwrap(),
    host.database.read("client_local_settings", "manifest").unwrap(),
    host.database.read("client_submission_epoch", "authority").unwrap(),
  ]
  let account = host.session.root.inspect_generation("account.json").unwrap()
  assert_true(host.check_binding() is Ok(_))
  assert_true(host.session.stage_configuration() is Ok(_))
  assert_true(host.check_binding() is Ok(_))
  assert_eq(
    host.session.root.inspect_generation("account.json").unwrap(),
    account,
  )
  let actual = [
    host.database.read("client_local_adoption", "adoption").unwrap(),
    host.database.read("client_local_settings", "manifest").unwrap(),
    host.database.read("client_submission_epoch", "authority").unwrap(),
  ]
  for i in 0..<expected.length() {
    assert_eq(actual[i].revision, expected[i].revision)
    assert_true(actual[i].body == expected[i].body)
  }
  host.close().unwrap()
  assert_true(host.check_binding() is Err(Closed))
}

///|
test "Native current staging refuses identical-byte source replacement before retained account use" {
  let host = local_journal_test_connection("current-stage-replaced")
  let source = host.session.source_root
  let name = host.session.source_name
  let expected = host.database
    .read("client_local_adoption", "adoption")
    .unwrap()
  let account = host.session.root.inspect_generation("account.json").unwrap()
  source.reclaim_generation(name, host.session.source_generation).unwrap()
  let replacement = source
    .create_writer("current-stage-replaced.stage", 4096L)
    .unwrap()
  replacement.append(local_selected_account).unwrap()
  replacement.seal(name).unwrap() |> ignore
  assert_true(host.check_binding() is Err(SourceChanged))
  assert_true(host.session.stage_configuration() is Err(SourceChanged))
  assert_true(
    host.database.read("client_local_adoption", "adoption").unwrap().body ==
    expected.body,
  )
  assert_eq(
    host.session.root.inspect_generation("account.json").unwrap(),
    account,
  )
  host.close().unwrap()
}

///|
test "Native current staging preserves original-source refusal priority over missing account custody" {
  let host = local_journal_test_connection("current-stage-priority")
  let account = host.session.root.inspect_generation("account.json").unwrap()
  let witness = host.session.root
    .inspect_generation("configuration-custody.json")
    .unwrap()
    .unwrap()
  host.session.root
  .reclaim_generation("configuration-custody.json", witness)
  .unwrap()
  // With the original source still intact, the existing staging refusal wins.
  assert_true(host.check_binding() is Err(AmbiguousInitialization))
  let source = host.session.source_root
  source
  .reclaim_generation(host.session.source_name, host.session.source_generation)
  .unwrap()
  let replacement = source
    .create_writer("current-stage-priority.stage", 4096L)
    .unwrap()
  replacement.append(local_selected_account).unwrap()
  replacement.seal(host.session.source_name).unwrap() |> ignore
  // Source validation remains before account/custody inspection on both paths.
  assert_true(host.check_binding() is Err(SourceChanged))
  assert_true(host.session.stage_configuration() is Err(SourceChanged))
  assert_eq(
    host.session.root.inspect_generation("account.json").unwrap(),
    account,
  )
  assert_eq(
    host.session.root.inspect_generation("configuration-custody.json").unwrap(),
    None,
  )
  host.close().unwrap()
}

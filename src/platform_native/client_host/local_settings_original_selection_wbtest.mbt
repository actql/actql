///|
// Selected configuration bytes are captured DATA. Their selection cannot
// initialize a Journal or turn changed current state into permission.
test "selected configuration data does not repeat current admission or authorize changed originals" {
  let name = "local-settings-data-original"
  let session = local_settings_fixture(name)
  let file = name + ".settings.json"
  let original = session.selected_configuration(file).unwrap()
  assert_eq(original, local_settings_original)
  let source = session.source_root
  let generation = source.inspect_generation(file).unwrap().unwrap()
  source.reclaim_generation(file, generation).unwrap()
  let replacement = source
    .create_writer(name + ".replace.stage", 65536L)
    .unwrap()
  replacement.append(b"{\"changed\":true}").unwrap()
  replacement.seal(file).unwrap() |> ignore
  // This is an original-value projection, not a fresh file observation. A
  // heavy selected-file read here would fail or return the replacement.
  for _ in 0..<3 {
    assert_eq(session.selected_configuration(file).unwrap(), original)
  }
  assert_true(
    session.selected_configuration("unselected.json") is Err(InvalidInput),
  )
  // The protected operation still observes changed current originals before
  // any account copy, database, schema or epoch can be created.
  assert_true(
    session.open_journal(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    )
    is Err(SourceChanged),
  )
  assert_eq(session.root.inspect_generation("account.json").unwrap(), None)
  assert_eq(session.root.inspect_generation("client.sqlite3").unwrap(), None)
  assert_true(session.close())
  assert_true(session.selected_configuration(file) is Err(Closed))
}

///|
test "selected configuration data preserves the original Reader refusal and cleanup" {
  let name = "local-settings-data-refused"
  let session = local_settings_fixture(name)
  let generation = session.source_root
    .inspect_generation(session.source_name)
    .unwrap()
    .unwrap()
  let refused = match
    session.source_root.open_reader_with_custody(session.source_name, {
      ..generation,
      size: generation.size - 1L,
    }) {
    Err(original) => original
    _ => {
      fail("wrong original Reader accepted")
      return
    }
  }
  session.retain_read_issue(ReadAcquisitionFailure(refused)) |> ignore
  assert_true(
    session.selected_configuration(name + ".settings.json")
    is Err(ReadAcquisitionFailure(original)) &&
    physical_equal(original, refused),
  )
  assert_true(
    session.read_cleanup is Some(ReadAcquisitionFailure(original)) &&
    physical_equal(original, refused),
  )
  assert_true(session.close())
  assert_true(session.read_cleanup is None)
  assert_true(refused.issue() is @filesystem.GenerationMismatch)
}

///|
// Run this case alone with existing Native diagnostics enabled. Slot 37 counts
// actual source-validation attempts; captured DATA selections require zero.
test "configuration staging validates the unchanged original once" {
  let name = "local-settings-stage-once"
  let session = local_settings_fixture(name)
  let file = name + ".settings.json"
  for _ in 0..<3 {
    assert_eq(
      session.selected_configuration(file).unwrap(),
      local_settings_original,
    )
  }
  session.stage_configuration().unwrap()
  let (account, _) = local_adoption_read(session.root, "account.json", 1048576L).unwrap()
  assert_eq(account, local_selected_account)
  assert_true(
    session.root.inspect_generation("configuration-custody.json").unwrap()
    is Some(_),
  )
  for _ in 0..<3 {
    assert_eq(
      session.selected_configuration(file).unwrap(),
      local_settings_original,
    )
  }
  assert_eq(session.root.inspect_generation("client.sqlite3").unwrap(), None)
  assert_true(session.close())
}

///|
// Existing legacy Library diagnostic. Slot 37 must remain one across the
// trusted staging, SQLite bootstrap and retained-original opening steps.
test "journal opening validates the unchanged source once" {
  let name = "local-settings-open-once"
  let session = local_settings_fixture(name)
  let host = session
    .open_journal(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    )
    .unwrap()
  assert_true(physical_equal(host.session, session))
  local_adoption_row(host.database, host.adoption_body).unwrap()
  assert_true(
    host.database.read("client_local_settings", "manifest") is Ok(original) &&
    original.revision == 0L &&
    original.body == session.settings.manifest,
  )
  host.close().unwrap()
  assert_true(host.closed && host.session.closed)
}

///|
// A new public Host observation is a real entry, not a pure internal getter.
// Slot 37 counts one opening admission and one fresh, refusing next entry.
test "next Host operation refuses a changed original after opening" {
  let name = "local-settings-next-operation"
  let session = local_settings_fixture(name)
  let host = session
    .open_journal(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    )
    .unwrap()
  let file = name + ".settings.json"
  let generation = session.source_root
    .inspect_generation(file)
    .unwrap()
    .unwrap()
  session.source_root.reclaim_generation(file, generation).unwrap()
  let writer = session.source_root
    .create_writer(name + ".next.stage", 65536L)
    .unwrap()
  writer.append(b"{\"changed\":true}").unwrap()
  writer.seal(file).unwrap() |> ignore
  assert_true(host.selected_configuration(file) is Err(SourceChanged))
  host.close().unwrap()
}

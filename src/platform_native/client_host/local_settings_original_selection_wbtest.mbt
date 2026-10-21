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

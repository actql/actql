///|
test "initial issue metadata reuses the selected raw-file CID without digesting it again" {
  let name = "initial-metadata-cid"
  let session = local_settings_fixture(name)
  let crypto = epoch_test_crypto()
  let host = session
    .open_journal(local_journal_test_library(), crypto, 100.0, 8, 8388608L)
    .unwrap()
  // Independent literal vector for the existing raw JSON/CRLF fixture. This
  // pure projection is not an entered Read, role decision or signing permit.
  let expected = "sha256:ebebff5626d0b882617e62527d5e013f24868a08772f6653b48e86d5f5e35fb6"
  let before = native_timing_counter_value(26)
  assert_true(before >= 0L)
  for _ in 0..<2 {
    assert_eq(
      host
      .selected_configuration_cid_after_current(
        name + ".settings.json",
        local_settings_original,
      )
      .unwrap(),
      expected,
    )
  }
  assert_eq(native_timing_counter_value(26) - before, 0L)
  assert_true(
    host.selected_configuration_cid_after_current(
      name + ".settings.json",
      b"changed raw bytes",
    )
    is Err(CustodyLost),
  )
  assert_true(
    host.selected_configuration_cid_after_current(
      "missing.settings.json", local_settings_original,
    )
    is Err(CustodyLost),
  )
  host.close().unwrap()
}

///|
test "initial issue CID keeps cold hashing and refuses a selected unentered Read" {
  let host = initial_signing_original_fixture("metadata-cid-no-read")
  let original = host.restore_initial_signing_original().unwrap()
  let before = native_timing_counter_value(26)
  assert_true(before >= 0L)
  for _ in 0..<2 {
    // Legacy DATA computation remains exactly the old raw digest; it neither
    // selects this name nor supplies the enclosing issuer's current checks.
    assert_eq(
      original
      .selected_configuration_cid_after_current("cold-only", b"cold-only")
      .unwrap(),
      "sha256:a9d7a02cd1cc975b62fa8b8784e3f65616291ff8a8fcbd6d6067e6ce567f6ae3",
    )
  }
  assert_eq(native_timing_counter_value(26) - before, 2L)
  let material = host.adopted_current_material().unwrap()
  let capture = prepare_native_local_journal_capture(
    host.session,
    local_journal_test_library(),
    host.epoch.crypto,
    100.0,
    8,
    8388608L,
  )
  // Negative-only metadata, with no paired or entered Read. Selecting Some
  // must refuse instead of falling back to the still-live legacy hasher.
  capture.opening = JournalAcquired(host)
  let scoped = { ..original, original_read: Some((capture, material)), }
  let refused_before = native_timing_counter_value(26)
  assert_true(
    scoped.selected_configuration_cid_after_current("cold-only", b"cold-only")
    is Err(OriginalResourceScopePending),
  )
  assert_eq(native_timing_counter_value(26), refused_before)
  host.close().unwrap()
}

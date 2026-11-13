///|
// Physical Host/Source and negative copied-metadata controls only. This does
// not manufacture a saved approval scope, paired Read or successful Allow.
test "terminal saved registration keeps full configured and cold initial Host fences" {
  for initial in [false, true] {
    let name = "reviewer-terminal-legacy-" + initial.to_string()
    let (host, file) = if initial {
      initial_reviewer_fixture(name)
    } else {
      local_reviewer_installation_fixture(name)
    }
    let installed = if initial {
      host
      .install_initial_effect_reviewer(
        host.restore_initial_signing_original().unwrap(),
        "machine-user",
        "cli",
        file,
      )
      .unwrap()
    } else {
      host.install_effect_reviewer(configuration_file=Some(file)).unwrap()
    }
    let library = local_journal_test_library()
    let capture = prepare_native_local_journal_capture(
      host.session,
      library,
      host.epoch.crypto,
      100.0,
      8,
      8388608L,
    )
    installed.terminal_saved_host_current(host, capture).unwrap()
    // Replace even identical Source bytes. A legacy registration must still
    // perform the actual original-generation fence, not merely return DATA.
    let account = host.session.source_name
    let root = host.session.source_root
    let (body, generation) = local_adoption_read(root, account, 65536L).unwrap()
    root.reclaim_generation(account, generation).unwrap()
    let writer = root.create_writer("terminal-account.stage", 65536L).unwrap()
    writer.append(body).unwrap()
    writer.seal(account).unwrap() |> ignore
    assert_true(
      installed.terminal_saved_host_current(host, capture) is Err(SourceChanged),
    )
    host.close().unwrap()
    assert_true(library.close_checked() is Err(Physical(_)))
  }
}

///|
test "terminal saved registration refuses foreign and expired Read metadata without legacy fallback" {
  let (host, file) = initial_reviewer_fixture("reviewer-terminal-copied")
  let original = host.restore_initial_signing_original().unwrap()
  let installed = host
    .install_initial_effect_reviewer(original, "machine-user", "cli", file)
    .unwrap()
  let material = host.adopted_current_material().unwrap()
  let library = local_journal_test_library()
  let capture = prepare_native_local_journal_capture(
    host.session,
    library,
    host.epoch.crypto,
    100.0,
    8,
    8388608L,
  )
  let foreign = prepare_native_local_journal_capture(
    host.session,
    library,
    host.epoch.crypto,
    100.0,
    8,
    8388608L,
  )
  capture.opening = JournalAcquired(host)
  capture.read_callback_active = true
  capture.read_facts_valid = true
  capture.read_material = Some(material)
  let copied = { ..original, original_read: Some((capture, material)), }
  let selected = { ..installed, initial_original: Some(copied), }
  assert_true(
    selected.terminal_saved_host_current(host, foreign)
    is Err(OriginalResourceScopePending),
  )
  // Equal labels and callback flags do not supply an actual entered Read.
  assert_true(
    selected.terminal_saved_host_current(host, capture)
    is Err(OriginalResourceScopePending),
  )
  capture.read_callback_active = false
  capture.read_facts_valid = false
  capture.clear_read_operation_facts()
  assert_true(
    selected.terminal_saved_host_current(host, capture)
    is Err(OriginalResourceScopePending),
  )
  host.close().unwrap()
  assert_true(library.close_checked() is Err(Physical(_)))
}

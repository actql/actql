///|
test "operator Host original follows its physical file not the Product copy" {
  let path = product_test_parent("operator-host-original")
  let crypto = epoch_test_crypto()
  let capture = prepare_local_operator_host_capture(
      path,
      [".config", "actql"],
      "host.json",
      true,
      LegacyPrivateRoots,
    )
    |> material_choice_ok("operator capture")
  let original = capture.open() |> material_choice_ok("operator open")
  assert_eq(
    original.original_wire() |> material_choice_ok("operator wire"),
    "{\"version\":\"actql-host/0.1\"}\n",
  )
  let source = @filesystem.open_private_root(path).unwrap()
  // There is deliberately no Product-side host.json at this root.
  assert_eq(source.inspect_generation("host.json").unwrap(), None)
  let selected = select_native_local_configuration(
      source,
      "account.json",
      ["host.json"],
      None,
      crypto,
      operator_host=Some(original),
    )
    |> material_choice_ok("operator selection")
  assert_eq(selected.files[0].generation, original.generation)
  selected.check_source(source) |> material_choice_ok("operator current")
  let operator_root = capture.roots[2]
  let lock = operator_root.acquire_lock("host.json.actql-write.lock").unwrap()
  let replacement = operator_root
    .create_writer("replacement.stage", 65536L)
    .unwrap()
  // Equal bytes do not replace the original physical generation/current.
  replacement.append(original.body).unwrap()
  replacement.replace_observed_file(original.observation, lock).unwrap()
  |> ignore
  replacement.close_retaining_files().unwrap()
  assert_true(original.original_wire() is Err(_))
  assert_true(selected.check_source(source) is Err(_))
  let restored = prepare_local_operator_host_capture(
      path,
      [".config", "actql"],
      "host.json",
      false,
      LegacyPrivateRoots,
    )
    |> material_choice_ok("operator restore capture")
  let changed = restored.open() |> material_choice_ok("operator changed open")
  let changed_selection = select_native_local_configuration(
      source,
      "account.json",
      ["host.json"],
      None,
      crypto,
      operator_host=Some(changed),
    )
    |> material_choice_ok("operator changed selection")
  assert_true(selected.manifest != changed_selection.manifest)
  lock.close_checked().unwrap()
  restored.close() |> material_choice_ok("operator restored close")
  capture.close() |> material_choice_ok("operator close")
  assert_true(changed.original_wire() is Err(Closed))
  assert_true(original.original_wire() is Err(Closed))
  source.close().unwrap()
  crypto.close_checked().unwrap()
}

///|
test "operator Host restore never creates a missing file or rewrites explicit signers" {
  let path = product_test_parent("operator-host-no-fallback")
  let missing = prepare_local_operator_host_capture(
      path,
      [],
      "host.json",
      false,
      LegacyPrivateRoots,
    )
    |> material_choice_ok("missing operator capture")
  assert_true(missing.open() is Err(CustodyLost))
  missing.close() |> material_choice_ok("missing operator close")
  let root = @filesystem.open_private_root(path).unwrap()
  assert_eq(root.inspect_generation("host.json").unwrap(), None)
  let body = b"{\"version\":\"actql-host/0.1\",\"signers\":{}}"
  let generation = local_adoption_write(root, "host.json", body)
    |> material_choice_ok("explicit operator write")
  let capture = prepare_local_operator_host_capture(
      path,
      [],
      "host.json",
      true,
      LegacyPrivateRoots,
    )
    |> material_choice_ok("explicit operator capture")
  let original = capture.open() |> material_choice_ok("explicit operator open")
  assert_eq(original.body, body)
  assert_eq(original.generation, generation)
  assert_eq(root.inspect_generation("host.json").unwrap(), Some(generation))
  capture.close() |> material_choice_ok("explicit operator close")
  assert_true(original.original_wire() is Err(Closed))
  root.close().unwrap()
}

///|
test "operator Host scoped entrance refuses a missing original Read before opening files" {
  let path = product_test_parent("operator-host-missing-scope")
  let capture = prepare_native_local_operator_host_capture_in_current_read_context(
      path,
      [],
      "host.json",
      true,
      128,
    )
    |> material_choice_ok("scoped operator capture")
  assert_true(capture.open() is Err(Filesystem(@filesystem.RootOpen(_))))
  assert_eq(capture.roots.length(), 0)
  assert_true(capture.original is None)
  capture.close() |> material_choice_ok("scoped operator close")
  let root = @filesystem.open_private_root(path).unwrap()
  assert_eq(root.inspect_generation("host.json").unwrap(), None)
  root.close().unwrap()
}

///|
test "operator Host joins the actual adoption capture without a private-file fallback" {
  let path = product_test_parent("operator-host-adoption-join")
  let crypto = epoch_test_crypto()
  let source = @filesystem.open_private_root(path).unwrap()
  local_adoption_write(source, "account.json", local_selected_account)
  |> material_choice_ok("join account")
  |> ignore
  let operator = prepare_local_operator_host_capture(
      path,
      [".config", "actql"],
      "host.json",
      true,
      LegacyPrivateRoots,
    )
    |> material_choice_ok("join operator capture")
  let original = operator.open() |> material_choice_ok("join operator open")
  assert_eq(source.inspect_generation("host.json").unwrap(), None)
  let adoption = prepare_local_existing_adoption_capture(
      {
        parent_path: path,
        state_name: "state",
        source_path: path,
        source_name: "account.json",
        account_id: "operator",
        configuration_files: ["host.json"],
        managed_root_path: None,
      },
      crypto,
      LegacyPrivateRoots,
      existing_only=false,
    )
    |> material_choice_ok("join adoption capture")
  assert_true(adoption.open(operator_host=Some(original)).issue() is None)
  let session = adoption.original_session().unwrap()
  assert_eq(session.settings.files[0].generation, original.generation)
  assert_eq(
    session.selected_configuration("host.json")
    |> material_choice_ok("join selected Host"),
    original.body,
  )
  session.stage_configuration() |> material_choice_ok("join staged account")
  session.check_original() |> material_choice_ok("join current")
  assert_true(adoption.close().issue() is None)
  assert_true(adoption.descriptor_cleanup_acknowledged())
  operator.close() |> material_choice_ok("join operator close")
  assert_true(original.original_wire() is Err(Closed))
  source.close().unwrap()
  crypto.close_checked().unwrap()
}

///|
test "missing explicit operator Host refuses without creating authority or staging files" {
  let path = product_test_parent("explicit-operator-host-missing")
  // The command's exact explicit-path selection supplies create_default=false
  // even for init. The filename itself, including host.json, grants nothing.
  let capture = prepare_local_operator_host_capture(
      path,
      [],
      "host.json",
      false,
      LegacyPrivateRoots,
    )
    |> material_choice_ok("explicit missing capture")
  assert_true(capture.open() is Err(CustodyLost))
  assert_true(capture.original is None)
  assert_true(capture.writer is None)
  capture.close() |> material_choice_ok("explicit missing close")
  let root = @filesystem.open_private_root(path).unwrap()
  assert_eq(root.inspect_generation("host.json").unwrap(), None)
  assert_eq(root.inspect_generation("host.json.stage").unwrap(), None)
  root.close().unwrap()
}

///|
fn product_test_parent(name : String) -> String {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = @filesystem.open_private_root(path).unwrap()
  root.create_directory(name).unwrap() |> ignore
  path + "/" + name
}

///|
test "product originals retain exact values and original file generations on reopen" {
  let path = product_test_parent("product-parent-reopen")
  let crypto = epoch_test_crypto()
  let originals = [
    ("account.json", local_selected_account),
    ("config.json", @utf8.encode("{\"s\":\"e\u{0301}\r\n\"}")),
  ]
  let session = begin_native_local_product_configuration(
    path, "product-reopen", originals, crypto,
  ).unwrap()
  session.stage_configuration().unwrap()
  let root = @filesystem.open_private_root(path)
    .unwrap()
    .open_child("product-reopen")
    .unwrap()
  let original = root.inspect_generation("config.json").unwrap()
  assert_true(session.close())
  assert_true(session.close())
  assert_true(session.stage_configuration() is Err(Closed))
  let restored = begin_native_local_product_configuration(
    path,
    "product-reopen",
    originals,
    crypto,
    existing_only=true,
  ).unwrap()
  restored.stage_configuration().unwrap()
  assert_eq(root.inspect_generation("config.json").unwrap(), original)
  assert_eq(
    local_adoption_read(root, "config.json", 65536L).unwrap().0,
    originals[1].1,
  )
  assert_true(restored.close())
  let restored_selection = restore_native_local_product_configuration(
    path, "product-reopen", crypto,
  ).unwrap()
  // The existing String comparison orders by length before code units;
  // retained selection order is independent of caller insertion order.
  assert_eq(restored_selection.originals, [originals[1], originals[0]])
  assert_eq(root.inspect_generation("config.json").unwrap(), original)
  assert_true(restored_selection.close())
}

///|
test "product originals reject invalid selection before physical creation" {
  assert_true(product_original_names([("config.json", b"{}")]))
  for
    name in [
      "..", "../config.json", "product-initialization.json", "a/b", "a\\b",
    ] {
    assert_false(product_original_names([(name, b"{}")]))
  }
  assert_false(product_original_names([]))
  assert_false(product_original_names([("a", b"{}"), ("a", b"{}")]))
  assert_false(product_original_names([("a", b"")]))
  assert_false(product_original_names([("a", Bytes::make(65537, 0))]))
  assert_true(
    product_original_names(Array::makei(10, i => ("a" + i.to_string(), b"{}"))),
  )
  assert_true(
    product_original_names(
      Array::makei(11, i => ("a" + (i + 10).to_string(), b"{}")),
    ),
  )
  assert_false(
    product_original_names(
      Array::makei(12, i => ("a" + (i + 10).to_string(), b"{}")),
    ),
  )
}

///|
test "File installation refuses stale tenth and eleventh claims before creating an intent" {
  for (label, index) in [("tenth", "9"), ("eleventh", "10")] {
    let path = product_test_parent("product-parent-\{label}-claim")
    let parent = @filesystem.open_private_root(path).unwrap()
    let writer = parent.create_writer("tenth.stage", 4096L).unwrap()
    writer.append(b"original-unresolved-claim").unwrap()
    let claim = writer.seal("product-original-\{index}.claim").unwrap()
    let cleanup = new_local_adoption_open_failure()
    assert_true(
      begin_native_local_product_configuration_original(
        path,
        "product-\{label}-claim",
        [("config.json", b"{}")],
        epoch_test_crypto(),
        custody=Some(cleanup),
      )
      is Err(CustodyLost),
    )
    assert_eq(
      parent.inspect_generation("product-initialization.json").unwrap(),
      None,
    )
    assert_eq(parent.inspect_directory("product-\{label}-claim").unwrap(), None)
    assert_eq(
      parent.inspect_generation("product-original-\{index}.claim").unwrap(),
      Some(claim),
    )
    cleanup.retry_cleanup().unwrap()
    parent.close().unwrap()
  }
}

///|
test "product originals refuse orphaned private directory and missing original intent" {
  let path = product_test_parent("product-parent-orphan")
  let parent = @filesystem.open_private_root(path).unwrap()
  parent.create_directory("product-orphan").unwrap() |> ignore
  assert_true(
    begin_native_local_product_configuration(
      path,
      "product-orphan",
      [("config.json", b"{}")],
      epoch_test_crypto(),
    )
    is Err(AmbiguousInitialization),
  )
  assert_eq(
    parent.inspect_generation("product-initialization.json").unwrap(),
    None,
  )
}

///|
test "product originals restore staged configuration before Host adoption without repairing witnesses" {
  let path = product_test_parent("product-parent-partial")
  let parent = @filesystem.open_private_root(path).unwrap()
  let crypto = epoch_test_crypto()
  let originals = [("config.json", b"{}")]
  let session = begin_native_local_product_configuration(
    path, "product-partial", originals, crypto,
  ).unwrap()
  session.stage_configuration().unwrap()
  assert_true(session.close())
  let restored = begin_native_local_product_configuration(
    path, "product-partial", originals, crypto,
  ).unwrap()
  restored.stage_configuration().unwrap()
  let root = parent.open_child("product-partial").unwrap()
  let generation = root.inspect_generation("config.json").unwrap()
  parent
  .reclaim_generation(
    "product-original-0.custody",
    parent.inspect_generation("product-original-0.custody").unwrap().unwrap(),
  )
  .unwrap()
  assert_true(restored.stage_configuration() is Err(AmbiguousInitialization))
  assert_eq(root.inspect_generation("config.json").unwrap(), generation)
  assert_eq(
    parent.inspect_generation("product-original-0.custody").unwrap(),
    None,
  )
  assert_true(restored.close())
  assert_true(
    restore_native_local_product_configuration(path, "product-partial", crypto)
    is Err(AmbiguousInitialization),
  )
}

///|
test "product restore never replaces lost original bytes or a renamed source directory" {
  let path = product_test_parent("product-parent-lost")
  let crypto = epoch_test_crypto()
  let session = begin_native_local_product_configuration(
    path,
    "product-lost",
    [("config.json", b"{}")],
    crypto,
  ).unwrap()
  session.stage_configuration().unwrap()
  let generation = session.root
    .inspect_generation("config.json")
    .unwrap()
    .unwrap()
  session.root.reclaim_generation("config.json", generation).unwrap()
  assert_true(session.stage_configuration() is Err(CustodyLost))
  assert_eq(session.root.inspect_generation("config.json").unwrap(), None)
  assert_true(session.close())
  assert_true(
    restore_native_local_product_configuration(path, "product-lost", crypto)
    is Err(CustodyLost),
  )
  assert_true(
    restore_native_local_product_configuration(path, "other", crypto)
    is Err(SourceChanged),
  )
}

///|
test "product originals reject changed bundled bytes and an uncompleted creation claim" {
  let path = product_test_parent("product-parent-claim")
  let crypto = epoch_test_crypto()
  let session = begin_native_local_product_configuration(
    path,
    "product-claim",
    [("config.json", b"{}")],
    crypto,
  ).unwrap()
  let claim = local_adoption_record([
    ("intent_cid", session.intent_cid),
    ("name", "config.json"),
  ]).unwrap()
  local_adoption_write(session.parent, "product-original-0.claim", claim).unwrap()
  |> ignore
  assert_true(session.stage_configuration() is Err(AmbiguousInitialization))
  assert_eq(session.root.inspect_generation("config.json").unwrap(), None)
  assert_true(session.close())
  assert_true(
    begin_native_local_product_configuration(
      path,
      "product-claim",
      [("config.json", b"{\"changed\":true}")],
      crypto,
    )
    is Err(SourceChanged),
  )
}

///|
test "product configuration uses the existing exclusive adoption claim" {
  let path = product_test_parent("product-parent-concurrent")
  let originals = [("config.json", b"{}")]
  let crypto = epoch_test_crypto()
  let first = begin_native_local_product_configuration(
    path, "product-concurrent", originals, crypto,
  ).unwrap()
  assert_true(
    begin_native_local_product_configuration(
      path, "product-concurrent", originals, crypto,
    )
    is Err(Filesystem(@filesystem.Lock(_))),
  )
  assert_eq(first.root.inspect_generation("config.json").unwrap(), None)
  first.stage_configuration().unwrap()
  assert_true(first.close())
}

///|
test "product restore rejects same-byte replacement without changing the witness" {
  let path = product_test_parent("product-parent-replaced")
  let crypto = epoch_test_crypto()
  let originals = [("config.json", b"{}")]
  let first = begin_native_local_product_configuration(
    path, "product-replaced", originals, crypto,
  ).unwrap()
  first.stage_configuration().unwrap()
  let generation = first.root
    .inspect_generation("config.json")
    .unwrap()
    .unwrap()
  // Keep the original inode allocated while creating the new name, so this
  // counterexample cannot accidentally reuse the deleted inode number.
  let replacement = first.root.create_writer("replacement.stage", 2L).unwrap()
  replacement.append(b"{}").unwrap()
  first.root.reclaim_generation("config.json", generation).unwrap()
  replacement.seal("config.json").unwrap() |> ignore
  assert_true(first.stage_configuration() is Err(CustodyLost))
  assert_true(first.close())
  assert_true(
    restore_native_local_product_configuration(path, "product-replaced", crypto)
    is Err(CustodyLost),
  )
}

///|
test "reopening or repeating product staging never infers first creation from absent claims" {
  let path = product_test_parent("product-parent-no-repair")
  let crypto = epoch_test_crypto()
  let originals = [("config.json", b"{}")]
  let first = begin_native_local_product_configuration(
    path, "product-no-repair", originals, crypto,
  ).unwrap()
  assert_true(first.close())
  let reopened = begin_native_local_product_configuration(
    path, "product-no-repair", originals, crypto,
  ).unwrap()
  assert_true(reopened.stage_configuration() is Err(CustodyLost))
  assert_eq(reopened.root.inspect_generation("config.json").unwrap(), None)
  assert_eq(
    reopened.parent.inspect_generation("product-original-0.claim").unwrap(),
    None,
  )
  assert_true(reopened.close())
}

///|
#borrow(root)
extern "C" fn product_test_parent_mode(
  root : @filesystem.Root,
  mode : Int,
) -> Bool = "actql_native_filesystem_test_private_mode"

///|
test "product configuration uses trusted HOME-like parent and retains private child" {
  let path = product_test_parent("product-home-parent")
  let parent = @filesystem.open_root(path).unwrap()
  assert_true(product_test_parent_mode(parent, 0o750))
  assert_true(parent.private_ownership() is Err(@filesystem.RootOpen(_)))
  let crypto = epoch_test_crypto()
  let originals = [("config.json", b"{}")]
  let session = begin_native_local_product_configuration(
    path, "product-home", originals, crypto,
  ).unwrap()
  session.stage_configuration().unwrap()
  let child = parent.open_child("product-home").unwrap()
  let generation = child.inspect_generation("config.json").unwrap()
  let intent = local_adoption_read(parent, "product-initialization.json", 8192L).unwrap()
  let witness = local_adoption_read(
    parent, "product-directory-custody.json", 8192L,
  ).unwrap()
  assert_true(session.close())
  let restored = restore_native_local_product_configuration(
    path, "product-home", crypto,
  ).unwrap()
  assert_eq(restored.originals, originals)
  assert_eq(child.private_ownership().unwrap(), restored.root_ownership)
  assert_eq(child.inspect_generation("config.json").unwrap(), generation)
  assert_eq(
    local_adoption_read(parent, "product-initialization.json", 8192L).unwrap(),
    intent,
  )
  assert_eq(
    local_adoption_read(parent, "product-directory-custody.json", 8192L).unwrap(),
    witness,
  )
  assert_true(restored.close())
}

///|
test "HOME-like restore refuses missing intent without recreating original custody" {
  let path = product_test_parent("product-home-missing-intent")
  let parent = @filesystem.open_root(path).unwrap()
  assert_true(product_test_parent_mode(parent, 0o750))
  let crypto = epoch_test_crypto()
  let session = begin_native_local_product_configuration(
    path,
    "product-home-missing",
    [("config.json", b"{}")],
    crypto,
  ).unwrap()
  session.stage_configuration().unwrap()
  let child = parent.open_child("product-home-missing").unwrap()
  let generation = child.inspect_generation("config.json").unwrap()
  assert_true(session.close())
  parent
  .reclaim_generation(
    "product-initialization.json",
    parent.inspect_generation("product-initialization.json").unwrap().unwrap(),
  )
  .unwrap()
  assert_true(
    restore_native_local_product_configuration(
      path, "product-home-missing", crypto,
    )
    is Err(CustodyLost),
  )
  assert_eq(
    parent.inspect_generation("product-initialization.json").unwrap(),
    None,
  )
  assert_eq(child.inspect_generation("config.json").unwrap(), generation)
}

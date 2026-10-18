///|
test "product capture snapshots the original selection before scoped acquisition" {
  let values = [("account.json", b"{}"), ("config.json", b"{\"v\":1}")]
  let capture = prepare_native_local_product_configuration_capture_in_current_read_context(
    "/unused",
    "product",
    epoch_test_crypto(),
    128,
    originals=Some(values),
  ).unwrap()
  values[0] = ("changed.json", b"{}")
  let selected = capture.originals.unwrap()
  assert_true(product_original_names(selected))
  assert_true(selected.contains(("account.json", b"{}")))
  assert_false(selected.contains(("changed.json", b"{}")))
  capture.close().unwrap()
  assert_true(capture.descriptor_cleanup_acknowledged())
  assert_true(capture.open() is Err(Closed))
}

///|
test "product capture retains missing current Read refusal without legacy fallback" {
  let path = product_test_parent("product-scoped-refused-parent")
  let capture = prepare_native_local_product_configuration_capture_in_current_read_context(
    path,
    "never-created",
    epoch_test_crypto(),
    128,
    originals=Some([("config.json", b"{}")]),
  ).unwrap()
  assert_true(capture.open() is Err(Filesystem(@filesystem.RootOpen(_))))
  assert_true(capture.original.parent is None)
  assert_true(capture.original.root is None)
  assert_true(capture.original.lock is None)
  assert_true(capture.original.root_acquisition is Some(_))
  assert_true(capture.open() is Err(Filesystem(@filesystem.RootOpen(_))))
  capture.close().unwrap()
  capture.close().unwrap()
  assert_true(capture.descriptor_cleanup_acknowledged())
  let parent = @filesystem.open_private_root(path).unwrap()
  assert_eq(
    parent.inspect_generation("product-initialization.json").unwrap(),
    None,
  )
  assert_eq(parent.inspect_directory("never-created").unwrap(), None)
  parent.close().unwrap()
}

///|
test "explicit initial adoption capture keeps missing scope failure in its original holder" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let capture = prepare_native_local_initial_adoption_capture_in_current_read_context(
    {
      parent_path: path,
      state_name: "initial-capture-not-created",
      source_path: path,
      source_name: "not-read.account.json",
      account_id: "operator",
      configuration_files: [],
      managed_root_path: None,
    },
    epoch_test_crypto(),
    128,
  ).unwrap()
  assert_false(capture.existing_only)
  let reply = capture.open()
  assert_true(
    reply.issue() is Some(AdoptionOriginal(Filesystem(@filesystem.RootOpen(_)))),
  )
  assert_true(capture.original.source_root is None)
  assert_true(capture.original.parent is None)
  assert_true(capture.original.lock is None)
  assert_true(capture.close().issue() is None)
  assert_true(capture.close().issue() is None)
  let parent = @filesystem.open_private_root(path).unwrap()
  assert_eq(
    parent.inspect_directory("initial-capture-not-created").unwrap(),
    None,
  )
  parent.close().unwrap()
}

///|
fn ordinary_holder_scope(
  current : () -> Bool,
) -> HolderEffectHostSetupScope raise {
  let scope = prepare_holder_effect_host_ordinary_scope(
    host_setup_test_site(1),
    128L,
    1024L,
  ).unwrap()
  scope.preparation_binding = Some(() => true)
  assert_true(install_holder_effect_host_store_current(scope, current))
  scope
}

///|
test "ordinary holder acquires bounded platform input without a mapped arena profile" {
  let scope = ordinary_holder_scope(() => true)
  let before = @site.site_status(scope.site)
  assert_true(scope.profile is None)
  assert_true(scope.read_domain is None)
  assert_true(scope.caller_operation is None)
  assert_eq(holder_effect_host_scope_read_ceiling(scope), 128)
  assert_true(holder_effect_host_read_scope_current(scope))
  assert_true(
    retain_holder_effect_host_snapshot(
      scope,
      "ordinary-root",
      Array::make(11, ("subject", "value")),
    ),
  )
  assert_eq(@site.site_status(scope.site), before)
  assert_true(leave_holder_effect_host_read_scope(scope))
  assert_true(retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach)
  assert_true(scope.read_domain is None)
  assert_true(scope.holding is None)
}

///|
fn ordinary_holder_file(
  label : String,
) -> (String, @filesystem.Root, @filesystem.Writer) raise {
  let parent = @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap()
  let root = @filesystem.open_root(parent).unwrap()
  root.create_directory(label).unwrap() |> ignore
  let child = root.open_child(label).unwrap()
  let writer = child.create_writer("stage", 5L).unwrap()
  writer.append(b"hello").unwrap()
  writer.seal("value").unwrap() |> ignore
  root.close().unwrap()
  // The Writer owns the sealed name until cancel. Retain that real original
  // through the input/current checks instead of deleting the input beforehand.
  (parent + "/" + label, child, writer)
}

///|
test "ordinary holder real bounded read keeps original failure cleanup and does not reacquire" {
  let (path, root, writer) = ordinary_holder_file("ordinary-holder-read")
  let scope = ordinary_holder_scope(() => true)
  assert_eq(
    read_holder_effect_host_text(scope, path, "value", 5L),
    Some("hello"),
  )
  assert_true(scope.pending is None)
  assert_true(read_holder_effect_host_text(scope, path, "value", 4L) is None)
  let failure = scope.pending.unwrap()
  assert_true(read_holder_effect_host_text(scope, path, "value", 5L) is None)
  assert_true(physical_equal(scope.pending.unwrap(), failure))
  ignore(leave_holder_effect_host_read_scope(scope))
  assert_true(retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach)
  assert_true(scope.pending is None)
  assert_true(scope.read_domain is None)
  assert_true(read_holder_effect_host_text(scope, path, "value", 5L) is None)
  if scope.cleanup is Some(cleanup) {
    assert_true(@site.release_site_cleanup(cleanup))
    scope.cleanup = None
  }
  writer.cancel().unwrap()
  root.close().unwrap()
}

///|
test "ordinary holder withholds real read after current loss and never revives" {
  let (path, root, writer) = ordinary_holder_file("ordinary-holder-current")
  let checks = Ref(0)
  let allow = Ref(true)
  let scope = ordinary_holder_scope(() => {
    checks.val += 1
    allow.val && checks.val < 3
  })
  // Installation checked once. The real read checks before and after I/O.
  assert_true(read_holder_effect_host_text(scope, path, "value", 5L) is None)
  assert_eq(checks.val, 3)
  assert_true(scope.pending is None)
  assert_true(scope.retiring)
  allow.val = true
  assert_false(holder_effect_host_read_scope_current(scope))
  assert_false(scope.current_binding.unwrap()())
  assert_eq(checks.val, 3)
  assert_true(quiesce_holder_effect_host_setup_scope(scope))
  assert_true(retire_holder_effect_host_scope(scope) is HostSetupReadyToDetach)
  writer.cancel().unwrap()
  root.close().unwrap()
}

///|
test "ordinary holder rejects invalid managed limits before opening platform input" {
  for (file_limit, record_limit) in [(0L, 1L), (1L, 0L), (1L, 2147483648L)] {
    assert_true(
      holder_effect_host_ordinary_limits(file_limit, record_limit) is None,
    )
  }
  let limits = holder_effect_host_ordinary_limits(2000000L, 1024L).unwrap()
  assert_eq(limits.read_ceiling, 1000000)
  assert_eq(limits.catalog_read_ceiling, 1024L)
}

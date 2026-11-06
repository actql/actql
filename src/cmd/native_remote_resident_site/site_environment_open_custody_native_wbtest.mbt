///|
test "failed Site preparation keeps original Slot when process holding is unconfirmed" {
  let parent = @env.get_env_var("ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT").unwrap()
  let slot = @slot.open_native_executor_slot(parent + "/site-open-pending.slot").unwrap()
  assert_true(slot.try_acquire().unwrap())
  let original = site_environment_open_custody(
    "original unavailable hold",
    "original-process",
    release_required=true,
  )
  let custody : HolderSiteEnvironmentOpenCleanup = {
    original,
    slot,
    slot_close_unknown: false,
    slot_closed: false,
  }
  assert_false(retry_holder_site_environment_open_cleanup(custody))
  assert_true(original.release_required)
  assert_eq(slot.verify_current_hold(), Ok(()))
  assert_false(custody.slot_closed)
  assert_false(retry_holder_site_environment_open_cleanup(custody))
  assert_eq(slot.verify_current_hold(), Ok(()))
  // Only the independent fixture's explicit end retires this real Slot;
  // production cleanup never fabricates release for the missing holding.
  assert_true(slot.close())
}

///|
test "failed Site preparation returns inherited Slot only after original cleanup ACK" {
  let parent = @env.get_env_var("ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT").unwrap()
  let slot = @slot.open_native_executor_slot(parent + "/site-open-retired.slot").unwrap()
  assert_true(slot.try_acquire().unwrap())
  let original = site_environment_open_custody(
    "original preparation refused", "original-process",
  )
  let custody : HolderSiteEnvironmentOpenCleanup = {
    original,
    slot,
    slot_close_unknown: false,
    slot_closed: false,
  }
  assert_true(retry_holder_site_environment_open_cleanup(custody))
  assert_true(custody.slot_closed)
  assert_false(custody.slot_close_unknown)
  assert_true(retry_holder_site_environment_open_cleanup(custody))
  let next = @slot.open_native_executor_slot(parent + "/site-open-retired.slot").unwrap()
  assert_true(next.try_acquire().unwrap())
  assert_true(next.close())
  assert_eq(original.original_failure, "original preparation refused")
}

///|
test "invalid original Site selection refuses before executable Library or Store reads" {
  let progress_events : Array[(String, Array[(String, String)])] = []
  let observe_progress = (kind, fields) => progress_events.push((kind, fields))
  // All physical paths are deliberately unavailable. The actual caller must
  // return the original Site refusal before executable identity or dlopen.
  for (generation, operations) in [("-1", "4"), ("4", "0")] {
    let matches = command().parse(argv=[
      "--site-key",
      "site-before-store",
      "--site-generation=" + generation,
      "--runtime-bundle-cid",
      "original-configured-runtime",
      "--max-operations",
      operations,
      "--journal",
      "/unavailable/original-journal",
      "--target-triple",
      "aarch64-apple-darwin",
      "--component-cid",
      "deliberately-not-the-test-executable",
      "--sqlite-library",
      "/unavailable/original-sqlite",
      "--crypto-library",
      "/unavailable/original-crypto",
      "--runtime-root",
      "/unavailable/original-store",
      "run",
    ])
    let original = match
      open_site_environment(
        matches,
        "original-process",
        capture_resident_initial_control(),
        report_progress=observe_progress,
      ) {
      Err(original) => original
      Ok(_) => {
        fail("invalid Site was accepted")
        return
      }
    }
    assert_eq(original.original_failure, "invalid execution Site")
    assert_eq(original.process_hold_id, "original-process")
    assert_true(original.bundles is None)
    assert_true(original.failed_bundle is None)
    assert_true(original.failed_journal is None)
    assert_false(original.release_required)
    // No acquired process holding is invented by this pre-I/O refusal.
    assert_true(retry_site_environment_open_custody(original))
  }
  assert_eq(progress_events, [])
}

///|
test "issued active binding cannot replace the original configured Site selection" {
  let (bundles, _) = control_bundle_test_open("site-original-active")
  let installer = control_bundle_test_install(bundles, "1")
  installer.append(b"runtime-one").unwrap()
  installer.seal().unwrap() |> ignore
  let runtime = control_bundle_test_cid("1")
  bundles.activate(runtime).unwrap() |> ignore
  let binding = bundles
    .acquire_active_component(
      "sha256:5cbfccb321655cdc50146d4dad052ac646ba09180cefd34d8c48cd248166346f",
      "aarch64-apple-darwin", "runtime-process:site-original-active",
    )
    .unwrap()
  let site = @site.create_site(
    "site-original-active", 4, runtime, 4, 4, 268435456L, 268435456L,
  ).unwrap()
  assert_true(holder_site_active_runtime_current(site, 4, binding))
  assert_false(holder_site_active_runtime_current(site, 3, binding))
  let foreign = @site.create_site(
    "site-original-active", 4, "independently-selected-foreign-runtime", 4, 4, 268435456L,
    268435456L,
  ).unwrap()
  assert_false(holder_site_active_runtime_current(foreign, 4, binding))
  @site.revoke_site(site)
  assert_false(holder_site_active_runtime_current(site, 4, binding))
  assert_true(bundles.release("runtime-process:site-original-active").unwrap())
  bundles.drain(runtime).unwrap() |> ignore
  bundles.reclaim(runtime).unwrap() |> ignore
  bundles.close_checked().unwrap()
}

///|
test "original Site failure cannot treat an unscoped Library as a close ACK" {
  let parent = @env.get_env_var("ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT").unwrap()
  let library_path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap()
  let slot = @slot.open_native_executor_slot(
    parent + "/site-library-pending.slot",
  ).unwrap()
  assert_true(slot.try_acquire().unwrap())
  // A real legacy handle cannot stand in for the selected installer's original
  // context. Keep it as pending responsibility; do not translate its refusal
  // into a physical retirement or a new Library load.
  let library = @sqlite.load_library(library_path).unwrap()
  let original = site_environment_open_custody(
    "original selected Library context unavailable",
    "original-process",
    selected_sqlite_library=Some(library),
  )
  let custody : HolderSiteEnvironmentOpenCleanup = {
    original,
    slot,
    slot_close_unknown: false,
    slot_closed: false,
  }
  for _ in 0..<2 {
    assert_false(retry_holder_site_environment_open_cleanup(custody))
    assert_true(
      original.selected_sqlite_library is Some(same) &&
      physical_equal(same, library),
    )
    assert_eq(slot.verify_current_hold(), Ok(()))
    assert_false(custody.slot_closed)
    assert_false(custody.slot_close_unknown)
    assert_eq(
      original.original_failure,
      "original selected Library context unavailable",
    )
  }
  // Independent fixture retirement only. Production never converts the absent
  // original context into a Library or Slot close acknowledgement.
  assert_true(slot.close())
}

///|
test "cleanup cannot detach a nested caller or invoke another Store current read" {
  let site = host_setup_test_site(1)
  let current_reads = Ref(0)
  let scope = prepare_holder_effect_host_ordinary_scope(site, 128L, 1024L).unwrap()
  let current = () => {
    current_reads.val += 1
    true
  }
  scope.current_binding = Some(current)
  assert_true(enter_holder_effect_host_read_scope(scope))
  assert_eq(scope.depth, 2)
  let before_cleanup = current_reads.val
  let reserved = @site.site_status(site)
  assert_false(quiesce_holder_effect_host_setup_scope(scope))
  assert_eq(scope.depth, 2)
  assert_true(
    scope.current_binding is Some(same) && physical_equal(same, current),
  )
  assert_eq(current_reads.val, before_cleanup)
  assert_eq(@site.site_status(site), reserved)
  // The actual nested caller ends its own read; cleanup never forges this step.
  assert_false(leave_holder_effect_host_read_scope(scope))
  assert_eq(scope.depth, 1)
  assert_true(quiesce_holder_effect_host_setup_scope(scope))
  assert_true(quiesce_holder_effect_host_setup_scope(scope))
  assert_eq(scope.depth, 0)
  assert_true(scope.current_binding is None)
  assert_eq(current_reads.val, before_cleanup)
  assert_eq(@site.site_status(site), reserved)
  let (same_operation, _) = take_holder_effect_host_caller_reservation(scope)
  assert_true(same_operation is None)
}

///|
test "native restored output retains original input cleanup after its file is gone" {
  let bundles = restored_runtime_bundles(name="input-cleanup")
  let bundle_cid = @env.get_env_var(
    "ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID",
  ).unwrap()
  let binding = @remote.prepare_remote_input_binding("{}", 16).unwrap()
  let budget = @remote.prepare_remote_dispatch_budget(128L, 128L).unwrap()
  let executions = Ref(0)
  let (journal, request, root, name, _, site) = restored_output_fixture(
    "runtime-restored-input-cleanup",
    runtime_bundle_cid=Some(bundle_cid),
    input_binding_cid=Some(@remote.remote_input_binding_cid(binding)),
    budget_cid=Some(@remote.remote_dispatch_budget_cid(budget)),
  )
  let runtime = restored_runtime(
    bundles, journal, site, name, budget, executions,
  )
  let attempts = Ref(0)
  let complete = Ref(false)
  assert_true(
    @standard.restore_native_remote_standard_runtime_output(
      runtime,
      request,
      binding,
      root,
      10L,
      () => true,
      release_input=() => {
        attempts.val += 1
        complete.val
      },
    )
    is @runtime.CompletedRuntimeReady(_),
  )
  assert_eq(attempts.val, 0)
  assert_true(
    runtime.release(request) is Err(@runtime.CleanupPending("output")),
  )
  assert_eq(attempts.val, 1)
  assert_true(
    @filesystem.open_root(root).unwrap().inspect_generation("output-" + name)
    is Ok(None),
  )
  assert_false(
    @remote.remote_runtime_record_released(journal.require(request).unwrap()),
  )
  assert_true(runtime.retains_dispatch_resources())
  assert_eq(@site.site_status(site)[6], 10L)
  complete.val = true
  assert_true(runtime.release(request).unwrap())
  assert_false(runtime.release(request).unwrap())
  assert_eq(attempts.val, 2)
  assert_eq(executions.val, 0)
  assert_eq(@site.site_status(site)[6], 0L)
  assert_true(
    @remote.remote_runtime_record_released(journal.require(request).unwrap()),
  )
  assert_true(runtime.close().unwrap())
  assert_true(journal.close())
  assert_true(bundles.close().unwrap())
}

///|
test "native saved output cleanup keeps the same input duty across exclusive custody refusal" {
  let (journal, request, root, name, _, _) = restored_output_fixture(
    "saved-input-cleanup",
  )
  let current = Ref(false)
  let attempts = Ref(0)
  let cleanup = @standard.prepare_native_remote_standard_saved_output_cleanup(
    journal.observation(request).unwrap(),
    root,
    10L,
    () => {
      attempts.val += 1
      attempts.val > 1
    },
    () => current.val,
  ).unwrap()
  assert_false(cleanup())
  assert_eq(attempts.val, 0)
  assert_true(
    @filesystem.open_root(root).unwrap().inspect_generation("output-" + name)
    is Ok(Some(_)),
  )
  current.val = true
  assert_false(cleanup())
  assert_eq(attempts.val, 1)
  assert_true(
    @filesystem.open_root(root).unwrap().inspect_generation("output-" + name)
    is Ok(None),
  )
  assert_true(cleanup())
  assert_eq(attempts.val, 2)
  // A cleanup-only projection never invents a formal Released observation.
  assert_false(
    @remote.remote_runtime_record_released(journal.require(request).unwrap()),
  )
  assert_true(journal.close())
}

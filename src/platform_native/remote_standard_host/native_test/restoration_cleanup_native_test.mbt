///|
#borrow(source, target)
extern "C" fn rename_restoration_root(source : Bytes, target : Bytes) -> Int = "actql_test_restoration_rename"

///|
fn move_restoration_root(source : String, target : String) -> Unit raise {
  assert_eq(
    rename_restoration_root(
      @utf8.encode(source + "\u{0}"),
      @utf8.encode(target + "\u{0}"),
    ),
    0,
  )
}

///|
test "native restoration cleanup retries the original root and preserves foreign replacement" {
  let bundles = restored_runtime_bundles(name="retry-root")
  let bundle_cid = @env.get_env_var(
    "ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID",
  ).unwrap()
  let binding = @remote.prepare_remote_input_binding("{}", 16).unwrap()
  let budget = @remote.prepare_remote_dispatch_budget(128L, 128L).unwrap()
  let executions = Ref(0)
  let parent = @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap()
  for replacement in [false, true] {
    let suffix = if replacement { "foreign" } else { "original" }
    let name = "restore-root-" + suffix
    @filesystem.open_root(parent).unwrap().create_directory(name).unwrap()
    |> ignore
    let root = parent + "/" + name
    let slot = @slot.open_native_executor_slot(parent + "/" + name + ".slot").unwrap()
    assert_true(slot.try_acquire().unwrap())
    let competing = @slot.open_native_executor_slot(
      parent + "/" + name + ".slot",
    ).unwrap()
    let (journal, request, _, _, generation, site) = restored_output_fixture(
      name,
      runtime_bundle_cid=Some(bundle_cid),
      input_binding_cid=Some(@remote.remote_input_binding_cid(binding)),
      budget_cid=Some(@remote.remote_dispatch_budget_cid(budget)),
      root_path=Some(root),
    )
    let runtime = restored_runtime(
      bundles, journal, site, name, budget, executions,
    )
    move_restoration_root(root, root + "-away")
    assert_true(
      @standard.restore_native_remote_standard_runtime_output(
        runtime,
        request,
        binding,
        root,
        10L,
        () => slot.verify_current_hold() == Ok(()),
      )
      is @runtime.CompletedRuntimePending(
        @runtime.CompletedMaterialUnavailable("output-restore-physical")
      ),
    )
    assert_true(
      runtime.cleanup(request) is Err(@runtime.CleanupPending("output")),
    )
    assert_true(runtime.retains_dispatch_resources())
    assert_false(competing.try_acquire().unwrap())
    assert_eq(@site.site_status(site)[6], 10L)
    assert_eq(@site.site_status(site)[4], 1L)
    assert_true(
      runtime.open_output_reader(request, "original-generation", 10)
      is Err(@runtime.OutputReaderUnavailable),
    )
    move_restoration_root(root + "-away", root)
    let physical = @filesystem.open_root(root).unwrap()
    if replacement {
      // Keep the old inode pinned so the replacement cannot reuse it.
      let pin = physical.open_reader("output-" + name, generation).unwrap()
      physical.reclaim_generation("output-" + name, generation).unwrap()
      let writer = physical.create_writer("foreign-stage", 10L).unwrap()
      writer.append(b"[{\"id\":9}]").unwrap()
      let foreign = writer.seal("output-" + name).unwrap()
      assert_true(
        runtime.cleanup(request) is Err(@runtime.CleanupPending("output")),
      )
      assert_true(physical.verify_generation("output-" + name, foreign))
      assert_eq(@site.site_status(site)[6], 10L)
      pin.close().unwrap()
      // Only the test's replacement owner removes its own file.
      writer.cancel().unwrap()
    }
    assert_true(runtime.cleanup(request) is Ok(true))
    assert_false(runtime.cleanup(request).unwrap())
    assert_eq(@site.site_status(site)[6], 0L)
    assert_eq(@site.site_status(site)[4], 0L)
    assert_true(physical.inspect_generation("output-" + name) is Ok(None))
    assert_true(
      @remote.remote_runtime_record_released(journal.require(request).unwrap()),
    )
    assert_false(runtime.retains_dispatch_resources())
    assert_false(
      bundles
      .release("dispatch:" + @remote.dispatch_request_identity(request))
      .unwrap(),
    )
    assert_true(runtime.close().unwrap())
    assert_false(bundles.release("runtime-process:" + name).unwrap())
    assert_true(slot.close())
    assert_false(slot.close())
    assert_true(competing.try_acquire().unwrap())
    assert_true(competing.close())
    assert_true(journal.close())
  }
  assert_eq(executions.val, 0)
  assert_true(bundles.close().unwrap())
}

///|
fn restoration_observer(name : String, bundle_cid : String) -> @journal.Journal {
  @journal.open_journal(
    @sqlite.load_library(
      @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
    ).unwrap(),
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/" +
    name +
    ".sqlite3",
    1048576L,
    @remote.create_site_dispatch_journal(
      @site.create_site("site", 1, bundle_cid, 4, 4, 1000L, 1000L).unwrap(),
      "actql-remote-site/0.1",
    ).unwrap(),
  ).unwrap()
}

///|
test "native pending restoration reconciles release before physical retry" {
  let bundles = restored_runtime_bundles(name="between-attempts")
  let bundle_cid = @env.get_env_var(
    "ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID",
  ).unwrap()
  let binding = @remote.prepare_remote_input_binding("{}", 16).unwrap()
  let budget = @remote.prepare_remote_dispatch_budget(128L, 128L).unwrap()
  let executions = Ref(0)
  let (journal, request, root, name, _, site) = restored_output_fixture(
    "restoration-release-between-attempts",
    runtime_bundle_cid=Some(bundle_cid),
    input_binding_cid=Some(@remote.remote_input_binding_cid(binding)),
    budget_cid=Some(@remote.remote_dispatch_budget_cid(budget)),
  )
  let runtime = restored_runtime(
    bundles, journal, site, name, budget, executions,
  )
  let occupied = @site.retain_site_holding(site, 995L).unwrap()
  assert_true(
    @standard.restore_native_remote_standard_runtime_output(
      runtime,
      request,
      binding,
      root,
      10L,
      () => true,
    )
    is @runtime.CompletedRuntimePending(@runtime.CapacityRejected),
  )
  let observer = restoration_observer(name, bundle_cid)
  observer
  .commit_transition(
    @remote.prepare_begin_remote_release(observer.require(request).unwrap()).unwrap(),
  )
  .unwrap()
  |> ignore
  assert_true(
    journal.require(request) is Err(@journal.Protocol(@remote.StateCollision)),
  )
  assert_true(@site.release_site_holding(occupied))
  assert_true(
    @standard.restore_native_remote_standard_runtime_output(
      runtime,
      request,
      binding,
      root,
      10L,
      () => true,
    )
    is @runtime.CompletedRuntimePending(
      @runtime.CleanupPending("restoration-transition")
    ),
  )
  assert_true(runtime.cleanup_pending())
  assert_true(
    runtime.open_output_reader(request, "original-generation", 10)
    is Err(@runtime.OutputReaderUnavailable),
  )
  assert_eq(@site.site_status(site)[6], 10L)
  assert_true(runtime.cleanup(request) is Ok(true))
  assert_false(runtime.cleanup(request).unwrap())
  assert_eq(@site.site_status(site)[6], 0L)
  assert_eq(@site.site_status(site)[4], 0L)
  assert_eq(executions.val, 0)
  assert_true(
    @remote.remote_runtime_record_released(journal.require(request).unwrap()),
  )
  assert_false(
    bundles
    .release("dispatch:" + @remote.dispatch_request_identity(request))
    .unwrap(),
  )
  assert_true(runtime.close().unwrap())
  assert_false(bundles.release("runtime-process:" + name).unwrap())
  assert_true(observer.close())
  assert_true(journal.close())
  assert_true(bundles.close().unwrap())
}

///|
test "native pending restoration cancellation keeps original exclusive cleanup custody" {
  let bundles = restored_runtime_bundles(name="cancel-pending")
  let bundle_cid = @env.get_env_var(
    "ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID",
  ).unwrap()
  let binding = @remote.prepare_remote_input_binding("{}", 16).unwrap()
  let budget = @remote.prepare_remote_dispatch_budget(128L, 128L).unwrap()
  let executions = Ref(0)
  let (journal, request, root, name, generation, site) = restored_output_fixture(
    "restoration-cancel-pending",
    runtime_bundle_cid=Some(bundle_cid),
    input_binding_cid=Some(@remote.remote_input_binding_cid(binding)),
    budget_cid=Some(@remote.remote_dispatch_budget_cid(budget)),
  )
  let runtime = restored_runtime(
    bundles, journal, site, name, budget, executions,
  )
  let exclusive = Ref(true)
  let current = () => journal.cancellation_requested(request) is Ok(false)
  let occupied = @site.retain_site_holding(site, 995L).unwrap()
  assert_true(
    @standard.restore_native_remote_standard_runtime_output(
      runtime,
      request,
      binding,
      root,
      10L,
      current,
      cleanup_current=Some(() => exclusive.val),
    )
    is @runtime.CompletedRuntimePending(@runtime.CapacityRejected),
  )
  journal.request_cancellation(request).unwrap() |> ignore
  assert_true(@site.release_site_holding(occupied))
  exclusive.val = false
  // A later caller cannot replace the first owner's custody observer.
  assert_true(
    @standard.restore_native_remote_standard_runtime_output(
      runtime,
      request,
      binding,
      root,
      10L,
      () => true,
      cleanup_current=Some(() => true),
    )
    is @runtime.CompletedRuntimePending(@runtime.StartAuthorizationRejected),
  )
  assert_eq(@site.site_status(site)[6], 0L)
  assert_true(runtime.retains_dispatch_resources())
  assert_true(runtime.close() is Err(@runtime.CompletedRestorationPending))
  exclusive.val = true
  assert_true(
    @standard.restore_native_remote_standard_runtime_output(
      runtime, request, binding, root, 10L, current,
    )
    is @runtime.CompletedRuntimePending(
      @runtime.CleanupPending("restoration-transition")
    ),
  )
  assert_eq(@site.site_status(site)[6], 10L)
  assert_true(
    runtime.open_output_reader(request, "original-generation", 10)
    is Err(@runtime.OutputReaderUnavailable),
  )
  exclusive.val = false
  assert_true(
    runtime.cleanup(request)
    is Err(@runtime.CleanupPending("restoration-custody")),
  )
  assert_true(
    @filesystem.open_root(root)
    .unwrap()
    .verify_generation("output-" + name, generation),
  )
  assert_eq(@site.site_status(site)[6], 10L)
  exclusive.val = true
  assert_true(runtime.cleanup(request) is Ok(true))
  assert_false(runtime.cleanup(request).unwrap())
  assert_eq(@site.site_status(site)[6], 0L)
  assert_eq(@site.site_status(site)[4], 0L)
  assert_eq(executions.val, 0)
  assert_false(
    bundles
    .release("dispatch:" + @remote.dispatch_request_identity(request))
    .unwrap(),
  )
  assert_true(runtime.close().unwrap())
  assert_false(bundles.release("runtime-process:" + name).unwrap())
  assert_true(journal.close())
  assert_true(bundles.close().unwrap())
}

///|
test "native restoration revocation after physical callback moves exact output to cleanup" {
  let bundles = restored_runtime_bundles(name="revoke-after-output")
  let bundle_cid = @env.get_env_var(
    "ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID",
  ).unwrap()
  let binding = @remote.prepare_remote_input_binding("{}", 16).unwrap()
  let budget = @remote.prepare_remote_dispatch_budget(128L, 128L).unwrap()
  let executions = Ref(0)
  let (journal, request, root, name, _, site) = restored_output_fixture(
    "restoration-revoke-after-output",
    runtime_bundle_cid=Some(bundle_cid),
    input_binding_cid=Some(@remote.remote_input_binding_cid(binding)),
    budget_cid=Some(@remote.remote_dispatch_budget_cid(budget)),
  )
  let runtime = restored_runtime(
    bundles, journal, site, name, budget, executions,
  )
  let opens = Ref(0)
  let cleanup_opens = Ref(0)
  let port : @runtime.NativeCompletedCleanupRestoration = {
    current: () => true,
    restore: _ => {
      cleanup_opens.val += 1
      () => false
    },
  }
  assert_true(
    runtime.restore_completed(
      request,
      binding,
      () => @site.site_available(site),
      recovered => {
        opens.val += 1
        let restored = @standard.restore_native_remote_standard_output(
          recovered,
          root,
          10L,
          () => true,
        )
        @site.revoke_site(site)
        match restored {
          @standard.NativeRestoredOutput(
            @runtime.NativeRemoteOutputReady(output)
          ) => @runtime.RestoredCompletedOutput(output)
          _ =>
            @runtime.CompletedOutputUnavailable("unexpected-output", () => false)
        }
      },
      cleanup=Some(port),
    )
    is @runtime.CompletedRuntimePending(
      @runtime.CleanupPending("restoration-authority")
    ),
  )
  assert_eq(opens.val, 1)
  assert_eq(cleanup_opens.val, 0)
  assert_true(
    runtime.open_output_reader(request, "original-generation", 10)
    is Err(@runtime.OutputReaderUnavailable),
  )
  assert_eq(@site.site_status(site)[6], 10L)
  assert_true(runtime.cleanup(request) is Ok(true))
  assert_false(runtime.cleanup(request).unwrap())
  assert_eq(@site.site_status(site)[6], 0L)
  assert_eq(@site.site_status(site)[4], 0L)
  assert_eq(executions.val, 0)
  assert_true(
    @filesystem.open_root(root).unwrap().inspect_generation("output-" + name)
    is Ok(None),
  )
  assert_false(
    bundles
    .release("dispatch:" + @remote.dispatch_request_identity(request))
    .unwrap(),
  )
  assert_true(runtime.close().unwrap())
  assert_false(bundles.release("runtime-process:" + name).unwrap())
  assert_true(journal.close())
  assert_true(bundles.close().unwrap())
}

///|
test "native cleanup survives first use refusal and rechecks custody after physical release" {
  let bundles = restored_runtime_bundles(name="refuse-use-cleanup-fence")
  let bundle_cid = @env.get_env_var(
    "ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID",
  ).unwrap()
  let binding = @remote.prepare_remote_input_binding("{}", 16).unwrap()
  let budget = @remote.prepare_remote_dispatch_budget(128L, 128L).unwrap()
  let executions = Ref(0)
  let (journal, request, root, name, _, site) = restored_output_fixture(
    "restoration-refuse-use-cleanup-fence",
    runtime_bundle_cid=Some(bundle_cid),
    input_binding_cid=Some(@remote.remote_input_binding_cid(binding)),
    budget_cid=Some(@remote.remote_dispatch_budget_cid(budget)),
  )
  let runtime = restored_runtime(
    bundles, journal, site, name, budget, executions,
  )
  let exclusive = Ref(true)
  let cleanup_calls = Ref(0)
  let port : @runtime.NativeCompletedCleanupRestoration = {
    current: () => exclusive.val,
    restore: _ => () => false,
  }
  assert_true(
    runtime.restore_completed(
      request,
      binding,
      () => true,
      recovered => {
        match
          @standard.restore_native_remote_standard_output(
            recovered,
            root,
            10L,
            () => false,
            cleanup_current=Some(() => exclusive.val),
          ) {
          @standard.NativeOutputRestorationPending(code, cleanup) =>
            @runtime.CompletedOutputUnavailable(code, () => {
              cleanup_calls.val += 1
              let released = cleanup()
              if cleanup_calls.val == 1 {
                exclusive.val = false
              }
              released
            })
          _ =>
            @runtime.CompletedOutputUnavailable("unexpected-readable-output", () => {
              false
            })
        }
      },
      cleanup=Some(port),
    )
    is @runtime.CompletedRuntimePending(
      @runtime.CompletedMaterialUnavailable("output-restore-current")
    ),
  )
  assert_true(
    runtime.open_output_reader(request, "original-generation", 10)
    is Err(@runtime.OutputReaderUnavailable),
  )
  assert_true(
    runtime.cleanup(request)
    is Err(@runtime.CleanupPending("restoration-custody")),
  )
  assert_true(
    @filesystem.open_root(root).unwrap().inspect_generation("output-" + name)
    is Ok(None),
  )
  assert_eq(@site.site_status(site)[6], 10L)
  assert_eq(@site.site_status(site)[4], 1L)
  assert_false(
    @remote.remote_runtime_record_released(journal.require(request).unwrap()),
  )
  exclusive.val = true
  assert_true(runtime.cleanup(request) is Ok(true))
  assert_false(runtime.cleanup(request).unwrap())
  assert_eq(cleanup_calls.val, 2)
  assert_eq(@site.site_status(site)[6], 0L)
  assert_eq(@site.site_status(site)[4], 0L)
  assert_eq(executions.val, 0)
  assert_false(
    bundles
    .release("dispatch:" + @remote.dispatch_request_identity(request))
    .unwrap(),
  )
  assert_true(runtime.close().unwrap())
  assert_false(bundles.release("runtime-process:" + name).unwrap())
  assert_true(journal.close())
  assert_true(bundles.close().unwrap())
}

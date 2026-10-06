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


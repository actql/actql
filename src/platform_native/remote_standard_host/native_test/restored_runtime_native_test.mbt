///|
fn restored_runtime_bundles(
  name? : String = "original",
) -> @bundle.NativeRuntimeBundleStore {
  let parent = @env.get_env_var("ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT").unwrap()
  @filesystem.open_root(parent).unwrap().create_directory(name).unwrap()
  |> ignore
  let root_path = parent + "/" + name
  let sqlite = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let crypto = @signature.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
  ).unwrap()
  let component = b"native-runtime"
  let root = @filesystem.open_root(root_path).unwrap()
  let writer = root
    .create_writer("runtime-stage", component.length().to_int64())
    .unwrap()
  writer.append(component).unwrap()
  let generation = writer.seal("runtime-component").unwrap()
  let store = @bundle.open_runtime_bundle_store(
    sqlite,
    crypto,
    root_path,
    [
      {
        issuer_authority: "bundle-authority-a",
        key_id: "key-a",
        public_key_pem: @env.get_env_var(
          "ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY",
        ).unwrap(),
      },
    ],
    "aarch64-apple-darwin",
    component.length().to_int64(),
    4,
    16,
    262144L,
  ).unwrap()
  store
  .adopt(
    "actql-remote-runtime-bundle-signature/0.1",
    "key-a",
    @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID").unwrap(),
    @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY").unwrap(),
    @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_SIGNATURE").unwrap(),
    "runtime-component",
    generation,
  )
  .unwrap()
  |> ignore
  store
  .activate(
    @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID").unwrap(),
  )
  .unwrap()
  |> ignore
  store
}

///|
fn restored_runtime(
  bundles : @bundle.NativeRuntimeBundleStore,
  journal : @journal.Journal,
  site : @site.ExecutionSite,
  name : String,
  budget : @remote.RemoteDispatchBudget,
  executions : Ref[Int],
) -> @runtime.NativeRemoteRuntime {
  let cid = "sha256:" + "a".repeat(64)
  let active = bundles
    .acquire_active_component(
      "sha256:" + @sha.hex(b"native-runtime"),
      "aarch64-apple-darwin",
      "runtime-process:" + name,
    )
    .unwrap()
  let executor = @runtime.install_native_remote_task_executor(cid, "task", (
    _,
    _,
    _,
  ) => {
    executions.val += 1
    @runtime.prepare_native_remote_failure(
      "unexpected-reexecution",
      false,
      false,
      true,
      () => true,
    ).unwrap()
  }).unwrap()
  let registration = @runtime.install_native_remote_runtime_registry_registration(
    site,
    active,
    cid,
    cid,
    [executor],
  ).unwrap()
  @runtime.open_native_remote_runtime(journal, bundles, [registration], [budget]).unwrap()
}

///|
test "native restored runtime owns capacity cleanup and exact retry without execution" {
  let bundles = restored_runtime_bundles()
  let bundle_cid = @env.get_env_var(
    "ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID",
  ).unwrap()
  let binding = @remote.prepare_remote_input_binding("{}", 16).unwrap()
  let budget = @remote.prepare_remote_dispatch_budget(128L, 128L).unwrap()
  let executions = Ref(0)
  let (journal, request, root, name, _, site) = restored_output_fixture(
    "runtime-restored-normal",
    runtime_bundle_cid=Some(bundle_cid),
    input_binding_cid=Some(@remote.remote_input_binding_cid(binding)),
    budget_cid=Some(@remote.remote_dispatch_budget_cid(budget)),
  )
  let runtime = restored_runtime(
    bundles, journal, site, name, budget, executions,
  )
  let revision = @remote.dispatch_record_revision(
    journal.require(request).unwrap(),
  )
  let current = Ref(true)
  let refused_opens = Ref(0)
  let unused = fn(_ : @journal.RecoveredSiteDispatch) {
    refused_opens.val += 1
    @runtime.CompletedOutputUnavailable("unexpected-refused-open", () => false)
  }
  assert_true(
    runtime.restore_completed(request, binding, () => false, unused)
    is @runtime.CompletedRuntimeRefused(@runtime.StartAuthorizationRejected),
  )
  assert_true(
    runtime.restore_completed(
      request,
      @remote.prepare_remote_input_binding("[]", 16).unwrap(),
      () => true,
      unused,
    )
    is @runtime.CompletedRuntimeRefused(
      @runtime.Protocol(@remote.DispatchIdentityMismatch)
    ),
  )
  let cid = "sha256:" + "a".repeat(64)
  let wrong_generation = @remote.prepare_dispatch_request(
    "authority",
    cid,
    "task",
    1,
    name,
    "site",
    2,
    bundle_cid,
    "local",
    "local/1",
    "strategy/1",
    @remote.remote_input_binding_cid(binding),
    cid,
    @remote.remote_dispatch_budget_cid(budget),
    cid,
    cid,
  ).unwrap()
  assert_true(
    runtime.restore_completed(wrong_generation, binding, () => true, unused)
    is @runtime.CompletedRuntimeRefused(@runtime.RuntimeUnsupported),
  )
  assert_eq(refused_opens.val, 0)
  assert_eq(@site.site_status(site)[6], 0L)
  guard @standard.restore_native_remote_standard_runtime_output(
      runtime,
      request,
      binding,
      root,
      10L,
      () => current.val,
    )
    is @runtime.CompletedRuntimeReady(completion) else {
    fail("original output restoration failed")
  }
  assert_eq(completion.revision, revision)
  assert_eq(executions.val, 0)
  assert_eq(@site.site_status(site)[6], 10L)
  assert_eq(@site.site_status(site)[4], 1L)
  assert_eq(@site.site_status(site)[2], 0L)
  let reopened = Ref(0)
  assert_true(
    runtime.restore_completed(request, binding, () => true, _ => {
      reopened.val += 1
      @runtime.CompletedOutputUnavailable("unexpected-reopen", () => false)
    })
    is @runtime.CompletedRuntimeReady(_),
  )
  assert_eq(reopened.val, 0)
  assert_eq(@site.site_status(site)[6], 10L)
  assert_eq(@site.site_status(site)[4], 1L)
  let reader = runtime
    .open_output_reader(request, "original-generation", 10)
    .unwrap()
  assert_eq(reader.next().unwrap().bytes, b"[{\"id\":3}]")
  assert_true(reader.next().unwrap().eof)
  assert_true(reader.finish().unwrap())
  current.val = false
  assert_true(
    runtime.observed_completion(request)
    is Err(@runtime.StartAuthorizationRejected),
  )
  assert_true(
    runtime.open_output_reader(request, "original-generation", 10)
    is Err(@runtime.OutputReaderUnavailable),
  )
  current.val = true
  assert_true(runtime.release(request).unwrap())
  assert_false(runtime.release(request).unwrap())
  assert_true(
    @remote.remote_runtime_record_released(journal.require(request).unwrap()),
  )
  assert_eq(@site.site_status(site)[6], 0L)
  assert_eq(@site.site_status(site)[4], 0L)
  assert_eq(executions.val, 0)
  assert_true(
    @filesystem.open_root(root).unwrap().inspect_generation("output-" + name)
    is Ok(None),
  )
  // No late start can turn the historical completion into a new executor call.
  assert_true(
    runtime.start(request, binding) is Err(@runtime.DispatchAlreadyStarted),
  )
  assert_true(runtime.close().unwrap())
  assert_true(journal.close())

  let (journal, request, root, name, _, site) = restored_output_fixture(
    "runtime-restored-corrupt",
    wrong_content=true,
    runtime_bundle_cid=Some(bundle_cid),
    input_binding_cid=Some(@remote.remote_input_binding_cid(binding)),
    budget_cid=Some(@remote.remote_dispatch_budget_cid(budget)),
  )
  let runtime = restored_runtime(
    bundles, journal, site, name, budget, executions,
  )
  let original = @remote.dispatch_record_state_codes(
    journal.require(request).unwrap(),
  )
  let cleanup_attempts = Ref(0)
  assert_true(
    runtime.restore_completed(request, binding, () => true, recovered => {
      match
        @standard.restore_native_remote_standard_output(recovered, root, 10L, () => {
          true
        }) {
        @standard.NativeOutputRestorationPending(code, cleanup) =>
          @runtime.CompletedOutputUnavailable(code, () => {
            cleanup_attempts.val += 1
            cleanup_attempts.val > 1 && cleanup()
          })
        @standard.NativeRestoredOutput(@runtime.NativeRemoteOutputReady(output)) =>
          @runtime.RestoredCompletedOutput(output)
        _ =>
          @runtime.CompletedOutputUnavailable("unexpected-output", () => false)
      }
    })
    is @runtime.CompletedRuntimePending(
      @runtime.CompletedMaterialUnavailable("output-restore-content")
    ),
  )
  assert_eq(
    @remote.dispatch_record_state_codes(journal.require(request).unwrap()),
    original,
  )
  assert_eq(@site.site_status(site)[6], 10L)
  assert_true(runtime.cleanup_pending())
  assert_true(
    runtime.observed_completion(request)
    is Err(@runtime.OutputReaderUnavailable),
  )
  assert_true(
    runtime.cleanup(request) is Err(@runtime.CleanupPending("output")),
  )
  assert_eq(@site.site_status(site)[6], 10L)
  assert_true(runtime.cleanup_pending())
  assert_false(
    @remote.remote_runtime_record_released(journal.require(request).unwrap()),
  )
  assert_true(runtime.cleanup(request).unwrap())
  assert_false(runtime.cleanup(request).unwrap())
  assert_eq(cleanup_attempts.val, 2)
  assert_true(
    @remote.remote_runtime_record_released(journal.require(request).unwrap()),
  )
  assert_eq(@site.site_status(site)[6], 0L)
  assert_eq(executions.val, 0)
  assert_true(runtime.close().unwrap())
  assert_true(journal.close())

  let (journal, request, root, name, _, site) = restored_output_fixture(
    "runtime-restored-capacity",
    runtime_bundle_cid=Some(bundle_cid),
    input_binding_cid=Some(@remote.remote_input_binding_cid(binding)),
    budget_cid=Some(@remote.remote_dispatch_budget_cid(budget)),
  )
  let runtime = restored_runtime(
    bundles, journal, site, name, budget, executions,
  )
  let occupied = @site.retain_site_holding(site, 995L).unwrap()
  let opened = Ref(0)
  assert_true(
    runtime.restore_completed(request, binding, () => true, _ => {
      opened.val += 1
      @runtime.CompletedOutputUnavailable("unexpected-open", () => false)
    })
    is @runtime.CompletedRuntimePending(@runtime.CapacityRejected),
  )
  assert_eq(opened.val, 0)
  assert_eq(@site.site_status(site)[6], 995L)
  assert_true(runtime.retains_dispatch_resources())
  assert_true(
    runtime.start(request, binding) is Err(@runtime.CompletedRestorationPending),
  )
  assert_true(
    runtime.release(request)
    is Err(@runtime.Protocol(@remote.MaterialUnavailable)),
  )
  assert_true(runtime.close() is Err(@runtime.CompletedRestorationPending))
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
    is @runtime.CompletedRuntimeReady(_),
  )
  assert_eq(@site.site_status(site)[6], 10L)
  assert_eq(@site.site_status(site)[4], 1L)
  assert_true(runtime.release(request).unwrap())
  assert_eq(@site.site_status(site)[6], 0L)
  assert_eq(executions.val, 0)
  assert_true(runtime.close().unwrap())
  assert_true(journal.close())
  let (journal, request, root, name, _, site) = restored_output_fixture(
    "runtime-restored-concurrent-release",
    runtime_bundle_cid=Some(bundle_cid),
    input_binding_cid=Some(@remote.remote_input_binding_cid(binding)),
    budget_cid=Some(@remote.remote_dispatch_budget_cid(budget)),
  )
  let runtime = restored_runtime(
    bundles, journal, site, name, budget, executions,
  )
  let observer = @journal.open_journal(
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
  let strict_refused = Ref(false)
  assert_true(
    runtime.restore_completed(request, binding, () => true, recovered => {
      let restored = @standard.restore_native_remote_standard_output(
        recovered,
        root,
        10L,
        () => true,
      )
      // A second connection/control progresses cleanup during physical I/O.
      // It cannot update Runtime's cached record through an in-process alias.
      // Use the existing transition owner, never direct journal mutation.
      let record = observer.require(request).unwrap()
      observer
      .commit_transition(@remote.prepare_begin_remote_release(record).unwrap())
      .unwrap()
      strict_refused.val = journal.require(request)
        is Err(@journal.Protocol(@remote.StateCollision))
      match restored {
        @standard.NativeRestoredOutput(@runtime.NativeRemoteOutputReady(output)) =>
          @runtime.RestoredCompletedOutput(output)
        @standard.NativeOutputRestorationPending(code, cleanup) =>
          @runtime.CompletedOutputUnavailable(code, cleanup)
        _ =>
          @runtime.CompletedOutputUnavailable("unexpected-output", () => false)
      }
    })
    is @runtime.CompletedRuntimePending(
      @runtime.CleanupPending("restoration-transition")
    ),
  )
  assert_true(strict_refused.val)
  assert_true(
    runtime.observed_completion(request)
    is Err(@runtime.OutputReaderUnavailable),
  )
  assert_eq(@site.site_status(site)[6], 10L)
  assert_false(
    @remote.remote_runtime_record_released(journal.require(request).unwrap()),
  )
  assert_true(runtime.cleanup(request).unwrap())
  assert_false(runtime.cleanup(request).unwrap())
  assert_true(
    @remote.remote_runtime_record_released(journal.require(request).unwrap()),
  )
  assert_eq(@site.site_status(site)[6], 0L)
  assert_eq(executions.val, 0)
  assert_true(observer.close())
  assert_true(runtime.close().unwrap())
  assert_true(journal.close())
  assert_true(bundles.close().unwrap())
}

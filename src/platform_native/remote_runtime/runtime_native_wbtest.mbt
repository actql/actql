///|
fn runtime_test_cid(character : String) -> String {
  "sha256:" + character
}

///|
fn required_env(name : String) -> String? {
  @env.get_env_var(name)
}

///|
test "native remote runtime owns success failure and cleanup progression" {
  guard required_env("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(sqlite_path) else {
    return
  }
  guard required_env("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(crypto_path) else {
    return
  }
  guard required_env("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_ROOT") is Some(root_path) else {
    return
  }
  guard required_env("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_TARGET") is Some(target) else {
    return
  }
  guard required_env("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY")
    is Some(public_key) else {
    return
  }
  guard required_env("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY")
    is Some(bundle_body) else {
    return
  }
  guard required_env("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID")
    is Some(bundle_cid) else {
    return
  }
  guard required_env("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_SIGNATURE")
    is Some(signature) else {
    return
  }
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let crypto = @signature.load_library(crypto_path).unwrap()
  let root = @filesystem.open_root(root_path).unwrap()
  let component = b"native-runtime"
  let writer = root
    .create_writer("runtime-stage", component.length().to_int64())
    .unwrap()
  writer.append(component).unwrap()
  let generation = writer.seal("runtime-component").unwrap()
  let bundles = @bundle.open_runtime_bundle_store(
    sqlite,
    crypto,
    root_path,
    [
      {
        issuer_authority: "bundle-authority-a",
        key_id: "key-a",
        public_key_pem: public_key,
      },
    ],
    target,
    component.length().to_int64(),
    4,
    8,
    262144L,
  ).unwrap()
  bundles
  .adopt(
    "actql-remote-runtime-bundle-signature/0.1", "key-a", bundle_cid, bundle_body,
    signature, "runtime-component", generation,
  )
  .unwrap()
  |> ignore
  bundles.activate(bundle_cid).unwrap() |> ignore
  let site = @site.create_site(
    "native-runtime-site", 1, bundle_cid, 2, 2, 1024L, 1024L,
  ).unwrap()
  let control = @remote.create_site_dispatch_journal(
    site, "actql-remote-site/0.1",
  ).unwrap()
  let journal = @journal.open_journal(
    sqlite,
    root_path + "/runtime-journal.sqlite3",
    262144L,
    control,
  ).unwrap()
  let budget = @remote.prepare_remote_dispatch_budget(128L, 128L).unwrap()
  let operation_capability = runtime_test_cid(
    "4444444444444444444444444444444444444444444444444444444444444444",
  )
  let issuer_capability = runtime_test_cid(
    "5555555555555555555555555555555555555555555555555555555555555555",
  )
  let executions = [0]
  let released = [0]
  let stopped = [0]
  let registration = install_native_remote_runtime_registration(
    site,
    bundle_cid,
    "local",
    "local/1",
    "strategy/1",
    operation_capability,
    issuer_capability,
    (_request, binding) => {
      if @remote.remote_input_binding_body(binding) == "{}" {
        executions[0] += 1
      } else {
        executions[0] += 1000
      }
      if executions[0] == 2 {
        return prepare_native_remote_failure(
          "native-stop-pending",
          false,
          true,
          false,
          () => {
            stopped[0] += 1
            true
          },
        ).unwrap()
      }
      let measurement = @remote.prepare_remote_managed_output_measurement(
        1,
        1,
        1,
        1,
        [1],
        [1],
        [1],
        [1],
        [0],
        [1],
      ).unwrap()
      let output_release_attempts = [0]
      prepare_native_remote_output(
        {
          material_generation: "native-material-a",
          holding_evidence_cid: runtime_test_cid(
            "6666666666666666666666666666666666666666666666666666666666666666",
          ),
          managed_profile_cid: runtime_test_cid(
            "7777777777777777777777777777777777777777777777777777777777777777",
          ),
          result_schema_cid: runtime_test_cid(
            "8888888888888888888888888888888888888888888888888888888888888888",
          ),
          logical_view_cid: runtime_test_cid(
            "9999999999999999999999999999999999999999999999999999999999999999",
          ),
          representation_codec_cid: runtime_test_cid(
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          ),
          physical_manifest_cid: runtime_test_cid(
            "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          ),
          row_count: 1,
          retained_bytes: 1L,
          measurement,
        },
        () => {
          released[0] += 1
          output_release_attempts[0] += 1
          output_release_attempts[0] > 1
        },
      ).unwrap()
    },
  ).unwrap()
  let runtime = open_native_remote_runtime(journal, bundles, [registration], [
    budget,
  ]).unwrap()
  let request = fn(dispatch_id : String) {
    @remote.prepare_dispatch_request(
      "native-coordinator",
      runtime_test_cid(
        "0000000000000000000000000000000000000000000000000000000000000000",
      ),
      "task-a",
      match dispatch_id {
        "dispatch-a" => 1
        "dispatch-b" => 2
        "dispatch-c" => 3
        _ => 4
      },
      dispatch_id,
      "native-runtime-site",
      1,
      bundle_cid,
      "local",
      "local/1",
      "strategy/1",
      runtime_test_cid(
        "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
      ),
      runtime_test_cid(
        "2222222222222222222222222222222222222222222222222222222222222222",
      ),
      @remote.remote_dispatch_budget_cid(budget),
      issuer_capability,
      operation_capability,
    ).unwrap()
  }
  let input_binding = @remote.prepare_remote_input_binding("{}", 16).unwrap()
  let first = request("dispatch-a")
  let completion = runtime.start(first, input_binding).unwrap()
  assert_eq(
    completion.dispatch_request_cid,
    @remote.dispatch_request_identity(first),
  )
  assert_eq(executions[0], 1)
  assert_true(runtime.release(first) is Err(CleanupPending("output")))
  assert_true(runtime.release(first).unwrap())
  assert_eq(released[0], 2)
  let second = request("dispatch-b")
  assert_true(
    runtime.start(second, input_binding) is Err(Physical("native-stop-pending")),
  )
  assert_true(runtime.cleanup_pending())
  assert_true(runtime.cleanup(second).unwrap())
  assert_eq(stopped[0], 1)
  assert_false(runtime.cleanup_pending())
  let status = @site.site_status(site)
  assert_eq(status[2], 0L)
  assert_eq(status[4], 0L)
  assert_eq(status[6], 0L)
  assert_eq(status[7], 0L)
  assert_eq(status[8], 0L)
  runtime.start(request("dispatch-c"), input_binding).unwrap() |> ignore
  runtime.start(request("dispatch-d"), input_binding).unwrap() |> ignore
  assert_true(runtime.close() is Err(CleanupPending("output")))
  assert_eq(released[0], 4)
  assert_false(runtime.close().unwrap())
  assert_eq(released[0], 6)
  assert_true(journal.close())
  assert_true(bundles.close().unwrap())
}

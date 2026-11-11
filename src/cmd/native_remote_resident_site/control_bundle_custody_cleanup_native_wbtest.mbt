///|
fn control_bundle_test_body(revision : String) -> String {
  "{\"bundle_name\":\"native-runtime\",\"components\":[{\"bytes\":\"11\"," +
  "\"cid\":\"sha256:" +
  "5cbfccb321655cdc50146d4dad052ac646ba09180cefd34d8c48cd248166346f\"," +
  "\"role\":\"runtime_executable\"}]," +
  "\"connector_registration\":\"local\",\"connector_revision\":\"local/" +
  revision +
  "\",\"issuer_authority\":\"bundle-authority-a\",\"revision\":\"native/" +
  revision +
  "\",\"strategy_revision\":\"strategy/1\"," +
  "\"target_triple\":\"aarch64-apple-darwin\"," +
  "\"version\":\"actql-remote-runtime-bundle/0.1\"}"
}

///|
fn control_bundle_test_cid(revision : String) -> String {
  match revision {
    "1" =>
      "sha256:a9be58865e039acd3c0921b70b86b5ede2a2047dbabab24abbad9af51cf09f5d"
    "2" =>
      "sha256:8199ffa40a83b6147f2dc69a44117be8568ff4dada1d506bf4c8ed488573c8a3"
    "3" =>
      "sha256:e829a99edcad82a5fd56b2f68339c25bf7bb0e91ca7d81905427f2c3c30fa88c"
    "4" =>
      "sha256:107c2ea5cbadf49edd7f8508826ae04a72aecf8791588b978b2cfe4fd777cf53"
    _ => ""
  }
}

///|
fn control_bundle_test_signature(revision : String) -> String {
  match revision {
    "1" =>
      "uEiiGpn1eP-fd03qFXRUB1ADYqE_0kekPwA1HCXMGSdhuk_ecyOECxmymphETVciPuhlFiiA5CS_NW17mTeXAg"
    "2" =>
      "6rqZ1dpERg5vQhVNV6hmpHx3P37JRQXr2a0FB3kyqQVSIWwyJNW_ZlGGcA1YdcBZ54-yhbIOSUM0hBtc0O5kCg"
    "3" =>
      "ZpobnHVpe5065mOgHMVIC82n60vikn37qD0O2Z1F5DcjiEi4dAA9yy8EjKFwblLGyNOxXFEM0RNtzSwcpzz8AQ"
    "4" =>
      "iIUeRdz3abH3gqj7fdCMGn6hoHpY1YBFb_uF1rYezrKgGHZlHA7ANOe2vBSWCvVzfGidPkodx2KB0cYEmN2FDA"
    _ => ""
  }
}

///|
fn control_bundle_test_authorities() -> Array[
  @bundle.NativeRuntimeBundleAuthority,
] {
  [
    {
      issuer_authority: "bundle-authority-a",
      key_id: "key-a",
      public_key_pem: "-----BEGIN PUBLIC KEY-----\n" +
      "MCowBQYDK2VwAyEA0EqyMnQrtKs6E2i9RhXk5tAiSrcaAWuvhSCjMsl3hzc=\n" +
      "-----END PUBLIC KEY-----\n",
    },
  ]
}

///|
fn control_bundle_test_open(
  name : String,
) -> (@bundle.NativeRuntimeBundleStore, String) {
  let parent = @env.get_env_var("ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT").unwrap()
  let root = @filesystem.open_root(parent).unwrap()
  root.create_directory(name).unwrap() |> ignore
  root.close().unwrap()
  let path = parent + "/" + name
  let store = @bundle.open_runtime_bundle_store_with_custody(
    @sqlite.load_library(
      @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
    ).unwrap(),
    @signature.load_library(
      @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
    ).unwrap(),
    path,
    control_bundle_test_authorities(),
    "aarch64-apple-darwin",
    22L,
    8,
    8,
    1048576L,
  ).unwrap()
  (store, path)
}

///|
fn control_bundle_test_delivery() -> @remote.RemotePollBundleCustody {
  let distribution = @bundle_protocol.prepare_bundle_distribution([
    control_bundle_test_cid("1"),
  ]).unwrap()
  let scope = @bundle_protocol.prepare_bundle_hold_scope(
    distribution,
    "coordinator-a",
    "workspace-a",
    "sha256:" + "a".repeat(64),
    "development",
    "sha256:" + "b".repeat(64),
    control_bundle_test_cid("1"),
    "site-a",
    7,
    "original-attempt",
  ).unwrap()
  let request = @bundle_protocol.prepare_bundle_custody_context_query(
    distribution, scope,
  ).unwrap()
  @remote.admit_remote_poll_bundle_custody_json(
    @remote.remote_poll_bundle_custody_json(request, 37L).unwrap(),
  ).unwrap()
}

///|
fn control_bundle_test_install(
  store : @bundle.NativeRuntimeBundleStore,
  revision : String,
) -> @bundle.NativeRuntimeBundleInstaller {
  store
  .begin_install(
    "original-install-" + revision,
    "actql-remote-runtime-bundle-signature/0.1",
    "key-a",
    control_bundle_test_cid(revision),
    control_bundle_test_body(revision),
    control_bundle_test_signature(revision),
  )
  .unwrap()
}

///|
test "control Bundle cleanup keeps original Store and Slot until physical ACK before report" {
  let progress_events : Array[(String, Array[(String, String)])] = []
  let observe_progress = (kind, fields) => progress_events.push((kind, fields))
  let (store, path) = control_bundle_test_open("control-bundle-report")
  let installer = control_bundle_test_install(store, "1")
  installer.append(b"runtime-one").unwrap()
  installer.seal().unwrap() |> ignore
  store.activate(control_bundle_test_cid("1")).unwrap() |> ignore
  let delivery = control_bundle_test_delivery()
  let configuration : @agent.NativeBundleCustodyConfiguration = {
    coordinator_authority: "coordinator-a",
    workspace_id: "workspace-a",
    authority_scope_cid: "sha256:" + "a".repeat(64),
    environment: "development",
    runtime_bundle_cid: control_bundle_test_cid("1"),
    site_key: "site-a",
    site_generation: 7,
    connector_registration: "local",
    connector_revision: "local/1",
    strategy_revision: "strategy/1",
  }
  let response = @agent.prepare_native_bundle_custody_response(
    store, delivery, configuration, "coordinator-a", true,
  ).unwrap()
  let expected_response = @bundle_protocol.bundle_custody_response_identity(
    response,
  )
  // A real active installer makes Store.close_checked refuse retirement.
  let pending_install = control_bundle_test_install(store, "2")
  let slot = @slot.open_native_executor_slot(path + "/original.slot").unwrap()
  assert_true(slot.try_acquire().unwrap())
  let original = control_bundle_custody_cleanup(
    delivery,
    slot,
    BundleCustodyPrepared(response),
    store=Some(store),
  )
  assert_true(
    advance_control_bundle_custody_cleanup(
      original,
      report_progress=observe_progress,
    )
    is Some(Retiring(same)) &&
    physical_equal(same, original),
  )
  assert_true(original.store is Some(same) && physical_equal(same, store))
  assert_eq(slot.verify_current_hold(), Ok(()))
  assert_false(original.slot_retired)
  assert_true(
    advance_control_bundle_custody_cleanup(
      original,
      report_progress=observe_progress,
    )
    is Some(Retiring(_)),
  )
  pending_install.cancel().unwrap()
  let pending = match
    advance_control_bundle_custody_cleanup(
      original,
      report_progress=observe_progress,
    ) {
    Some(Responding(same)) => same
    _ => {
      fail(
        "physical ACK did not pass the original response to its report Owner",
      )
      return
    }
  }
  assert_true(original.store is None)
  assert_true(original.slot_retired)
  let mut sends = 0
  let mut same_delivery = false
  let mut same_response = false
  // Callback response loss is synthetic; it does not reopen or mutate Store.
  let (remaining, reply) = @agent.advance_native_bundle_custody_report(
    Some(pending),
    fn(actual_delivery, actual_response) {
      sends += 1
      same_delivery = physical_equal(actual_delivery, delivery)
      same_response = @bundle_protocol.bundle_custody_response_identity(
          actual_response,
        ) ==
        expected_response
      Err(@client.HttpStatus(503))
    },
  )
  assert_eq(sends, 1)
  assert_true(same_delivery)
  assert_true(same_response)
  assert_true(reply is None)
  assert_true(remaining is Some(same) && physical_equal(same, pending))
  let request = @remote.remote_poll_bundle_custody_request(delivery)
  let ack = @remote.admit_remote_bundle_custody_observation_reply_json(
    @remote.remote_bundle_custody_observation_ack_json(request, response, 37L).unwrap(),
    request,
    response,
    37L,
  ).unwrap()
  let (remaining, reply) = @agent.advance_native_bundle_custody_report(
    remaining,
    (_, _) => Ok(ack),
  )
  assert_true(remaining is None)
  assert_true(reply is Some(Accepted))
  let next_slot = @slot.open_native_executor_slot(path + "/original.slot").unwrap()
  assert_true(next_slot.try_acquire().unwrap())
  assert_true(next_slot.close())
  assert_eq(progress_events, [])
}

///|
test "control Bundle uncertain action keeps original typed duty after physical cleanup" {
  let progress_events : Array[(String, Array[(String, String)])] = []
  let observe_progress = (kind, fields) => progress_events.push((kind, fields))
  let (store, path) = control_bundle_test_open("control-bundle-uncertain")
  let slot = @slot.open_native_executor_slot(path + "/original.slot").unwrap()
  assert_true(slot.try_acquire().unwrap())
  // An explicitly injected uncertain Owner result, not an observed SQL fault.
  let original = control_bundle_custody_cleanup(
    control_bundle_test_delivery(),
    slot,
    BundleCustodyUncertain(@agent.Store(@bundle.CleanupPending)),
    store=Some(store),
  )
  assert_true(
    advance_control_bundle_custody_cleanup(
      original,
      report_progress=observe_progress,
    )
    is Some(Unconfirmed(same)) &&
    physical_equal(same, original),
  )
  assert_true(original.store is None)
  assert_true(original.slot_retired)
  assert_true(
    original.completion
    is BundleCustodyUncertain(@agent.Store(@bundle.CleanupPending)),
  )
  assert_true(
    advance_control_bundle_custody_cleanup(
      original,
      report_progress=observe_progress,
    )
    is Some(Unconfirmed(same)) &&
    physical_equal(same, original),
  )
  assert_eq(progress_events, [
    (
      "bundle-custody-unconfirmed",
      [
        ("reason", "original-store-outcome"),
        ("category", "store"),
        ("slot-state", "retired"),
      ],
    ),
    (
      "bundle-custody-unconfirmed",
      [
        ("reason", "original-store-outcome"),
        ("category", "store"),
        ("slot-state", "retired"),
      ],
    ),
  ])
}

///|
test "control Bundle failed constructor keeps its original cleanup carrier through retirement" {
  let progress_events : Array[(String, Array[(String, String)])] = []
  let observe_progress = (kind, fields) => progress_events.push((kind, fields))
  let parent = @env.get_env_var("ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT").unwrap()
  let root = @filesystem.open_root(parent).unwrap()
  root.create_directory("control-bundle-open-failure").unwrap() |> ignore
  root.close().unwrap()
  let path = parent + "/control-bundle-open-failure"
  let directory = @filesystem.open_root(path).unwrap()
  directory.create_directory(".actql-runtime-bundle.sqlite3").unwrap() |> ignore
  directory.close().unwrap()
  let failure = match
    @bundle.open_runtime_bundle_store_with_custody(
      @sqlite.load_library(
        @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
      ).unwrap(),
      @signature.load_library(
        @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
      ).unwrap(),
      path,
      control_bundle_test_authorities(),
      "aarch64-apple-darwin",
      22L,
      8,
      8,
      1048576L,
    ) {
    Err(CleanupRequired(original)) => original
    _ => {
      fail("mandatory failed constructor did not return acquired custody")
      return
    }
  }
  let slot = @slot.open_native_executor_slot(path + "/original.slot").unwrap()
  assert_true(slot.try_acquire().unwrap())
  let original = control_bundle_custody_cleanup(
    control_bundle_test_delivery(),
    slot,
    BundleCustodyRejected("store-open-failed"),
    failed_store=Some(failure),
  )
  assert_true(
    original.failed_store is Some(same) && physical_equal(same, failure),
  )
  assert_false(original.slot_retired)
  assert_true(failure.issue() is @bundle.Database(@sqlite.DatabaseOpen(_)))
  assert_true(
    advance_control_bundle_custody_cleanup(
      original,
      report_progress=observe_progress,
    )
    is None,
  )
  assert_true(original.failed_store is None)
  assert_true(original.slot_retired)
  assert_true(failure.issue() is @bundle.Database(@sqlite.DatabaseOpen(_)))
  assert_true(retry_control_bundle_custody_cleanup(original))
  assert_eq(progress_events, [
    ("bundle-custody-refused", [("reason", "store-open-failed")]),
  ])
}

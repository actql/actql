// Real signed Store fixture; no runtime execution or mock custody success.

///|
fn native_bundle_body(revision : String) -> String {
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
fn native_bundle_cid(revision : String) -> String {
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
fn native_bundle_signature(revision : String) -> String {
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
fn native_bundle_authorities() -> Array[@bundle.NativeRuntimeBundleAuthority] {
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
test "outbound typed Bundle receiver retains real Store custody across restart and rejects late reply" {
  // Required physical fixture inputs deliberately fail if absent.
  let parent = @env.get_env_var("ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT").unwrap()
  let root = @filesystem.open_root(parent).unwrap()
  root.create_directory("outbound-custody").unwrap() |> ignore
  let child = root.open_child("outbound-custody").unwrap()
  let path = parent + "/outbound-custody"
  let sqlite = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let crypto = @signature.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
  ).unwrap()
  let writer = child.create_writer("stage", 11L).unwrap()
  writer.append(b"runtime-one").unwrap()
  let generation = writer.seal("artifact").unwrap()
  child.close().unwrap()
  root.close().unwrap()
  let store = @bundle.open_runtime_bundle_store(
    sqlite,
    crypto,
    path,
    native_bundle_authorities(),
    "aarch64-apple-darwin",
    22L,
    8,
    8,
    1048576L,
  ).unwrap()
  store
  .adopt(
    "actql-remote-runtime-bundle-signature/0.1",
    "key-a",
    native_bundle_cid("1"),
    native_bundle_body("1"),
    native_bundle_signature("1"),
    "artifact",
    generation,
  )
  .unwrap()
  |> ignore
  store.activate(native_bundle_cid("1")).unwrap() |> ignore
  let distribution = @bundle_protocol.prepare_bundle_distribution([
    native_bundle_cid("1"),
  ]).unwrap()
  let scope = @bundle_protocol.prepare_bundle_hold_scope(
    distribution,
    "coordinator-a",
    "workspace-a",
    "sha256:" + "a".repeat(64),
    "development",
    "sha256:" + "b".repeat(64),
    native_bundle_cid("1"),
    "site-a",
    7,
    "original-attempt",
  ).unwrap()
  let configuration : @agent.NativeBundleCustodyConfiguration = {
    coordinator_authority: "coordinator-a",
    workspace_id: "workspace-a",
    authority_scope_cid: "sha256:" + "a".repeat(64),
    environment: "development",
    runtime_bundle_cid: native_bundle_cid("1"),
    site_key: "site-a",
    site_generation: 7,
    connector_registration: "local",
    connector_revision: "local/1",
    strategy_revision: "strategy/1",
  }
  let context = @bundle_protocol.prepare_bundle_custody_context_query(
    distribution, scope,
  ).unwrap()
  let delivery = @remote.admit_remote_poll_bundle_custody_json(
    @remote.remote_poll_bundle_custody_json(context, 1L).unwrap(),
  ).unwrap()
  assert_true(
    @agent.prepare_native_bundle_custody_response(
      store,
      delivery,
      { ..configuration, connector_revision: "other", },
      "coordinator-a",
      true,
    )
    is Err(@agent.RegistrationMismatch),
  )
  let response = @agent.prepare_native_bundle_custody_response(
    store, delivery, configuration, "coordinator-a", true,
  ).unwrap()
  let binding = @bundle_protocol.bundle_custody_response_binding(response)
  let retain = @bundle_protocol.prepare_bundle_custody_request(
    distribution, binding, "retain",
  ).unwrap()
  let retain_wire = @remote.remote_poll_bundle_custody_json(retain, 2L).unwrap()
  let delivery = @remote.admit_remote_poll_bundle_custody_json(retain_wire).unwrap()
  assert_true(
    @agent.prepare_native_bundle_custody_response(
      store, delivery, configuration, "foreign", true,
    )
    is Err(@agent.AuthorityRejected),
  )
  assert_true(
    @agent.prepare_native_bundle_custody_response(
      store, delivery, configuration, "coordinator-a", false,
    )
    is Err(@agent.AdmissionClosed),
  )
  let retained = @agent.prepare_native_bundle_custody_response(
    store, delivery, configuration, "coordinator-a", true,
  ).unwrap()
  assert_eq(
    @bundle_protocol.bundle_custody_response_observation(retained),
    Some(@bundle_protocol.BundleHoldRetained),
  )
  let observation = @remote.remote_bundle_custody_observation_json(
    retain, retained, 2L,
  ).unwrap()
  let ack = @remote.remote_bundle_custody_observation_ack_json(
    retain, retained, 2L,
  ).unwrap()
  assert_true(store.close().unwrap())
  // Restart reconstructs the exact original pending binding; not a new context.
  let store = @bundle.open_runtime_bundle_store(
    sqlite,
    crypto,
    path,
    native_bundle_authorities(),
    "aarch64-apple-darwin",
    22L,
    8,
    8,
    1048576L,
  ).unwrap()
  let original = @remote.admit_remote_poll_bundle_custody_json(retain_wire).unwrap()
  let recovered = @agent.prepare_native_bundle_custody_response(
    store, original, configuration, "coordinator-a", true,
  ).unwrap()
  assert_eq(
    @remote.remote_bundle_custody_observation_json(retain, recovered, 2L).unwrap(),
    observation,
  )
  assert_true(
    @remote.admit_remote_bundle_custody_observation_ack_json(
      ack, retain, recovered, 3L,
    )
    is Err(_),
  )
  assert_true(
    @remote.admit_remote_bundle_custody_observation_json(
      observation, retain, 3L,
    )
    is Err(_),
  )
  let release = @bundle_protocol.prepare_bundle_custody_request(
    distribution, binding, "release",
  ).unwrap()
  let delivery = @remote.admit_remote_poll_bundle_custody_json(
    @remote.remote_poll_bundle_custody_json(release, 3L).unwrap(),
  ).unwrap()
  let released = @agent.prepare_native_bundle_custody_response(
    store, delivery, configuration, "coordinator-a", false,
  ).unwrap()
  assert_eq(
    @bundle_protocol.bundle_custody_response_observation(released),
    Some(@bundle_protocol.BundleHoldFenced),
  )
  let late = @agent.prepare_native_bundle_custody_response(
    store, original, configuration, "coordinator-a", true,
  ).unwrap()
  assert_eq(
    @bundle_protocol.bundle_custody_response_observation(late),
    Some(@bundle_protocol.BundleHoldFenced),
  )
  assert_true(store.close().unwrap())
}

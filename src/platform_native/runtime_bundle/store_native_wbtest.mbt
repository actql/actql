///|
fn native_bundle_body(revision : String) -> String {
  "{\"bundle_name\":\"native-runtime\",\"component_bytes\":\"11\"," +
  "\"component_cid\":\"sha256:" +
  "5cbfccb321655cdc50146d4dad052ac646ba09180cefd34d8c48cd248166346f\"," +
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
      "sha256:e5a10059631b11842bb9fafd38c222d20ddffbc28123915457d45273fbf22863"
    "2" =>
      "sha256:a89dd00a0bb36a2becd2e2d7f2b94081d6d8e1f5e4653d64437790df1510f61f"
    "3" =>
      "sha256:65c01d0428976c7f2d317391d05f03dc848dbd54cbe361350ee7c2e6c66a62a1"
    "4" =>
      "sha256:340343dca069b3c5c0224ff0f282beb31320c6f4a0e40db059be9533601f2812"
    _ => ""
  }
}

///|
fn native_bundle_signature(revision : String) -> String {
  match revision {
    "1" =>
      "cCQxbtE8Zb7nFFjgw88W3lXVmWB3qpC1YrFcUTmtmtx8oc4N6cvC6Dzv4aHSHI8qXrPS9TL_sCEXmQCN09TgCQ"
    "2" =>
      "bFlmRDpxcU4k5nd3d3g5Reo4s1Hdy_qtiJwts6fZqiba01Aeqfzq4qT3ZYsxbgSczC-GiDgs8TwWgutmVm0wCQ"
    "3" =>
      "e76Lms-YOo-AjBe3vYqT7ZCZUILepq_2VHWPS9Z89-i8kmYl0Lap9LrvzoZUpKtqx0s5KQ-qVaj5JXtRyh1BCQ"
    "4" =>
      "OcDRGqLfuxaSmcAmPApg1orT7OqFnilDGG24HzE7r5HlFtvLkyP5xnn51tP-Hzq6yOVc0SKJh7TRnJkTteUCCA"
    _ => ""
  }
}

///|
fn native_bundle_authorities() -> Array[NativeRuntimeBundleAuthority] {
  [
    {
      issuer_authority: "bundle-authority-a",
      key_id: "key-a",
      public_key_pem: "-----BEGIN PUBLIC KEY-----\n" +
      "MCowBQYDK2VwAyEA11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=\n" +
      "-----END PUBLIC KEY-----\n",
    },
  ]
}

///|
fn rotated_bundle_authority() -> NativeRuntimeBundleAuthority {
  {
    issuer_authority: "bundle-authority-b",
    key_id: "key-b",
    public_key_pem: "-----BEGIN PUBLIC KEY-----\n" +
    "MCowBQYDK2VwAyEANcMbAe2pxniljiDNtULyS6N23OFacFQwUGOy4GQL1P4=\n" +
    "-----END PUBLIC KEY-----\n",
  }
}

///|
fn rotated_bundle_body() -> String {
  "{\"bundle_name\":\"native-runtime\",\"component_bytes\":\"11\"," +
  "\"component_cid\":\"sha256:" +
  "5cbfccb321655cdc50146d4dad052ac646ba09180cefd34d8c48cd248166346f\"," +
  "\"connector_registration\":\"local\"," +
  "\"connector_revision\":\"local/rotation\"," +
  "\"issuer_authority\":\"bundle-authority-b\"," +
  "\"revision\":\"native/rotation\"," +
  "\"strategy_revision\":\"strategy/1\"," +
  "\"target_triple\":\"aarch64-apple-darwin\"," +
  "\"version\":\"actql-remote-runtime-bundle/0.1\"}"
}

///|
fn rotated_bundle_cid() -> String {
  "sha256:27b8a9bba8e0f071b19e4856920bdaa57a6550c2ddfda6c6163726922331033d"
}

///|
fn rotated_bundle_signature() -> String {
  "mr3OGOBwp4WkvNjXM7_bQc-Vj3WqKBypoYSFaLXQf074uOxYk3xwP54sCK7OcV0_" +
  "AyaU6Xqk3mCtULKIyHpYDg"
}

///|
fn rotation_trust(
  rotated_key_admits_new_bundles : Bool,
) -> Array[NativeRuntimeBundleTrust] {
  [
    { authority: native_bundle_authorities()[0], admit_new_bundles: false, },
    {
      authority: rotated_bundle_authority(),
      admit_new_bundles: rotated_key_admits_new_bundles,
    },
  ]
}

///|
fn native_bundle_fixture(
  label : String,
) -> (
  NativeRuntimeBundleStore,
  @filesystem.NativeFileGeneration,
  String,
  @sqlite.Library,
  @signature.Library,
)? {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return None
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY")
    is Some(crypto_path) else {
    return None
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(root_path) else {
    return None
  }
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let crypto = @signature.load_library(crypto_path).unwrap()
  let token = label + "-" + @env.now().to_string()
  let artifact_name = "bundle-component-" + @sha.hex(@utf8.encode(token))
  let root = @filesystem.open_root(root_path).unwrap()
  let writer = root
    .create_writer("stage-" + @sha.hex(@utf8.encode(token)), 11L)
    .unwrap()
  writer.append(b"runtime-one").unwrap()
  let generation = writer.seal(artifact_name).unwrap()
  let store = open_runtime_bundle_store(
    sqlite,
    crypto,
    root_path,
    native_bundle_authorities(),
    "aarch64-apple-darwin",
    22L,
    8,
    8,
    1048576L,
  ).unwrap()
  Some((store, generation, artifact_name, sqlite, crypto))
}

///|
fn adopt_native_bundle(
  store : NativeRuntimeBundleStore,
  generation : @filesystem.NativeFileGeneration,
  artifact_name : String,
  revision : String,
) -> NativeRuntimeBundleSnapshot {
  store
  .adopt(
    "actql-remote-runtime-bundle-signature/0.1",
    "key-a",
    native_bundle_cid(revision),
    native_bundle_body(revision),
    native_bundle_signature(revision),
    artifact_name,
    generation,
  )
  .unwrap()
}

///|
fn native_staging_record(
  store : NativeRuntimeBundleStore,
  install_id : String,
  revision : String,
  phase : NativeRuntimeBundleStagingPhase,
) -> NativeRuntimeBundleStaging {
  let runtime_bundle_cid = native_bundle_cid(revision)
  let manifest = admit_signed_bundle(
    store.signature_library,
    store.authorities,
    "actql-remote-runtime-bundle-signature/0.1",
    "key-a",
    runtime_bundle_cid,
    native_bundle_body(revision),
    native_bundle_signature(revision),
    store.target_triple,
  ).unwrap()
  let install_key = @sha.hex(
    @utf8.encode(install_id + "\u0000" + runtime_bundle_cid),
  )
  {
    install_id,
    manifest,
    signature_version: "actql-remote-runtime-bundle-signature/0.1",
    signature_key_id: "key-a",
    signature: native_bundle_signature(revision),
    artifact_name: "runtime-bundle-" +
    @sha.hex(@utf8.encode(runtime_bundle_cid)),
    staging_name: "runtime-stage-" + install_key,
    component_bytes: 11L,
    phase,
  }
}

///|
fn persist_test_staging(
  store : NativeRuntimeBundleStore,
  staging : NativeRuntimeBundleStaging,
) -> Unit {
  let current = load_catalog(store).unwrap()
  let values = current.staging.copy()
  values.push(staging)
  persist_catalog(
    store,
    current,
    with_catalog_staging(current, current.entries, values),
  ).unwrap()
}

///|
test "native bundle operations survive restart and preserve shared code" {
  guard native_bundle_fixture("lifecycle")
    is Some((store, generation, artifact_name, sqlite, crypto)) else {
    return
  }
  let first = adopt_native_bundle(store, generation, artifact_name, "1")
  let second = adopt_native_bundle(store, generation, artifact_name, "2")
  let shared_usage = store.capacity_usage().unwrap()
  assert_eq(shared_usage.reserved_bytes, 11L)
  assert_eq(shared_usage.reserved_objects, 1L)
  let root_path = @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap()
  let root = @filesystem.open_root(root_path).unwrap()
  let copied_name = artifact_name + "-copy"
  let copied_writer = root
    .create_writer(artifact_name + "-copy-stage", 11L)
    .unwrap()
  copied_writer.append(b"runtime-one").unwrap()
  let copied_generation = copied_writer.seal(copied_name).unwrap()
  let third = adopt_native_bundle(store, copied_generation, copied_name, "3")
  let copied_usage = store.capacity_usage().unwrap()
  assert_eq(copied_usage.reserved_bytes, 22L)
  assert_eq(copied_usage.reserved_objects, 2L)
  let excess_name = artifact_name + "-excess"
  let excess_writer = root
    .create_writer(artifact_name + "-excess-stage", 11L)
    .unwrap()
  excess_writer.append(b"runtime-one").unwrap()
  let excess_generation = excess_writer.seal(excess_name).unwrap()
  assert_true(
    store.adopt(
      "actql-remote-runtime-bundle-signature/0.1",
      "key-a",
      native_bundle_cid("4"),
      native_bundle_body("4"),
      native_bundle_signature("4"),
      excess_name,
      excess_generation,
    )
    is Err(CapacityExceeded),
  )
  root.reclaim_generation(excess_name, excess_generation).unwrap()
  assert_eq(first.state, ["0", "0", "0"])
  assert_true(
    store.acquire_active_component(
      "sha256:5cbfccb321655cdc50146d4dad052ac646ba09180cefd34d8c48cd248166346f",
      "aarch64-apple-darwin", "runtime-process:first",
    )
    is Err(MissingBundle),
  )
  store.activate(first.runtime_bundle_cid).unwrap() |> ignore
  assert_true(
    store.acquire_active_component(
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "aarch64-apple-darwin", "runtime-process:first",
    )
    is Err(ComponentMismatch),
  )
  assert_true(
    store.acquire_active_component(
      "sha256:5cbfccb321655cdc50146d4dad052ac646ba09180cefd34d8c48cd248166346f",
      "x86_64-unknown-linux-gnu", "runtime-process:first",
    )
    is Err(ComponentMismatch),
  )
  let binding = store
    .acquire_active_component(
      "sha256:5cbfccb321655cdc50146d4dad052ac646ba09180cefd34d8c48cd248166346f",
      "aarch64-apple-darwin", "runtime-process:first",
    )
    .unwrap()
  assert_eq(native_active_runtime_bundle_cid(binding), first.runtime_bundle_cid)
  assert_eq(
    native_active_runtime_component_cid(binding),
    "sha256:5cbfccb321655cdc50146d4dad052ac646ba09180cefd34d8c48cd248166346f",
  )
  assert_eq(
    native_active_runtime_target_triple(binding),
    "aarch64-apple-darwin",
  )
  assert_eq(
    native_active_runtime_connector_scope(binding),
    ("local", "local/1", "strategy/1"),
  )
  assert_eq(
    native_active_runtime_process_hold_id(binding),
    "runtime-process:first",
  )
  store.verify_active_component_binding(binding).unwrap()
  store.retain(first.runtime_bundle_cid, "attempt-a", "dispatch").unwrap()
  |> ignore
  store.activate(second.runtime_bundle_cid).unwrap() |> ignore
  assert_eq(store.inspect(first.runtime_bundle_cid).unwrap().unwrap().state, [
    "4", "2", "2",
  ])
  assert_true(
    open_runtime_bundle_store(
      sqlite,
      crypto,
      root_path,
      native_bundle_authorities(),
      "aarch64-apple-darwin",
      22L,
      8,
      8,
      1048576L,
    )
    is Err(Filesystem(@filesystem.Lock(_))),
  )
  assert_true(store.close().unwrap())

  assert_true(
    open_runtime_bundle_store(
      sqlite,
      crypto,
      root_path,
      native_bundle_authorities(),
      "aarch64-apple-darwin",
      21L,
      8,
      8,
      1048576L,
    )
    is Err(CapacityExceeded),
  )
  let reopened = open_runtime_bundle_store(
    sqlite,
    crypto,
    root_path,
    native_bundle_authorities(),
    "aarch64-apple-darwin",
    22L,
    8,
    8,
    1048576L,
  ).unwrap()
  assert_eq(
    reopened.active().unwrap().unwrap().runtime_bundle_cid,
    second.runtime_bundle_cid,
  )
  assert_true(reopened.release("attempt-a").unwrap())
  assert_true(reopened.release("runtime-process:first").unwrap())
  assert_true(
    reopened.verify_active_component_binding(binding) is Err(MissingBundle),
  )
  reopened.rollback(first.runtime_bundle_cid).unwrap() |> ignore
  reopened.activate(second.runtime_bundle_cid).unwrap() |> ignore
  reopened.reclaim(first.runtime_bundle_cid).unwrap() |> ignore
  reopened.verify(second.runtime_bundle_cid).unwrap() |> ignore
  reopened.reclaim(third.runtime_bundle_cid).unwrap() |> ignore
  let one_allocation = reopened.capacity_usage().unwrap()
  assert_eq(one_allocation.reserved_bytes, 11L)
  assert_eq(one_allocation.reserved_objects, 1L)
  assert_false(root.verify_generation(copied_name, copied_generation))
  assert_true(root.verify_generation(artifact_name, generation))
  reopened.drain(second.runtime_bundle_cid).unwrap() |> ignore
  assert_true(
    reopened.acquire_active_component(
      native_active_runtime_component_cid(binding),
      native_active_runtime_target_triple(binding),
      "runtime-process:drained",
    )
    is Err(MissingBundle),
  )
  reopened.reclaim(second.runtime_bundle_cid).unwrap() |> ignore
  let released_usage = reopened.capacity_usage().unwrap()
  assert_eq(released_usage.reserved_bytes, 0L)
  assert_eq(released_usage.reserved_objects, 0L)
  assert_true(reopened.recover().unwrap().length() == 3)
  assert_true(reopened.close().unwrap())
}

///|
test "native bundle adoption rejects altered authority and generation" {
  guard native_bundle_fixture("rejection")
    is Some((store, generation, artifact_name, _, _)) else {
    return
  }
  let original_count = store.list().unwrap().length()
  assert_true(
    store.adopt(
      "actql-remote-runtime-bundle-signature/0.1",
      "key-a",
      native_bundle_cid("1"),
      native_bundle_body("1"),
      "A" + native_bundle_signature("1")[1:].to_owned(),
      artifact_name,
      generation,
    )
    is Err(_),
  )
  assert_true(
    store.adopt(
      "actql-remote-runtime-bundle-signature/0.1",
      "key-a",
      native_bundle_cid("1"),
      native_bundle_body("1"),
      native_bundle_signature("1"),
      artifact_name,
      { ..generation, size: generation.size + 1L, },
    )
    is Err(ComponentMismatch),
  )
  assert_eq(store.list().unwrap().length(), original_count)
  assert_true(store.close().unwrap())
}

///|
test "native bundle install rejects capacity before creating output" {
  guard native_bundle_fixture("stream-capacity")
    is Some((store, _, _, sqlite, crypto)) else {
    return
  }
  assert_true(store.close().unwrap())
  let root_path = @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap()
  let bounded = open_runtime_bundle_store(
    sqlite,
    crypto,
    root_path,
    native_bundle_authorities(),
    "aarch64-apple-darwin",
    10L,
    8,
    8,
    1048576L,
  ).unwrap()
  assert_true(
    bounded.begin_install(
      "install-over-capacity",
      "actql-remote-runtime-bundle-signature/0.1",
      "key-a",
      native_bundle_cid("4"),
      native_bundle_body("4"),
      native_bundle_signature("4"),
    )
    is Err(CapacityExceeded),
  )
  assert_eq(bounded.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(bounded.inspect_install("install-over-capacity").unwrap(), None)
  assert_true(bounded.close().unwrap())
}

///|
test "exclusive install conflict never reclaims a preexisting staging file" {
  guard native_bundle_fixture("stream-existing-stage")
    is Some((store, _, _, _, _)) else {
    return
  }
  let staging = native_staging_record(
    store,
    "install-existing-stage",
    "4",
    Intent,
  )
  let foreign = store.root.create_writer(staging.staging_name, 7L).unwrap()
  foreign.append(b"foreign").unwrap()
  let before = store.root
    .inspect_generation(staging.staging_name)
    .unwrap()
    .unwrap()
  assert_true(
    store.begin_install(
      staging.install_id,
      staging.signature_version,
      staging.signature_key_id,
      staging_cid(staging),
      @bundle.bundle_manifest_json(staging.manifest).unwrap(),
      staging.signature,
    )
    is Err(Filesystem(@filesystem.Conflict)),
  )
  assert_eq(store.inspect_install(staging.install_id).unwrap(), None)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(
    store.root.inspect_generation(staging.staging_name).unwrap(),
    Some(before),
  )
  foreign.cancel().unwrap()
  assert_true(store.close().unwrap())
}

///|
test "seal conflict and cancel preserve a preexisting final artifact" {
  guard native_bundle_fixture("stream-existing-final")
    is Some((store, _, _, _, _)) else {
    return
  }
  let staging = native_staging_record(
    store,
    "install-existing-final",
    "4",
    Intent,
  )
  let foreign = store.root
    .create_writer(staging.artifact_name + "-foreign-stage", 7L)
    .unwrap()
  foreign.append(b"foreign").unwrap()
  let foreign_generation = foreign.seal(staging.artifact_name).unwrap()
  let installer = store
    .begin_install(
      staging.install_id,
      staging.signature_version,
      staging.signature_key_id,
      staging_cid(staging),
      @bundle.bundle_manifest_json(staging.manifest).unwrap(),
      staging.signature,
    )
    .unwrap()
  installer.append(b"runtime-one").unwrap()
  assert_true(installer.seal() is Err(Filesystem(@filesystem.Conflict)))
  installer.cancel().unwrap()
  assert_eq(store.inspect_install(staging.install_id).unwrap(), None)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(
    store.root.verify_generation(staging.artifact_name, foreign_generation),
  )
  foreign.cancel().unwrap()
  assert_true(store.close().unwrap())
}

///|
test "recovery rejects a replacement for an owned staging allocation" {
  guard native_bundle_fixture("stream-owned-replacement")
    is Some((store, _, _, _, _)) else {
    return
  }
  let intent = native_staging_record(
    store,
    "install-owned-replacement",
    "4",
    Intent,
  )
  persist_test_staging(store, intent)
  let original = store.root.create_writer(intent.staging_name, 11L).unwrap()
  let owned = record_staging_phase(
    store,
    intent,
    StagingOwned(original.ownership()),
  ).unwrap()
  original.cancel().unwrap()
  let replacement = store.root.create_writer(intent.staging_name, 11L).unwrap()
  replacement.append(b"runtime-one").unwrap()
  let replacement_generation = store.root
    .inspect_generation(intent.staging_name)
    .unwrap()
    .unwrap()
  assert_true(
    store.recover_install(intent.install_id)
    is Err(Filesystem(@filesystem.GenerationMismatch)),
  )
  assert_true(
    store.root.verify_generation(intent.staging_name, replacement_generation),
  )
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 11L)
  assert_true(
    same_staging_phase(
      load_catalog(store).unwrap().staging[0].phase,
      owned.phase,
    ),
  )
  replacement.cancel().unwrap()
  assert_true(store.recover_install(intent.install_id).unwrap())
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(store.close().unwrap())
}

///|
test "recovery retains reservation until post-unlink sync succeeds" {
  guard native_bundle_fixture("stream-sync-retry") is Some((store, _, _, _, _)) else {
    return
  }
  let intent = native_staging_record(store, "install-sync-retry", "4", Intent)
  persist_test_staging(store, intent)
  let writer = store.root.create_writer(intent.staging_name, 11L).unwrap()
  let owned = record_staging_phase(
    store,
    intent,
    StagingOwned(writer.ownership()),
  ).unwrap()
  writer.append(b"runtime-one").unwrap()
  let physical = cleanup_operations(store)
  let mut sync_failures = 2
  let injected : NativeRuntimeBundleCleanupOperations = {
    inspect: physical.inspect,
    reclaim: physical.reclaim,
    sync: fn() {
      if sync_failures > 0 {
        sync_failures = sync_failures - 1
        Err(Filesystem(@filesystem.Cleanup("injected root sync failure")))
      } else {
        (physical.sync)()
      }
    },
  }
  assert_true(
    recover_staging_install_with_operations(store, intent.install_id, injected)
    is Err(Filesystem(@filesystem.Cleanup(_))),
  )
  assert_eq(store.root.inspect_generation(intent.staging_name).unwrap(), None)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 11L)
  assert_true(store.inspect_install(intent.install_id).unwrap() is Some(_))
  assert_true(
    recover_staging_install_with_operations(store, intent.install_id, injected)
    is Err(Filesystem(@filesystem.Cleanup(_))),
  )
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 11L)
  assert_true(
    same_staging_phase(
      load_catalog(store).unwrap().staging[0].phase,
      owned.phase,
    ),
  )
  assert_true(
    recover_staging_install_with_operations(store, intent.install_id, injected).unwrap(),
  )
  assert_eq(store.inspect_install(intent.install_id).unwrap(), None)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(store.close().unwrap())
}

///|
test "native bundle recovery removes sealed precommit staging" {
  guard native_bundle_fixture("stream-recovery") is Some((store, _, _, _, _)) else {
    return
  }
  let manifest = admit_signed_bundle(
    store.signature_library,
    store.authorities,
    "actql-remote-runtime-bundle-signature/0.1",
    "key-a",
    native_bundle_cid("4"),
    native_bundle_body("4"),
    native_bundle_signature("4"),
    store.target_triple,
  ).unwrap()
  let staging : NativeRuntimeBundleStaging = {
    install_id: "install-crash-precommit",
    manifest,
    signature_version: "actql-remote-runtime-bundle-signature/0.1",
    signature_key_id: "key-a",
    signature: native_bundle_signature("4"),
    artifact_name: "runtime-bundle-crash-precommit",
    staging_name: "runtime-stage-crash-precommit",
    component_bytes: 11L,
    phase: Intent,
  }
  let current = load_catalog(store).unwrap()
  let next = with_catalog_staging(current, current.entries, [staging])
  persist_catalog(store, current, next).unwrap()
  let writer = store.root.create_writer(staging.staging_name, 11L).unwrap()
  writer.append(b"runtime-one").unwrap()
  let generation = writer.seal(staging.artifact_name).unwrap()
  record_staging_phase(store, staging, Sealed(generation)).unwrap() |> ignore
  assert_true(store.root.verify_generation(staging.artifact_name, generation))
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 11L)
  store.recover().unwrap() |> ignore
  assert_false(store.root.verify_generation(staging.artifact_name, generation))
  assert_eq(store.inspect_install(staging.install_id).unwrap(), None)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(store.close().unwrap())
}

///|
test "native bundle streaming install reserves, cancels, and commits once" {
  guard native_bundle_fixture("stream-install") is Some((store, _, _, _, _)) else {
    return
  }
  let incomplete = store
    .begin_install(
      "install-stream-incomplete",
      "actql-remote-runtime-bundle-signature/0.1",
      "key-a",
      native_bundle_cid("4"),
      native_bundle_body("4"),
      native_bundle_signature("4"),
    )
    .unwrap()
  incomplete.append(b"runtime-").unwrap()
  assert_true(incomplete.seal() is Err(ComponentMismatch))
  assert_true(store.close() is Err(CleanupPending))
  incomplete.cancel().unwrap()
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  let installer = store
    .begin_install(
      "install-stream-one",
      "actql-remote-runtime-bundle-signature/0.1",
      "key-a",
      native_bundle_cid("4"),
      native_bundle_body("4"),
      native_bundle_signature("4"),
    )
    .unwrap()
  let reserved = store.capacity_usage().unwrap()
  assert_eq(reserved.reserved_bytes, 11L)
  assert_eq(reserved.reserved_objects, 1L)
  let pending = store.inspect_install("install-stream-one").unwrap().unwrap()
  assert_eq(pending.runtime_bundle_cid, native_bundle_cid("4"))
  assert_eq(pending.reserved_bytes, 11L)
  installer.append(b"runtime-").unwrap()
  installer.append(b"one").unwrap()
  let installed = installer.seal().unwrap()
  assert_eq(installed.runtime_bundle_cid, native_bundle_cid("4"))
  assert_eq(store.inspect_install("install-stream-one").unwrap(), None)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 11L)
  store.verify(installed.runtime_bundle_cid).unwrap() |> ignore
  store.activate(installed.runtime_bundle_cid).unwrap() |> ignore
  store.drain(installed.runtime_bundle_cid).unwrap() |> ignore
  store.reclaim(installed.runtime_bundle_cid).unwrap() |> ignore
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(store.close().unwrap())
}

///|
test "rotated bundle key verifies history without admitting new bundles" {
  guard native_bundle_fixture("rotation")
    is Some((store, generation, artifact_name, sqlite, crypto)) else {
    return
  }
  let root_path = @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap()
  assert_true(store.close().unwrap())
  let current = open_runtime_bundle_store_with_trust(
    sqlite,
    crypto,
    root_path,
    rotation_trust(true),
    "aarch64-apple-darwin",
    22L,
    8,
    8,
    1048576L,
  ).unwrap()
  let installed = current
    .adopt(
      "actql-remote-runtime-bundle-signature/0.1",
      "key-b",
      rotated_bundle_cid(),
      rotated_bundle_body(),
      rotated_bundle_signature(),
      artifact_name,
      generation,
    )
    .unwrap()
  assert_true(current.close().unwrap())
  let historical = open_runtime_bundle_store_with_trust(
    sqlite,
    crypto,
    root_path,
    rotation_trust(false),
    "aarch64-apple-darwin",
    22L,
    8,
    8,
    1048576L,
  ).unwrap()
  assert_eq(
    historical.verify(installed.runtime_bundle_cid).unwrap().runtime_bundle_cid,
    installed.runtime_bundle_cid,
  )
  assert_true(
    historical.begin_install(
      "rotation-reject-old-key",
      "actql-remote-runtime-bundle-signature/0.1",
      "key-b",
      rotated_bundle_cid(),
      rotated_bundle_body(),
      rotated_bundle_signature(),
    )
    is Err(AdmissionRejected),
  )
  assert_true(
    historical.adopt(
      "actql-remote-runtime-bundle-signature/0.1",
      "key-b",
      rotated_bundle_cid(),
      rotated_bundle_body(),
      rotated_bundle_signature(),
      artifact_name,
      generation,
    )
    is Err(AdmissionRejected),
  )
  assert_true(historical.close().unwrap())
  let current = open_runtime_bundle_store_with_trust(
    sqlite,
    crypto,
    root_path,
    rotation_trust(true),
    "aarch64-apple-darwin",
    22L,
    8,
    8,
    1048576L,
  ).unwrap()
  let readmitted = current
    .adopt(
      "actql-remote-runtime-bundle-signature/0.1",
      "key-b",
      rotated_bundle_cid(),
      rotated_bundle_body(),
      rotated_bundle_signature(),
      artifact_name,
      generation,
    )
    .unwrap()
  assert_eq(readmitted.runtime_bundle_cid, installed.runtime_bundle_cid)
  current.activate(installed.runtime_bundle_cid).unwrap() |> ignore
  current.drain(installed.runtime_bundle_cid).unwrap() |> ignore
  current.reclaim(installed.runtime_bundle_cid).unwrap() |> ignore
  assert_true(current.close().unwrap())
}

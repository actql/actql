///|
// Synthetic library descriptors only. These tests do not load physical libs.
// Asset inputs come from the existing original source-bound fixture bodies.
fn runtime_test_manifest(platform? : String = "darwin-arm64") -> Json {
  let library = fn(role : String) {
    product_object([
      ("role", Json::string(role)),
      ("path", Json::string("lib/" + role + ".bin")),
      ("bytes", Json::number(64)),
      ("sha256", Json::string("0".repeat(64))),
      ("license", Json::string("licenses/fixture.txt")),
      (
        "dependencies",
        product_texts(
          if platform == "darwin-arm64" {
            ["/usr/lib/libSystem.B.dylib"]
          } else {
            ["libc.so.6"]
          },
        ),
      ),
      (
        "abi",
        product_object([
          (
            if platform == "darwin-arm64" {
              "minimumMacOS"
            } else {
              "minimumGlibc"
            },
            Json::string("14.0"),
          ),
        ]),
      ),
    ])
  }
  let assets = product_test_assets()
  product_object([
    ("sourceSha", Json::string("a".repeat(40))),
    ("platform", Json::string(platform)),
    ("libraries", Json::array([library("sqlite"), library("crypto")])),
    (
      "assets",
      Json::array(
        [
          ("environment", assets.environment),
          ("registry", assets.registry),
          ("values", assets.values),
          ("fragment", assets.fragment),
          ("ordered", assets.ordered.unwrap()),
          ("result-policy", assets.result_policy),
        ].map(pair => {
          let bytes = @utf8.encode(pair.1)
          product_object([
            ("role", Json::string(pair.0)),
            ("path", Json::string("data/" + pair.0 + ".json")),
            ("bytes", Json::number(bytes.length().to_double())),
            ("sha256", Json::string(@sha.hex(bytes))),
          ])
        }),
      ),
    ),
    (
      "licenses",
      Json::array([
        product_object([
          ("path", Json::string("licenses/fixture.txt")),
          ("bytes", Json::number(1)),
          ("sha256", Json::string("0".repeat(64))),
        ]),
      ]),
    ),
  ])
}

///|
fn runtime_test_admit(
  json : Json,
  platform? : String = "darwin-arm64",
) -> Result[ClientNativeLocalRuntime, ClientNativeLocalRuntimeIssue] {
  // Caller identity over declared input bytes, not an expected product output.
  let wire = json.stringify()
  admit_client_native_local_runtime(
    wire,
    "a".repeat(40),
    platform,
    @sha.hex(@utf8.encode(wire)),
  )
}

///|
fn runtime_test_library(value : Json, index : Int) -> Map[String, Json] {
  match value {
    Object(root) =>
      match root.get("libraries") {
        Some(Array(libraries)) =>
          match libraries[index] {
            Object(fields) => fields
            _ => abort("library fixture")
          }
        _ => abort("libraries fixture")
      }
    _ => abort("root fixture")
  }
}

///|
test "Darwin runtime accepts exact OS zlib and refuses aliases or foreign platform" {
  let value = runtime_test_manifest()
  runtime_test_library(value, 0)["dependencies"] = product_texts([
    "/usr/lib/libSystem.B.dylib", "/usr/lib/libz.1.dylib",
  ])
  let admitted = runtime_test_admit(value).unwrap()
  assert_eq(client_native_local_runtime_original(admitted), value.stringify())
  for
    dependency in [
      "/usr/lib/libz.dylib", "/usr/lib/libz.2.dylib", "/usr/local/lib/libz.1.dylib",
      "/opt/homebrew/lib/libz.1.dylib", "@rpath/libz.1.dylib", "@loader_path/libz.1.dylib",
      "libz.1.dylib",
    ] {
    let value = runtime_test_manifest()
    runtime_test_library(value, 0)["dependencies"] = product_texts([dependency])
    assert_eq(runtime_test_admit(value).map(_ => 1), Err(InvalidClosure))
  }
  let value = runtime_test_manifest(platform="linux-x64-gnu")
  runtime_test_library(value, 0)["dependencies"] = product_texts([
    "/usr/lib/libz.1.dylib",
  ])
  assert_eq(
    runtime_test_admit(value, platform="linux-x64-gnu").map(_ => 1),
    Err(InvalidClosure),
  )
}

///|
test "Native runtime metadata preserves both finite formal platform closures" {
  for platform in ["darwin-arm64", "linux-x64-gnu"] {
    let value = runtime_test_manifest(platform~)
    let admitted = runtime_test_admit(value, platform~).unwrap()
    assert_eq(client_native_local_runtime_original(admitted), value.stringify())
    let members = client_native_local_runtime_members(admitted)
    assert_eq(members.map(entry => entry.role), [
      "license", "sqlite", "crypto", "environment", "registry", "values", "fragment",
      "ordered", "result-policy",
    ])
    // Returned metadata can be copied without mutating the retained original.
    members.clear()
    assert_eq(client_native_local_runtime_members(admitted).length(), 9)
  }
}

///|
test "runtime identity and closed descriptors refuse mismatch and loader fallback" {
  let wire = runtime_test_manifest().stringify()
  for
    (source, platform, hash) in [
      ("b".repeat(40), "darwin-arm64", @sha.hex(@utf8.encode(wire))),
      ("a".repeat(40), "linux-x64-gnu", @sha.hex(@utf8.encode(wire))),
      ("a".repeat(40), "darwin-arm64", "b".repeat(64)),
    ] {
    assert_eq(
      admit_client_native_local_runtime(wire, source, platform, hash).map(_ => 1),
      Err(InvalidIdentity),
    )
  }
  for
    dependency in [
      "/opt/homebrew/lib/crypto.dylib", "@rpath/crypto.dylib", "../crypto.bin", "missing.bin",
    ] {
    let value = runtime_test_manifest()
    runtime_test_library(value, 0)["dependencies"] = product_texts([dependency])
    assert_eq(runtime_test_admit(value).map(_ => 1), Err(InvalidClosure))
  }
  let value = runtime_test_manifest()
  runtime_test_library(value, 0)["authority"] = Json::boolean(true)
  assert_eq(runtime_test_admit(value).map(_ => 1), Err(InvalidManifest))
  for path in ["/outside", "lib/../outside", "lib/link/file", "lib/.hidden"] {
    let value = runtime_test_manifest()
    runtime_test_library(value, 0)["path"] = Json::string(path)
    assert_eq(runtime_test_admit(value).map(_ => 1), Err(InvalidMember))
  }
}

///|
test "runtime missing duplicate and over-budget members fail without replacement" {
  let value = runtime_test_manifest()
  runtime_test_library(value, 1)["role"] = Json::string("sqlite")
  assert_eq(runtime_test_admit(value).map(_ => 1), Err(InvalidMember))
  let value = runtime_test_manifest()
  runtime_test_library(value, 1)["path"] = Json::string("lib/sqlite.bin")
  assert_eq(runtime_test_admit(value).map(_ => 1), Err(InvalidMember))
  let value = runtime_test_manifest()
  runtime_test_library(value, 0)["license"] = Json::string(
    "licenses/missing.txt",
  )
  assert_eq(runtime_test_admit(value).map(_ => 1), Err(InvalidClosure))
  for
    bytes in [
      Json::number(0),
      Json::number(1.5),
      Json::string("64"),
      Json::number(67108865),
    ] {
    let value = runtime_test_manifest()
    runtime_test_library(value, 0)["bytes"] = bytes
    assert_eq(runtime_test_admit(value).map(_ => 1), Err(InvalidMember))
  }
  let value = runtime_test_manifest()
  runtime_test_library(value, 0)["bytes"] = Json::number(67108864)
  assert_eq(runtime_test_admit(value).map(_ => 1), Err(CapacityExceeded))
}

///|
test "packaged runtime joins the existing bounded selection without changing old originals" {
  let runtime = runtime_test_admit(runtime_test_manifest()).unwrap()
  let originals = client_native_local_product_originals(
    "/Users/operator/.actql-local",
    "/product/lib/sqlite.bin",
    "/product/lib/crypto.bin",
    "2026-10-12T00:00:00.000Z",
    product_test_assets(),
    runtime,
  ).unwrap()
  assert_eq(originals.length(), 8)
  assert_eq(
    product_test_original(originals, "runtime.json"),
    client_native_local_runtime_original(runtime),
  )
  let old = client_local_product_originals(
    "/Users/operator/.actql-local",
    "/product/lib/sqlite.bin",
    "/product/lib/crypto.bin",
    "2026-10-12T00:00:00.000Z",
    product_test_assets(),
  ).unwrap()
  for
    name in [
      "account.json", "environment.json", "run.json", "read.json", "retention.json",
      "store.json",
    ] {
    assert_eq(
      product_test_original(originals, name),
      product_test_original(old, name),
    )
  }
  let config = product_asset_value(
    product_test_original(originals, "config.json"),
  ).unwrap()
  assert_eq(
    @canonical.stringify_value(
      product_test_field(config, ["native", "local", "installation_files"]),
      65536,
      8192,
      64,
    ),
    "[\"read.json\",\"run.json\",\"retention.json\",\"store.json\",\"runtime.json\"]",
  )
  assert_eq(
    client_native_local_product_originals(
      "/Users/operator/.actql-local",
      "/product/lib/sqlite.bin",
      "/product/lib/crypto.bin",
      "2026-10-12T00:00:00.000Z",
      { ..product_test_assets(), environment: "{}", },
      runtime,
    ).map(_ => 1),
    Err(UnsupportedAsset),
  )
  assert_eq(
    client_native_local_product_originals(
      "/Users/operator/.actql-local",
      "/product/lib/sqlite.bin",
      "/product/lib/crypto.bin",
      "2026-10-12T00:00:00.000Z",
      { ..product_test_assets(), ordered: None, },
      runtime,
    ).map(_ => 1),
    Err(UnsupportedAsset),
  )
}

///|
test "finite packaged profile retains File and runtime within eight installation and ten Host selections" {
  let runtime = runtime_test_admit(runtime_test_manifest()).unwrap()
  let originals = client_native_local_finite_product_originals(
    "/Users/operator/.actql-local",
    "/product/lib/sqlite.bin",
    "/product/lib/crypto.bin",
    "2026-10-12T00:00:00.000Z",
    product_test_assets(),
    runtime,
  ).unwrap()
  assert_eq(originals.length(), 11)
  assert_eq(
    product_test_original(originals, "file-read.json"),
    finite_file_selection_fixture,
  )
  assert_eq(
    product_test_original(originals, "profile.json"),
    run_profile_fixture,
  )
  assert_eq(
    product_test_original(originals, "material-read.json"),
    finite_material_selection_fixture,
  )
  assert_eq(
    product_test_original(originals, "runtime.json"),
    client_native_local_runtime_original(runtime),
  )
  let config = product_asset_value(
    product_test_original(originals, "config.json"),
  ).unwrap()
  assert_eq(
    @canonical.stringify_value(
      product_test_field(config, ["native", "local", "installation_files"]),
      65536,
      8192,
      64,
    ),
    "[\"read.json\",\"run.json\",\"retention.json\",\"store.json\",\"runtime.json\",\"profile.json\",\"material-read.json\",\"file-read.json\"]",
  )
}

///|
test "fresh selected Mock signer retains actual Host configuration and independent Sign tuple" {
  let runtime = runtime_test_admit(runtime_test_manifest()).unwrap()
  let subjects : @authorization.LocalMockAccountSubjects = {
    account_id: "local-cli",
    principal: "local-cli",
    control_connection: "local",
    sources: [
      ("salesforce", "Opportunity"),
      ("drive", "files"),
      ("drive", "contents"),
    ],
    model_tasks: ["sha256:" + "a".repeat(64)],
    request_target: None,
    update_target: Some(("salesforce", "Opportunity")),
    signing_key_resource: Some("key/initial-host-attestation"),
  }
  let select = (subjects, host_configuration) => {
    client_native_local_finite_product_originals(
      "/Users/operator/.actql-local",
      "/product/lib/sqlite.bin",
      "/product/lib/crypto.bin",
      "2026-10-12T00:00:00.000Z",
      product_test_assets(),
      runtime,
      mock=Some(subjects),
      host_configuration~,
    ).unwrap()
  }
  let host_wire = "{\"version\":\"actql-host/0.1\"}"
  let originals = select(subjects, Some(host_wire))
  assert_eq(originals.length(), 12)
  assert_eq(
    product_test_original(originals, "host.json"),
    "{\"version\":\"actql-host/0.1\"}",
  )
  let host = admit_client_host_signer_configuration(
    product_test_original(originals, "host.json"),
    { max_wire_bytes: 65536, max_nodes: 1024, max_depth: 16, max_signers: 64, },
  ).unwrap()
  assert_false(host.has_explicit_signers())
  assert_true(
    client_native_local_finite_product_originals(
      "/Users/operator/.actql-local",
      "/product/lib/sqlite.bin",
      "/product/lib/crypto.bin",
      "2026-10-12T00:00:00.000Z",
      product_test_assets(),
      runtime,
      mock=Some(subjects),
      host_configuration=Some("{\"version\":\"actql-host/0.1\",\"signers\":{}}"),
    )
    is Err(UnsupportedAsset),
  )
  let config = product_asset_value(
    product_test_original(originals, "config.json"),
  ).unwrap()
  let settings = product_test_field(config, ["native", "local"])
  assert_eq(
    product_test_text(
      product_test_field(settings, ["initial_host_signing", "principal"]),
    ),
    "local-cli",
  )
  assert_eq(
    product_test_text(
      product_test_field(settings, ["initial_host_signing", "connection"]),
    ),
    "local",
  )
  assert_eq(
    product_test_text(
      product_test_field(settings, ["initial_host_signing", "resource"]),
    ),
    "key/initial-host-attestation",
  )
  guard product_test_field(settings, ["installation_files"])
    is @canonical.Array(files) else {
    fail("installation originals missing")
  }
  assert_eq(@canonical.array_count(files), 8)
  let account = @authorization.admit_account_configuration_json(
    product_test_original(originals, "account.json"),
  ).unwrap()
  assert_true(
    @authorization.evaluate_account(account, {
      principal: "local-cli",
      connection: "local",
      resource: "key/initial-host-attestation",
      operation: "sign",
    })
    is @authorization.Allow(_),
  )
  assert_true(
    @authorization.evaluate_account(account, {
      principal: "local-cli",
      connection: "local",
      resource: "foreign-key",
      operation: "sign",
    })
    is @authorization.Deny(_),
  )
  assert_true(
    @authorization.evaluate_account(account, {
      principal: "local-cli",
      connection: "salesforce",
      resource: "Opportunity",
      operation: "effect",
    })
    is @authorization.Delegate(_),
  )
  let absent = select({ ..subjects, signing_key_resource: None, }, None)
  assert_eq(absent.length(), 11)
  assert_false(absent.any(entry => entry.0 == "host.json"))
  let absent = product_asset_value(product_test_original(absent, "config.json")).unwrap()
  assert_true(
    @canonical.object_field(
      product_test_field(absent, ["native", "local"]),
      "initial_host_signing",
    )
    is None,
  )
}

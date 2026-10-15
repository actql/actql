///|
fn bundle_command_arguments(trust_config? : Bool = true) -> Array[String] {
  let arguments = [
    "--store-root", "unopened-store", "--sqlite-library", "unloaded-sqlite", "--crypto-library",
    "unloaded-crypto", "--target-triple", "x86_64-unknown-linux-gnu", "--authority-root",
    "unopened-authorities",
  ]
  if trust_config {
    arguments.push("--trust-config-name")
    arguments.push("trust.json")
  }
  arguments
}

///|
fn bundle_install_arguments(signature_key? : Bool = true) -> Array[String] {
  let arguments = [
    "install", "--install-id", "install-a", "--bundle-cid", "sha256:fixture", "--input-root",
    "unopened-inputs", "--manifest-name", "manifest.json", "--signature-name", "signature.txt",
    "--component-name", "component.bin",
  ]
  if signature_key {
    arguments.push("--signature-key-id")
    arguments.push("key-a")
  }
  arguments
}

///|
fn assert_bundle_argument_refusal(
  arguments : Array[String],
  expected : String,
) -> Unit raise {
  try command().parse(argv=arguments[:], env=Map([])) catch {
    error => assert_true(error.to_string().contains(expected))
  } noraise {
    _ => fail("invalid bundle arguments were accepted")
  }
}

///|
test "bundle CLI accepts explicit trust and an independent install signature key" {
  let list_arguments = bundle_command_arguments() + ["list"]
  let listed = command().parse(argv=list_arguments[:], env=Map([]))
  assert_eq(option(listed, "trust-config-name"), Ok("trust.json"))
  assert_true(listed.subcommand is Some(("list", _)))
  let trailing_arguments = bundle_command_arguments(trust_config=false) +
    ["list", "--trust-config-name", "trust.json"]
  let trailing = command().parse(argv=trailing_arguments[:], env=Map([]))
  assert_eq(option(trailing, "trust-config-name"), Ok("trust.json"))
  let install_arguments = bundle_command_arguments() +
    bundle_install_arguments()
  let installed = command().parse(argv=install_arguments[:], env=Map([]))
  guard installed.subcommand is Some(("install", child)) else {
    fail("install subcommand was lost")
  }
  assert_eq(option(child, "signature-key-id"), Ok("key-a"))
  let help = command().render_help()
  assert_true(help.contains("--trust-config-name"))
  for retired in ["--issuer-authority", "--key-id", "--public-key-name"] {
    assert_false(help.contains(retired))
  }
}

///|
test "bundle CLI refuses retired trust flags before execution" {
  for retired in ["--issuer-authority", "--key-id", "--public-key-name"] {
    let expected = "error: unexpected argument '" + retired + "' found"
    assert_bundle_argument_refusal(
      bundle_command_arguments() + [retired, "obsolete", "list"],
      expected,
    )
    assert_bundle_argument_refusal(
      bundle_command_arguments() + ["list", retired, "obsolete"],
      expected,
    )
  }
  assert_bundle_argument_refusal(
    bundle_command_arguments(trust_config=false) +
    [
      "--issuer-authority", "issuer-a", "--key-id", "key-a", "--public-key-name",
      "public.pem", "list",
    ],
    "error: unexpected argument '--issuer-authority' found",
  )
}

///|
test "bundle CLI requires trust configuration and install signature key while parsing" {
  assert_bundle_argument_refusal(
    bundle_command_arguments(trust_config=false) + ["list"],
    "error: the following required argument was not provided: 'trust-config-name'",
  )
  assert_bundle_argument_refusal(
    bundle_command_arguments() + bundle_install_arguments(signature_key=false),
    "error: the following required argument was not provided: 'signature-key-id'",
  )
}

///|
fn snapshot_fixture(index : Int) -> @runtime_bundle.NativeRuntimeBundleSnapshot {
  {
    runtime_bundle_cid: "sha256:" + index.to_string(),
    manifest_json: "{}",
    artifact_name: "bundle-" + index.to_string(),
    generation: { device: 1UL, inode: index.to_uint64(), size: 1L, },
    state: ["0", "0", "0"],
    reclaim_pending: false,
  }
}

///|
test "bundle snapshot list budgets its complete JSON shape" {
  for count in [0, 1, 12, 13, 128] {
    let values = Array::makei(count, snapshot_fixture)
    let expected_nodes = 1 + 13 * count
    assert_eq(snapshots_node_limit(values), Ok(expected_nodes))
    guard snapshots_output_limit(count) is Ok(bytes) else {
      fail("valid output size was rejected")
    }
    guard write_snapshots_with_limits(values, bytes, expected_nodes) is Ok(body) else {
      fail("exact node budget was rejected")
    }
    if count == 0 {
      assert_eq(body, "[]")
    } else {
      assert_true(body.has_prefix("["))
      assert_true(body.has_suffix("]"))
      for index in 0..<count {
        assert_true(
          body.contains(
            "\"artifact_name\":\"bundle-" + index.to_string() + "\"",
          ),
        )
      }
    }
    if expected_nodes > 0 {
      assert_eq(
        write_snapshots_with_limits(values, bytes, expected_nodes - 1),
        Err("result encoding failed"),
      )
    }
  }
}

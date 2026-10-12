///|
fn runtime_components_admit(json : Json) -> ClientNativeLocalRuntime {
  guard json is Object(fields) &&
    fields.get("sourceSha") is Some(String(source)) &&
    fields.get("platform") is Some(String(platform)) else {
    abort("manifest fixture")
  }
  let wire = json.stringify()
  admit_client_native_local_runtime(
    wire,
    source,
    platform,
    @sha.hex(@utf8.encode(wire)),
  ).unwrap()
}

///|
// Independent modifications to the existing synthetic fixture. These are
// descriptor comparisons only, never observed libraries or grant evidence.
test "runtime components do not equate source identities and match member order independently" {
  let original = runtime_components_admit(runtime_test_manifest())
  let candidate = runtime_test_manifest()
  guard candidate is Object(fields) else { fail("fixture") }
  fields["sourceSha"] = Json::string("b".repeat(40))
  for key in ["libraries", "assets", "licenses"] {
    guard fields.get(key) is Some(Array(items)) else { fail("category") }
    fields[key] = Json::array(
      Array::makei(items.length(), i => items[items.length() - 1 - i]),
    )
  }
  let current = runtime_components_admit(candidate)
  assert_true(original.wire != current.wire)
  assert_eq(original.source_sha, "a".repeat(40))
  assert_eq(current.source_sha, "b".repeat(40))
  assert_eq(
    validate_client_native_local_runtime_library_components(original, current),
    Ok(()),
  )
  assert_eq(
    validate_client_native_local_runtime_compute_components(original, current),
    Ok(()),
  )
}

///|
test "library comparison keeps bytes dependency ABI role and license separate from asset identity" {
  let original = runtime_components_admit(runtime_test_manifest())
  for
    (field, value) in [
      ("bytes", Json::number(65)),
      ("sha256", Json::string("1".repeat(64))),
      (
        "dependencies",
        product_texts(["/usr/lib/libSystem.B.dylib", "/usr/lib/libz.1.dylib"]),
      ),
      ("abi", product_object([("minimumMacOS", Json::string("26.0"))])),
      ("path", Json::string("lib/other.bin")),
    ] {
    let candidate = runtime_test_manifest()
    runtime_test_library(candidate, 0)[field] = value
    let current = runtime_components_admit(candidate)
    assert_eq(
      validate_client_native_local_runtime_library_components(original, current),
      Err(InvalidClosure),
    )
    assert_eq(
      validate_client_native_local_runtime_compute_components(original, current),
      Ok(()),
    )
  }
  let candidate = runtime_test_manifest()
  guard candidate is Object(fields) &&
    fields.get("licenses") is Some(Array(items)) &&
    items[0] is Object(license) else {
    fail("license")
  }
  license["sha256"] = Json::string("2".repeat(64))
  let current = runtime_components_admit(candidate)
  assert_eq(
    validate_client_native_local_runtime_library_components(original, current),
    Err(InvalidClosure),
  )
}

///|
test "asset agreement cannot be inferred from same libraries wire family or role count" {
  let original = runtime_components_admit(runtime_test_manifest())
  for
    role in [
      "environment", "registry", "values", "fragment", "ordered", "result-policy",
    ] {
    let candidate = runtime_test_manifest()
    guard candidate is Object(fields) &&
      fields.get("assets") is Some(Array(items)) else {
      fail("assets")
    }
    let entry = items
      .iter()
      .find_first(item => {
        match item {
          Object(fields) => fields.get("role") == Some(Json::string(role))
          _ => false
        }
      })
      .unwrap()
    guard entry is Object(fields) else { fail("asset") }
    fields["sha256"] = Json::string("3".repeat(64))
    let current = runtime_components_admit(candidate)
    assert_eq(
      validate_client_native_local_runtime_library_components(original, current),
      Ok(()),
    )
    assert_eq(
      validate_client_native_local_runtime_compute_components(original, current),
      Err(InvalidClosure),
    )
  }
}

///|
test "runtime platform mismatch is refused even when individual asset descriptors agree" {
  let original = runtime_components_admit(runtime_test_manifest())
  let foreign = runtime_components_admit(
    runtime_test_manifest(platform="linux-x64-gnu"),
  )
  assert_eq(
    validate_client_native_local_runtime_library_components(original, foreign),
    Err(InvalidIdentity),
  )
  assert_eq(
    validate_client_native_local_runtime_compute_components(original, foreign),
    Err(InvalidIdentity),
  )
}

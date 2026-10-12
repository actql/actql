///|
fn scalar_pair_test_admit(wire : String) -> ClientNativeLocalRuntime {
  let parsed = @json.parse(wire) catch { _ => abort("fixture") }
  guard parsed is Object(fields) &&
    fields.get("sourceSha") is Some(String(source)) &&
    fields.get("platform") is Some(String(platform)) else {
    abort("fixture")
  }
  admit_client_native_local_runtime(
    wire,
    source,
    platform,
    @sha.hex(@utf8.encode(wire)),
  ).unwrap()
}

///|
fn scalar_pair_test_inspect(
  current : ClientNativeLocalRuntime,
  original_assets? : ClientLocalProductAssets = scalar_pair_test_original_assets(),
  current_assets? : ClientLocalProductAssets = client_local_product_assets(),
) -> Result[
  ClientNativeLocalScalarRuntimePair,
  ClientNativeLocalScalarRuntimePairIssue,
] {
  inspect_client_native_local_scalar_runtime_pair(
    scalar_pair_test_admit(scalar_pair_test_original_runtime_wire()),
    current,
    original_assets,
    current_assets,
  )
}

///|
// Genuine retained descriptor/asset bytes and a synthetic current descriptor.
// No library loading, adoption, original Run restoration or migration occurs.
test "scalar runtime pair keeps exact complete source and manifest identities" {
  let current = scalar_pair_test_admit(scalar_pair_test_current_runtime_wire())
  let pair = scalar_pair_test_inspect(current).unwrap()
  let body = client_native_local_scalar_runtime_pair_body(pair)
  assert_eq(body.length(), 523)
  // Independent Python normative-body oracle, retained in the vector file.
  assert_eq(
    @sha.hex(body),
    "00df605c2c1173cdbd982bd7b54107df020de33f57b28d121c58c7daccc67090",
  )
  assert_eq(
    native_local_scalar_pair_evidence_cid(),
    "sha256:8bdf483589d04809f0e2e198708adc8335b38179f332e58d25a8a09497633a22",
  )
  assert_eq(
    @utf8.encode(native_local_scalar_pair_evidence_wire()).length(),
    6234,
  )
  assert_eq(
    pair.original.source_sha,
    "109564ef9a4f8241096292843b875d4c81fbb6f3",
  )
  assert_eq(pair.current.source_sha, "b".repeat(40))
  assert_true(pair.original.wire != pair.current.wire)
  assert_eq(
    restore_client_native_local_scalar_runtime_pair(
      body,
      pair.original,
      current,
      scalar_pair_test_original_assets(),
      client_local_product_assets(),
    ).map(_ => 0),
    Ok(0),
  )
}

///|
test "scalar runtime pair refuses unknown or relabelled predecessor and changed library closure" {
  let original = scalar_pair_test_admit(
    scalar_pair_test_original_runtime_wire(),
  )
  let current = scalar_pair_test_admit(scalar_pair_test_current_runtime_wire())
  assert_eq(
    inspect_client_native_local_scalar_runtime_pair(
      current,
      current,
      scalar_pair_test_original_assets(),
      client_local_product_assets(),
    ).map(_ => 0),
    Err(UnknownPredecessor),
  )
  for
    (field, value) in [
      ("sha256", Json::string("0".repeat(64))),
      ("bytes", Json::number(65)),
      ("abi", product_object([("minimumMacOS", Json::string("25.0"))])),
      ("dependencies", product_texts(["/usr/lib/libSystem.B.dylib"])),
    ] {
    let parsed = @json.parse(scalar_pair_test_current_runtime_wire())
    runtime_test_library(parsed, 0)[field] = value
    assert_eq(
      scalar_pair_test_inspect(scalar_pair_test_admit(parsed.stringify())).map(_ => {
        0
      }),
      Err(LibraryChanged),
    )
  }
  assert_eq(original.source_sha, "109564ef9a4f8241096292843b875d4c81fbb6f3")
}

///|
test "scalar runtime pair refuses absent or altered asset bytes despite a valid manifest" {
  let current = scalar_pair_test_admit(scalar_pair_test_current_runtime_wire())
  let original_assets = scalar_pair_test_original_assets()
  let current_assets = client_local_product_assets()
  assert_eq(
    scalar_pair_test_inspect(current, original_assets=current_assets).map(_ => 0),
    Err(AssetChanged),
  )
  assert_eq(
    scalar_pair_test_inspect(current, current_assets=original_assets).map(_ => 0),
    Err(AssetChanged),
  )
  assert_eq(
    scalar_pair_test_inspect(current, current_assets={
      ..current_assets,
      ordered: None,
    }).map(_ => 0),
    Err(AssetChanged),
  )
  assert_eq(
    scalar_pair_test_inspect(current, current_assets={
      ..current_assets,
      values: current_assets.values + " ",
    }).map(_ => 0),
    Err(AssetChanged),
  )
  let parsed = @json.parse(scalar_pair_test_current_runtime_wire())
  guard parsed is Object(fields) && fields.get("assets") is Some(Array(assets)) else {
    fail("fixture")
  }
  guard assets[0] is Object(asset) else { fail("asset") }
  asset["sha256"] = Json::string("1".repeat(64))
  assert_eq(
    scalar_pair_test_inspect(scalar_pair_test_admit(parsed.stringify())).map(_ => {
      0
    }),
    Err(AssetChanged),
  )
}

///|
test "scalar runtime pair restores only exact original correspondence bytes" {
  let pair = scalar_pair_test_inspect(
    scalar_pair_test_admit(scalar_pair_test_current_runtime_wire()),
  ).unwrap()
  let body = @utf8.decode(pair.body)
  for
    changed in [
      body.replace(old="primitive-scalar-values", new="all-values"),
      body.replace(old="8bdf4835", new="00000000"),
      body.replace(old="bbbbbbbb", new="cccccccc"),
      body + " ",
      "{}",
    ] {
    assert_eq(
      restore_client_native_local_scalar_runtime_pair(
        @utf8.encode(changed),
        pair.original,
        pair.current,
        scalar_pair_test_original_assets(),
        client_local_product_assets(),
      ).map(_ => 0),
      Err(InvalidOriginal),
    )
  }
}

///|
test "scalar runtime pair retains nominal preparation without making a replacement runnable" {
  let pair = scalar_pair_test_inspect(
    scalar_pair_test_admit(scalar_pair_test_current_runtime_wire()),
  ).unwrap()
  let prepared = scalar_profile_prepared(run_materials_document)
  let profile = inspect_client_native_local_scalar_values_profile(
    prepared, 1000,
  ).unwrap()
  assert_eq(
    validate_client_native_local_scalar_runtime_pair_preparation(
      pair, profile, prepared,
    ),
    Ok(()),
  )
  assert_eq(
    validate_client_native_local_scalar_runtime_pair_preparation(
      pair,
      profile,
      scalar_profile_prepared(run_materials_document),
    ),
    Err(ForeignPreparation),
  )
  // This is a current synthetic preparation. It does not prove an old Run's
  // material exists or that its strict old contract reader can restore it.
}

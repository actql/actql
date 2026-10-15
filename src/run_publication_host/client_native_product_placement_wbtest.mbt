///|
fn product_placement_fixture(
  platform_root : String,
  launcher_root? : String = "/consumer/node_modules/actql",
) -> Result[ClientNativeProductPlacement, ClientNativeLocalRuntimeIssue] {
  prepare_client_native_product_placement(
    product_inventory_fixture(product_inventory_fixture_0, package_name="actql").unwrap(),
    product_inventory_fixture(product_inventory_fixture_1).unwrap(),
    launcher_root,
    platform_root,
  )
}

///|
fn product_placement_parents(
  value : ClientNativeProductPlacement,
  part : ClientNativeProductPart,
) -> Array[String] {
  Array::makei(client_native_product_placement_parent_count(value, part), index => {
    client_native_product_placement_parent_at(value, part, index).unwrap()
  })
}

///|
test "installed product hoisted pair keeps the two payload Roots independent" {
  let value = product_placement_fixture(
    "/consumer/node_modules/@actql/cli-darwin-arm64",
  ).unwrap()
  assert_eq(
    client_native_product_placement_root(value, LauncherProduct),
    "/consumer/node_modules/actql",
  )
  assert_eq(
    client_native_product_placement_root(value, PlatformProduct),
    "/consumer/node_modules/@actql/cli-darwin-arm64",
  )
  for part in [LauncherProduct, PlatformProduct] {
    assert_eq(product_placement_parents(value, part), ["", "bin"])
    assert_eq(
      product_census_names(
        client_native_product_placement_census(value, part, "").unwrap(),
      ),
      ["README.md", "bin", "local-product-members.json", "package.json"],
    )
    assert_eq(
      product_census_names(
        client_native_product_placement_census(value, part, "bin").unwrap(),
      ),
      ["actql-native-client"],
    )
    assert_eq(client_native_product_placement_parent_at(value, part, -1), None)
    assert_eq(client_native_product_placement_parent_at(value, part, 2), None)
  }
}

///|
test "installed product nested pair permits only its exact directory route" {
  let value = product_placement_fixture(
    "/consumer/node_modules/actql/node_modules/@actql/cli-darwin-arm64",
  ).unwrap()
  assert_eq(product_placement_parents(value, LauncherProduct), [
    "", "bin", "node_modules", "node_modules/@actql",
  ])
  assert_eq(product_placement_parents(value, PlatformProduct), ["", "bin"])
  let root = client_native_product_placement_census(value, LauncherProduct, "").unwrap()
  assert_eq(product_census_names(root), [
    "README.md", "bin", "local-product-members.json", "node_modules", "package.json",
  ])
  assert_eq(
    client_native_product_census_at(root, 3).unwrap().kind,
    ProductDirectory,
  )
  let modules = client_native_product_placement_census(
    value,
    LauncherProduct,
    "node_modules",
  ).unwrap()
  assert_eq(product_census_names(modules), ["@actql"])
  assert_eq(
    client_native_product_census_at(modules, 0).unwrap().kind,
    ProductDirectory,
  )
  let scope = client_native_product_placement_census(
    value,
    LauncherProduct,
    "node_modules/@actql",
  ).unwrap()
  assert_eq(product_census_names(scope), ["cli-darwin-arm64"])
  assert_eq(
    client_native_product_census_at(scope, 0).unwrap().kind,
    ProductDirectory,
  )
  assert_eq(
    client_native_product_placement_parent_at(value, LauncherProduct, 4),
    None,
  )
}

///|
test "installed product pair rejects foreign role source and platform" {
  let launcher = product_inventory_fixture(
    product_inventory_fixture_0,
    package_name="actql",
  ).unwrap()
  let platform = product_inventory_fixture(product_inventory_fixture_1).unwrap()
  assert_true(
    prepare_client_native_product_placement(
      platform, launcher, "/consumer/node_modules/actql", "/consumer/node_modules/@actql/cli-darwin-arm64",
    )
    is Err(InvalidIdentity),
  )
  let foreign_source = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let foreign = admit_client_native_product_members(
    product_inventory_fixture_1.replace(
      old="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      new=foreign_source,
    ),
    foreign_source,
    "darwin-arm64",
    "@actql/cli-darwin-arm64",
  ).unwrap()
  assert_true(
    prepare_client_native_product_placement(
      launcher, foreign, "/consumer/node_modules/actql", "/consumer/node_modules/@actql/cli-darwin-arm64",
    )
    is Err(InvalidIdentity),
  )
  let linux = admit_client_native_product_members(
    product_inventory_fixture_1.replace(old="darwin-arm64", new="linux-x64-gnu"),
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "linux-x64-gnu",
    "@actql/cli-linux-x64-gnu",
  ).unwrap()
  assert_true(
    prepare_client_native_product_placement(
      launcher, linux, "/consumer/node_modules/actql", "/consumer/node_modules/@actql/cli-linux-x64-gnu",
    )
    is Err(InvalidIdentity),
  )
}

///|
test "installed product pair rejects normalized alternate and foreign routes" {
  for
    path in [
      "consumer/node_modules/@actql/cli-darwin-arm64", "/consumer//node_modules/@actql/cli-darwin-arm64",
      "/consumer/node_modules/@actql/cli-darwin-arm64/", "/consumer/./node_modules/@actql/cli-darwin-arm64",
      "/consumer/other/@actql/cli-darwin-arm64", "/consumer/node_modules/@foreign/cli-darwin-arm64",
      "/consumer/node_modules/@actql/cli-linux-x64-gnu", "/consumer/node_modules/actql/node_modules/@actql/cli-darwin-arm64/child",
      "/consumer/node_modules/@actql/cli-darwin-arm64\u{0000}",
    ] {
    assert_true(product_placement_fixture(path) is Err(InvalidIdentity))
  }
  assert_true(
    product_placement_fixture(
      "/consumer/node_modules/@actql/cli-darwin-arm64",
      launcher_root="/consumer/node_modules/other",
    )
    is Err(InvalidIdentity),
  )
}

///|
test "installed product metadata never exempts another nested entry or scope" {
  let value = product_placement_fixture(
    "/consumer/node_modules/actql/node_modules/@actql/cli-darwin-arm64",
  ).unwrap()
  for part in [LauncherProduct, PlatformProduct] {
    for
      parent in [
        "missing", "@actql", "package.json", "node_modules/@other", "node_modules/@actql/cli-darwin-arm64",
        "bin/extra",
      ] {
      assert_true(
        client_native_product_placement_census(value, part, parent)
        is Err(InvalidMember),
      )
    }
  }
  for parent in ["node_modules", "node_modules/@actql"] {
    assert_true(
      client_native_product_placement_census(value, PlatformProduct, parent)
      is Err(InvalidMember),
    )
  }
}

///|
test "installed product nested route cannot replace a declared payload" {
  let platform = product_inventory_fixture(product_inventory_fixture_1).unwrap()
  for path in ["node_modules", "node_modules/member"] {
    let wire = product_inventory_fixture_0.replace(old="package.json", new=path)
    let launcher = product_inventory_fixture(wire, package_name="actql").unwrap()
    assert_true(
      prepare_client_native_product_placement(
        launcher, platform, "/consumer/node_modules/actql", "/consumer/node_modules/actql/node_modules/@actql/cli-darwin-arm64",
      )
      is Err(InvalidMember),
    )
  }
}

///|
test "installed product traversal groups one original parent per payload directory" {
  let launcher = product_inventory_fixture(
    product_inventory_fixture_0.replace(old="package.json", new="bin/z"),
    package_name="actql",
  ).unwrap()
  let platform = product_inventory_fixture(product_inventory_fixture_1).unwrap()
  let value = prepare_client_native_product_placement(
    launcher, platform, "/consumer/node_modules/actql", "/consumer/node_modules/actql/node_modules/@actql/cli-darwin-arm64",
  ).unwrap()
  assert_eq(product_placement_parents(value, LauncherProduct), [
    "", "bin", "node_modules", "node_modules/@actql",
  ])
  assert_eq(
    product_census_names(
      client_native_product_placement_census(value, LauncherProduct, "bin").unwrap(),
    ),
    ["actql-native-client", "z"],
  )
}

///|
test "installed product route bound is encoded bytes rather than UTF16 length" {
  let root = "/" + "a".repeat(4096 - 6 - 1) + "/actql"
  let platform = root[:root.length() - 6].to_owned() +
    "/@actql/cli-darwin-arm64"
  // The longer selected platform path must also fit; the exact root pair
  // below is chosen so its platform path is 4096 bytes.
  let prefix = "/" + "a".repeat(4096 - 1 - "/@actql/cli-darwin-arm64".length())
  let exact = product_placement_fixture(
    prefix + "/@actql/cli-darwin-arm64",
    launcher_root=prefix + "/actql",
  )
  assert_true(exact is Ok(_))
  assert_true(
    product_placement_fixture(platform, launcher_root=root)
    is Err(InvalidIdentity),
  )
  let multibyte = "/" + "é".repeat(2040) + "/actql"
  assert_true(multibyte.length() < 4096)
  assert_true(
    product_placement_fixture(
      multibyte + "/node_modules/@actql/cli-darwin-arm64",
      launcher_root=multibyte,
    )
    is Err(InvalidIdentity),
  )
  assert_true(
    product_placement_fixture(
      prefix + "a/@actql/cli-darwin-arm64",
      launcher_root=prefix + "a/actql",
    )
    is Err(InvalidIdentity),
  )
}

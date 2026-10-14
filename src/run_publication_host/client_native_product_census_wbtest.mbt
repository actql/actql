///|
fn product_census_names(value : ClientNativeProductCensus) -> Array[String] {
  Array::makei(client_native_product_census_count(value), index => {
    client_native_product_census_at(value, index).unwrap().name
  })
}

///|
test "product census exact independent root and child require the descriptor file" {
  for
    (wire, package_name) in [
      (product_inventory_fixture_0, "actql"),
      (product_inventory_fixture_1, "@actql/cli-darwin-arm64"),
    ] {
    let value = product_inventory_fixture(wire, package_name~).unwrap()
    let root = client_native_product_census(value, "").unwrap()
    assert_eq(product_census_names(root), [
      "README.md", "bin", "local-product-members.json", "package.json",
    ])
    assert_eq(
      client_native_product_census_at(root, 0).unwrap().kind,
      ProductFile,
    )
    assert_eq(
      client_native_product_census_at(root, 1).unwrap().kind,
      ProductDirectory,
    )
    assert_eq(
      client_native_product_census_at(root, 2).unwrap().kind,
      ProductFile,
    )
    assert_eq(client_native_product_census_at(root, -1), None)
    assert_eq(client_native_product_census_at(root, 4), None)
    let child = client_native_product_census(value, "bin").unwrap()
    assert_eq(product_census_names(child), ["actql-native-client"])
    assert_eq(
      client_native_product_census_at(child, 0).unwrap().kind,
      ProductFile,
    )
  }
}

///|
test "product census sorts immediate names rather than paths or Core shortlex" {
  let value = product_inventory_fixture(
    product_inventory_fixture_1.replace(old="README.md", new="bin.a"),
  ).unwrap()
  assert_eq(
    product_census_names(client_native_product_census(value, "").unwrap()),
    ["bin", "bin.a", "local-product-members.json", "package.json"],
  )
}

///|
test "product census refuses file directory collisions for every selection" {
  let value = product_inventory_fixture(
    product_inventory_fixture_1.replace(old="README.md", new="bin"),
  ).unwrap()
  for parent in ["", "bin"] {
    assert_true(
      client_native_product_census(value, parent) is Err(InvalidMember),
    )
  }
}

///|
test "product census self exception is one regular root file only" {
  let collision = product_inventory_fixture(
    product_inventory_fixture_1.replace(
      old="bin/actql-native-client",
      new="local-product-members.json/member",
    ),
  ).unwrap()
  assert_true(client_native_product_census(collision, "") is Err(InvalidMember))
  let nested = product_inventory_fixture(
    product_inventory_fixture_1.replace(
      old="bin/actql-native-client",
      new="bin/local-product-members.json",
    ),
  ).unwrap()
  assert_eq(
    product_census_names(client_native_product_census(nested, "bin").unwrap()),
    ["local-product-members.json"],
  )
  // The nested file remains a normal hashed member, never another exception.
  assert_eq(client_native_product_members_at(nested, 1).unwrap().bytes, 2L)
}

///|
test "product census refuses unknown empty route file and malformed parent" {
  let value = product_inventory_fixture(product_inventory_fixture_1).unwrap()
  for
    parent in [
      "missing", "package.json", "node_modules", "@actql", ".", "..", "bin/child",
    ] {
    assert_true(
      client_native_product_census(value, parent) is Err(InvalidMember),
    )
  }
}

///|
test "product census groups multiple child files without duplicate directories" {
  let wire = product_inventory_fixture_1.replace(
    old="package.json",
    new="bin/z",
  )
  let value = product_inventory_fixture(wire).unwrap()
  assert_eq(
    product_census_names(client_native_product_census(value, "").unwrap()),
    ["README.md", "bin", "local-product-members.json"],
  )
  assert_eq(
    product_census_names(client_native_product_census(value, "bin").unwrap()),
    ["actql-native-client", "z"],
  )
}

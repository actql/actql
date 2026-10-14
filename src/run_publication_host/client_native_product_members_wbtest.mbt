///|
// Independent literal formal inventory vectors shared with the existing Node reader.

///|
let product_inventory_fixture_0 = "{\"files\":[{\"bytes\":1,\"mode\":420,\"path\":\"README.md\",\"sha256\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},{\"bytes\":2,\"mode\":493,\"path\":\"bin/actql-native-client\",\"sha256\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},{\"bytes\":0,\"mode\":420,\"path\":\"package.json\",\"sha256\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"}],\"packageName\":\"actql\",\"platform\":\"darwin-arm64\",\"sourceSha\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}"

///|
let product_inventory_fixture_1 = "{\"files\":[{\"bytes\":1,\"mode\":420,\"path\":\"README.md\",\"sha256\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},{\"bytes\":2,\"mode\":493,\"path\":\"bin/actql-native-client\",\"sha256\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"},{\"bytes\":0,\"mode\":420,\"path\":\"package.json\",\"sha256\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"}],\"packageName\":\"@actql/cli-darwin-arm64\",\"platform\":\"darwin-arm64\",\"sourceSha\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}"

///|
fn product_inventory_fixture(
  wire : String,
  package_name? : String = "@actql/cli-darwin-arm64",
) -> Result[ClientNativeProductMembers, ClientNativeLocalRuntimeIssue] {
  admit_client_native_product_members(
    wire, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "darwin-arm64", package_name,
  )
}

///|
test "formal product metadata exact launcher and platform vectors" {
  let launcher = product_inventory_fixture(
    product_inventory_fixture_0,
    package_name="actql",
  ).unwrap()
  let platform = product_inventory_fixture(product_inventory_fixture_1).unwrap()
  assert_eq(
    client_native_product_members_wire(launcher),
    product_inventory_fixture_0,
  )
  assert_eq(
    client_native_product_members_wire(platform),
    product_inventory_fixture_1,
  )
  assert_eq(
    @sha.hex(@utf8.encode(product_inventory_fixture_0)),
    "86f72e1005718344a9eb9d7252a4ef2472a724added468677949201054167eb4",
  )
  assert_eq(
    @sha.hex(@utf8.encode(product_inventory_fixture_1)),
    "563dbe623a3df434ff049942de129a827530dfb3baa3d1c33999fea11baab69e",
  )
  assert_eq(
    client_native_product_members_source(platform),
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  assert_eq(client_native_product_members_platform(platform), "darwin-arm64")
  assert_eq(client_native_product_members_package(launcher), "actql")
  assert_eq(client_native_product_members_count(platform), 3)
  assert_eq(
    client_native_product_members_at(platform, 0).unwrap().path,
    "README.md",
  )
  assert_eq(
    client_native_product_members_at(platform, 1).unwrap().path,
    "bin/actql-native-client",
  )
  assert_eq(client_native_product_members_at(platform, 2).unwrap().bytes, 0L)
  assert_eq(client_native_product_members_at(platform, -1), None)
  assert_eq(client_native_product_members_at(platform, 3), None)
}

///|
test "formal product metadata rejects closed shape and alternate canonical bytes" {
  for
    wire in [
      product_inventory_fixture_1 + "\n",
      product_inventory_fixture_1.replace(
        old="\"files\":",
        new="\"unknown\":0,\"files\":",
      ),
      product_inventory_fixture_1.replace(
        old="\"platform\":\"darwin-arm64\"",
        new="\"platform\":\"darwin-arm64\",\"platform\":\"darwin-arm64\"",
      ),
      product_inventory_fixture_1.replace(
        old="\"bytes\":1",
        new="\"bytes\":null",
      ),
      product_inventory_fixture_1.replace(
        old="\"mode\":420",
        new="\"mode\":\"420\"",
      ),
      product_inventory_fixture_1.replace(
        old="\"bytes\":1",
        new="\"bytes\":1.0",
      ),
    ] {
    assert_true(product_inventory_fixture(wire) is Err(_))
  }
}

///|
test "formal product metadata compares selected identities without normalization" {
  for
    (source, platform, package_name) in [
      (
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "darwin-arm64", "@actql/cli-darwin-arm64",
      ),
      (
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "darwin-arm64", "@actql/cli-darwin-arm64",
      ),
      (
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "linux-x64-gnu", "@actql/cli-linux-x64-gnu",
      ),
      ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "darwin-arm64", "actql"),
      ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "darwin-arm64", "foreign"),
    ] {
    assert_true(
      admit_client_native_product_members(
        product_inventory_fixture_1, source, platform, package_name,
      )
      is Err(InvalidIdentity),
    )
  }
}

///|
test "formal product metadata rejects self hash malformed paths modes and sizes" {
  for
    (old, new) in [
      ("README.md", "local-product-members.json"),
      ("README.md", "@actql"),
      ("README.md", "../README.md"),
      ("README.md", "data/extra/README.md"),
      ("\"mode\":420", "\"mode\":512"),
      ("\"bytes\":1", "\"bytes\":-1"),
      ("\"bytes\":1", "\"bytes\":67108865"),
      ("\"bytes\":1", "\"bytes\":0.5"),
    ] {
    assert_true(
      product_inventory_fixture(product_inventory_fixture_1.replace(old~, new~))
      is Err(_),
    )
  }
}

///|
test "formal product metadata uses ASCII path order and rejects duplicates" {
  // Existing Core comparison is length-first; the formal inventory is not.
  assert_true("bin/actql-native-client" > "package.json")
  assert_true(
    product_inventory_path_before("bin/actql-native-client", "package.json"),
  )
  let duplicate = product_inventory_fixture_1.replace(
    old="package.json",
    new="bin/actql-native-client",
  )
  assert_true(product_inventory_fixture(duplicate) is Err(InvalidMember))
  let disorder = product_inventory_fixture_1.replace(
    old="README.md",
    new="z.md",
  )
  assert_true(product_inventory_fixture(disorder) is Err(InvalidMember))
}

///|
test "formal product metadata refuses oversize intake and empty membership" {
  let huge = "x".repeat(65537)
  assert_true(product_inventory_fixture(huge) is Err(CapacityExceeded))
  assert_true(
    product_inventory_fixture(
      "{\"files\":[],\"packageName\":\"@actql/cli-darwin-arm64\",\"platform\":\"darwin-arm64\",\"sourceSha\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}",
    )
    is Err(InvalidManifest),
  )
}

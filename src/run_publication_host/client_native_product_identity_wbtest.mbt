///|
// Independent six-field successor identity vector, not a physical original.
let product_identity_golden = "{\"launcher_inventory_sha256\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"native_binary_sha256\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"platform\":\"darwin-arm64\",\"platform_inventory_sha256\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"runtime_manifest_sha256\":\"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"source_sha\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}"

///|
test "product identity preserves the adopted six-field bytes and independent digest" {
  let value = client_native_product_identity(
    "b".repeat(64),
    "c".repeat(64),
    "darwin-arm64",
    "d".repeat(64),
    "e".repeat(64),
    "a".repeat(40),
  ).unwrap()
  assert_eq(client_native_product_identity_wire(value), product_identity_golden)
  assert_eq(
    @sha.hex(@utf8.encode(product_identity_golden)),
    "28afdb17f3ec0ad92626b6f752cb7ff2fbe0839ea63d027dbd2212667a640dac",
  )
  assert_eq(
    client_native_product_identity_wire(
      read_client_native_product_identity(product_identity_golden).unwrap(),
    ),
    product_identity_golden,
  )
  let linux = product_identity_golden.replace(
    old="darwin-arm64",
    new="linux-x64-gnu",
  )
  assert_eq(
    client_native_product_identity_wire(
      read_client_native_product_identity(linux).unwrap(),
    ),
    linux,
  )
}

///|
test "product identity refuses alternate wire shape and noncanonical copies" {
  for
    wire in [
      product_identity_golden + "\n",
      product_identity_golden.replace(old="{", new="{\"other\":\"x\","),
      product_identity_golden.replace(
        old="\"platform\":\"darwin-arm64\"",
        new="\"platform\":\"darwin-arm64\",\"platform\":\"darwin-arm64\"",
      ),
      product_identity_golden.replace(
        old="\"platform\":\"darwin-arm64\"",
        new="\"platform\":null",
      ),
      product_identity_golden.replace(
        old="\"platform\":\"darwin-arm64\"",
        new="\"platform\":1",
      ),
    ] {
    assert_true(
      read_client_native_product_identity(wire) is Err(InvalidManifest),
    )
  }
}

///|
test "product identity refuses repaired selectors and digest domains" {
  for
    (old, new) in [
      ("darwin-arm64", "darwin-x64"),
      ("a".repeat(40), "A".repeat(40)),
      ("b".repeat(64), "sha256:" + "b".repeat(64)),
      ("c".repeat(64), "c".repeat(63)),
      ("d".repeat(64), "D".repeat(64)),
      ("e".repeat(64), "x".repeat(64)),
    ] {
    assert_true(
      read_client_native_product_identity(
        product_identity_golden.replace(old~, new~),
      )
      is Err(InvalidIdentity),
    )
  }
}

///|
test "product identity keeps exact intake boundary separate from validation" {
  let exact = product_identity_golden +
    " ".repeat(4096 - @utf8.encode(product_identity_golden).length())
  assert_eq(@utf8.encode(exact).length(), 4096)
  assert_true(
    read_client_native_product_identity(exact) is Err(InvalidManifest),
  )
  assert_true(
    read_client_native_product_identity(exact + " ") is Err(CapacityExceeded),
  )
}

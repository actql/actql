///|
test "Account wire geometry retains an original beyond the old one MiB byte boundary" {
  let wire = " ".repeat(1048577) + account_inventory_wire([])
  let admitted = admit_account_configuration_json(wire).unwrap()
  assert_eq(admitted.entry_count(), 0)
  assert_true(admitted.retains_original_bytes(@utf8.encode(wire)))
  assert_true(
    evaluate_account(admitted, account_inventory_at("resource"))
    is Deny(NoMatch),
  )
  assert_eq(
    admitted.configuration_cid(),
    admit_account_configuration_json(account_inventory_wire([]))
    .unwrap()
    .configuration_cid(),
  )
}

///|
test "Account wire geometry decodes all 262145 original selector nodes without an unrelated node ceiling" {
  let names = Array::makei(262145, index => {
    let suffix = index.to_string()
    "resource-" + "0".repeat(6 - suffix.length()) + suffix
  })
  let row = {
    ..account_inventory_entry(0),
    scope: account_inventory_scope(AnyOf(names)),
  }
  let raw = decode_account_configuration_json(account_inventory_wire([row])).unwrap()
  assert_eq(raw.entries.length(), 1)
  guard raw.entries[0].scope.resource is AnyOf(retained) else {
    fail("original finite selector required")
  }
  assert_eq(retained.length(), 262145)
  assert_eq(retained[0], "resource-000000")
  assert_eq(retained[262144], "resource-262144")
}

///|
test "Account canonical geometry preserves the independently authored 4635253 byte identity" {
  let names = Array::makei(9000, index => {
    account_inventory_name("resource-", index) + "x".repeat(499)
  })
  let row = {
    ..account_inventory_entry(0),
    scope: account_inventory_scope(AnyOf(names)),
  }
  let admitted = admit_account_configuration(account_inventory_raw([row])).unwrap()
  // Independently authored canonical sorted-key JSON, 4,635,253 ASCII bytes,
  // hashed with Python standard json/hashlib before any product correction.
  assert_eq(
    admitted.configuration_cid(),
    "sha256:f527e965a409a7c03c424071e3dd4fc29181744c84ef54c1ab51ddfc15f058b9",
  )
  assert_true(
    evaluate_account(admitted, account_inventory_at(names[8999]))
    is Allow("entry-0000"),
  )
  assert_true(
    evaluate_account(admitted, account_inventory_at("resource-9000"))
    is Deny(NoMatch),
  )
}

///|
test "Account wire geometry preserves exact nonempty identifiers beyond the historical 512 units" {
  let name = "n".repeat(513)
  let row = {
    ..account_inventory_entry(0),
    entry_id: name,
    scope: {
      principal: AnyOf([name]),
      connection: AnyOf([name]),
      resource: AnyOf([name]),
      operation: AnyOf(["read"]),
    },
  }
  let raw = { ..account_inventory_raw([row]), account_id: name, }
  let admitted = admit_account_configuration(raw).unwrap()
  let wire = account_inventory_wire([row]).replace_all(
    old="\"account_id\":\"inventory-account\"",
    new="\"account_id\":\"" + name + "\"",
  )
  let decoded = admit_account_configuration_json(wire).unwrap()
  assert_eq(admitted.configuration_cid(), decoded.configuration_cid())
  assert_true(
    evaluate_account(decoded, {
      principal: name,
      connection: name,
      resource: name,
      operation: "read",
    })
    is Allow(original) &&
    original == name,
  )
  assert_true(
    evaluate_account(decoded, {
      principal: name,
      connection: name,
      resource: name + "x",
      operation: "read",
    })
    is Deny(NoMatch),
  )
}

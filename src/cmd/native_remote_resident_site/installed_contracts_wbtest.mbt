///|
test "resident installation rejects incomplete contract DATA before execution" {
  assert_true(resident_installed_contracts("{}", "{}", None) is None)
  assert_true(resident_installed_contracts("", "{}", Some("{}")) is None)
  assert_true(resident_installed_contracts("{}", "", Some("{}")) is None)
}

///|
test "resident installation retains independently admitted current contract DATA" {
  let assets = @host.client_local_product_assets()
  let first = resident_installed_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
  ).unwrap()
  let second = resident_installed_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
  ).unwrap()
  assert_false(physical_equal(first, second))
  assert_true(
    resident_installed_contracts(assets.registry, assets.values, Some("{}"))
    is None,
  )
  assert_true(
    resident_installed_contracts(assets.registry, "{}", Some(assets.fragment))
    is None,
  )
}

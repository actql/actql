///|
test "resident installation rejects incomplete contract DATA before execution" {
  assert_true(
    @local_values.prepare_installed_sequence_contracts("{}", "{}", None, None)
    is Err(_),
  )
  assert_true(
    @local_values.prepare_installed_sequence_contracts(
      "",
      "{}",
      Some("{}"),
      None,
    )
    is Err(_),
  )
  assert_true(
    @local_values.prepare_installed_sequence_contracts(
      "{}",
      "",
      Some("{}"),
      None,
    )
    is Err(_),
  )
}

///|
test "resident installation retains independently admitted current contract DATA" {
  let assets = @host.client_local_product_assets()
  let first = @local_values.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    None,
  ).unwrap()
  let second = @local_values.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    None,
  ).unwrap()
  assert_false(physical_equal(first, second))
  assert_true(
    @local_values.prepare_installed_sequence_contracts(
      assets.registry,
      assets.values,
      Some("{}"),
      None,
    )
    is Err(_),
  )
  assert_true(
    @local_values.prepare_installed_sequence_contracts(
      assets.registry,
      "{}",
      Some(assets.fragment),
      None,
    )
    is Err(_),
  )
}

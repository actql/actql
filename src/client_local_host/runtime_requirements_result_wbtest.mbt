///|
fn runtime_result_contracts() -> ClientInstalledSequenceContracts {
  let assets = @publication_host.client_local_product_assets()
  prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
}

///|
test "runtime requirements Result retains checked originals and Option compatibility" {
  let assets = @publication_host.client_local_product_assets()
  let prepared = source_free_requirements_prepared()
  let contracts = runtime_result_contracts()
  let result = prepare_source_free_runtime_requirements_result(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_true(physical_equal(result.prepared, prepared))
  assert_true(physical_equal(result.registry, contracts))
  assert_true(
    result.matches(
      prepared,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ),
  )
  assert_eq(result.maximum_limits().attempts, 1)
  assert_true(result.simultaneous_limits() is None)
  let legacy = prepare_source_free_runtime_requirements(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_true(
    legacy.matches(
      prepared,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ),
  )
  assert_eq(legacy.maximum_limits(), result.maximum_limits())
}

///|
test "runtime requirements Result preserves the original sequence selection refusal" {
  let assets = @publication_host.client_local_product_assets()
  let prepared = source_free_requirements_prepared()
  let contracts = runtime_result_contracts()
  // An equal-looking replacement body is not the original installed binding.
  let changed_values = assets.values + " "
  assert_true(
    prepare_source_free_runtime_requirements_result(
      prepared,
      contracts,
      changed_values,
      Some(assets.fragment),
      assets.ordered,
    )
    is Err(SequencePreparation(Unsupported)),
  )
  assert_true(
    prepare_source_free_runtime_requirements(
      prepared,
      contracts,
      changed_values,
      Some(assets.fragment),
      assets.ordered,
    )
    is None,
  )
}

///|
test "legacy simultaneous demand stays distinct from runtime Result selection" {
  let assets = @publication_host.client_local_product_assets()
  let prepared = source_free_requirements_prepared()
  let contracts = runtime_result_contracts()
  let legacy = prepare_source_free_local_requirements(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_true(legacy.simultaneous_limits() is Some(_))
  assert_true(
    legacy.matches(
      prepared,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ),
  )
}

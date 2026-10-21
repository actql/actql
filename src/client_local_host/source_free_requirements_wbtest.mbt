///|
// Real checked Program and Local provider, with a nominal Resource Ledger.
// This is not Native physical backing, Account or durable Run admission.
test "source-free requirements keep maximum allowances separate and execute the same prepared rows" {
  let prepared = single_source_free_capacity_prepared()
  let assets = @publication_host.client_local_product_assets()
  let quote = prepare_source_free_local_requirements(
    prepared,
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let maximum = quote.maximum_limits()
  assert_eq(maximum.retained_bytes, 200000000L)
  assert_eq(maximum.execution_bytes, 536870912L)
  assert_eq(
    source_free_local_ledger_limits(
      prepared,
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ),
    Some(maximum),
  )
  let required = quote.simultaneous_limits().unwrap()
  assert_true(required.retained_bytes > 0L)
  assert_true(required.retained_bytes < maximum.retained_bytes)
  assert_true(required.execution_bytes > required.retained_bytes)
  assert_true(required.execution_bytes < maximum.execution_bytes)
  assert_eq(required.attempts, maximum.attempts)
  assert_eq(required.holdings, maximum.holdings)
  assert_eq(required.transfer_bytes, maximum.transfer_bytes)
  let ledger = @resources.create_ledger(required).unwrap()
  let setup = open_source_free_local_retained_host_on_ledger(
    prepared,
    ledger,
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    requirements=Some(quote),
  ).unwrap()
  let execution = match
    execute_source_free_local_tasks_guarded(setup, 64, 100000, () => true) {
    Ok(value) => value
    Err(original) => {
      retry_local_values_execution_failure_cleanup(original) |> ignore
      fail("quoted original Local execution refused")
    }
  }
  assert_eq(execution.rows().unwrap(), ["{\"id\":1}", "{\"id\":2}"])
  assert_true(execution.close())
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "source-free requirements cannot select a different preparation or installed input" {
  let prepared = single_source_free_capacity_prepared()
  let assets = @publication_host.client_local_product_assets()
  let quote = prepare_source_free_local_requirements(
    prepared,
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let foreign = single_source_free_capacity_prepared()
  assert_true(
    quote.matches(
      prepared,
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ),
  )
  assert_false(
    quote.matches(
      foreign,
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ),
  )
  let ledger = @resources.create_ledger(quote.maximum_limits()).unwrap()
  assert_true(
    open_source_free_local_retained_host_on_ledger(
      foreign,
      ledger,
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      requirements=Some(quote),
    )
    is None,
  )
  assert_true(
    open_source_free_local_retained_host_on_ledger(
      prepared,
      ledger,
      assets.registry,
      "{}",
      Some(assets.fragment),
      assets.ordered,
      requirements=Some(quote),
    )
    is None,
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

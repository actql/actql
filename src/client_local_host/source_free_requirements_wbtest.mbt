///|
fn source_free_requirements_prepared(
  sql? : String? = None,
) -> @publication_host.PreparedClientProgram raise {
  let assets = @publication_host.client_local_product_assets()
  guard @json.parse(assets.environment) is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(cid)) else {
    fail("packaged Environment evidence missing")
  }
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  if sql is Some(text) {
    let context = @frontend.bind_query_context([], cid).unwrap()
    let original = @frontend.lower(text, @frontend.Sql, Some(context)).unwrap()
    return @publication_host.prepare_parsed_effect_free_client_program(
      original.program.unwrap(),
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
    ).unwrap()
  }
  @publication_host.prepare_effect_free_client_program(
    "{\"version\":\"actql/0.1\",\"id\":\"source-free-requirements\",\"stages\":[{\"id\":\"source\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1},{\"id\":2}]},\"as\":\"selected\"}],\"results\":{\"rows\":{\"from\":\"selected\",\"fields\":[\"id\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"source\",\"result\":\"rows\"}}}}",
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
// Real checked Program and Local provider, with a nominal Resource Ledger.
// This is not Native physical backing, Account or durable Run admission.
test "source-free requirements keep maximum allowances separate and execute the same prepared rows" {
  let prepared = source_free_requirements_prepared()
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
  let prepared = source_free_requirements_prepared()
  let assets = @publication_host.client_local_product_assets()
  let quote = prepare_source_free_local_requirements(
    prepared,
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let foreign = source_free_requirements_prepared()
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

///|
test "original eight-task UNION preserves its finite facility with prepared requirements" {
  let prepared = source_free_tasks_original_union()
  let assets = @publication_host.client_local_product_assets()
  let quote = prepare_source_free_local_requirements(
    prepared,
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let required = quote.simultaneous_limits().unwrap()
  let maximum = quote.maximum_limits()
  // A conservative upper bound is not a new supported-Program restriction.
  // Above the old facility, keep its existing actual allocation/OOM behavior.
  let selected = if required.retained_bytes <= maximum.retained_bytes &&
    required.execution_bytes <= maximum.execution_bytes {
    required
  } else {
    maximum
  }
  let ledger = @resources.create_ledger(selected).unwrap()
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
      fail("original multi-task execution refused its simultaneous reservation")
    }
  }
  assert_eq(execution.rows().unwrap(), ["{\"n\":1}", "{\"n\":2}"])
  assert_eq(@resources.ledger_usage(ledger).attempts, 8)
  assert_true(execution.close())
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
// Exercise the public lowering's multi-step task, rather than a Values-only
// Program. Its installed Relation provider retains child scratch as well as
// the outer sequence, before any Resource reservation or physical start.
test "source-free SQL chain quotes its installed provider and rejects one byte short" {
  let prepared = source_free_requirements_prepared(sql=Some("SELECT 1 AS x"))
  let assets = @publication_host.client_local_product_assets()
  let quote = prepare_source_free_local_requirements(
    prepared,
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let required = quote.simultaneous_limits().unwrap()
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
      fail("quoted SQL task refused its installed provider")
    }
  }
  assert_eq(execution.rows().unwrap(), ["{\"x\":1}"])
  assert_true(execution.close())
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  let short = @resources.create_ledger({
    ..required,
    execution_bytes: required.execution_bytes - 1L,
  }).unwrap()
  assert_true(
    open_source_free_local_retained_host_on_ledger(
      prepared,
      short,
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      requirements=Some(quote),
    )
    is None,
  )
  assert_eq(@resources.ledger_usage(short).attempts, 0)
  assert_eq(@resources.ledger_usage(short).reserved_execution_bytes, 0L)
}

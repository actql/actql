///|
test "managed source-free preparation retains the quoted original sequences and scalar limits" {
  let prepared = source_free_tasks_original_union()
  let assets = @publication_host.client_local_product_assets()
  let original = prepare_installed_managed_source_free(
    prepared,
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let quoted = prepared_installed_managed_source_free_requirements(original)
  let legacy = installed_managed_run_requirements(
    prepared,
    [],
    "{}",
    "{}",
    [],
    [],
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_eq(quoted, legacy)
  assert_eq(quoted[1], 8L)
  quoted[0] = 0L
  assert_eq(
    prepared_installed_managed_source_free_requirements(original),
    legacy,
  )
  assert_true(
    installed_source_free_preparation_matches(
      original,
      Pure(prepared),
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ),
  )
  let retained = original.sequences
  ignore(prepared_installed_managed_source_free_requirements(original))
  assert_true(physical_equal(original.sequences, retained))
  assert_eq(retained.length(), 8)
}

///|
test "managed source-free preparation executes the same generated originals on one diagnostic Ledger" {
  let prepared = source_free_tasks_original_union()
  let assets = @publication_host.client_local_product_assets()
  let original = prepare_installed_managed_source_free(
    prepared,
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  // Explicit unaccounted test storage only, not an operational Resource
  // admission. The production entry still requires its original admission.
  let ledger = @resources.create_ledger(original.limits).unwrap()
  let setup = open_checked_local_host(
    prepared,
    None,
    assets.registry,
    assets.values,
    1L,
    0L,
    0L,
    0L,
    fragment_body=Some(assets.fragment),
    ordered_body=assets.ordered,
    retained_output=true,
    acquisition_ledger=Some(ledger),
    source_free_preparation=Some(original),
  ).unwrap()
  let execution = match
    execute_source_free_local_tasks_guarded(setup, 64, 100000, () => true) {
    Ok(value) => value
    Err(failure) => {
      retry_local_values_execution_failure_cleanup(failure) |> ignore
      fail("retained original UNION execution failed")
    }
  }
  assert_eq(execution.rows().unwrap(), ["{\"n\":1}", "{\"n\":2}"])
  assert_eq(@resources.ledger_usage(ledger).attempts, 8)
  assert_true(execution.close())
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
test "managed source-free preparation refuses a foreign owner or changed contract original" {
  let prepared = source_free_tasks_original_union()
  let assets = @publication_host.client_local_product_assets()
  let original = prepare_installed_managed_source_free(
    prepared,
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let foreign = source_free_tasks_original_union()
  assert_false(
    installed_source_free_preparation_matches(
      original,
      Pure(foreign),
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ),
  )
  for
    (registry, values, fragment, ordered) in [
      ("{}", assets.values, Some(assets.fragment), assets.ordered),
      (assets.registry, "{}", Some(assets.fragment), assets.ordered),
      (assets.registry, assets.values, None, assets.ordered),
      (assets.registry, assets.values, Some(assets.fragment), Some("{}")),
    ] {
    assert_false(
      installed_source_free_preparation_matches(
        original,
        Pure(prepared),
        registry,
        values,
        fragment,
        ordered,
      ),
    )
  }
  assert_true(
    prepare_installed_managed_source_free(
      prepared,
      "{}",
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    )
    is Err(Unsupported),
  )
  // Use the independently authored Source Environment's declared identity;
  // do not retarget the historical helpers or their original failed vectors.
  guard @json.parse(source_query_original_environment) is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(cid)) else {
    fail("original Source Environment evidence")
  }
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let source = @publication_host.prepare_effect_free_client_program(
    source_query_original_document,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  assert_true(
    prepare_installed_managed_source_free(
      source,
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    )
    is Err(Unsupported),
  )
}

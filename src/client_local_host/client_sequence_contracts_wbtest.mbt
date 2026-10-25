///|
test "installed contract original retains the admitted closure across repeated selections" {
  let assets = @publication_host.client_local_product_assets()
  let installed = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let original = installed.original
  let registry = original.value.contracts
  for _ in 0..<10 {
    assert_true(
      client_local_sequence_selection_matches(
        installed,
        assets.values,
        Some(assets.fragment),
        assets.ordered,
      ),
    )
    assert_true(
      client_local_sequence_selection_matches(
        installed,
        assets.values,
        None,
        None,
      ),
    )
    assert_true(physical_equal(installed.original, original))
    assert_true(physical_equal(installed.original.value.contracts, registry))
  }
  assert_eq(original.registry_body, assets.registry)
  assert_eq(original.values_body, assets.values)
  assert_eq(original.fragment_body, Some(assets.fragment))
  assert_eq(original.ordered_body, assets.ordered)
}

///|
test "invalid installed bodies refuse without changing an admitted original or its selected capabilities" {
  let assets = @publication_host.client_local_product_assets()
  let installed = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  for
    (registry, values, fragment, ordered) in [
      ("{}", assets.values, Some(assets.fragment), assets.ordered),
      (assets.registry, "{}", Some(assets.fragment), assets.ordered),
      (assets.registry, assets.values, Some("{"), assets.ordered),
      (assets.registry, assets.values, Some(assets.fragment), Some("{}")),
    ] {
    assert_true(
      prepare_installed_sequence_contracts(registry, values, fragment, ordered)
      is Err(Unsupported),
    )
    assert_true(
      client_local_sequence_selection_matches(
        installed,
        assets.values,
        Some(assets.fragment),
        assets.ordered,
      ),
    )
  }
  assert_false(
    client_local_sequence_selection_matches(
      installed,
      "{}",
      Some(assets.fragment),
      assets.ordered,
    ),
  )
  assert_false(
    client_local_sequence_selection_matches(
      installed,
      assets.values,
      Some("{"),
      assets.ordered,
    ),
  )
  assert_false(
    client_local_sequence_selection_matches(
      installed,
      assets.values,
      Some(assets.fragment),
      Some("{}"),
    ),
  )
  let absent = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    None,
    None,
  ).unwrap()
  assert_true(absent.original.value.fragment_contract is None)
  assert_true(absent.original.value.ordered_contract is None)
  assert_false(
    client_local_sequence_selection_matches(
      absent,
      assets.values,
      Some(assets.fragment),
      None,
    ),
  )
  assert_true(installed.original.value.fragment_contract is Some(_))
}

///|
test "independently admitted installed originals never become one mutable cache cell" {
  let assets = @publication_host.client_local_product_assets()
  let first = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    None,
    None,
  ).unwrap()
  let second = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    None,
    None,
  ).unwrap()
  assert_false(physical_equal(first, second))
  assert_false(physical_equal(first.original, second.original))
  assert_false(
    physical_equal(
      first.original.value.contracts,
      second.original.value.contracts,
    ),
  )
  for _ in 0..<2 {
    assert_true(
      prepare_installed_sequence_contracts("{}", assets.values, None, None)
      is Err(Unsupported),
    )
    assert_true(
      client_local_sequence_selection_matches(first, assets.values, None, None),
    )
    assert_true(
      client_local_sequence_selection_matches(second, assets.values, None, None),
    )
  }
}

///|
test "shared contracts retain distinct original query sequence preparation" {
  let assets = @publication_host.client_local_product_assets()
  let installed = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  guard @json.parse(assets.environment) is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(evidence)) else {
    fail("original bundled Environment evidence missing")
  }
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    evidence,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let prepare = (document : String) => {
    @publication_host.prepare_effect_free_client_program(
      document,
      Json,
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
    ).unwrap()
  }
  let first = prepare(
    (
      #|{"version":"actql/0.1","id":"first-contract-query","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"rows"}}}}
    ),
  )
  let second = prepare(
    (
      #|{"version":"actql/0.1","id":"second-contract-query","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"rows"}}}}
    ),
  )
  assert_false(physical_equal(first, second))
  let a = prepare_client_local_sequences(
    first,
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let b = prepare_client_local_sequences(
    second,
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_eq(a.length(), 1)
  assert_eq(b.length(), 1)
  assert_false(physical_equal(a[0], b[0]))
}

///|
test "equal canonical contract identity does not replace an exact installed original" {
  let assets = @publication_host.client_local_product_assets()
  let original = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    None,
    None,
  ).unwrap()
  let changed = prepare_installed_sequence_contracts(
    " " + assets.registry,
    assets.values,
    None,
    None,
  ).unwrap()
  assert_false(physical_equal(original, changed))
  assert_eq(original.original.registry_body, assets.registry)
  assert_eq(changed.original.registry_body, " " + assets.registry)
  assert_true(
    client_local_sequence_selection_matches(original, assets.values, None, None),
  )
  assert_true(
    client_local_sequence_selection_matches(changed, assets.values, None, None),
  )
}

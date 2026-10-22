///|
test "same immutable sequence contracts are admitted once with original typed identity" {
  let assets = @publication_host.client_local_product_assets()
  let cached = Ref(None)
  let reads = Ref(0)
  let read = (registry, values, fragment, ordered) => {
    reads.val += 1
    read_client_local_sequence_contracts(registry, values, fragment, ordered)
  }
  let first = client_local_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    cached~,
    read~,
  ).unwrap()
  let second = client_local_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    cached~,
    read~,
  ).unwrap()
  assert_eq(reads.val, 1)
  assert_true(physical_equal(first, second))
  assert_true(physical_equal(first.contracts, second.contracts))
}

///|
test "foreign changed and absent contract bodies cannot borrow retained contracts" {
  let assets = @publication_host.client_local_product_assets()
  let cached = Ref(None)
  assert_true(
    client_local_sequence_contracts(
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      cached~,
    )
    is Some(_),
  )
  for
    (registry, values, fragment, ordered) in [
      ("{}", assets.values, Some(assets.fragment), assets.ordered),
      (assets.registry, "{}", Some(assets.fragment), assets.ordered),
      (assets.registry, assets.values, Some("{"), assets.ordered),
      (assets.registry, assets.values, Some(assets.fragment), Some("{}")),
    ] {
    assert_true(
      client_local_sequence_contracts(
        registry,
        values,
        fragment,
        ordered,
        cached~,
      )
      is None,
    )
  }
  let absent = client_local_sequence_contracts(
    assets.registry,
    assets.values,
    None,
    None,
    cached~,
  ).unwrap()
  assert_true(absent.fragment_contract is None)
  assert_true(absent.ordered_contract is None)
  let restored = client_local_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    cached~,
  ).unwrap()
  assert_true(restored.fragment_contract is Some(_))
}

///|
test "independent contract cells and bounded admission failures remain separate" {
  let assets = @publication_host.client_local_product_assets()
  let cached = Ref(None)
  let other = Ref(None)
  let reads = Ref(0)
  let read = (registry, values, fragment, ordered) => {
    reads.val += 1
    read_client_local_sequence_contracts(registry, values, fragment, ordered)
  }
  let first = client_local_sequence_contracts(
    assets.registry,
    assets.values,
    None,
    None,
    cached~,
    read~,
  ).unwrap()
  let second = client_local_sequence_contracts(
    assets.registry,
    assets.values,
    None,
    None,
    cached=other,
    read~,
  ).unwrap()
  assert_eq(reads.val, 2)
  assert_false(physical_equal(first, second))
  for _ in 0..<2 {
    assert_true(
      client_local_sequence_contracts(
        "{}",
        assets.values,
        None,
        None,
        cached~,
        read~,
      )
      is None,
    )
  }
  assert_eq(reads.val, 3)
}

///|
test "shared contracts retain distinct original query sequence preparation" {
  let assets = @publication_host.client_local_product_assets()
  let first = single_source_free_capacity_prepared()
  let second = single_source_free_capacity_prepared()
  assert_false(physical_equal(first, second))
  let a = prepare_client_local_sequences(
    first,
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let b = prepare_client_local_sequences(
    second,
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_eq(a.length(), 1)
  assert_eq(b.length(), 1)
  assert_false(physical_equal(a[0], b[0]))
}

///|
test "equal canonical identity does not replace exact original contract wires" {
  let assets = @publication_host.client_local_product_assets()
  let cached = Ref(None)
  let reads = Ref(0)
  let read = (registry, values, fragment, ordered) => {
    reads.val += 1
    read_client_local_sequence_contracts(registry, values, fragment, ordered)
  }
  let original = client_local_sequence_contracts(
    assets.registry,
    assets.values,
    None,
    None,
    cached~,
    read~,
  ).unwrap()
  let changed = client_local_sequence_contracts(
    " " + assets.registry,
    assets.values,
    None,
    None,
    cached~,
    read~,
  ).unwrap()
  assert_eq(reads.val, 2)
  assert_false(physical_equal(original, changed))
  let same = client_local_sequence_contracts(
    " " + assets.registry,
    assets.values,
    None,
    None,
    cached~,
    read~,
  ).unwrap()
  assert_eq(reads.val, 2)
  assert_true(physical_equal(changed, same))
}

///|
fn registered_relation_contracts() -> RegisteredRelationContracts raise {
  admit_relation_registry(
    registered_body(),
    registered_values(),
    registry_limits(),
  ).unwrap()
}

///|
fn registry_limits() -> RegistryLimits {
  { max_body_bytes: 100000, max_body_nodes: 10000, max_body_depth: 100, }
}

///|
test "registry admission hashes complete immutable bodies and excludes historical selection" {
  let accepted = admit_relation_registry(
    registered_body(),
    registered_values(),
    registry_limits(),
  ).unwrap()
  assert_eq(
    accepted.registry_cid,
    "sha256:604f29b5b36a5b9e66fdd8b866978a65f529d56a41c9c571052a59364196943a",
  )
  assert_eq(
    accepted.values_contract_cid,
    "sha256:9dec7cf1abedfb23b0af130ec5e25c7442d28c205a94cad0218b2f5982d44b44",
  )
  assert_true(
    admit_relation_registry(
      historical_body(),
      registered_values(),
      registry_limits(),
    )
    is Err(UnsupportedRegistry),
  )
  assert_true(
    admit_relation_registry(
      registered_body(),
      historical_body(),
      registry_limits(),
    )
    is Err(ValuesContractMismatch),
  )
}

///|
test "registry admission enforces per-body budgets before issuing a token" {
  let body = registered_body()
  let values = registered_values()
  assert_true(
    admit_relation_registry(body, values, {
      ..registry_limits(),
      max_body_bytes: -1,
    })
    is Err(InvalidRegistryLimits),
  )
  assert_true(
    admit_relation_registry(body, values, {
      ..registry_limits(),
      max_body_nodes: 0,
    })
    is Err(RegistryBodyLimit),
  )
  assert_true(
    admit_relation_registry(body, values, {
      ..registry_limits(),
      max_body_depth: 0,
    })
    is Err(RegistryBodyLimit),
  )
  let size = @identity.measure_value(body, 100000, 10000, 100)
  assert_true(
    admit_relation_registry(body, values, {
      ..registry_limits(),
      max_body_bytes: size - 1,
    })
    is Err(RegistryBodyLimit),
  )
  // The values contract is larger than the registry, so its own limit must also
  // be enforced after the registry successfully passes.
  assert_true(@identity.measure_value(values, 100000, 10000, 100) > size)
  assert_true(
    admit_relation_registry(body, values, {
      ..registry_limits(),
      max_body_bytes: size,
    })
    is Err(ValuesContractBodyLimit),
  )
}

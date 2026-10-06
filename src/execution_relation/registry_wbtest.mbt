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
    "sha256:1513a0a6b1db1e5847fdb46b191a6f5d67cd806e1ba234843ac12f86f9f49b38",
  )
  assert_eq(
    accepted.values_contract_cid,
    "sha256:9b716536b27d313e93deadae776d9abf21c3d06dcd653d2eb3b74e0c276a182b",
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
test "new constructor registration pins its complete execution contract" {
  // Independent Node canonical SHA-256 of the machine contract, not product output.
  assert_eq(
    @identity.cid_value(registered_property_graph(), 100000, 10000, 100),
    "sha256:b00de8912497c6af1596debd1c59ee8d3477faf0391be40f64ac82ebc6d9ebb7",
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

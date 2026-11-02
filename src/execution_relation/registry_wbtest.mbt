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
    "sha256:204fd80c64c2bff246015f06ae50d0044aa566f197922f14cd15ecf0b3285fdb",
  )
  assert_eq(
    accepted.values_contract_cid,
    "sha256:96c7925a693801dcb3bce9f3e2da9b4fd9ed39e517af90cbac0e1adbee5ad2ae",
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
    @identity.cid_value(registered_graph(), 100000, 10000, 100),
    "sha256:0979999a64bb47f7fcb0d113c0bbcab592ad0a268b548a8776f8fac4fd6f6d84",
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

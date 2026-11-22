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
    "sha256:52e62094b1162213605e27199aa9a0e4832ee7771bcc1be66124f2fefb0a01e7",
  )
  assert_eq(
    accepted.values_contract_cid,
    "sha256:acdc65097f478d6b14126eb2d2e1bdd8df5893de923b3f9db7412b73b4a318fe",
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
    "sha256:1c871512fceef5e68415511a2fe40a62df2c287fb31360edca749b3f13921113",
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

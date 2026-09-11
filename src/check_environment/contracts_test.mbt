///|
fn envelope(body : String, cid : String) -> String {
  "{\"body\":" +
  body +
  ",\"cid\":\"" +
  cid +
  "\",\"id\":\"example\",\"kind\":\"request_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"external-7\"}"
}

///|
fn registry_wire(entries : Array[String]) -> WireEnvironment {
  entries.sort_by((a, b) => {
    @sha.hex(@utf8.encode(a)).compare(@sha.hex(@utf8.encode(b)))
  })
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[" +
    entries.join(",") +
    "],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let id = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  read(
    @utf8.encode(prefix + "\"evidence_bundle_cid\":\"" + id + "\"," + suffix),
    id,
    caps(),
  ).unwrap()
}

///|
// Fixed self-CIDs calculated independently with Node crypto over the canonical
// five-member preimage, not by the product emitter or registry reader.
fn null_contract_cid() -> String {
  "sha256:1b51a2bea6cc92150522f106c46b1798f38c3ea5e9136c4454788b43b6680d4d"
}

///|
test "contract envelopes preserve null body external version and exact environment" {
  let wire = registry_wire([envelope("null", null_contract_cid())])
  let registry = check_contract_registry(wire, caps()).unwrap()
  assert_true(physical_equal(contract_registry_environment(registry), wire))
  let found = resolve_contract(
    registry,
    "example",
    "external-7",
    null_contract_cid(),
    "request_schema",
  ).unwrap()
  assert_true(@decode.is_null(contract_body(found)))
  assert_eq(
    contract_identity(found),
    ("example", "external-7", null_contract_cid()),
  )
  assert_eq(contract_role(found), "request_schema")
  assert_true(physical_equal(member_environment(contract_member(found)), wire))
  assert_true(contract_at(registry, -1) is None)
  assert_true(contract_at(registry, 1) is None)
  assert_true(
    resolve_contract(
      registry,
      "example",
      "0.1",
      null_contract_cid(),
      "request_schema",
    )
    is Err(UnknownReference(_, _)),
  )
  assert_true(
    resolve_contract(
      registry,
      "example",
      "external-7",
      "sha256:" + "0".repeat(64),
      "request_schema",
    )
    is Err(ReferenceMismatch(_, _)),
  )
  assert_true(
    resolve_contract(
      registry,
      "example",
      "external-7",
      null_contract_cid(),
      "carrier_schema",
    )
    is Err(WrongKind(_, _)),
  )
  let (bytes, nodes, count) = contract_registry_usage(registry)
  let exact = {
    ..caps(),
    max_bytes: bytes,
    max_nodes: nodes,
    max_members: count,
  }
  assert_true(check_contract_registry(wire, exact) is Ok(_))
  assert_true(
    check_contract_registry(wire, { ..exact, max_bytes: bytes - 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    check_contract_registry(wire, { ..exact, max_nodes: nodes - 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    check_contract_registry(wire, { ..exact, max_members: 0, })
    is Err(BudgetExceeded),
  )
  assert_true(
    check_contract_registry(wire, { ..exact, max_depth: 0, })
    is Err(BudgetExceeded),
  )
  assert_true(
    check_contract_registry(wire, { ..exact, max_nodes: -1, })
    is Err(InvalidLimits),
  )
}

///|
test "nested cid and parameter-looking business data remain in envelope preimage" {
  let id = "sha256:3ca7a1261409b13f01cd9398a691ccfc3a0a336ab7f2ce5773ee2aa2650b5302"
  let body = "{\"cid\":\"nested\",\"literal\":{\"$param\":\"business\"}}"
  let registry = check_contract_registry(
    registry_wire([envelope(body, id)]),
    caps(),
  ).unwrap()
  assert_eq(contract_identity(contract_at(registry, 0).unwrap()).2, id)
  // Recomputing the aggregate environment cannot repair a stale inner CID.
  assert_true(
    check_contract_registry(registry_wire([envelope("{}", id)]), caps())
    is Err(IdentityMismatch(0)),
  )
  assert_true(
    check_contract_registry(
      registry_wire([envelope(body, "sha256:" + @sha.hex(@utf8.encode(body)))]),
      caps(),
    )
    is Err(IdentityMismatch(0)),
  )
  assert_true(
    check_contract_registry(
      registry_wire([envelope(body, id), envelope("null", null_contract_cid())]),
      caps(),
    )
    is Err(ConflictingIdentity("example", "external-7")),
  )
}

///|
test "contract envelope closed shape and kind are mandatory even for unused entries" {
  let valid = envelope("null", null_contract_cid())
  for
    changed in [
      valid.replace(old="\"body\":null,", new=""),
      valid.replace(old="\"id\":", new="\"extra\":0,\"id\":"),
      valid.replace(old="\"example\"", new="\"\""),
      valid.replace(old="\"external-7\"", new="null"),
      valid.replace(old="request_schema", new="unknown"),
      valid.replace(old="actql.contract/0.1", new="actql.contract/1.0"),
    ] {
    assert_true(
      check_contract_registry(registry_wire([changed]), caps())
      is Err(InvalidEnvelope(0)),
    )
  }
  assert_true(check_contract_registry(registry_wire([]), caps()) is Ok(_))
}

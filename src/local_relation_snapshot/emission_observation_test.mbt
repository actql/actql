///|
test "member emission observation retains the original complete writer cells" {
  let environment = wire_environment("[" + base() + "]", "[]")
  let entry = @environment.member_at(environment, SchemaSnapshots, 0).unwrap()
  let (result, observed) = observe_read_member(entry, caps())
  let attached = result.unwrap()
  assert_true(physical_equal(environment_member(attached), entry))
  // Independently counted value nodes and open containers in the fixed body.
  assert_eq(observed, Some((@utf8.encode(base()).length(), 9, 3)))
  assert_eq(
    usage(environment_snapshot(attached)),
    (@utf8.encode(base()).length(), 9),
  )
  assert_eq(member_emission_observation_extent(), {
    record_headers: 5L,
    reference_slots: 5L,
    scalar_words: 5L,
  })
}

///|
test "member emission refusal preserves actually charged nodes bytes and depth" {
  let environment = wire_environment("[" + base() + "]", "[]")
  let entry = @environment.member_at(environment, SchemaSnapshots, 0).unwrap()
  let node_prefix =
    #|{"output_carrier":"relation","schema":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"source_ref":"source:local/s/rows","version":
  let (result, used) = observe_read_member(entry, { ..caps(), max_nodes: 8, })
  assert_true(result is Err(BudgetExceeded))
  assert_eq(used, Some((@utf8.encode(node_prefix).length(), 8, 3)))
  let depth_prefix =
    #|{"output_carrier":"relation","schema":{"additional_properties":false,"fields":
  let (result, used) = observe_read_member(entry, { ..caps(), max_depth: 2, })
  assert_true(result is Err(BudgetExceeded))
  // value_start charges the refused fields container before its depth guard.
  assert_eq(used, Some((@utf8.encode(depth_prefix).length(), 5, 2)))
  let size = @utf8.encode(base()).length()
  let (result, used) = observe_read_member(entry, {
    ..caps(),
    max_bytes: size - 1,
  })
  assert_true(result is Err(BudgetExceeded))
  let (bytes, nodes, depth) = used.unwrap()
  assert_true(bytes > 0 && bytes <= size - 1)
  assert_true(nodes > 0 && nodes <= 9)
  assert_true(depth > 0 && depth <= 3)
}

///|
test "member emission absence distinguishes no writer from a completed malformed domain" {
  let environment = wire_environment("[" + base() + "]", "[" + base() + "]")
  let entry = @environment.member_at(environment, SchemaSnapshots, 0).unwrap()
  let wrong = @environment.member_at(environment, MappingContracts, 0).unwrap()
  let (result, used) = observe_read_member(wrong, { ..caps(), max_bytes: -1, })
  assert_true(result is Err(WrongSection))
  assert_true(used is None)
  let (result, used) = observe_read_member(entry, { ..caps(), max_bytes: -1, })
  assert_true(result is Err(InvalidSnapshot(InvalidLimits)))
  assert_true(used is None)
  let (result, used) = observe_read_member(entry, { ..caps(), max_nodes: 0, })
  assert_true(result is Err(BudgetExceeded))
  assert_true(used is None)
  let malformed = base().replace(
    old="\"nullable\":false",
    new="\"nullable\":true",
  )
  let environment = wire_environment("[" + malformed + "]", "[]")
  let entry = @environment.member_at(environment, SchemaSnapshots, 0).unwrap()
  let (result, used) = observe_read_member(entry, caps())
  assert_true(result is Err(InvalidSnapshot(InvalidSnapshot)))
  assert_eq(used, Some((@utf8.encode(malformed).length(), 9, 3)))
}

///|
test "observed member preserves original byte reader contract error coordinates" {
  let malformed = base().replace(
    old="\"nullable\":false",
    new="\"nullable\":\"no\"",
  )
  let environment = wire_environment("[" + malformed + "]", "[]")
  let entry = @environment.member_at(environment, SchemaSnapshots, 0).unwrap()
  let bytes = @utf8.encode(malformed)
  let original = match read(bytes, @environment.member_cid(entry), caps()) {
    Err(TypeContract(issue)) => issue
    _ => abort("original typed contract refusal required")
  }
  let (result, used) = observe_read_member(entry, caps())
  match result {
    Err(InvalidSnapshot(TypeContract(issue))) => assert_eq(issue, original)
    _ => abort("same original typed contract refusal required")
  }
  assert_eq(used, Some((bytes.length(), 9, 3)))
}

///|
test "saved publication counts receipt nodes independently of CID text bytes" {
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 1048576,
    max_nodes: 10000,
    max_depth: 64,
  }
  let short = "{\"a\":{\"nullable\":false,\"type\":\"string\"}}"
  let long = "{\"" +
    "a".repeat(4096) +
    "\":{\"nullable\":false,\"type\":\"string\"}}"
  let a = @publication.admit_hashed_effect_dependency_body(
    "relation_schema", "sha256:a6fdd6aaeebbc3e1e731b017de57774622d432d2a6408ce2768a86aa35c8fb3c",
    short, 8192, 32, 8,
  ).unwrap()
  let b = @publication.admit_hashed_effect_dependency_body(
    "relation_schema", "sha256:8e9ef3eacadac4b4dfc1a06fc2261297b280328b00cb946a8f61f87bd18467e3",
    long, 8192, 32, 8,
  ).unwrap()
  let (ab, an, ad) = @publication.captured_effect_dependency_body_wire_usage(a).unwrap()
  let (bb, bn, bd) = @publication.captured_effect_dependency_body_wire_usage(b).unwrap()
  let af = @publication.captured_effect_dependency_body_field_count(a).unwrap()
  let bf = @publication.captured_effect_dependency_body_field_count(b).unwrap()
  let (short_bytes, short_nodes, short_depth) = saved_effect_publication_geometry(
    (8192, 48, 5),
    (ab.to_int64(), an.to_int64(), ad, af.to_int64()),
    2L,
    1,
    1,
    limits,
  ).unwrap()
  let (bytes, nodes, depth) = saved_effect_publication_geometry(
    (8192, 48, 5),
    (bb.to_int64(), bn.to_int64(), bd, bf.to_int64()),
    2L,
    1,
    1,
    limits,
  ).unwrap()
  assert_true(bytes > short_bytes)
  assert_eq(nodes, short_nodes)
  assert_eq(depth, short_depth)
  let capacity = @local.installed_effect_contract_response_construction_capacity(
    bytes, nodes, depth,
  ).unwrap()
  // The caller adds this packet to its existing 7MiB Read baseline under the
  // unchanged 8MiB ticket. This constructor is not another whole Read base.
  assert_true(@execution.execution_capacity_retained_bytes(capacity) < 1048576L)
}

///|
test "saved publication geometry preserves original limits and checked overflow" {
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 1048576,
    max_nodes: 10000,
    max_depth: 64,
  }
  let schema = (64L, 12L, 3, 2L)
  assert_true(
    saved_effect_publication_geometry(
      (1024, 48, 5),
      schema,
      9223372036854775807L,
      1,
      1,
      limits,
    )
    is None,
  )
  assert_true(
    saved_effect_publication_geometry((1024, 48, 65), schema, 2L, 1, 1, limits)
    is None,
  )
  assert_true(
    saved_effect_publication_geometry(
      (1024, 10001, 5),
      schema,
      2L,
      1,
      1,
      limits,
    )
    is None,
  )
  assert_true(
    saved_effect_publication_geometry(
      (1048576, 48, 5),
      schema,
      2L,
      1,
      1,
      limits,
    )
    is None,
  )
  let (_, nodes, depth) = saved_effect_publication_geometry(
    (1024, 48, 3),
    schema,
    2L,
    1,
    1,
    { max_wire_bytes: 1048576, max_nodes: 100, max_depth: 3, },
  ).unwrap()
  assert_eq(nodes, 100)
  assert_eq(depth, 3)
  let (ascii_bytes, _, _) = saved_effect_publication_geometry(
    (1024, 48, 5),
    schema,
    2L,
    1,
    1,
    limits,
  ).unwrap()
  let (unicode_bytes, _, _) = saved_effect_publication_geometry(
    (3072, 48, 5),
    schema,
    2L,
    1,
    1,
    limits,
  ).unwrap()
  assert_eq(unicode_bytes - ascii_bytes, 2048)
}

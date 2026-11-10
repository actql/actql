///|
test "saved publication counts receipt nodes independently of CID text bytes" {
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 1048576,
    max_nodes: 10000,
    max_depth: 64,
  }
  let (_, short_nodes, short_depth) = saved_effect_publication_geometry(
    (1024, 48, 5),
    1024,
    64L,
    2L,
    1,
    1,
    limits,
  ).unwrap()
  let (bytes, nodes, depth) = saved_effect_publication_geometry(
    (8192, 48, 5),
    8192,
    64L,
    2L,
    1,
    1,
    limits,
  ).unwrap()
  // Longer scalar/CID spellings do not introduce JSON nodes or nesting.
  assert_eq(nodes, short_nodes)
  assert_eq(depth, short_depth)
  assert_true(bytes > nodes)
  let capacity = @local.installed_json_effect_response_construction_capacity(
    @execution.execution_capacity(0L, 0L).unwrap(),
    bytes,
    nodes,
    depth,
  ).unwrap()
  // This same two-row closed constructor fits the existing 7MiB Read retained
  // facility; no policy, resource ceiling or arbitrary provider shape changes.
  assert_true(
    @execution.execution_capacity_retained_bytes(capacity) < 7L * 1048576L,
  )
}

///|
test "saved publication geometry preserves original limits and checked overflow" {
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 1048576,
    max_nodes: 10000,
    max_depth: 64,
  }
  assert_true(
    saved_effect_publication_geometry(
      (1024, 48, 5),
      1024,
      64L,
      9223372036854775807L,
      1,
      1,
      limits,
    )
    is None,
  )
  assert_true(
    saved_effect_publication_geometry(
      (1024, 48, 65),
      1024,
      64L,
      2L,
      1,
      1,
      limits,
    )
    is None,
  )
  assert_true(
    saved_effect_publication_geometry(
      (1024, 10001, 5),
      1024,
      64L,
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
      1048576,
      64L,
      2L,
      1,
      1,
      limits,
    )
    is None,
  )
  let (_, nodes, depth) = saved_effect_publication_geometry(
    (1024, 48, 3),
    1024,
    64L,
    2L,
    1,
    1,
    { max_wire_bytes: 1048576, max_nodes: 100, max_depth: 3, },
  ).unwrap()
  assert_eq(nodes, 100)
  assert_eq(depth, 3)
  // Unicode byte length must not inflate the old UTF16 escaping envelope.
  let (ascii_bytes, _, _) = saved_effect_publication_geometry(
    (1024, 48, 5),
    1024,
    64L,
    2L,
    1,
    1,
    limits,
  ).unwrap()
  let (unicode_bytes, _, _) = saved_effect_publication_geometry(
    (3072, 48, 5),
    1024,
    64L,
    2L,
    1,
    1,
    limits,
  ).unwrap()
  assert_eq(unicode_bytes, ascii_bytes)
  let (wide_bytes, wide_nodes, _) = saved_effect_publication_geometry(
    (1024, 48, 5),
    1024,
    2048L,
    2L,
    1,
    1,
    limits,
  ).unwrap()
  let (_, narrow_nodes, _) = saved_effect_publication_geometry(
    (1024, 48, 5),
    1024,
    64L,
    2L,
    1,
    1,
    limits,
  ).unwrap()
  assert_true(wide_bytes > ascii_bytes)
  assert_true(wide_nodes > narrow_nodes)
}

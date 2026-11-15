///|
test "typed Publication dependency borrows its original while preserving strict roles and exact limits" {
  let original = issue_single_source_acquisition_scope(
    relation_fixture_cid("1"),
    relation_fixture_cid("2"),
    10000,
    1000,
    32,
  ).unwrap()
  let (bytes, nodes, depth) = publication_contract_wire_usage(original).unwrap()
  let body = capture_publication_effect_dependency_body(
    "acquisition_scope", original, bytes, nodes, depth,
  ).unwrap()
  assert_true(physical_equal(body.value, original.value))
  assert_eq(body.wire, original.wire)
  assert_eq(body.node.identity, original.identity)
  assert_eq(body.node.canonical_bytes, bytes)
  assert_eq(body.wire_usage, Some((bytes, nodes, depth)))
  assert_eq(body.node.references.map(value => (value.kind, value.identity)), [
    ("source_contract", relation_fixture_cid("1")),
    ("request_values", relation_fixture_cid("2")),
  ])
  assert_true(
    capture_publication_effect_dependency_body(
      "ordering_evidence", original, bytes, nodes, depth,
    )
    is Err(WrongDependencyKind),
  )
  for
    (b, n, d) in [
      (bytes - 1, nodes, depth),
      (bytes, nodes - 1, depth),
      (bytes, nodes, depth - 1),
    ] {
    assert_true(
      capture_publication_effect_dependency_body(
        "acquisition_scope", original, b, n, d,
      )
      is Err(InvalidBody),
    )
  }
  let admitted = admit_publication_effect_dependency_body(
    "acquisition_scope",
    original.wire,
    bytes,
    nodes,
    depth,
  ).unwrap()
  assert_eq(admitted.node.identity, body.node.identity)
  assert_eq(admitted.wire, body.wire)
  assert_eq(
    admitted.node.references.map(value => (value.kind, value.identity)),
    body.node.references.map(value => (value.kind, value.identity)),
  )
}

///|
test "typed Source dependency preserves the admitted logical value and its exact reference partition" {
  // Existing independently pinned codec fixture, not a physical Source ACK.
  let original = listing_report_codec_fields("connector://fixture/rows").input
  let (bytes, nodes, depth) = run_evidence_value_wire_usage(original).unwrap()
  let body = capture_source_effect_dependency_body(
    original, bytes, nodes, depth,
  ).unwrap()
  assert_true(physical_equal(body.value, original.value))
  assert_eq(body.wire, original.wire)
  assert_eq(body.node.identity, original.identity)
  assert_eq(body.node.canonical_bytes, bytes)
  assert_eq(body.node.references.map(value => (value.kind, value.identity)), [
    ("relation_value", relation_fixture_cid("d")),
    ("relation_schema", relation_fixture_cid("e")),
    ("source_contract", relation_fixture_cid("b")),
  ])
  for
    (b, n, d) in [
      (bytes - 1, nodes, depth),
      (bytes, nodes - 1, depth),
      (bytes, nodes, depth - 1),
    ] {
    assert_true(
      capture_source_effect_dependency_body(original, b, n, d)
      is Err(InvalidBody),
    )
  }
  assert_true(
    capture_source_effect_dependency_body(
      { ..original, wire_usage: None, },
      bytes,
      nodes,
      depth,
    )
    is Err(InvalidBody),
  )
  let admitted = admit_source_effect_dependency_body(
    "source_input_logical",
    original.wire,
    bytes,
    nodes,
    depth,
  ).unwrap()
  assert_eq(admitted.node.identity, body.node.identity)
  assert_eq(admitted.wire, body.wire)
  assert_eq(
    admitted.node.references.map(value => (value.kind, value.identity)),
    body.node.references.map(value => (value.kind, value.identity)),
  )
}

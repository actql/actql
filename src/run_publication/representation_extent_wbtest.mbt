///|
test "evidence extent reads the same admitted tree and leaves its wire unchanged" {
  let cid = "sha256:" + "1".repeat(64)
  let original = seal_run_evidence_value(
    "bound_invocation_template",
    "{\"version\":\"actql-bound-invocation-template/0.1\",\"program_definition_cid\":\"" +
    cid +
    "\",\"parameter_values_cid\":\"" +
    cid +
    "\",\"invocation_bindings_cid\":\"" +
    cid +
    "\",\"check_environment_cid\":\"" +
    cid +
    "\",\"grammar_manifest_cid\":\"" +
    cid +
    "\",\"barrier_contract_manifest_cid\":\"" +
    cid +
    "\",\"required_profile_contracts\":[],\"source_evidence\":\"unbound\"}",
    16384,
    128,
    8,
  ).unwrap()
  let wire = run_evidence_value_json(original)
  let identity = run_evidence_value_identity(original)
  let extent = run_evidence_value_representation_extent(original, 128, 8, 16384).unwrap()
  assert_eq(extent.contract_strings, 3L)
  assert_eq(
    extent.contract_text_utf16_units,
    original.name.length().to_int64() +
    identity.length().to_int64() +
    wire.length().to_int64(),
  )
  assert_eq(extent.canonical.objects, 1L)
  assert_eq(extent.canonical.arrays, 1L)
  assert_eq(run_evidence_value_json(original), wire)
  assert_eq(run_evidence_value_identity(original), identity)
  assert_true(
    run_evidence_value_representation_extent(original, 128, 8, 1)
    is Err(Encoding),
  )
}

///|
test "Publication representation extent measures original admitted contract without reissuance" {
  assert_true(
    prepare_result_definition("sha256:" + "1".repeat(64), "e\u0301😀")
    is Err(NonCanonicalResultName),
  )
  let original = result_definition_contract(
    prepare_result_definition("sha256:" + "1".repeat(64), "é😀").unwrap(),
  )
  let wire = publication_contract_json(original)
  let cid = publication_contract_identity(original)
  let extent = publication_contract_representation_extent(original, 32, 8, 4096).unwrap()
  assert_eq(extent.contract_records, 1L)
  assert_eq(extent.contract_strings, 4L)
  assert_eq(
    extent.contract_text_utf16_units,
    "result_definition".length().to_int64() +
    "result_definition_cid".length().to_int64() +
    cid.length().to_int64() +
    wire.length().to_int64(),
  )
  // Root plus four admitted string fields, including the issued identity.
  assert_eq(extent.canonical.nodes, 5L)
  assert_eq(extent.canonical.strings, 8L)
  assert_eq(extent.canonical.objects, 1L)
  assert_eq(extent.canonical.arrays, 0L)
  assert_eq(publication_contract_json(original), wire)
  assert_eq(publication_contract_identity(original), cid)
  assert_true(
    publication_contract_representation_extent(original, 32, 8, 1)
    is Err(Encoding),
  )
  assert_true(
    publication_contract_representation_extent(original, 0, 8, 4096)
    is Err(InvalidLimits),
  )
}

///|
test "dependency retained extent includes reference backing and measured option without changing its original" {
  let original = issue_single_source_acquisition_scope(
    relation_fixture_cid("1"),
    relation_fixture_cid("2"),
    10000,
    1000,
    32,
  ).unwrap()
  let (bytes, nodes, depth) = publication_contract_wire_usage(original).unwrap()
  let measured = capture_publication_effect_dependency_body(
    "acquisition_scope", original, bytes, nodes, depth,
  ).unwrap()
  let strict = admit_publication_effect_dependency_body(
    "acquisition_scope",
    original.wire,
    bytes,
    nodes,
    depth,
  ).unwrap()
  assert_eq(captured_effect_dependency_body_wire_usage(strict), None)
  let (tree, controls, text) = captured_effect_dependency_body_representation_extent(
    strict, 1000, 32, 10000,
  ).unwrap()
  let (same_tree, measured_controls, same_text) = captured_effect_dependency_body_representation_extent(
    measured, 1000, 32, 10000,
  ).unwrap()
  assert_eq(tree.nodes, nodes.to_int64())
  assert_eq(same_tree.nodes, tree.nodes)
  assert_eq(same_text, text)
  assert_eq(
    (
      measured_controls.record_headers - controls.record_headers,
      measured_controls.reference_slots - controls.reference_slots,
      measured_controls.scalar_words - controls.scalar_words,
    ),
    (2L, 1L, 4L),
  )
  assert_true(
    controls.reference_slots >=
    strict.node.references.capacity().to_int64() + 11L,
  )
  assert_eq(strict.wire, original.wire)
  assert_eq(strict.node.identity, original.identity)
  assert_true(
    captured_effect_dependency_body_representation_extent(strict, 1, 32, 10000)
    is Err(Encoding),
  )
  assert_true(
    captured_effect_dependency_body_representation_extent(strict, 1000, 32, 1)
    is Err(Encoding),
  )
}

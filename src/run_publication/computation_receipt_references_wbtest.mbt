///|
test "fresh and retained receipt root laws preserve the original typed mismatches" {
  let receipt = @json.from_source(
    @source.parse_json(
      "{\"invocation_cid\":\"sha256:" + "a".repeat(64) + "\"}",
      { max_input_bytes: 1024, max_nodes: 16, max_depth: 4, },
    ).unwrap(),
    16,
    4,
    1024,
  )
  check_receipt_invocation_reference(receipt, "sha256:" + "a".repeat(64)).unwrap()
  assert_eq(
    check_receipt_invocation_reference(receipt, "sha256:" + "b".repeat(64)),
    Err(EvidenceReferenceMismatch("invocation_cid")),
  )
  // Existing field meanings and failure order stay with the computation
  // validator. The retained projection reuses them; it is not another table.
  let roots = commit_cursor_fixture(["answer"]).reference_inputs
  let definition = roots.run_definition
  assert_eq(
    check_receipt_compiled_plan_reference(receipt, definition),
    Err(EvidenceReferenceMismatch("compiled_plan_cid")),
  )
  let manifest = roots.manifest
  assert_eq(
    check_receipt_manifest_reference(receipt, manifest),
    Err(EvidenceReferenceMismatch("result_manifest_cid")),
  )
}

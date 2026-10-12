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

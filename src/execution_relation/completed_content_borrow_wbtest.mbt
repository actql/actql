///|
fn content_borrow_export_fixture(
  conditional : Bool,
  first_live : Ref[Bool],
  second_live : Ref[Bool],
) -> (CompletedRelationExportReceipt, Array[@admitted.Value]) raise {
  let (source, originals, _) = reference_export_fixture(
    conditional, first_live, second_live,
  )
  let stream = prepare_completed_relation_export(
    source,
    4,
    stream_value_limits(),
    row_wire_limits(),
    row_wire_limits(),
    publication_schema_limits(),
    4096,
  ).unwrap()
  while next_completed_output_export(stream).unwrap() is Some(_) {
    ()
  }
  let (receipt, _) = finish_completed_relation_export(stream).unwrap()
  (receipt, originals)
}

///|
test "Content export borrow preserves each original issuer despite equal wire" {
  let (receipt, originals) = content_borrow_export_fixture(
    false,
    Ref(true),
    Ref(true),
  )
  let first = completed_relation_export_content_reference(receipt, 0, 1).unwrap()
  let second = completed_relation_export_content_reference(receipt, 3, 1).unwrap()
  guard originals[0] is @admitted.Reference(original_first) &&
    originals[1] is @admitted.Reference(original_second) else {
    fail("original Content occurrences")
  }
  assert_true(physical_equal(first, original_first))
  assert_true(physical_equal(second, original_second))
  assert_eq(@admitted.reference_wire(first), @admitted.reference_wire(second))
  assert_false(@admitted.reference_same_issuer(first, second))
  assert_true(
    completed_relation_export_content_reference(receipt, 0, 0) is None,
  )
  assert_true(
    completed_relation_export_content_reference(receipt, 1, 1) is None,
  )
  assert_true(
    completed_relation_export_content_reference(receipt, -1, 1) is None,
  )
  assert_true(
    completed_relation_export_content_reference(receipt, 4, 1) is None,
  )
  assert_true(
    completed_relation_export_content_reference(receipt, 0, -1) is None,
  )
  assert_true(
    completed_relation_export_content_reference(receipt, 0, 2) is None,
  )
}

///|
test "Content export borrow refuses absent revoked and retired originals" {
  let live = Ref(true)
  let (receipt, _) = content_borrow_export_fixture(true, live, Ref(true))
  assert_true(
    completed_relation_export_content_reference(receipt, 0, 1) is Some(_),
  )
  assert_true(
    completed_relation_export_content_reference(receipt, 2, 1) is None,
  )
  live.val = false
  assert_true(
    completed_relation_export_content_reference(receipt, 0, 1) is None,
  )
  assert_true(
    completed_relation_export_content_reference(receipt, 3, 1) is Some(_),
  )
  cancel_completed_relation_export_receipt(receipt)
  assert_true(
    completed_relation_export_content_reference(receipt, 3, 1) is None,
  )
}

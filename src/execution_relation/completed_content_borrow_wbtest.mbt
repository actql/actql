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
test "Content export borrow rechecks custody after original authorization callback" {
  let contract = select_checked_contract(
    "{\"type\":\"content_ref\",\"nullable\":false,\"media_type\":\"application/json\"}",
  )
  let seed = issued_content_value(contract, Ref(true))
  guard seed.value is @admitted.Reference(seed_reference) else {
    fail("Content reference fixture")
  }
  let wire = @admitted.reference_wire(seed_reference)
  let retained : Ref[CompletedRelationExportReceipt?] = Ref(None)
  let value = @admitted.issue_reference(
    @admitted.bind_reference_issuer((_, candidate) => candidate == wire, _ => {
      if retained.val is Some(receipt) {
        cancel_completed_relation_export_receipt(receipt)
      }
      true
    }),
    contract,
    wire,
    { max_bytes: 4096, max_nodes: 64, max_depth: 4, max_text_units: 4096, },
  ).unwrap()
  let id_contract = @contract.primitive(NumberType, nullable=false)
  let schema = @schema.from_fields(
    [
      (@schema.Unqualified("id"), id_contract),
      (@schema.Unqualified("content"), contract),
    ],
    max_fields=2,
    max_name_bytes=9,
  ).unwrap()
  let owner = presence_output_owner(schema~)
  let admitted = prepare_admitted_output(
    owner,
    Step(0),
    1,
    stream_value_limits(),
  ).unwrap()
  let id = @admitted.admit(id_contract, input_cursor("1"), {
    max_nodes: 1,
    max_depth: 0,
    max_text_bytes: 0,
  }).unwrap()
  append_admitted_output(admitted, [id, value]).unwrap()
  let rows = finish_admitted_output(admitted).unwrap()
  let preparation = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(owner),
    ["events_0"],
    10000,
    1000,
  ).unwrap()
  let source = complete_trusted_output(
    prepare_trusted_output_port(preparation, Step(0), 1000, 10000, (_ : Unit) => {
      Some(rows)
    }).unwrap(),
    (),
  ).unwrap()
  let (receipt, _) = export_relation_all(source)
  retained.val = Some(receipt)
  assert_true(
    completed_relation_export_content_reference(receipt, 0, 1) is None,
  )
  assert_true(receipt.rows.source is None)
  assert_true(receipt.rows.references.unwrap().revoked)
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

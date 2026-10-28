///|
test "Parameter default body inventories original nested builders and Decimal backing" {
  let parameter = @contract.read_parameter_syntax(
      json_steps_cursor(
        "{\"type\":\"object\",\"fields\":{\"xs\":{\"type\":\"array\",\"items\":{\"type\":\"decimal\",\"precision\":8,\"scale\":2}},\"label\":{\"type\":\"string\"}}}",
      ),
      { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
    ).unwrap().parameter_type
  let source = json_steps_cursor(
    "{\"xs\":[\"-12.30\",\"0.00\"],\"label\":\"é\"}",
  )
  let geometry = @decode.observe_subtree_construction_geometry(source)
  assert_eq(
    (geometry.nodes, geometry.arrays, geometry.objects, geometry.fields),
    (5, 1, 1, 2),
  )
  let body = parameter_value_body_construction_inventory(parameter, geometry).unwrap()
  let values = @shape.collection_construction_extent(body.values).unwrap()
  assert_eq(
    (values.record_headers, values.reference_slots, values.scalar_words),
    (21L, 52L, 20L),
  )
  let traversal = @shape.collection_construction_extent(body.traversal).unwrap()
  assert_eq(
    (
      traversal.record_headers,
      traversal.reference_slots,
      traversal.scalar_words,
    ),
    (39L, 140L, 109L),
  )
  assert_eq(body.owned_value_utf16_units, 18L)
  assert_eq(body.owned_decimal_scratch_utf16_units, 20L)
  assert_eq(body.key_normalization, @canonical.nfc_lf_construction_extent(5))
  let original = start_typed_admission(parameter.contract, source, {
    max_nodes: 5,
    max_depth: 2,
    max_text_bytes: 19,
  }).unwrap()
  let mut peak_frames = 0
  let mut peak_children = 0
  let mut completed = None
  for _ in 0..<1000 {
    peak_frames = Int::max(peak_frames, original.frames.length())
    for frame in original.frames {
      match frame {
        TypedObjectInput(object, _)
        | TypedObjectFind(object, _, _, _, _, _)
        | TypedObjectNames(object, _)
        | TypedObjectNext(object, _, _) =>
          peak_children = Int::max(peak_children, object.children.length())
        _ => ()
      }
    }
    match advance_typed_admission(original) {
      TypedAdmissionContinue => ()
      TypedAdmissionComplete(value, nodes, text) => {
        assert_eq((nodes, text), (5, 19))
        completed = Some(value)
        break
      }
      _ => abort("the independent original Parameter default must admit")
    }
  }
  assert_true(peak_frames.to_int64() <= body.traversal.reference_items)
  assert_true(peak_children.to_int64() <= body.traversal.map_entries)
  let checked = completed.unwrap()
  assert_eq(
    typed_steps_wire(checked),
    "{\"label\":\"é\",\"xs\":[\"-12.30\",\"0.00\"]}",
  )
  assert_true(physical_equal(checked.contract, parameter.contract))
  cancel_typed_admission(original)
  assert_eq(
    typed_steps_wire(checked),
    "{\"label\":\"é\",\"xs\":[\"-12.30\",\"0.00\"]}",
  )
  assert_eq(@decode.object_length(source), Some(2))
}

///|
test "Parameter body quantities exclude siblings and preserve actual one-short refusal" {
  let whole = json_steps_cursor(
    "{\"default\":[1,2],\"meta\":{\"unrelated\":[0,0,0,0]}}",
  )
  let selected = @decode.field_at(whole, 0).unwrap().1
  let g = @decode.observe_subtree_construction_geometry(selected)
  let parameter = @contract.read_parameter_syntax(
      json_steps_cursor("{\"type\":\"array\",\"items\":{\"type\":\"number\"}}"),
      { max_nodes: 10, max_depth: 10, max_text_bytes: 100, },
    ).unwrap().parameter_type
  let body = parameter_value_body_construction_inventory(parameter, g).unwrap()
  assert_eq((g.nodes, body.traversal.map_entries), (3, 0L))
  assert_eq(
    (body.owned_value_utf16_units, body.owned_decimal_scratch_utf16_units),
    (0L, 0L),
  )
  assert_true(body.key_normalization is None)
  let original = start_typed_admission(parameter.contract, selected, {
    max_nodes: 2,
    max_depth: 1,
    max_text_bytes: 0,
  }).unwrap()
  assert_true(
    advance_typed_admission(original)
    is TypedAdmissionFailed(ValueIssue(BudgetExceeded, ..)),
  )
  assert_true(original.frames.is_empty() && original.root is None)
  assert_eq(@decode.array_length(selected), Some(2))
  assert_eq(@decode.object_length(whole), Some(2))
  assert_true(
    parameter_value_body_construction_inventory(parameter, { ..g, fields: 1, })
    is None,
  )
  assert_true(
    parameter_value_body_construction_inventory(parameter, {
      ..g,
      total_utf16: -1L,
    })
    is None,
  )
}

///|
test "String Parameter default borrows text without a hypothetical Decimal output" {
  let parameter = @contract.read_parameter_syntax(
      json_steps_cursor("{\"type\":\"string\"}"),
      { max_nodes: 10, max_depth: 10, max_text_bytes: 100, },
    ).unwrap().parameter_type
  let root = json_steps_cursor("\"" + "x".repeat(4096) + "\"")
  let body = parameter_value_body_construction_inventory(
    parameter,
    @decode.observe_subtree_construction_geometry(root),
  ).unwrap()
  let checked = admit(parameter.contract, root, {
    max_nodes: 1,
    max_depth: 0,
    max_text_bytes: 4096,
  }).unwrap()
  guard checked.value is Text(text) else { abort("String default") }
  assert_eq(text.length(), 4096)
  // The actual scalar owner returns the original Text, not a Decimal copy.
  assert_eq(body.owned_value_utf16_units, 0L)
  assert_eq(body.owned_decimal_scratch_utf16_units, 0L)
}

///|
test "mixed original Decimal precision never prices a large borrowed String as digits" {
  let parameter = @contract.read_parameter_syntax(
      json_steps_cursor(
        "{\"type\":\"object\",\"fields\":{\"text\":{\"type\":\"string\"},\"amount\":{\"type\":\"decimal\",\"precision\":4,\"scale\":2}}}",
      ),
      { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
    ).unwrap().parameter_type
  let root = json_steps_cursor(
    "{\"text\":\"" + "x".repeat(4096) + "\",\"amount\":\"12.34\"}",
  )
  let body = parameter_value_body_construction_inventory(
    parameter,
    @decode.observe_subtree_construction_geometry(root),
  ).unwrap()
  // Two source Text leaves co-count the original four-digit alternative:
  // each <=P+1 coefficient slots, one scratch builder <=3P+2. No raw Text
  // length, duplicate precision ceiling or policy maximum selects these sizes.
  assert_eq(body.owned_value_utf16_units, 10L)
  assert_eq(body.owned_decimal_scratch_utf16_units, 14L)
  let checked = admit(parameter.contract, root, {
    max_nodes: 3,
    max_depth: 1,
    max_text_bytes: 4111,
  }).unwrap()
  guard checked.value is Object(fields) else { abort("mixed Object default") }
  guard element_at(fields, 0) is Some(("amount", Decimal(amount))) else {
    abort("Decimal default")
  }
  assert_eq(amount.coefficient, "1234")
  guard element_at(fields, 1) is Some(("text", Text(text))) else {
    abort("borrowed String default")
  }
  assert_eq(text.length(), 4096)
}

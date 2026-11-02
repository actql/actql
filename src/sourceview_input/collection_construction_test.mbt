///|
test "collection construction selects only original names for NFC backing" {
  let prefix =
    #|{"connector":"é","resource":"r","view":"v","request":{"data":"
  let suffix =
    #|"},"meta":{"opaque":"business"}}
  let small = owner(prefix + "x" + suffix)
  let large = owner(prefix + "x".repeat(10000) + suffix)
  let g = observe_collect_construction_geometry(small, caps())
  let other = observe_collect_construction_geometry(large, caps())
  assert_eq(g, other)
  assert_eq((g.stages, g.inputs, g.remotes), (1, 2, 1))
  assert_eq(
    (g.normalization_calls, g.normalization_utf16, g.max_normalization_utf16),
    (3, 4L, 2),
  )
  assert_eq((g.max_request_fields, g.max_meta_fields), (1, 1))
  assert_eq(g.max_path_segments, 9L)
  assert_true(g.inspection_work <= collect_construction_inspection_bound(small))
  let q = collect_construction_inventory(g, caps()).unwrap()
  assert_eq(q, collect_construction_inventory(other, caps()).unwrap())
  // One returned Inputs/Ok, one declaration/key/Cursor/optional family,
  // three normalized Strings, one entries Array and one one-entry Map.
  assert_eq(q.returned, {
    record_headers: 28L,
    reference_slots: 67L,
    scalar_words: 48L,
  })
  // Three returned normalized names contain 4 input UTF16 units in total;
  // the pinned canonical decomposition bounds the returned backing by 4 * 4.
  assert_eq(q.returned_utf16_units, 16L)
  let inputs = collect(large, caps()).unwrap()
  assert_true(physical_equal(source(inputs), large))
  assert_eq(at(inputs, 0).unwrap().connector, "é")
}

///|
test "collection construction retains actual wide policy and order refusal paths" {
  let wide = owner(
    (
      #|{"connector":"c","resource":"r","duplicates":{"k0":0,"k1":0,"k2":0,"k3":0,"k4":0,"k5":0,"k6":0,"k7":0,"k8":0}}
    ),
  )
  let g = observe_collect_construction_geometry(wide, caps())
  assert_eq(g.max_duplicates_fields, 9)
  assert_true(g.inspection_work <= collect_construction_inspection_bound(wide))
  assert_true(collect_construction_inventory(g, caps()) is Some(_))
  guard collect(wide, caps()) is Err(Decode(issue)) else {
    abort("original closed duplicate policy must refuse")
  }
  assert_eq(issue.kind, @decode.UnknownField)
  assert_eq(issue.path.length(), 6)
  let order = owner(
    (
      #|{"connector":"c","resource":"r","duplicates":{"first_by_order":{"order_by":[{"field":"id","dir":"asc","nulls":"last","k0":0,"k1":0,"k2":0,"k3":0,"k4":0,"k5":0}]}}}
    ),
  )
  let g = observe_collect_construction_geometry(order, caps())
  assert_eq((g.order_owners, g.order_terms, g.max_order_fields), (1, 1, 9))
  assert_true(g.inspection_work <= collect_construction_inspection_bound(order))
  guard collect(order, caps()) is Err(Order(issue)) &&
    issue.diagnostic is Some(diagnostic) else {
    abort("original long order shape must refuse")
  }
  assert_eq(diagnostic.kind, @decode.UnknownField)
  assert_eq(diagnostic.path.length(), 9)
  let full = collect_construction_inventory(g, caps()).unwrap()
  let none = collect_construction_inventory(g, { ..caps(), max_order_keys: 0, }).unwrap()
  assert_true(full.temporary.record_headers > none.temporary.record_headers)
  assert_true(
    collect(order, { ..caps(), max_order_keys: 0, }) is Err(OrderLimit),
  )
}

///|
test "collection construction bounds pending backing by actual charged prefix" {
  let small = owner(
    (
      #|{"connector":"c","resource":"r","request":{"data":[null]}}
    ),
  )
  let large = owner(
    "{\"connector\":\"c\",\"resource\":\"r\",\"request\":{\"data\":[" +
    "null,".repeat(500) +
    "null]}}",
  )
  let g = observe_collect_construction_geometry(small, caps())
  let bigger = observe_collect_construction_geometry(large, caps())
  assert_eq(bigger.max_remote_nodes - g.max_remote_nodes, 500)
  assert_true(
    bigger.inspection_work <= collect_construction_inspection_bound(large),
  )
  let full = collect_construction_inventory(bigger, caps()).unwrap()
  let narrow = collect_construction_inventory(g, caps()).unwrap()
  // Original pending/pop references and growth backing survive the traversal,
  // even though its final logical length is zero. Original tree stays borrowed.
  assert_true(full.temporary.reference_slots > narrow.temporary.reference_slots)
  let short : Limits = { max_work: 1, max_order_keys: 0, }
  assert_eq(
    collect_construction_inventory(g, short),
    collect_construction_inventory(bigger, short),
  )
  let (result, spent) = observe_collect(large, short)
  assert_true(result is Err(WorkLimit))
  assert_eq(spent, 1)
}

///|
test "collection construction rejects invalid quantity without changing original limits" {
  let original = owner("{\"connector\":\"c\",\"resource\":\"r\"}")
  let g = observe_collect_construction_geometry(original, caps())
  assert_true(
    collect_construction_inventory({ ..g, normalization_utf16: -1L, }, caps())
    is None,
  )
  assert_true(
    collect_construction_inventory(
      { ..g, max_path_segments: 9223372036854775807L, },
      caps(),
    )
    is None,
  )
  let invalid : Limits = { max_work: -1, max_order_keys: 0, }
  let g = observe_collect_construction_geometry(original, invalid)
  assert_eq((g.stages, g.inputs, g.inspection_work), (0, 0, 0L))
  let q = collect_construction_inventory(g, invalid).unwrap()
  assert_eq(q.returned, {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
  })
  assert_eq((q.returned_utf16_units, q.temporary_utf16_units), (0L, 0L))
}

///|
test "collection construction retains original cross-stage orders and declaration aliases" {
  let first =
    #|{"connector":"c","resource":"r","view":"v","duplicates":{"first_by_order":{"order_by":[{"field":"id","dir":"asc","nulls":"first"},{"other":"desc"}]}}}
  let second =
    #|,{"id":"b","inputs":{"remote":{"connector":"q","resource":"p","duplicates":{"first_by_order":{"order_by":[{"code":"asc"}]}}}},"steps":[],"results":{"r":{}}}
  let original = owner(first, second~)
  let g = observe_collect_construction_geometry(original, caps())
  assert_eq((g.stages, g.inputs, g.remotes), (2, 3, 2))
  assert_eq((g.order_owners, g.order_terms, g.max_order_fields), (2, 3, 3))
  assert_true(
    g.inspection_work <= collect_construction_inspection_bound(original),
  )
  let q = collect_construction_inventory(g, caps()).unwrap()
  // Two original declarations/index keys, five returned names, three Keys
  // with original term/field Cursors, entries plus two order arrays, one Map.
  assert_eq(q.returned, {
    record_headers: 58L,
    reference_slots: 155L,
    scalar_words: 93L,
  })
  let inputs = collect(original, caps()).unwrap()
  let a = input_for(inputs, 0, "remote").unwrap()
  let b = input_for(inputs, 1, "remote").unwrap()
  assert_false(physical_equal(a, b))
  assert_true(physical_equal(a, at(inputs, 0).unwrap()))
  let keys = first_by_order(a).unwrap()
  assert_eq(
    (keys[0].field, keys[0].explicit_nulls, keys[0].work),
    ("id", true, 4),
  )
  assert_eq(@decode.text(keys[0].field_source), Ok("id"))
  assert_eq(
    (keys[1].field, keys[1].explicit_nulls, keys[1].work),
    ("other", false, 2),
  )
  keys.clear()
  assert_eq(first_by_order(a).unwrap().length(), 2)
  assert_eq(first_by_order(b).unwrap()[0].field, "code")
}

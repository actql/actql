///|
test "original index observation reports exact authored work and name bytes on typed failure" {
  let original = parsed_source()
  let (result, measured) = observe_prepare(original, caps())
  let index = result.unwrap()
  // Stages2, inputs3+4, imports2, nonimport connector fields2 =13.
  // Stage names7 + input names37 + import names13 + connector keys17 =74.
  assert_eq(measured, { work: 13, text_bytes: 74, })
  assert_eq(index_usage(index), measured)
  assert_true(physical_equal(@stage_source_refs.source(index), original))
  for
    (maximum, expected_work, expected_text) in [
      (0, 0, 0),
      (1, 0, 0),
      (2, 2, 3),
      (3, 2, 3),
      (4, 2, 3),
      (11, 11, 42),
      (12, 11, 42),
    ] {
    let (result, used) = observe_prepare(original, {
      ..caps(),
      max_work: maximum,
    })
    assert_true(result is Err(BudgetExceeded))
    assert_eq(used, { work: expected_work, text_bytes: expected_text, })
  }
  for
    (maximum, expected_work, expected_text) in [(0, 2, 0), (2, 2, 0), (3, 5, 3)] {
    let (result, used) = observe_prepare(original, {
      ..caps(),
      max_text_bytes: maximum,
    })
    assert_true(result is Err(BudgetExceeded))
    assert_eq(used, { work: expected_work, text_bytes: expected_text, })
  }
  let (result, invalid) = observe_prepare(original, { ..caps(), max_work: -1, })
  assert_true(result is Err(InvalidLimits))
  assert_eq(invalid, { work: 0, text_bytes: 0, })
  assert_eq(index_preparation_observation_control_extent(), {
    record_headers: 4L,
    reference_slots: 4L,
    scalar_words: 3L,
  })
}

///|
test "index geometry quotes original maps under the same minimum prefix" {
  let original = parsed_source()
  let geometry = observe_index_construction_geometry(original, caps())
  assert_eq(
    (
      geometry.stages,
      geometry.object_views,
      geometry.slot_maps,
      geometry.import_maps,
    ),
    (2, 2, 2, 2),
  )
  assert_eq(
    (geometry.slots, geometry.imports, geometry.max_stage_fields),
    (7L, 2L, 5),
  )
  assert_true(
    geometry.inspection_work > 0L &&
    geometry.inspection_work <=
    index_construction_inspection_bound(original, caps()),
  )
  assert_eq(@syntax.stage_closed_field_count(), 9)
  let full = index_construction_inventory(geometry, caps()).unwrap()
  assert_true(
    full.returned.record_headers > 0L && full.temporary.record_headers > 0L,
  )
  let short : Limits = { ..caps(), max_work: 1, }
  let geometry = observe_index_construction_geometry(original, short)
  assert_eq(
    (geometry.stages, geometry.object_views, geometry.slot_maps),
    (2, 0, 0),
  )
  assert_eq(geometry.inspection_work, 1L)
  let quote = index_construction_inventory(geometry, short).unwrap()
  assert_eq(quote.returned, {
    record_headers: 2L,
    reference_slots: 1L,
    scalar_words: 2L,
  })
  assert_eq(quote.temporary, {
    record_headers: 9L,
    reference_slots: 18L,
    scalar_words: 24L,
  })
  assert_true(prepare(original, short) is Err(BudgetExceeded))
  // The root ObjectView precedes input-count failure; the import Map precedes
  // import-count failure. Later field costs are conservatively omitted.
  let before_inputs = observe_index_construction_geometry(original, {
    ..caps(),
    max_work: 2,
  })
  assert_eq(
    (
      before_inputs.object_views,
      before_inputs.import_maps,
      before_inputs.slot_maps,
    ),
    (1, 0, 0),
  )
  let before_imports = observe_index_construction_geometry(original, {
    ..caps(),
    max_work: 10,
  })
  assert_eq(
    (
      before_imports.object_views,
      before_imports.import_maps,
      before_imports.slot_maps,
    ),
    (2, 2, 1),
  )
  assert_true(
    index_construction_inventory({ ..geometry, slots: -1L, }, caps()) is None,
  )
}

///|
fn opaque_index_source(size : Int) -> @stages.Source {
  let program = @syntax.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"s\",\"inputs\":{\"rows\":{\"carrier\":\"relation\",\"meta\":{\"opaque\":\"" +
    "x".repeat(size) +
    "\"}},\"other\":\"relation\"},\"steps\":[],\"results\":{\"out\":{}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"s\",\"result\":\"out\"}}}}",
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
  @stages.prepare(program, {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
}

///|
test "index geometry ignores opaque nested input text without NFC or data copies" {
  let small = opaque_index_source(1)
  let large = opaque_index_source(5000)
  let g = observe_index_construction_geometry(small, caps())
  let larger = observe_index_construction_geometry(large, caps())
  assert_eq(g, larger)
  assert_true(
    g.inspection_work <= index_construction_inspection_bound(large, caps()),
  )
  let quote = index_construction_inventory(g, caps()).unwrap()
  assert_eq(quote, index_construction_inventory(larger, caps()).unwrap())
  assert_eq(quote.returned, {
    record_headers: 37L,
    reference_slots: 81L,
    scalar_words: 92L,
  })
  assert_eq(quote.temporary, {
    record_headers: 64L,
    reference_slots: 109L,
    scalar_words: 129L,
  })
  let (_, used) = observe_prepare(large, caps())
  assert_eq(used, { work: 5, text_bytes: 21, })
  assert_eq(index_construction_inspection_extent(), {
    record_headers: 11L,
    reference_slots: 8L,
    scalar_words: 19L,
  })
}

///|
test "index container inventory includes each retained original input Cursor" {
  let original = opaque_index_source(1)
  let index = prepare(original, caps()).unwrap()
  let selected = resolve(
    index,
    [selector("s", "rows"), selector("s", "other")],
    caps(),
  ).unwrap()
  let first = declaration(entry_at(selected, 0).unwrap())
  let second = declaration(entry_at(selected, 1).unwrap())
  // resolve/declaration forwards each original Slot cursor without copying.
  // Distinct original positions require two retained Cursor records, even
  // though both borrow the SAME admitted tree/usage and all original text.
  assert_false(physical_equal(first, second))
  assert_true(
    @decode.tree_index(first, second) != @decode.tree_index(first, first),
  )
  let geometry = observe_index_construction_geometry(original, caps())
  assert_eq(geometry.slots, 2L)
  let quoted = index_construction_inventory(geometry, caps()).unwrap()
  // Add two original Cursor1H2R1W records to the independently authored
  //35H77R90W Map/Index/Slot/alternative container baseline.
  assert_eq(quoted.returned, {
    record_headers: 37L,
    reference_slots: 81L,
    scalar_words: 92L,
  })
}

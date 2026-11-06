///|
test "same bounded emission retains structural geometry without text or another visit" {
  let plain = measuring_writer(1000, 20, 5)
  measurement_fixture(plain)
  let expected = finish_measurement_usage(plain)
  let measured = construction_measuring_writer(1000, 20, 5)
  measurement_fixture(measured)
  let geometry = finish_construction_measurement(measured)
  assert_eq(construction_geometry_usage(geometry), expected)
  assert_eq((geometry.arrays, geometry.objects, geometry.fields), (1, 1, 1))
  let parent = construction_measuring_writer(3000, 50, 8)
  begin_array(parent)
  emit_construction_measurement(parent, geometry)
  emit_construction_measurement(parent, geometry)
  end_array(parent)
  let combined = finish_construction_measurement(parent)
  assert_eq(combined.arrays, 3)
  assert_eq(combined.objects, 2)
  assert_eq(combined.fields, 2)
  assert_eq(combined.nodes, expected.1 * 2 + 1)
  assert_eq(combined.depth, expected.2 + 1)
  let unknown = construction_measuring_writer(3000, 50, 8)
  begin_array(unknown)
  emit_measurement(unknown, expected)
  end_array(unknown)
  let conservative = finish_construction_measurement(unknown)
  assert_eq(conservative.arrays, 1 + expected.1)
  assert_eq(conservative.objects, expected.1)
  assert_eq(conservative.fields, expected.1 - 1)
}

///|
test "construction measurement preserves codec refusal and cannot issue text" {
  for cap in [1, 10, 1000] {
    let plain = try {
      let writer = measuring_writer(cap, 20, 5)
      measurement_fixture(writer)
      Some(finish_measurement_usage(writer))
    } catch {
      _ => None
    }
    let shape = try {
      let writer = construction_measuring_writer(cap, 20, 5)
      measurement_fixture(writer)
      Some(construction_geometry_usage(finish_construction_measurement(writer)))
    } catch {
      _ => None
    }
    assert_eq(plain, shape)
  }
  let writer = construction_measuring_writer(4, 1, 0)
  null_value(writer)
  try finish_document(writer) catch {
    InvalidStructure => ()
    _ => assert_true(false)
  } noraise {
    _ => assert_true(false)
  }
  try finish_construction_measurement(writer) catch {
    ClosedWriter => ()
    _ => assert_true(false)
  } noraise {
    _ => assert_true(false)
  }
}

///|
test "construction shape keeps original ordered width and decoded Unicode text across cursors" {
  let writer = construction_measuring_writer(1000, 20, 5)
  begin_ordered_object(writer)
  ordered_key(writer, "a")
  begin_array(writer)
  for name in ["雪", "😀"] {
    begin_object(writer)
    key(writer, name)
    string_value(writer, "e\u0301")
    end_object(writer)
  }
  end_array(writer)
  ordered_key(writer, "b")
  let cursor = start_prefixed_string_value(writer, "😀", "e\u0301")
  while !advance_string_value(cursor) {
    ()
  }
  end_object(writer)
  let shape = finish_construction_measurement(writer)
  assert_eq(shape.objects, 3)
  assert_eq(shape.fields, 4)
  assert_eq(shape.largest_object, 2)
  assert_eq(shape.strings, 3)
  assert_eq(shape.text_units, 2 + 1 + 2 + 2 * 2 + 4)
}

///|
test "construction DATA rejects negative String census and preserves composition byte overflow" {
  let exact : EncodingConstructionGeometry = {
    bytes: 1,
    nodes: 1,
    depth: 0,
    arrays: 0,
    objects: 0,
    fields: 0,
    largest_object: 0,
    strings: 0,
    text_units: 0,
  }
  for
    invalid in [
      { ..exact, strings: -1, },
      { ..exact, strings: 2, },
      { ..exact, text_units: -1, },
      { ..exact, text_units: 2, },
    ] {
    let writer = construction_measuring_writer(100, 100, 1)
    try emit_construction_measurement(writer, invalid) catch {
      InvalidStructure => ()
      _ => assert_true(false)
    } noraise {
      _ => assert_true(false)
    }
    try finish_construction_measurement(writer) catch {
      ClosedWriter => ()
      _ => assert_true(false)
    } noraise {
      _ => assert_true(false)
    }
  }
  let large = { ..exact, bytes: 2147483645, text_units: 2147483645, }
  let writer = construction_measuring_writer(2147483647, 4, 1)
  begin_array(writer)
  emit_construction_measurement(writer, large)
  try emit_construction_measurement(writer, large) catch {
    OutputLimit => ()
    _ => assert_true(false)
  } noraise {
    _ => assert_true(false)
  }
}

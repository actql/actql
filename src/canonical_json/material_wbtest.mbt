///|
fn material_test_drain(value : CanonicalMaterial) -> Unit raise {
  for _ in 0..<10000 {
    if advance_material(value) {
      return
    }
  }
  fail("Finite canonical material operation did not finish")
}

///|
test "canonical material retains exact immutable children and complete usage" {
  let original = from_json({ "k": [1, 2] }, 10, 3, 100)
  let value = start_material(100, 20, 4)
  material_begin_object(value)
  material_key(value, "a")
  material_test_drain(value)
  material_begin_array(value)
  material_value(value, original)
  material_test_drain(value)
  material_text(value, "e\u0301\r\n😀")
  material_test_drain(value)
  material_end_array(value)
  material_end_object(value)
  let (actual, usage) = finish_material(value)
  let expected = "{\"a\":[{\"k\":[1,2]},\"é\\r\\n😀\"]}"
  assert_eq(stringify_value(actual, 100, 20, 4), expected)
  let child = object_field(actual, "a").unwrap()
  guard child is Array(children) else { fail("Expected original array") }
  assert_true(physical_equal(array_at(children, 0).unwrap(), original))
  assert_eq(usage.0, @utf8.encode(expected).length())
  assert_eq(usage.1, 7)
  assert_eq(usage.2, 4)
  assert_true(value.closed && value.frames.is_empty() && value.value is None)
  assert_true(
    (try finish_material(value) catch {
      error => Err(error)
    } noraise {
      value => Ok(value)
    })
    is Err(_),
  )
}

///|
test "canonical material rejects order malformed text aggregate limits and partial output" {
  for key in ["a", "0", String::from_array([(0xd800).unsafe_to_char()])] {
    let value = start_material(100, 10, 3)
    material_begin_object(value)
    material_key(value, "a")
    material_test_drain(value)
    material_text(value, "first")
    material_test_drain(value)
    material_key(value, key)
    assert_true(
      (try material_test_drain(value) catch {
        error => Err(error)
      } noraise {
        value => Ok(value)
      })
      is Err(_),
    )
    assert_true(value.closed && value.frames.is_empty())
    assert_true(
      (try finish_material(value) catch {
        error => Err(error)
      } noraise {
        value => Ok(value)
      })
      is Err(_),
    )
  }
  let original = from_json([1, 2], 3, 1, 100)
  for (bytes, nodes, depth) in [(6, 4, 2), (7, 3, 2), (7, 4, 1)] {
    let value = start_material(bytes, nodes, depth)
    material_begin_array(value)
    material_value(value, original)
    let completed = try {
      material_test_drain(value)
      material_end_array(value)
      finish_material(value)
    } catch {
      error => Err(error)
    } noraise {
      value => Ok(value)
    }
    assert_true(completed is Err(_))
    assert_true(value.closed && value.frames.is_empty())
  }
  let exact = start_material(7, 4, 2)
  material_begin_array(exact)
  material_value(exact, original)
  material_test_drain(exact)
  material_end_array(exact)
  assert_eq(finish_material(exact).1, (7, 4, 2))
  let partial = start_material(1000, 10, 3)
  material_begin_object(partial)
  material_key(partial, String::make(257, 'a'))
  assert_false(advance_material(partial))
  cancel_material(partial)
  cancel_material(partial)
  assert_true(partial.closed && partial.frames.is_empty())
  assert_true(
    (try advance_material(partial) catch {
      error => Err(error)
    } noraise {
      value => Ok(value)
    })
    is Err(_),
  )
  assert_true(
    (try finish_material(partial) catch {
      error => Err(error)
    } noraise {
      value => Ok(value)
    })
    is Err(_),
  )
}

///|
test "canonical material cancellation retires pending children without changing originals" {
  let original = from_json([String::make(257, 'é')], 2, 1, 1000)
  let original_wire = stringify_value(original, 1000, 2, 1)
  for kind in 0..<3 {
    let value = start_material(2000, 10, 3)
    if kind == 0 {
      material_begin_object(value)
      material_key(value, String::make(257, 'a'))
    } else {
      material_begin_array(value)
      if kind == 1 {
        material_text(value, String::make(257, 'é'))
      } else {
        material_value(value, original)
      }
    }
    assert_false(advance_material(value))
    cancel_material(value)
    assert_true(value.closed && value.frames.is_empty() && value.value is None)
    assert_true(value.pending is MaterialIdle)
    assert_eq(stringify_value(original, 1000, 2, 1), original_wire)
    try finish_material(value) catch {
      @encode.ClosedWriter => ()
      _ => fail("Expected terminal material")
    } noraise {
      _ => fail("Cancelled material exposed a value")
    }
  }
}

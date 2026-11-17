///|
fn work_geometry_fixture(
  writer : Writer,
  text : String,
) -> Unit raise EncodeFailure {
  construction_work_step(writer, 1)
  begin_object(writer)
  key(writer, "a")
  string_value(writer, text)
  key(writer, "b")
  begin_array(writer)
  construction_work_step(writer, 1)
  number_value(writer, 7.0)
  end_array(writer)
  end_object(writer)
}

///|
test "controlled geometry uses bulk observed spans and preserves the same canonical geometry" {
  let text = "a".repeat(100000) + "😀"
  let original = construction_measuring_writer(200000, 20, 5)
  work_geometry_fixture(original, text)
  let expected = finish_construction_measurement(original)
  let calls = Ref(0)
  let spent = Ref(0)
  let writer = work_construction_measuring_writer(200000, 20, 5, units => {
    calls.val += 1
    spent.val += units
    true
  })
  work_geometry_fixture(writer, text)
  assert_eq(finish_construction_measurement(writer), expected)
  assert_true(spent.val >= text.length())
  assert_true(calls.val < 32, msg="no per-character work/current callback")
}

///|
test "controlled geometry verifies existing canonical order without a field-sized key map" {
  let writer = work_construction_measuring_writer(1000, 20, 5, _ => true)
  begin_object(writer)
  key(writer, "z")
  null_value(writer)
  try {
    key(writer, "a")
    assert_true(
      false,
      msg="out-of-order dependency emitter must not be trusted",
    )
  } catch {
    InvalidStructure => ()
    _ =>
      assert_true(
        false,
        msg="canonical ordering refusal must retain its typed cause",
      )
  }
  let legacy = construction_measuring_writer(1000, 20, 5)
  begin_object(legacy)
  key(legacy, "z")
  null_value(legacy)
  key(legacy, "a")
  null_value(legacy)
  end_object(legacy)
  assert_eq(finish_construction_measurement(legacy).fields, 2)
}

///|
test "declined or expired controlled work closes the writer before further traversal" {
  let live = Ref(true)
  let writer = work_construction_measuring_writer(1000, 20, 5, _ => live.val)
  begin_array(writer)
  live.val = false
  try {
    string_value(writer, "unvisited")
    assert_true(
      false,
      msg="expired work view must not permit another String walk",
    )
  } catch {
    OutputLimit => ()
    _ =>
      assert_true(false, msg="work refusal must close before another emission")
  }
  assert_true(writer.closed)
  try {
    finish_construction_measurement(writer) |> ignore
    assert_true(false, msg="partial geometry must remain unavailable")
  } catch {
    ClosedWriter => ()
    _ => assert_true(false, msg="failed controlled writer must remain closed")
  }
}

///|
test "prepaid String and ordered-key cursors cannot scan after work view expiry" {
  for key_cursor in [false, true] {
    let live = Ref(true)
    let writer = work_construction_measuring_writer(1000, 20, 5, _ => live.val)
    if key_cursor {
      begin_ordered_object(writer)
      let cursor = start_ordered_key(writer, "unvisited")
      let position = cursor.position
      live.val = false
      try {
        advance_ordered_key(cursor) |> ignore
        assert_true(false, msg="expired ordered-key cursor must not scan")
      } catch {
        OutputLimit => ()
        _ =>
          assert_true(false, msg="expired key view must refuse before scanning")
      }
      assert_eq(cursor.position, position)
    } else {
      begin_array(writer)
      let cursor = start_string_value(writer, "unvisited")
      let position = cursor.position
      live.val = false
      try {
        advance_string_value(cursor) |> ignore
        assert_true(false, msg="expired String cursor must not scan")
      } catch {
        OutputLimit => ()
        _ =>
          assert_true(
            false,
            msg="expired String view must refuse before scanning",
          )
      }
      assert_eq(cursor.position, position)
    }
    assert_true(writer.closed)
  }
}

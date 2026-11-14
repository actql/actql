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
    fail("out-of-order dependency emitter must not be trusted")
  } catch {
    InvalidStructure => ()
    _ => fail("canonical ordering refusal must retain its typed cause")
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
    fail("expired work view must not permit another String walk")
  } catch {
    OutputLimit => ()
    _ => fail("work refusal must close before another emission")
  }
  assert_true(writer.closed)
  try {
    finish_construction_measurement(writer) |> ignore
    fail("partial geometry must remain unavailable")
  } catch {
    ClosedWriter => ()
    _ => fail("failed controlled writer must remain closed")
  }
}

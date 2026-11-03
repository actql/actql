///|
test "buffered writer inventory follows original drained progress not configured ceilings" {
  let initial = buffered_writer_start_construction_inventory()
  let small = buffered_writer(1000, 10, 3, 1000)
  let large = buffered_writer(1000000, 10000, 100, 1000000)
  assert_eq(buffered_writer_next_construction_inventory(small, 1, 0), buffered_writer_next_construction_inventory(large, 1, 0))
  assert_true(initial.owned_utf16_units < buffered_writer_next_construction_inventory(small, 100, 0).unwrap().owned_utf16_units)
  assert_true(buffered_writer_next_construction_inventory(small, -1, 0) is None)
  begin_object(small)
  assert_true(buffered_writer_next_construction_inventory(small, 10, 0) is None)
  assert_eq(drain_buffered_output(small), "{")
  let step = buffered_writer_next_construction_inventory(small, 12, 0).unwrap()
  assert_true(step.record_headers > initial.record_headers)
  key(small, "x")
  assert_eq(drain_buffered_output(small), "\"x\":")
  null_value(small)
  assert_eq(drain_buffered_output(small), "null")
  end_object(small)
  assert_eq(drain_buffered_output(small), "}")
  assert_eq(finish_buffered_usage(small), (10, 2, 1))
  assert_true(buffered_writer_next_construction_inventory(small, 0, 0) is None)
  cancel_writer(large)
  assert_true(buffered_writer_next_construction_inventory(large, 0, 0) is None)
}

///|
test "buffered writer refusal closes the exact provisional sink" {
  let writer = buffered_writer(10, 2, 1, 3)
  assert_true(buffered_writer_next_construction_inventory(writer, 4, 0) is None)
  try string_value(writer, "four") catch {
    OutputLimit => ()
    issue => raise issue
  } noraise { _ => assert_true(false) }
  assert_true(writer.closed)
  cancel_writer(writer)
  assert_true(buffered_writer_next_construction_inventory(writer, 0, 0) is None)
}

///|
test "buffered writer can conservatively retain prior fragment peak after transfer" {
  let writer = buffered_writer(10000, 10, 3, 10000)
  begin_object(writer)
  drain_buffered_output(writer) |> ignore
  key(writer, "x".repeat(512))
  let original = drain_buffered_output(writer)
  let short = buffered_writer_next_construction_inventory(writer, 4, original.length()).unwrap()
  let detached = buffered_writer_next_construction_inventory(writer, 4, 0).unwrap()
  assert_true(short.owned_utf16_units > detached.owned_utf16_units)
  assert_true(short.owned_utf16_units >= 3L * original.length().to_int64())
  cancel_writer(writer)
}

///|
test "buffered dense fragments replace long-name builder with constant empty constructor" {
  let writer = buffered_writer(20000, 100, 3, 20000)
  begin_object(writer)
  drain_buffered_output(writer) |> ignore
  key(writer, "n".repeat(4096))
  guard writer.output is BufferedTextOutput(buffer) else { assert_true(false); return }
  let named = buffer.text
  let name = drain_buffered_output(writer)
  assert_false(physical_equal(named, buffer.text))
  assert_true(buffer.text.is_empty())
  begin_array(writer)
  drain_buffered_output(writer) |> ignore
  let mut replacements = 0
  for index in 0..<64 {
    let original = buffer.text
    number_value(writer, index.to_double())
    let fragment = drain_buffered_output(writer)
    assert_false(fragment.is_empty())
    assert_false(physical_equal(original, buffer.text))
    assert_true(buffer.text.is_empty())
    replacements += 1
  }
  assert_eq(replacements, 64)
  assert_eq(name, "\"" + "n".repeat(4096) + "\":")
  end_array(writer)
  drain_buffered_output(writer) |> ignore
  end_object(writer)
  drain_buffered_output(writer) |> ignore
  finish_buffered_usage(writer) |> ignore
}

///|
test "writer deep then shallow retires native frame payloads but quotes peak backing" {
  let writer = buffered_writer(10000, 100, 50, 10000)
  for _ in 0..<40 { begin_array(writer); drain_buffered_output(writer) |> ignore }
  null_value(writer)
  drain_buffered_output(writer) |> ignore
  for _ in 0..<39 {
    let index = writer.frames.length() - 1
    end_array(writer)
    drain_buffered_output(writer) |> ignore
    if writer.frames.capacity() > index {
      assert_true(writer.frames.unsafe_get(index) is RetiredFrame)
    }
  }
  assert_eq(writer.frames.length(), 1)
  let inventory = buffered_writer_next_construction_inventory(writer, 1, 0).unwrap()
  let expected = buffered_writer_construction_inventory(1, 0, 42, 40).unwrap()
  assert_true(inventory.reference_slots >= expected.reference_slots)
  cancel_writer(writer)
  assert_eq(writer.frames.length(), 0)
}

///|
test "next writer inventories follow actual emission rather than policy ceilings" {
  let small = writer(128, 32, 4)
  let large = writer(16777216, 1048576, 1024)
  let initial = text_writer_next_construction_inventory(small, 8, 1, 1).unwrap()
  assert_eq(
    initial,
    text_writer_next_construction_inventory(large, 8, 1, 1).unwrap(),
  )
  let small_hash = hashing_writer(128, 32, 4)
  let large_hash = hashing_writer(16777216, 1048576, 1024)
  assert_eq(
    hash_writer_next_construction_inventory(small_hash, 1, 1),
    hash_writer_next_construction_inventory(large_hash, 1, 1),
  )
  for output in [small, large, small_hash, large_hash] {
    begin_ordered_object(output)
    ordered_key(output, "name")
    string_value(output, "actual")
  }
  let next = text_writer_next_construction_inventory(small, 8, 1, 0).unwrap()
  assert_eq(
    next,
    text_writer_next_construction_inventory(large, 8, 1, 0).unwrap(),
  )
  assert_true(next.owned_utf16_units > initial.owned_utf16_units)
  assert_eq(
    hash_writer_next_construction_inventory(small_hash, 1, 0),
    hash_writer_next_construction_inventory(large_hash, 1, 0),
  )
  // The observation neither emits nor changes the original policy/usage.
  assert_eq(observed_writer_usage(small), (16, 2, 1))
  assert_eq(observed_writer_usage(large), (16, 2, 1))
  for output in [small, large, small_hash, large_hash] {
    end_object(output)
  }
  assert_eq(finish(small), "{\"name\":\"actual\"}")
  assert_eq(finish(large), "{\"name\":\"actual\"}")
  assert_eq(finish_hash(small_hash), finish_hash(large_hash))
}

///|
test "next writer inventories retain prior depth and refuse closed foreign sink or invalid demand" {
  let output = writer(32, 10, 4)
  begin_array(output)
  begin_array(output)
  end_array(output)
  end_array(output)
  let next = text_writer_next_construction_inventory(output, 0, 0, 0).unwrap()
  assert_eq(next, text_writer_construction_inventory(4, 1, 2).unwrap())
  let hash = hashing_writer(32, 10, 4)
  assert_true(text_writer_next_construction_inventory(hash, 1, 1, 1) is None)
  assert_true(hash_writer_next_construction_inventory(output, 1, 1) is None)
  for (bytes, nodes, depth) in [(-1, 1, 1), (1, -1, 1), (1, 1, -1)] {
    assert_true(
      text_writer_next_construction_inventory(output, bytes, nodes, depth)
      is None,
    )
  }
  assert_true(hash_writer_next_construction_inventory(hash, -1, 1) is None)
  assert_true(hash_writer_next_construction_inventory(hash, 1, -1) is None)
  finish(output) |> ignore
  null_value(hash)
  finish_hash(hash) |> ignore
  assert_true(text_writer_next_construction_inventory(output, 1, 1, 1) is None)
  assert_true(hash_writer_next_construction_inventory(hash, 1, 1) is None)
}

///|
test "buffered hash next inventory retains bounded actual Unicode fragments instead of output maximum" {
  let text = "😀\n".repeat(1000)
  let output = buffered_hashing_writer(16777216, 1048576, 1024, 512)
  let cursor = start_string_value(output, text)
  let mut peak = 0
  let mut done = false
  while !done {
    let quote = buffered_hash_writer_next_construction_inventory(
      output, 388, peak, 1, 1,
    ).unwrap()
    assert_true(quote.owned_utf16_units < 10000L)
    done = advance_string_value(cursor)
    let fragment = drain_hash_output(output)
    assert_true(fragment.length() <= 388)
    peak = Int::max(peak, fragment.length())
  }
  assert_true(peak > 0)
  assert_eq(observed_writer_usage(output), (6002, 1, 0))
  assert_eq(finish_hash(output).length(), 64)
  assert_true(
    buffered_hash_writer_next_construction_inventory(output, 388, peak, 1, 1)
    is None,
  )
}

///|
test "hash growth follows live keys rather than cumulative retired array elements" {
  let output = hashing_writer(16777216, 10000, 1024)
  begin_array(output)
  let first = hash_writer_next_construction_inventory(output, 1, 0).unwrap()
  for index in 0..<1000 {
    number_value(output, index.to_double())
  }
  assert_eq(
    hash_writer_next_construction_inventory(output, 1, 0).unwrap(),
    first,
  )
  assert_eq(observed_writer_usage(output).1, 1001)
  end_array(output)
  assert_eq(finish_hash(output).length(), 64)
}

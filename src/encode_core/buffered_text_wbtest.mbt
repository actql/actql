///|
test "bounded text sink preserves exact drained bytes and cumulative hash-sink limits" {
  for capacity in [9, 10, 64] {
    let text = buffered_writer(100, 10, 4, capacity)
    let hash = buffered_hashing_writer(100, 10, 4, capacity)
    let mut wire = ""
    for writer in [text, hash] {
      begin_array(writer)
    }
    assert_eq(drain_buffered_output(text), drain_hash_output(hash))
    wire += "["
    for writer in [text, hash] {
      string_value(writer, "é😀")
    }
    let part = drain_buffered_output(text)
    assert_eq(part, drain_hash_output(hash))
    assert_eq(part, "\"é😀\"")
    wire += part
    for writer in [text, hash] {
      null_value(writer)
      end_array(writer)
    }
    let part = drain_buffered_output(text)
    assert_eq(part, drain_hash_output(hash))
    wire += part
    assert_eq(wire, "[\"é😀\",null]")
    let (_, bytes, nodes, depth) = finish_hash_metrics(hash)
    assert_eq(finish_buffered_usage(text), (bytes, nodes, depth))
    assert_eq((bytes, nodes, depth), (15, 3, 1))
    assert_true(text.closed && hash.closed)
  }
}

///|
test "bounded text sink refuses incomplete undrained wrong sink and overflow after cancellation" {
  let undrained = buffered_writer(4, 1, 0, 4)
  null_value(undrained)
  let refused = try {
    ignore(finish_buffered_usage(undrained))
    false
  } catch {
    InvalidStructure => true
    _ => false
  }
  assert_true(refused && undrained.closed)
  let wrong = buffered_writer(4, 1, 0, 4)
  null_value(wrong)
  assert_eq(drain_buffered_output(wrong), "null")
  let refused = try {
    ignore(finish_hash(wrong))
    false
  } catch {
    InvalidStructure => true
    _ => false
  }
  assert_true(refused && wrong.closed)
  let short = buffered_writer(4, 1, 0, 3)
  let refused = try {
    null_value(short)
    false
  } catch {
    OutputLimit => true
    _ => false
  }
  assert_true(refused && short.closed)
  cancel_writer(short)
  cancel_writer(short)
  let refused = try {
    ignore(drain_buffered_output(short))
    false
  } catch {
    ClosedWriter => true
    _ => false
  }
  assert_true(refused)
  let incomplete = buffered_writer(10, 3, 1, 8)
  begin_array(incomplete)
  assert_eq(drain_buffered_output(incomplete), "[")
  let refused = try {
    ignore(finish_buffered_usage(incomplete))
    false
  } catch {
    InvalidStructure => true
    _ => false
  }
  assert_true(refused && incomplete.closed)
}

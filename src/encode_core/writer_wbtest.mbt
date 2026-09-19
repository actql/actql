///|
test "exact writer preserves text and emits a single structural document" {
  let w = writer(128, 10, 3)
  begin_object(w)
  key(w, "values")
  begin_array(w)
  string_value(w, "e\u0301\r\n😀\"\\")
  number_value(w, 1.0)
  bool_value(w, false)
  null_value(w)
  end_array(w)
  end_object(w)
  assert_eq(
    finish(w),
    "{\"values\":[\"e\u0301\\r\\n😀\\\"\\\\\",1,false,null]}",
  )
  let closed = try {
    ignore(finish(w))
    false
  } catch {
    ClosedWriter => true
    _ => false
  }
  assert_true(closed)
}

///|
test "text finalization reports usage from the same traversal" {
  let output = writer(100, 10, 4)
  begin_array(output)
  number_value(output, 1.0)
  begin_object(output)
  key(output, "x")
  string_value(output, "é")
  end_object(output)
  end_array(output)
  assert_eq(finish_text_usage(output), ("[1,{\"x\":\"é\"}]", 14, 4, 2))
}

///|
test "UTF8 and escaped bytes are bounded and failure poisons output" {
  for sample in [("😀", 6), ("é", 4), ("\n", 4), ("\u0001", 8), ("", 2)] {
    let (text, size) = sample
    let exact = writer(size, 1, 0)
    string_value(exact, text)
    ignore(finish(exact))
    let short = writer(size - 1, 1, 0)
    let failed = try {
      string_value(short, text)
      false
    } catch {
      OutputLimit => true
      _ => false
    }
    assert_true(failed)
    let closed = try {
      ignore(finish(short))
      false
    } catch {
      ClosedWriter => true
      _ => false
    }
    assert_true(closed)
  }
}

///|
test "structural misuse cannot expose partial JSON" {
  let missing = writer(100, 10, 2)
  begin_object(missing)
  key(missing, "a")
  let rejected = try {
    end_object(missing)
    false
  } catch {
    InvalidStructure => true
    _ => false
  }
  assert_true(rejected)
  let duplicate = writer(100, 10, 2)
  begin_object(duplicate)
  key(duplicate, "a")
  null_value(duplicate)
  let rejected = try {
    key(duplicate, "a")
    false
  } catch {
    InvalidStructure => true
    _ => false
  }
  assert_true(rejected)
  let incomplete = writer(100, 10, 2)
  begin_array(incomplete)
  let rejected = try {
    ignore(finish(incomplete))
    false
  } catch {
    InvalidStructure => true
    _ => false
  }
  assert_true(rejected)
  let second = writer(100, 10, 2)
  null_value(second)
  let rejected = try {
    null_value(second)
    false
  } catch {
    InvalidStructure => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "node depth and numeric validity apply before successful finish" {
  let nodes = writer(100, 1, 2)
  begin_array(nodes)
  let rejected = try {
    null_value(nodes)
    false
  } catch {
    OutputLimit => true
    _ => false
  }
  assert_true(rejected)
  let depth = writer(100, 10, 1)
  begin_array(depth)
  let rejected = try {
    begin_array(depth)
    false
  } catch {
    OutputLimit => true
    _ => false
  }
  assert_true(rejected)
  for value in [0.0 / 0.0, 1.0 / 0.0, -0.0] {
    let w = writer(100, 1, 0)
    let rejected = try {
      number_value(w, value)
      false
    } catch {
      InvalidNumber => true
      _ => false
    }
    assert_true(rejected)
  }
}

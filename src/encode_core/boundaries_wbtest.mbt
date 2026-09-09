///|
test "constructors reject invalid limits and zero output admits no value" {
  for measure in [false, true] {
    for limits in [(-1, 1, 0), (10, 0, 0), (10, -1, 0), (10, 1, -1)] {
      let (bytes, nodes, depth) = limits
      let rejected = try {
        ignore(
          if measure {
            measuring_writer(bytes, nodes, depth)
          } else {
            writer(bytes, nodes, depth)
          },
        )
        false
      } catch {
        OutputLimit => true
        _ => false
      }
      assert_true(rejected)
    }
    let zero = if measure { measuring_writer(0, 1, 0) } else { writer(0, 1, 0) }
    let rejected = try {
      null_value(zero)
      false
    } catch {
      OutputLimit => true
      _ => false
    }
    assert_true(rejected)
    assert_encoding_closed(zero)
  }
}

///|
test "structural failure closes every emission and finalization entry point" {
  let child = writer(4, 1, 0)
  null_value(child)
  let document = finish_document(child)
  let operations : Array[(Writer) -> Unit raise EncodeFailure] = [
    null_value,
    w => bool_value(w, true),
    w => number_value(w, 1.0),
    w => string_value(w, "x"),
    begin_array,
    begin_object,
    w => key(w, "x"),
    end_array,
    end_object,
    w => emit_json(Json::null(), w),
    w => emit_document(w, document),
    w => ignore(finish(w)),
    w => ignore(finish_document(w)),
    w => ignore(finish_measurement(w)),
  ]
  for measure in [false, true] {
    for operation in operations {
      let w = if measure {
        measuring_writer(100, 10, 2)
      } else {
        writer(100, 10, 2)
      }
      let rejected = try {
        end_array(w)
        false
      } catch {
        InvalidStructure => true
        _ => false
      }
      assert_true(rejected)
      let closed = try {
        operation(w)
        false
      } catch {
        ClosedWriter => true
        _ => false
      }
      assert_true(closed)
    }
  }
}

///|
test "malformed UTF16 rejects for keys and values and closes the writer" {
  let high = "😀".unsafe_substring(start=0, end=1)
  let low = "😀".unsafe_substring(start=1, end=2)
  for text in [high, low, high + "x", high + high, "x" + low] {
    for as_key in [false, true] {
      let w = writer(100, 10, 2)
      if as_key {
        begin_object(w)
      }
      let rejected = try {
        if as_key {
          key(w, text)
        } else {
          string_value(w, text)
        }
        false
      } catch {
        InvalidUnicode => true
        _ => false
      }
      assert_true(rejected)
      let closed = try {
        null_value(w)
        false
      } catch {
        ClosedWriter => true
        _ => false
      }
      assert_true(closed)
    }
  }
}

///|
test "all public writing operations reject after finish" {
  let operations : Array[(Writer) -> Unit raise EncodeFailure] = [
    null_value,
    w => bool_value(w, true),
    w => number_value(w, 1.0),
    w => string_value(w, "x"),
    begin_array,
    begin_object,
    w => key(w, "x"),
    end_array,
    end_object,
  ]
  for operation in operations {
    let w = writer(100, 10, 2)
    null_value(w)
    assert_eq(finish(w), "null")
    let closed = try {
      operation(w)
      false
    } catch {
      ClosedWriter => true
      _ => false
    }
    assert_true(closed)
  }
}

///|
test "exact object keys remain spelling-sensitive and byte metered" {
  let w = writer(100, 3, 1)
  begin_object(w)
  key(w, "é")
  null_value(w)
  key(w, "e\u0301")
  null_value(w)
  end_object(w)
  assert_eq(finish(w), "{\"é\":null,\"e\u0301\":null}")
  let limited = writer(3, 10, 1)
  begin_object(limited)
  let rejected = try {
    key(limited, "oversized")
    false
  } catch {
    OutputLimit => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "completed documents retain exact escaped byte count and close the writer" {
  for sample in [("😀", 6), ("é", 4), ("\n", 4), ("\u0001", 8), ("", 2)] {
    let w = writer(1000, 1, 0)
    string_value(w, sample.0)
    let document = finish_document(w)
    assert_eq(document_bytes(document), sample.1)
    let expected = writer(1000, 1, 0)
    string_value(expected, sample.0)
    assert_eq(document_text(document), finish(expected))
    let closed = try {
      ignore(finish_document(w))
      false
    } catch {
      ClosedWriter => true
      InvalidStructure | InvalidUnicode | InvalidNumber | OutputLimit => false
    }
    assert_true(closed)
  }
}

///|
test "document byte count agrees with independent UTF8 encoding for nested roots" {
  let values : Array[Json] = [
    { "😀\n": ["e\u0301\r\n", 1.0000000000000002, true, null] },
    [[], {}, "\"\\\t\u0000", 5.0e-324, 1.7976931348623157e308],
    {},
    [],
  ]
  for value in values {
    let out = writer(10000, 100, 10)
    emit_json(value, out)
    let document = finish_document(out)
    let text = document_text(document)
    let bytes = @utf8.encode(text).length()
    assert_eq(document_bytes(document), bytes)
    let exact = writer(bytes, 100, 10)
    emit_json(value, exact)
    assert_eq(document_bytes(finish_document(exact)), bytes)
  }
}

///|
test "incomplete and poisoned writers cannot publish counted documents" {
  let empty = writer(100, 10, 2)
  let array = writer(100, 10, 2)
  begin_array(array)
  null_value(array)
  let object = writer(100, 10, 2)
  begin_object(object)
  key(object, "missing")
  for out in [empty, array, object] {
    let rejected = try {
      ignore(finish_document(out))
      false
    } catch {
      InvalidStructure => true
      InvalidUnicode | InvalidNumber | OutputLimit | ClosedWriter => false
    }
    assert_true(rejected)
    let closed = try {
      ignore(finish_document(out))
      false
    } catch {
      ClosedWriter => true
      InvalidStructure | InvalidUnicode | InvalidNumber | OutputLimit => false
    }
    assert_true(closed)
  }
  let poisoned = writer(1, 1, 0)
  let rejected = try {
    null_value(poisoned)
    false
  } catch {
    OutputLimit => true
    InvalidStructure | InvalidUnicode | InvalidNumber | ClosedWriter => false
  }
  assert_true(rejected)
  let closed = try {
    ignore(finish_document(poisoned))
    false
  } catch {
    ClosedWriter => true
    InvalidStructure | InvalidUnicode | InvalidNumber | OutputLimit => false
  }
  assert_true(closed)
}

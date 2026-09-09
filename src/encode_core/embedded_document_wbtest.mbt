///|
test "sealed document embedding charges bytes nodes depth and parent punctuation" {
  for value in [Json::null(), { "z": ["e\u0301\r\n😀", true] }, [], {}] {
    let child = writer(1000, 100, 10)
    emit_json(value, child)
    let document = finish_document(child)
    let direct = writer(1000, 100, 10)
    begin_array(direct)
    null_value(direct)
    emit_json(value, direct)
    end_array(direct)
    let expected = finish_document(direct)
    let embedded = writer(expected.bytes, expected.nodes, expected.depth)
    begin_array(embedded)
    null_value(embedded)
    emit_document(embedded, document)
    end_array(embedded)
    let actual = finish_document(embedded)
    assert_eq(actual.text, expected.text)
    assert_eq(actual.bytes, expected.bytes)
    assert_eq(actual.nodes, expected.nodes)
    assert_eq(actual.depth, expected.depth)
    for
      limits in [
        (expected.bytes - 1, expected.nodes, expected.depth),
        (expected.bytes, expected.nodes - 1, expected.depth),
        (expected.bytes, expected.nodes, expected.depth - 1),
      ] {
      let (bytes, nodes, depth) = limits
      let out = writer(bytes, nodes, depth)
      let rejected = try {
        begin_array(out)
        null_value(out)
        emit_document(out, document)
        end_array(out)
        ignore(finish(out))
        false
      } catch {
        OutputLimit => true
        _ => false
      }
      assert_true(rejected)
      let closed = try {
        ignore(finish(out))
        false
      } catch {
        ClosedWriter => true
        _ => false
      }
      assert_true(closed)
    }
    // Metadata remains exact when this composite is itself embedded again.
    let outer = writer(expected.bytes, expected.nodes, expected.depth)
    emit_document(outer, actual)
    let repeated = finish_document(outer)
    assert_eq(repeated.text, expected.text)
    assert_eq(repeated.depth, expected.depth)
    assert_eq(repeated.nodes, expected.nodes)
  }
}

///|
test "sealed document cannot bypass structural positions or writer closure" {
  let source = writer(4, 1, 0)
  null_value(source)
  let document = finish_document(source)
  let object = writer(100, 10, 10)
  begin_object(object)
  let root = writer(100, 10, 10)
  null_value(root)
  for out in [object, root] {
    let rejected = try {
      emit_document(out, document)
      false
    } catch {
      InvalidStructure => true
      _ => false
    }
    assert_true(rejected)
  }
  let out = writer(100, 10, 10)
  begin_object(out)
  key(out, "x")
  emit_document(out, document)
  end_object(out)
  assert_eq(finish(out), "{\"x\":null}")
  let rejected = try {
    emit_document(out, document)
    false
  } catch {
    ClosedWriter => true
    _ => false
  }
  assert_true(rejected)
}

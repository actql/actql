///|
fn limits() -> Limits {
  {
    max_input_bytes: 100000,
    max_parts: 10000,
    max_ast_bytes: 1000000,
    max_ast_nodes: 100000,
  }
}

///|
test "replacement grammar fixes all capture tokens and does not interpret Host syntax" {
  for capture in 1..<100 {
    let text = "$" + capture.to_string()
    let value = parse(text, limits()).unwrap()
    assert_eq(part_at(value, 0), Some(Capture(capture)))
    assert_eq(part_count(value), 1)
    assert_eq(stats(value).capture_reference_count, 1)
    assert_eq(stats(value).max_capture_index, capture)
    assert_eq(stats(value).literal_utf8_bytes, 0)
    if capture >= 10 {
      let extra = parse(text + "7", limits()).unwrap()
      assert_eq(part_at(extra, 0), Some(Capture(capture)))
      assert_eq(part_at(extra, 1), Some(Literal("7")))
    }
  }
  for suffix in ["&", "`", "'", "{1}", "<name>", "0", "01", "x"] {
    assert_true(parse("$" + suffix, limits()) is Err(InvalidReplacement(0)))
  }
  let text = "a$$b$$c".repeat(5000)
  let value = parse(text, limits()).unwrap()
  assert_eq(part_count(value), 1)
  assert_eq(part_at(value, 0), Some(Literal("a$b$c".repeat(5000))))
  assert_eq(stats(value).literal_utf8_bytes, 25000)
  assert_eq(stats(value).max_capture_index, 0)
  let repeated = parse("$1".repeat(5000), limits()).unwrap()
  assert_eq(part_count(repeated), 5000)
  assert_eq(stats(repeated).capture_reference_count, 5000)
  assert_eq(stats(repeated).max_capture_index, 1)
}

///|
test "replacement budgets include source bytes and complete canonical AST" {
  for text in ["", "é😀$$$1$99", "$1$1", "literal"] {
    let value = parse(text, limits()).unwrap()
    let (bytes, ast_bytes, nodes) = usage(value)
    let exact : Limits = {
      max_input_bytes: bytes,
      max_parts: part_count(value),
      max_ast_bytes: ast_bytes,
      max_ast_nodes: nodes,
    }
    assert_true(parse(text, exact) is Ok(_))
    assert_eq(nodes, 7 + 3 * part_count(value))
    let hash = @encode.hashing_writer(ast_bytes, nodes, 3)
    emit_preimage(value, hash)
    assert_eq("sha256:" + @encode.finish_hash(hash), cid(value))
    let measure = @encode.measuring_writer(ast_bytes, nodes, 3)
    emit(value, measure)
    assert_eq(@encode.finish_measurement(measure), ast_bytes)
    for
      short in [
        { ..exact, max_ast_bytes: ast_bytes - 1, },
        { ..exact, max_ast_nodes: nodes - 1, },
      ] {
      assert_true(parse(text, short) is Err(BudgetExceeded))
    }
    if bytes > 0 {
      assert_true(
        parse(text, { ..exact, max_input_bytes: bytes - 1, })
        is Err(BudgetExceeded),
      )
    }
    if part_count(value) > 0 {
      assert_true(
        parse(text, { ..exact, max_parts: part_count(value) - 1, })
        is Err(BudgetExceeded),
      )
    }
    for
      invalid in [
        { ..exact, max_input_bytes: -1, },
        { ..exact, max_parts: -1, },
        { ..exact, max_ast_bytes: -1, },
        { ..exact, max_ast_nodes: -1, },
      ] {
      assert_true(parse(text, invalid) is Err(InvalidLimits))
    }
    assert_true(part_at(value, -1) is None)
    assert_true(part_at(value, part_count(value)) is None)
    let writer = @encode.writer(ast_bytes - 1, nodes, 3)
    let failed = try {
      emit(value, writer)
      false
    } catch {
      _ => true
    }
    assert_true(failed)
    let closed = try {
      ignore(@encode.finish(writer))
      false
    } catch {
      _ => true
    }
    assert_true(closed)
  }
}

///|
test "replacement Unicode admission is shared across targets and does not repair text" {
  for unit in [0xD800, 0xDBFF, 0xDC00, 0xDFFF] {
    let text = "a" + String::from_array([unit.unsafe_to_char()])
    assert_true(parse(text, limits()) is Err(InvalidUnicode(1)))
  }
  for text in ["e\u{301}", "\r", "\r\n", "a\r$1"] {
    assert_true(parse(text, limits()) is Err(NonCanonicalText))
  }
  let value = parse("é😀\n\u{85}\u{2028}\u{0}$$$1", limits()).unwrap()
  assert_eq(stats(value).literal_utf8_bytes, 14)
  assert_eq(stats(value).capture_reference_count, 1)
  assert_eq(part_at(value, 0), Some(Literal("é😀\n\u{85}\u{2028}\u{0}$")))
  assert_eq(part_at(value, 1), Some(Capture(1)))
}

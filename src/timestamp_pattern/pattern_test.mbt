///|
fn limits() -> Limits {
  {
    max_pattern_bytes: 10000,
    max_components: 10000,
    max_ast_bytes: 1000000,
    max_ast_nodes: 100000,
  }
}

///|
test "timestamp pattern budgets include the complete AST and streaming emission" {
  let source = "yyyy-MM-ddTHH:mm:ss.SSS"
  let pattern = parse(source, Parse, limits()).unwrap()
  let (bytes, count, ast_bytes, ast_nodes) = usage(pattern)
  let exact : Limits = {
    max_pattern_bytes: bytes,
    max_components: count,
    max_ast_bytes: ast_bytes,
    max_ast_nodes: ast_nodes,
  }
  assert_true(parse(source, Parse, exact) is Ok(_))
  assert_eq(mode(pattern), Parse)
  assert_true(component_at(pattern, -1) is None)
  assert_true(component_at(pattern, count) is None)
  assert_eq(ast_nodes, 7 + 3 * count)
  for
    short in [
      { ..exact, max_pattern_bytes: bytes - 1, },
      { ..exact, max_components: count - 1, },
      { ..exact, max_ast_bytes: ast_bytes - 1, },
      { ..exact, max_ast_nodes: ast_nodes - 1, },
    ] {
    assert_true(parse(source, Parse, short) is Err(BudgetExceeded))
  }
  for
    invalid in [
      { ..exact, max_pattern_bytes: -1, },
      { ..exact, max_components: -1, },
      { ..exact, max_ast_bytes: -1, },
      { ..exact, max_ast_nodes: -1, },
    ] {
    assert_true(parse(source, Parse, invalid) is Err(InvalidLimits))
  }
  let hash = @encode.hashing_writer(ast_bytes, ast_nodes, 3)
  emit_preimage(pattern, hash)
  assert_eq("sha256:" + @encode.finish_hash(hash), cid(pattern))
  let measure = @encode.measuring_writer(ast_bytes, ast_nodes, 3)
  emit(pattern, measure)
  assert_eq(@encode.finish_measurement(measure), ast_bytes)
  for
    (cap, nodes, depth) in [
      (ast_bytes - 1, ast_nodes, 3),
      (ast_bytes, ast_nodes - 1, 3),
      (ast_bytes, ast_nodes, 2),
    ] {
    let writer = @encode.writer(cap, nodes, depth)
    let failed = try {
      emit(pattern, writer)
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
test "timestamp grammar covers all token subsets in both modes without a Host parser" {
  let tokens = ["yyyy", "MM", "dd", "HH", "mm", "ss", "SSS"]
  for mask in 1..<128 {
    let selected : Array[String] = []
    for i in 0..<7 {
      if (mask & (1 << i)) != 0 {
        selected.push(tokens[i])
      }
    }
    let source = selected.join("-")
    let hour = (mask & 8) != 0
    let minute = (mask & 16) != 0
    let second = (mask & 32) != 0
    let millis = (mask & 64) != 0
    let time_ok = hour == minute && (!second || hour) && (!millis || second)
    for selected_mode in [Mode::Parse, Mode::Format] {
      let date_ok = selected_mode == Format || (mask & 7) == 7
      assert_eq(
        parse(source, selected_mode, limits()) is Ok(_),
        time_ok && date_ok,
      )
    }
  }
  for token in tokens {
    assert_true(
      parse(token + token, Format, limits()) is Err(DuplicateToken(_)),
    )
  }
}

///|
test "timestamp pattern rejects all non-grammar units including malformed UTF-16" {
  for
    unit in [
      0, 9, 10, 13, 0x85, 0xA0, 0xE9, 0x2028, 0xFEFF, 0xD800, 0xDC00, 0x10FFFF,
    ] {
    let source = "yyyy" + String::from_array([unit.unsafe_to_char()])
    assert_true(parse(source, Format, limits()) is Err(InvalidComponent(4)))
  }
  // Components remain occurrences; adjacent identical literals are not merged.
  let source = "-".repeat(5000) + "yyyy"
  let pattern = parse(source, Format, limits()).unwrap()
  assert_eq(component_count(pattern), 5001)
  assert_eq(value_width(pattern), 5004)
  assert_eq(component_at(pattern, 4999), Some(Literal("-")))
  assert_eq(component_at(pattern, 5000), Some(Token("yyyy")))
}

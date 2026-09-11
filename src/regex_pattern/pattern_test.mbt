///|
fn limits() -> Limits {
  {
    max_input_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
    max_ast_bytes: 10000,
    max_ast_nodes: 10000,
  }
}

///|
test "regex ownership, source validation and exact budgets" {
  let p = parse("(ab|[x-z]){2,3}", limits()).unwrap()
  let (bytes, ast_bytes, ast_nodes) = usage(p)
  let exact = {
    ..limits(),
    max_input_bytes: bytes,
    max_ast_bytes: ast_bytes,
    max_ast_nodes: ast_nodes,
  }
  assert_true(parse("(ab|[x-z]){2,3}", exact) is Ok(_))
  for
    reduced in [
      { ..exact, max_input_bytes: bytes - 1, },
      { ..exact, max_ast_bytes: ast_bytes - 1, },
      { ..exact, max_ast_nodes: ast_nodes - 1, },
      { ..exact, max_nodes: 0, },
      { ..exact, max_depth: 0, },
    ] {
    assert_true(parse("(ab|[x-z]){2,3}", reduced) is Err(BudgetExceeded))
  }
  assert_true(parse("a", { ..limits(), max_nodes: -1, }) is Err(InvalidLimits))
  assert_eq(node_at(p, -1), None)
  assert_eq(node_at(p, node_count(p)), None)
  for i in 0..<node_count(p) {
    let before = node_at(p, i)
    match node_at(p, i) {
      Some(Sequence(items)) | Some(Alternation(items)) => items.clear()
      Some(CharacterClass(_, items)) => items.clear()
      _ => ()
    }
    assert_eq(node_at(p, i), before)
  }
  let malformed = String::from_array(['a', (0xD800).unsafe_to_char()])
  assert_true(parse(malformed, limits()) is Err(InvalidUnicode(1)))
  assert_true(parse("a{9007199254740994}", limits()) is Ok(_))
  assert_true(
    parse("a{" + "9".repeat(310) + "}", limits())
    is Err(QuantifierOutOfRange(2)),
  )
}

///|
test "regex depth and width use iterative parsing and emission" {
  let lim : Limits = {
    max_input_bytes: 100000,
    max_nodes: 50000,
    max_depth: 20000,
    max_ast_bytes: 2000000,
    max_ast_nodes: 200000,
  }
  let text = "(".repeat(10000) + "a" + ")".repeat(10000)
  let p = parse(text, lim).unwrap()
  assert_eq(capture_count(p), 10000)
  assert_eq(node_count(p), 10001)
  assert_true(parse(text, { ..lim, max_depth: 10000, }) is Err(BudgetExceeded))
  let text = "a".repeat(10000)
  let p = parse(text, { ..lim, max_depth: 2, }).unwrap()
  assert_eq(node_count(p), 10001)
  assert_true(parse(text, { ..lim, max_depth: 1, }) is Err(BudgetExceeded))
  let p = parse("[" + text + "]", { ..lim, max_depth: 2, }).unwrap()
  assert_eq(node_count(p), 1)
}

///|
test "regex emitters agree and close on failed output" {
  let p = parse("(ab|c)+", limits()).unwrap()
  let (_, bytes, nodes) = usage(p)
  for cap in [bytes - 1, bytes, bytes + 1] {
    for count in [nodes - 1, nodes, nodes + 1] {
      let w = @encode.writer(cap, count, 100)
      let text = try {
        emit(p, w)
        Some(@encode.finish(w))
      } catch {
        _ => None
      }
      let w = @encode.hashing_writer(cap, count, 100)
      let digest = try {
        emit(p, w)
        Some(@encode.finish_hash(w))
      } catch {
        _ => None
      }
      let w = @encode.measuring_writer(cap, count, 100)
      let measure = try {
        emit(p, w)
        Some(@encode.finish_measurement(w))
      } catch {
        _ => None
      }
      assert_eq(text is Some(_), digest is Some(_))
      assert_eq(text is Some(_), measure is Some(_))
      assert_eq(text is Some(_), cap >= bytes && count >= nodes)
      if measure is None {
        let closed = try {
          emit(p, w)
          false
        } catch {
          _ => true
        }
        assert_true(closed)
      }
    }
  }
}

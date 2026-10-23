///|
fn comparison_fixture(w : Writer) -> Unit raise EncodeFailure {
  begin_array(w)
  string_value(w, "a\n\"\\é😀")
  null_value(w)
  bool_value(w, true)
  number_value(w, 7)
  end_array(w)
}

///|
test "comparison sink preserves exact wire including scalar and escape boundaries" {
  let expected = "[\"a\\n\\\"\\\\é😀\",null,true,7]"
  let plain = writer(1000, 20, 4)
  comparison_fixture(plain)
  let document = finish_document(plain)
  assert_eq(document_text(document), expected)
  for
    target in [
      expected,
      "",
      expected + " ",
      " " + expected,
      expected.replace(old="7", new="8"),
    ] {
    let out = comparing_writer(target, 1000, 20, 4)
    comparison_fixture(out)
    assert_eq(
      finish_comparison_usage(out),
      (target == expected, document_bytes(document), 5, 1),
    )
    guard out.output is CompareOutput(state) else { abort("Wrong sink") }
    assert_eq(state.expected, "")
    let embedded = comparing_writer(target, 1000, 20, 4)
    emit_document(embedded, document)
    assert_eq(finish_comparison_usage(embedded).0, target == expected)
  }
}

///|
test "comparison mismatch does not bypass full byte node depth or structural checks" {
  let plain = writer(1000, 20, 4)
  comparison_fixture(plain)
  let size = document_bytes(finish_document(plain))
  for cap in [size - 1, size, size + 1] {
    for nodes in [4, 5, 6] {
      for depth in [0, 1, 2] {
        let ordinary = try {
          let out = writer(cap, nodes, depth)
          comparison_fixture(out)
          Some(finish_document(out).bytes)
        } catch {
          _ => None
        }
        let compared = try {
          let out = comparing_writer("mismatch", cap, nodes, depth)
          comparison_fixture(out)
          let (equal, bytes, _, _) = finish_comparison_usage(out)
          assert_false(equal)
          Some(bytes)
        } catch {
          _ => None
        }
        assert_eq(compared, ordinary)
      }
    }
  }
  let incomplete = comparing_writer("mismatch", 100, 10, 2)
  begin_array(incomplete)
  try finish_comparison_usage(incomplete) catch {
    InvalidStructure => ()
    _ => assert_true(false)
  } noraise {
    _ => assert_true(false)
  }
  assert_true(incomplete.closed)
}

///|
test "comparison cannot expose text or digest and cancellation retires its target" {
  let cancelled = comparing_writer("null", 4, 1, 0)
  null_value(cancelled)
  cancel_writer(cancelled)
  guard cancelled.output is CompareOutput(state) else { abort("Wrong sink") }
  assert_eq(state.expected, "")
  try finish_comparison_usage(cancelled) catch {
    ClosedWriter => ()
    _ => assert_true(false)
  } noraise {
    _ => assert_true(false)
  }
  for hash in [false, true] {
    let out = comparing_writer("null", 4, 1, 0)
    null_value(out)
    try {
      if hash {
        finish_hash(out)
      } else {
        finish(out)
      }
    } catch {
      InvalidStructure => ()
      _ => assert_true(false)
    } noraise {
      _ => assert_true(false)
    }
    assert_true(out.closed)
    cancel_writer(out)
  }
}

///|
test "comparison completes long spans and refuses invalid tails after mismatch" {
  let content = String::make(4096, 'x') + "😀é\n"
  let expected = "\"" + String::make(4096, 'x') + "😀é\\n\""
  let out = comparing_writer(expected, 10000, 1, 0)
  string_value(out, content)
  assert_eq(finish_comparison_usage(out), (true, 4106, 1, 0))
  let invalid = comparing_writer("different", 10000, 10, 2)
  begin_array(invalid)
  string_value(invalid, content)
  try
    string_value(invalid, String::from_array([(0xd800).unsafe_to_char()]))
  catch {
    InvalidUnicode => ()
    _ => assert_true(false)
  } noraise {
    _ => assert_true(false)
  }
  assert_true(invalid.closed)
  cancel_writer(invalid)
  let duplicate = comparing_writer("different", 100, 10, 2)
  begin_object(duplicate)
  key(duplicate, "x")
  null_value(duplicate)
  try key(duplicate, "x") catch {
    InvalidStructure => ()
    _ => assert_true(false)
  } noraise {
    _ => assert_true(false)
  }
  cancel_writer(duplicate)
}

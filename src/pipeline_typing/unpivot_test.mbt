///|
test "unpivot shares pipeline budgets and preserves duplicate source occurrences" {
  let text = "[{\"unpivot\":{\"columns\":[\"amount\",\"amount\"],\"keep\":[\"id\"],\"name_column\":\"key\",\"value_column\":\"value\"},\"from\":\"l\"},{\"filter\":\"value > 0\"}]"
  let p = join_pipeline(text).unwrap()
  match @pipeline_typing.step_at(p, 0).unwrap().operation {
    Unary(value) => {
      match @relation.reshape(value).unwrap() {
        Unpivot(columns~, keep~, ..) => {
          assert_eq(columns.length(), 2)
          assert_eq(keep.length(), 1)
        }
        _ => fail("expected unpivot")
      }
      assert_eq(@relation.pending_validations(value)[1].kind, ExpansionEnvelope)
    }
    _ => fail("expected unary operation")
  }
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
    max_tokens: u.tokens,
  }
  assert_true(
    @pipeline_typing.check(
      cursor(text),
      [("l", schema()), ("r", schema())],
      None,
      None,
      exact,
    )
    is Ok(_),
  )
  for
    bound in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check(
        cursor(text),
        [("l", schema()), ("r", schema())],
        None,
        None,
        bound,
      )
      is Err(_),
    )
  }
}

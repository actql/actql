///|
// Until the original published Command target and input-key correspondence are
// admitted, a parsed Effect must not be discarded into a successful pure query.
test "short COMMAND refuses unresolved lowering at both actual compiler entrances" {
  for
    text in [
      "FROM pair |> EFFECT COMMAND gmail.send ID x INPUT (body = y);", "FROM pair |> EFFECT send COMMAND slack.post TARGET x ID y INPUT ();",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    assert_true(
      compile(query, pair_context(), construction_limits())
      is Err(UnsupportedEffect),
    )
    assert_true(
      compile_query_script(
        @query.single_query_script(query),
        pair_context(),
        construction_limits(),
      )
      is Err(UnsupportedEffect),
    )
  }
}

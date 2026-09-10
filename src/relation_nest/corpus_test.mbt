///|
fn row(text : String) -> @schema.Schema {
  @schema.from_object(
    @contract.read_author(
      cursor("{\"type\":\"object\",\"nullable\":false,\"fields\":" + text + "}"),
      { max_nodes: 100000, max_depth: 30000, max_text_bytes: 2000000, },
    ).unwrap(),
  ).unwrap()
}

///|
fn corpus_case(
  body : String,
  parent : String,
  child : String,
  output : String?,
  expected_issue : String?,
) -> Unit raise {
  match
    @relation_nest.check(cursor(body), row(parent), row(child), None, limits()) {
    Ok(v) => {
      assert_eq(expected_issue, None)
      assert_true(
        @contract.type_equal(
          @schema.as_object(@relation_nest.output_schema(v)).unwrap(),
          @schema.as_object(row(output.unwrap())).unwrap(),
          100000,
        ),
      )
      assert_eq(@relation_nest.pending_validations(v).length(), 5)
    }
    Err(e) => {
      assert_eq(output, None)
      let name = match e.kind {
        InvalidBody => "InvalidBody"
        EmptyBody => "EmptyBody"
        InvalidName(_) => "InvalidName"
        UnknownField(_, _) => "UnknownField"
        IncomparableKeys(_, _) => "IncomparableKeys"
        DuplicateOutput(_) => "DuplicateOutput"
        InputCollision(_) => "InputCollision"
        NotConstructible(_) => "NotConstructible"
        InvalidOrder => "InvalidOrder"
        NotAuthorOrderable(_) => "NotAuthorOrderable"
        InvalidGuard => "InvalidGuard"
        UnknownParameter(_) => "UnknownParameter"
        _ => "unexpected"
      }
      assert_eq(Some(name), expected_issue)
    }
  }
}

///|
fn corpus_schema(fields : String) -> @schema.Schema {
  @schema.from_object(
    @contract.read_author(
      cursor(
        "{\"type\":\"object\",\"nullable\":false,\"fields\":" + fields + "}",
      ),
      { max_nodes: 10000, max_text_bytes: 100000, max_depth: 100, },
    ).unwrap(),
  ).unwrap()
}

///|
fn corpus_accepted(
  body : String,
  input : String,
  names : Array[String],
  nullable : Array[Bool],
  key_count : Int,
) -> Unit raise {
  let input = corpus_schema(input)
  let j = @relation_join.check(cursor(body), input, input, None, limits()).unwrap()
  let fields = @schema.fields(@relation_join.output_schema(j))
  assert_eq(fields.map(f => @schema.reference_name(f.name)), names)
  assert_eq(fields.map(f => f.contract.nullable), nullable)
  assert_eq(@relation_join.keys(j).length(), key_count)
}

///|
fn corpus_rejected(
  body : String,
  input : String,
  expected : String,
) -> Unit raise {
  let input = corpus_schema(input)
  match @relation_join.check(cursor(body), input, input, None, limits()) {
    Ok(_) => fail("unexpected join acceptance")
    Err(e) => {
      let actual = match e.kind {
        EmptyBody => "EmptyBody"
        InvalidBody => "InvalidBody"
        UnknownField(_, _) => "UnknownField"
        IncomparableKeys(_, _) => "IncomparableKeys"
        InvalidProjection(_) => "InvalidProjection"
        InvalidName(_) => "InvalidName"
        InvalidGuard => "InvalidGuard"
        _ => "unexpected issue"
      }
      assert_eq(actual, expected)
    }
  }
}

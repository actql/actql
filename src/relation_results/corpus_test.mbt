///|
fn corpus_accepted(
  text : String,
  expected_target : String,
  fields : Array[String],
  order : String?,
) -> Unit raise {
  let checked = check(text)
  let r = @relation_results.result_at(checked, 0).unwrap()
  let actual = match @relation_results.target(r) {
    Input(i) => "input:" + i.to_string()
    Step(i) => "step:" + i.to_string()
  }
  assert_eq(actual, expected_target)
  assert_eq(@relation_results.fields(r), fields)
  let input_fields = match input().shape {
    @contract.Object(v) => @contract.fields(v)
    _ => abort("fixture")
  }
  let expected = @contract.object_contract(
    fields.map(name => {
      let c = input_fields.filter(f => f.name == name)[0].contract
      (name, c)
    }),
    nullable=false,
    max_fields=100,
    max_name_bytes=10000,
  ).unwrap()
  assert_true(
    @contract.type_equal(@relation_results.output_schema(r), expected, 10000),
  )
  match order {
    None => assert_true(@relation_results.order_by(r) is None)
    Some(text) => {
      let expected = @decode.elements(cursor(text)).unwrap()
      let actual = @relation_results.order_by(r).unwrap()
      assert_eq(actual.length(), expected.length())
      for i in 0..<expected.length() {
        let parts = @decode.elements(expected[i]).unwrap()
        assert_eq(actual[i].field, @decode.text(parts[0]).unwrap())
        assert_eq(
          actual[i].direction,
          if @decode.text(parts[1]).unwrap() == "asc" {
            Asc
          } else {
            Desc
          },
        )
        assert_eq(
          actual[i].nulls,
          if @decode.text(parts[2]).unwrap() == "first" {
            First
          } else {
            Last
          },
        )
        assert_eq(actual[i].explicit_nulls, @decode.boolean(parts[3]).unwrap())
      }
    }
  }
  assert_eq(@relation_results.pending_validations(r), [TotalDeterministicOrder])
}

///|
fn corpus_rejected(text : String, expected : String) -> Unit raise {
  let e = @relation_results.check(pipeline(), cursor(text), limits()).unwrap_err()
  let actual = match e.kind {
    Decode(_) => "Decode"
    InvalidBody => "InvalidBody"
    DuplicateField(_) => "DuplicateField"
    UnknownField(_) => "UnknownField"
    UnknownSource(_) => "UnknownSource"
    InvalidOrder => "InvalidOrder"
    NotAuthorOrderable(_) => "NotAuthorOrderable"
    InvalidMetadata => "InvalidMetadata"
    _ => "unexpected"
  }
  assert_eq(actual, expected)
}

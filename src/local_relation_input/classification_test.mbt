///|
test "local input retains every admitted classification floor without inferring facts" {
  for level in ["public", "internal", "confidential", "restricted"] {
    let at = cursor(
      "{\"carrier\":\"relation\",\"minimum_classification\":\"" + level + "\"}",
    )
    let input = read(at, caps()).unwrap()
    assert_eq(minimum_classification(input), Some(level))
    assert_true(physical_equal(source(input), at))
    let rows = @carrier.relation_rows(carrier(input)).unwrap()
    assert_eq(@carrier.field_set(rows), Open)
    assert_eq(@carrier.field_count(rows), 0)
    assert_true(primary_key(input) is None)
    let used = usage(input)
    assert_true(
      read(at, {
        max_nodes: used.nodes,
        max_depth: 1,
        max_text_bytes: used.text_bytes,
      })
      is Ok(_),
    )
    assert_true(
      read(at, {
        max_nodes: used.nodes,
        max_depth: 1,
        max_text_bytes: used.text_bytes - 1,
      })
      is Err(BudgetExceeded),
    )
  }
  assert_true(
    minimum_classification(read(cursor("\"relation\""), caps()).unwrap())
    is None,
  )
  assert_true(
    minimum_classification(
      read(cursor("{\"carrier\":\"relation\"}"), caps()).unwrap(),
    )
    is None,
  )
}

///|
test "classification vocabulary is closed and reports the original field" {
  for level in ["", "Public", "secret", "unknown", " public", "restricted "] {
    let at = cursor(
      "{\"carrier\":\"relation\",\"minimum_classification\":\"" + level + "\"}",
    )
    match read(at, caps()) {
      Err(InvalidClassification(location)) => {
        let field = @decode.lookup(
          @decode.open_object(at).unwrap(),
          "minimum_classification",
        ).unwrap()
        assert_true(
          @decode.tree_index(at, location) == @decode.tree_index(at, field),
        )
      }
      _ => fail("invalid classification must retain its source")
    }
  }
  for value in ["null", "1", "true", "[]", "{}"] {
    assert_true(
      read(
        cursor(
          "{\"carrier\":\"relation\",\"minimum_classification\":" + value + "}",
        ),
        caps(),
      )
      is Err(Decode(_)),
    )
  }
}

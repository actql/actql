///|
test "artifact codec budget cannot replenish work or overspend zero remainder" {
  assert_true(query_artifact_budget(-1, 4, 4, 4) is None)
  assert_true(query_artifact_budget(3, -1, 4, 4) is None)
  assert_true(query_artifact_budget(3, 4, -1, 4) is None)
  assert_true(query_artifact_budget(3, 4, 4, -1) is None)
  let budget = query_artifact_budget(3, 4, 4, 4).unwrap()
  assert_false(query_artifact_spend_work(budget, -1))
  assert_false(query_artifact_spend_work(budget, 4))
  assert_eq(query_artifact_remaining(budget), (3, 4, 4))
  assert_true(query_artifact_spend_work(budget, 3))
  assert_true(query_artifact_spend_work(budget, 0))
  assert_false(query_artifact_spend_work(budget, 1))
  assert_eq(query_artifact_remaining(budget), (0, 4, 4))
}

///|
test "artifact serialization and hashing consume one cumulative budget" {
  let budget = query_artifact_budget(0, 4, 4, 4).unwrap()
  let (_, zero) = query_record_document(budget, writer => {
    @encode.number_value(writer, 0.0)
  })
  assert_eq(
    zero, "sha256:5feceb66ffc86f38d952786c6d696c79c2dbc239dd4e91b46729d73a27fb57e9",
  )
  assert_eq(query_artifact_remaining(budget), (0, 2, 2))
  let (_, one) = query_record_document(budget, writer => {
    @encode.number_value(writer, 1.0)
  })
  assert_eq(
    one, "sha256:6b86b273ff34fce19d6b804eff5a3f5747ada4eaa22f1d49c01e52ddb7875b4b",
  )
  assert_eq(query_artifact_remaining(budget), (0, 0, 0))
  let exhausted = try {
    let _ = query_record_document(budget, writer => {
      @encode.number_value(writer, 2.0)
    })
    false
  } catch {
    @encode.OutputLimit => true
    _ => false
  }
  assert_true(exhausted)
  assert_eq(query_artifact_remaining(budget), (0, 0, 0))
}

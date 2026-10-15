///|
test "temporal operands append projected fields without treating schema ordinals as row positions" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"at\":10}]},\"as\":\"l\"},{\"from\":\"l\",\"select\":[\"id\",\"at\"],\"as\":\"lp\"},{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2,\"at\":30}]},\"as\":\"r\"},{\"from\":\"r\",\"select\":[\"id\",\"at\"],\"as\":\"rp\"},{\"from\":\"lp\",\"append\":{\"with\":\"rp\"}}]",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["append_4"],
    100000,
    10000,
  ).unwrap()
  let completed = match execute_generated_sequence(generated, [], compute_test_limits()) {
    Ok(value) => value
    Err(Rows(step, InputMismatch)) =>
      fail("append input field mismatch at " + step.to_string())
    Err(Rows(step, OwnerMismatch)) =>
      fail("append owner mismatch at " + step.to_string())
    Err(_) => fail("other sequence refusal")
  }
  let table = test_row_output(completed_output(completed, Step(4)).unwrap())
  assert_eq(table.names, ["at", "id"])
  assert_eq(table.rows.length(), 2)
  assert_true(table.rows[0][0] is Number(10.0))
  assert_true(table.rows[0][1] is Number(1.0))
  assert_true(table.rows[1][0] is Number(30.0))
  assert_true(table.rows[1][1] is Number(2.0))
}

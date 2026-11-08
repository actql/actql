///|
test "Values failure diagnostics distinguish normalization budget from graph and current" {
  let fields : Map[Int, Int64] = Map([])
  let emit = (tag, value) => fields[tag] = value
  local_values_failure_tags(
    @local_host.Normalization(CommonInventory(BudgetExceeded)),
    emit,
  )
  assert_eq(fields.get(10), Some(9L))
  assert_eq(fields.get(11), Some(7006L))
  assert_eq(fields.get(12), Some(102L))
  fields.clear()
  local_values_failure_tags(@local_host.Execution(Fenced), emit)
  assert_eq(fields.get(11), Some(7007L))
  assert_eq(fields.get(12), Some(2L))
  assert_eq(fields.get(15), None)
}

///|
test "Values failure diagnostics preserve configuration and physical transaction uncertainty" {
  let fields : Map[Int, Int64] = Map([])
  let emit = (tag, value) => fields[tag] = value
  local_values_failure_tags(@local_host.Configuration, emit)
  assert_eq(fields.get(11), Some(7003L))
  assert_eq(fields.length(), 2)
  fields.clear()
  local_values_failure_tags(@local_host.Journal(TransactionUnknown), emit)
  assert_eq(fields.get(11), Some(7004L))
  assert_eq(fields.get(12), Some(4L))
  fields.clear()
  local_values_failure_tags(@local_host.Journal(Physical(BodyTooLarge)), emit)
  assert_eq(fields.get(12), Some(5L))
  assert_eq(fields.get(15), Some(10L))
}

///|
// A resolved order is not permission to manufacture a completion-free journal.
// Only original identity sorts, covered candidate keys, and retained total-order
// witnesses require no appended source terms. Real key completion stays explicit.
fn audit_local_completion_free_sort(
  operation : @relation.CheckedOperation,
  pipeline : @pipeline.CheckedPipeline,
  step : Int,
  available : Int,
) -> Result[Int, LocalSortAuditIssue] {
  audit_local_sort(operation, pipeline, step, available, None)
}

///|
fn local_sort_audit_fixture(
  body : String,
) -> (
  CheckedProgram,
  @pipeline.CheckedPipeline,
  Int,
  @relation.CheckedOperation,
) raise {
  let owner = checked_direct_program_fixture(top_k_step=body)
  let pipeline = owner.units[0].pipeline
  for index in 0..<@pipeline.step_count(pipeline) {
    if @pipeline.step_at(pipeline, index).unwrap().operation
      is @pipeline.Unary(operation) &&
      @relation.operation(operation) == @relation.Sort {
      return (owner, pipeline, index, operation)
    }
  }
  fail("original checked Sort missing")
}

///|
test "Sort audit keeps the exact pipeline step operation and original finite work" {
  let (_, pipeline, step, operation) = local_sort_audit_fixture(
    "{\"sort\":[{\"id\":\"asc\"}]}",
  )
  assert_true(
    audit_local_completion_free_sort(operation, pipeline, step, 4) is Ok(0),
  )
  assert_true(
    audit_local_completion_free_sort(operation, pipeline, step, 3)
    is Err(ProfileNotInstalled),
  )
  assert_true(
    audit_local_completion_free_sort(operation, pipeline, step - 1, 10000)
    is Err(ProfileNotInstalled),
  )
  let (_, foreign, _, _) = local_sort_audit_fixture(
    "{\"sort\":[{\"id\":\"asc\"}]}",
  )
  assert_true(
    audit_local_completion_free_sort(operation, foreign, step, 10000)
    is Err(ProfileNotInstalled),
  )
}

///|
test "empty Sort is the original identity and does not require an order proof" {
  let (_, pipeline, step, operation) = local_sort_audit_fixture("{\"sort\":[]}")
  assert_true(@pipeline.sort_order(pipeline, step) is None)
  assert_true(
    audit_local_completion_free_sort(operation, pipeline, step, 1) is Ok(0),
  )
  assert_true(
    audit_local_completion_free_sort(operation, pipeline, step, 0)
    is Err(ProfileNotInstalled),
  )
}

///|
test "actual missing candidate-key terms cannot receive a completion-free audit" {
  let (_, pipeline, step, operation) = local_sort_audit_fixture(
    "{\"derive\":{\"bucket\":\"id - id\"}},{\"sort\":[{\"bucket\":\"asc\"}]}",
  )
  let order = @pipeline.sort_order(pipeline, step).unwrap()
  guard @pipeline.sort_order_strategy(order) is CandidateKey(completion) else {
    fail("original candidate-key completion expected")
  }
  assert_eq(@pipeline.sort_completion_count(completion), 1)
  assert_true(
    audit_local_completion_free_sort(operation, pipeline, step, 10000)
    is Err(CompletionObserved),
  )
}

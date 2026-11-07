///|
test "submission diagnostic tags keep physical cause separate from transaction uncertainty" {
  let issue = @local_host.InstallationReadTransactionFailure(
    @local_host.OriginalResourceLeave(
      None,
      @initial_arena.Read(
        @initial_arena.Domain(
          @initial_bootstrap.Bootstrap(@initial_bootstrap.Physical(-3)),
        ),
      ),
    ),
    @local_host.TransactionUnknown,
  )
  let fields : Map[Int, Int64] = Map([])
  local_submission_failure_tags(issue, (tag, value) => fields[tag] = value)
  assert_eq(fields.get(8), Some(1L))
  assert_eq(fields.get(9), Some(1L))
  assert_eq(fields.get(10), Some(2L))
  assert_eq(fields.get(11), Some(1116L))
  assert_eq(fields.get(12), Some(2147483645L))
  assert_eq(fields.get(14), Some(1L))
  assert_eq(fields.length(), 6)
}

///|
test "submission diagnostic tags cannot carry SQL payloads or arbitrary error text" {
  let one : Map[Int, Int64] = Map([])
  let two : Map[Int, Int64] = Map([])
  local_submission_failure_tags(
    @local_host.InstallationReadTransactionFailure(
      @local_host.Physical(@local_sqlite.Physical("private-SQL-and-path-one")),
      @local_host.TransactionUnknown,
    ),
    (tag, value) => one[tag] = value,
  )
  local_submission_failure_tags(
    @local_host.InstallationReadTransactionFailure(
      @local_host.Physical(
        @local_sqlite.Physical("different-private-id-and-input"),
      ),
      @local_host.TransactionUnknown,
    ),
    (tag, value) => two[tag] = value,
  )
  assert_eq(one, two)
  assert_eq(one.get(15), Some(12L))
  assert_eq(one.get(14), Some(1L))
}

///|
test "submission diagnostic tags preserve Core funding refusal and plain Unknown" {
  let fields : Map[Int, Int64] = Map([])
  local_submission_failure_tags(
    @local_host.InstallationReadTransactionFailure(
      @local_host.OriginalResources(
        @initial_arena.Read(
          @initial_arena.Child(
            @initial_resources.Resource(
              @initial_resources.ChildFundingUnavailable,
            ),
          ),
        ),
      ),
      @local_host.TransactionUnknown,
    ),
    (tag, value) => fields[tag] = value,
  )
  assert_eq(fields.get(11), Some(1206L))
  assert_eq(fields.get(13), Some(17L))
  fields.clear()
  local_submission_failure_tags(
    @local_host.Journal(@local_host.TransactionUnknown),
    (tag, value) => fields[tag] = value,
  )
  assert_eq(fields.get(9), Some(6L))
  assert_eq(fields.get(14), Some(1L))
  assert_eq(fields.length(), 3)
}

///|
test "managed obligations distinguish retained sources from required identity" {
  let owner = capture_fixture()
  let retained = process_managed_obligations(owner)
  assert_true(physical_equal(managed_obligations_owner(retained), owner))
  assert_true(managed_obligations_retain_source(retained))
  assert_false(managed_obligations_require_logical_identity(retained))
  assert_eq(managed_obligations_identities(retained).length(), 1)

  let publication = prepare_managed_obligations(
    owner,
    [
      {
        domain: OrderedRows,
        subject: TaskOutput,
        occurrence: None,
        need: EstablishedBy(BeforeCidOperation),
      },
    ],
    LogicalContentAddressed,
    LogicalContentIdentity,
    1,
  ).unwrap()
  assert_true(managed_obligations_require_logical_identity(publication))
  assert_false(managed_obligations_retain_source(publication))
}

///|
test "managed obligations reject incomplete and duplicate identity demands" {
  let owner = capture_fixture()
  assert_true(
    prepare_managed_obligations(
      owner,
      [
        {
          domain: LogicalRelation,
          subject: NamedResult,
          occurrence: None,
          need: EstablishedBy(BeforePublication),
        },
      ],
      LogicalContentAddressed,
      MaterialBinding,
      1,
    )
    is Err(InvalidResultOccurrence),
  )
  assert_true(
    prepare_managed_obligations(
      owner,
      [],
      LogicalContentAddressed,
      MaterialBinding,
      1,
    )
    is Err(MissingRequiredIdentity),
  )
  assert_true(
    prepare_managed_obligations(
      owner,
      [
        {
          domain: OrderedRows,
          subject: TaskOutput,
          occurrence: None,
          need: UnestablishedRetained,
        },
        {
          domain: OrderedRows,
          subject: TaskOutput,
          occurrence: None,
          need: EstablishedBy(BeforeDiscard),
        },
      ],
      ManagedUse,
      MaterialBinding,
      2,
    )
    is Err(DuplicateIdentity(OrderedRows, TaskOutput)),
  )
}

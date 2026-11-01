///|
// Closed physical ports below isolate the production observation controller,
// not a real Python reader, Account grant, VM parent or normal distribution.
fn operation_current_fixture() -> (StoredHostCurrent, @buffers.BufferPool) {
  let account_wire = "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"local:operator\",\"entries\":[{\"entry_id\":\"files\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"local-files\"]},\"resource\":{\"all\":true},\"operation\":{\"all\":true},\"exclusions\":[]}]}"
  let body = b"{\"configuration_custody_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"device\":\"7\",\"inode\":\"9\",\"intent_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"version\":\"actql-native-local-journal-custody/0.1\"}"
  let pool = @buffers.open_pool(4096L, 2, 4096).unwrap()
  let slot = @buffers.reserve_output_buffer(pool, 1, 0L, () => true).unwrap()
  let record : StoredHostCurrent = {
    input: 1,
    borrow: Err(@buffers.InvalidPosition),
    slot,
    physical: 1,
    limit: 1,
    store: Ref(1),
    invoked: true,
    closing: false,
    output_closed: false,
    produced: false,
    account: Some(
      @authorization.admit_account_configuration_json(account_wire).unwrap(),
    ),
    account_original: Some(@utf8.encode(account_wire)),
    adoption_original: Some(body),
    generation: Some((7, 9)),
    principal: Some("operator"),
    connection: Some("local-files"),
    material: None,
    original_adoption_row: None,
    observed_operation: 0L,
  }
  (record, pool)
}

///|
test "original operation observation reuses only admitted data and still checks current and Account" {
  let (record, pool) = operation_current_fixture()
  let operation = Ref(1L)
  let checks = Ref(0)
  let reads = Ref(0)
  let current = () => {
    checks.val += 1
    Ok(())
  }
  let row : @host.ClientJournalPhysicalRow = {
    key: "adoption",
    revision: 0L,
    body: record.adoption_original.unwrap(),
  }
  let observe = () => {
    host_current_observe_original(
      record,
      () => {
        current().unwrap()
        Ok(operation.val)
      },
      current,
      cursor => {
        reads.val += 1
        Ok(if cursor == "" { Some(row) } else { None })
      },
    )
  }
  let material = @host.bind_client_local_adopted_host_material(
    record.store,
    observe,
  ).unwrap()
  record.material = Some(material)
  assert_eq(reads.val, 2)
  assert_eq(checks.val, 3)
  assert_true(physical_equal(record.original_adoption_row.unwrap(), row))
  assert_true(
    @host.client_local_adopted_account_outcome(material, record.store, {
      principal: "operator",
      connection: "local-files",
      resource: "run",
      operation: "read",
    })
    is Ok(@authorization.Allow(_)),
  )
  assert_true(
    @host.client_local_adopted_account_outcome(material, record.store, {
      principal: "foreign",
      connection: "local-files",
      resource: "run",
      operation: "read",
    })
    is Ok(@authorization.Deny(_)),
  )
  assert_eq(reads.val, 2)
  assert_eq(checks.val, 7)
  operation.val = 2L
  @host.client_local_adopted_current_account(material, record.store).unwrap()
  |> ignore
  assert_eq(reads.val, 4)
  assert_eq(checks.val, 10)
  operation.val = 0L
  @host.client_local_adopted_current_account(material, record.store).unwrap()
  |> ignore
  @host.client_local_adopted_current_account(material, record.store).unwrap()
  |> ignore
  assert_eq(reads.val, 8)
  assert_eq(checks.val, 16)
  assert_true(physical_equal(record.original_adoption_row.unwrap(), row))
  @buffers.close_buffer(pool, record.slot).unwrap()
  @buffers.close_pool(pool).unwrap()
}

///|
test "original operation observation refuses changed physical data before reusing a later operation" {
  let (record, pool) = operation_current_fixture()
  let operation = Ref(1L)
  let extra = Ref(false)
  let changed = Ref(false)
  let row : @host.ClientJournalPhysicalRow = {
    key: "adoption",
    revision: 0L,
    body: record.adoption_original.unwrap(),
  }
  let observe = () => {
    host_current_observe_original(
      record,
      () => Ok(operation.val),
      () => Ok(()),
      cursor => {
        if cursor == "" {
          Ok(
            Some(
              if changed.val {
                { key: "adoption", revision: 1L, body: row.body, }
              } else {
                row
              },
            ),
          )
        } else {
          Ok(if extra.val { Some(row) } else { None })
        }
      },
    )
  }
  let material = @host.bind_client_local_adopted_host_material(
    record.store,
    observe,
  ).unwrap()
  record.material = Some(material)
  operation.val = 2L
  extra.val = true
  assert_true(
    @host.client_local_adopted_current_account(material, record.store)
    is Err(@host.Physical(-32)),
  )
  assert_eq(record.observed_operation, 0L)
  extra.val = false
  changed.val = true
  assert_true(
    @host.client_local_adopted_current_account(material, record.store)
    is Err(@host.Physical(-32)),
  )
  assert_eq(record.observed_operation, 0L)
  changed.val = false
  @host.client_local_adopted_current_account(material, record.store).unwrap()
  |> ignore
  assert_eq(record.observed_operation, 2L)
  // Common still compares the complete original account source in the fast path.
  record.account_original = Some(record.account_original.unwrap() + b"\n")
  assert_true(
    @host.client_local_adopted_current_account(material, record.store)
    is Err(@host.ChangedCurrent),
  )
  @buffers.close_buffer(pool, record.slot).unwrap()
  @buffers.close_pool(pool).unwrap()
}

///|
test "original operation observation cannot publish ready data across a changed or failed final fence" {
  let (record, pool) = operation_current_fixture()
  let operation = Ref(1L)
  let checked = Ref(0)
  let fail = Ref(false)
  let race = Ref(false)
  let row : @host.ClientJournalPhysicalRow = {
    key: "adoption",
    revision: 0L,
    body: record.adoption_original.unwrap(),
  }
  let observe = () => {
    host_current_observe_original(
      record,
      () => {
        checked.val += 1
        if record.closing || fail.val {
          record.observed_operation = 0L
          Err(-41)
        } else {
          Ok(
            if race.val && checked.val % 2 == 0 {
              operation.val + 1L
            } else {
              operation.val
            },
          )
        }
      },
      () => Ok(()),
      cursor => Ok(if cursor == "" { Some(row) } else { None }),
    )
  }
  let material = @host.bind_client_local_adopted_host_material(
    record.store,
    observe,
  ).unwrap()
  record.material = Some(material)
  race.val = true
  assert_true(
    @host.client_local_adopted_current_account(material, record.store)
    is Err(@host.Physical(-41)),
  )
  assert_eq(record.observed_operation, 0L)
  race.val = false
  fail.val = true
  assert_true(
    @host.client_local_adopted_current_account(material, record.store)
    is Err(@host.Physical(-41)),
  )
  assert_eq(record.observed_operation, 0L)
  fail.val = false
  record.closing = true
  assert_true(
    @host.client_local_adopted_current_account(material, record.store)
    is Err(@host.Physical(-41)),
  )
  record.closing = false
  operation.val = 2L
  @host.client_local_adopted_current_account(material, record.store).unwrap()
  |> ignore
  assert_eq(record.observed_operation, 2L)
  @buffers.close_buffer(pool, record.slot).unwrap()
  @buffers.close_pool(pool).unwrap()
}

///|
test "entered physical current callback cannot return a ready operation after retirement" {
  for changed in [0, 1, 2] {
    let (record, pool) = operation_current_fixture()
    let closed = Ref(false)
    let calls = Ref(0)
    record.observed_operation = 9L
    let result = host_current_checked_operation_original(
      record,
      () => closed.val,
      () => {
        calls.val += 1
        if changed == 0 {
          closed.val = true
        } else if changed == 1 {
          record.closing = true
        } else {
          record.output_closed = true
        }
        9L
      },
    )
    assert_true(result is Err(-41))
    assert_eq(record.observed_operation, 0L)
    assert_eq(calls.val, 1)
    @buffers.close_buffer(pool, record.slot).unwrap()
    @buffers.close_pool(pool).unwrap()
  }
}

///|
test "closed entered observation shares only its adjacent pure projection sample" {
  let (record, pool) = operation_current_fixture()
  let checks = Ref(0)
  let reads = Ref(0)
  let entered = Ref(false)
  let row : @host.ClientJournalPhysicalRow = {
    key: "adoption",
    revision: 0L,
    body: record.adoption_original.unwrap(),
  }
  let current = () => Ok(())
  let observe = () => {
    let post : (() -> Result[Unit, Int])? = if entered.val {
      Some(() => Ok(()))
    } else {
      None
    }
    host_current_observe_original(
      record,
      () => {
        checks.val += 1
        Ok(1L)
      },
      current,
      cursor => {
        reads.val += 1
        Ok(if cursor == "" { Some(row) } else { None })
      },
      post_original=post,
    )
  }
  let material = @host.bind_client_local_adopted_host_material(record.store, observe).unwrap()
  record.material = Some(material)
  assert_eq(checks.val, 2)
  assert_eq(reads.val, 2)
  entered.val = true
  assert_true(
    @host.client_local_adopted_account_outcome(material, record.store, {
      principal: "operator",
      connection: "local-files",
      resource: "run",
      operation: "read",
    }) is Ok(@authorization.Allow(_)),
  )
  assert_true(
    @host.client_local_adopted_account_outcome(material, record.store, {
      principal: "foreign",
      connection: "local-files",
      resource: "run",
      operation: "read",
    }) is Ok(@authorization.Deny(_)),
  )
  assert_eq(checks.val, 4)
  assert_eq(reads.val, 2)
  @buffers.close_buffer(pool, record.slot).unwrap()
  @buffers.close_pool(pool).unwrap()
}

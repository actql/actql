///|
// The actual legacy SystemSQLite/Host fixture checks snapshot invalidation.
// The controlled cheap predicate is not a physical Read supplier or ACK.
test "adoption observation is reused only in one current Journal snapshot" {
  let host = policy_host_fixture("adoption-snapshot-facts")
  let full = Ref(0)
  let cheap = Ref(0)
  let retired = Ref(false)
  let observe = () => {
    host.current_adoption_material_with_reads(
      () => {
        full.val += 1
        host.check_binding()
      },
      snapshot_current=Some(() => {
        cheap.val += 1
        if retired.val {
          Err(Closed)
        } else {
          Ok(())
        }
      }),
    )
  }
  let observed = host.journal
    .transaction(() => {
      let first = match observe() {
        Ok(v) => v
        Err(_) => return Err(CustodyLost)
      }
      let second = match observe() {
        Ok(v) => v
        Err(_) => return Err(CustodyLost)
      }
      Ok(physical_equal(first, second))
    })
    .unwrap()
  assert_true(observed)
  assert_eq(full.val, 1)
  assert_eq(cheap.val, 2)
  assert_true(host.journal.admitted_adoption is None)
  let next = host.journal.transaction(() => {
    match observe() {
      Ok(_) => Ok(())
      Err(_) => Err(CustodyLost)
    }
  })
  assert_true(next is Ok(_))
  assert_eq(full.val, 2)
  // A live snapshot cannot ignore a failed cheap original-lifetime check.
  let stopped = host.journal.transaction(() => {
    match observe() {
      Ok(_) => ()
      Err(_) => return Err(CustodyLost)
    }
    retired.val = true
    match observe() {
      Err(Closed) => Ok(())
      _ => Err(CustodyLost)
    }
  })
  assert_true(stopped is Ok(_))
  assert_eq(full.val, 3)
  assert_true(host.journal.admitted_adoption is None)
  host.close().unwrap()
}

///|
test "explicit full current and a changed adoption row cannot borrow snapshot validity" {
  let host = policy_host_fixture("adoption-snapshot-tamper")
  let before = host.database.read("client_local_adoption", "adoption").unwrap()
  let calls = Ref(0)
  let result = host.journal.transaction(() => {
    match
      host.current_adoption_material_with_reads(
        () => {
          calls.val += 1
          host.check_binding()
        },
        snapshot_current=Some(() => Ok(())),
      ) {
      Ok(_) => ()
      Err(_) => return Err(CustodyLost)
    }
    // The ordinary default full-current entry does not opt into the private
    // captured snapshot port. Its own selected row must still be observed.
    host.database
    .compare_exchange(
      "client_local_adoption",
      "adoption",
      before.revision,
      b"changed selected original",
    )
    .unwrap()
    |> ignore
    let refused = host.current_adoption_material_with_reads(() => {
      calls.val += 1
      host.check_binding()
    })
    if host.journal.admitted_adoption is Some(_) {
      return Ok(())
    }
    match refused {
      Err(CustodyLost) => Err(CustodyLost)
      _ => Ok(())
    }
  })
  assert_true(result is Err(CustodyLost))
  assert_eq(calls.val, 2)
  assert_true(host.journal.admitted_adoption is None)
  let after = host.database.read("client_local_adoption", "adoption").unwrap()
  assert_eq(after.body, before.body)
  assert_eq(after.revision, before.revision)
  host.close().unwrap()
}

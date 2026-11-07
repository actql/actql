///|
// These cases require the original selected C provider; stock builds fail.
// Every successful transition below has an actual physical enter/leave ACK.
test "same original consumer resumes serial physical scopes without a second logical entry" {
  let fixture = original_read_consumer_fixture("consumer-serial")
  let host = fixture.host
  let consumer = host
    .prepare_domain_original_read_consumer(fixture.read, 8192L, 16384L)
    .unwrap()
  assert_true(
    host.resume_domain_original_read_consumer_scope(consumer)
    is Err(Read(@resources.SpentClaim)),
  )
  host.enter_domain_original_read_consumer(consumer).unwrap()
  assert_true(
    host.resume_domain_original_read_consumer_scope(consumer)
    is Err(Read(@resources.SpentClaim)),
  )
  host.leave_domain_original_read_consumer(consumer).unwrap()
  let claim = fixture.read.claim.unwrap()
  let workspace = host
    .borrow_domain_original_read_consumer_workspace(consumer)
    .unwrap()
  for _ in 0..<3 {
    host.resume_domain_original_read_consumer_scope(consumer).unwrap()
    host.leave_domain_original_read_consumer(consumer).unwrap()
    assert_true(physical_equal(fixture.read.claim.unwrap(), claim))
    assert_true(
      physical_equal(
        host.borrow_domain_original_read_consumer_workspace(consumer).unwrap(),
        workspace,
      ),
    )
    assert_true(host.borrow_domain_original_read(fixture.read) is Err(_))
    assert_true(host.enter_domain_original_read_consumer(consumer) is Err(_))
  }
  assert_true(
    host.resume_domain_original_read_consumer_scope({ ..consumer, })
    is Err(Read(@resources.ForeignOrigin)),
  )
  original_read_consumer_finish(fixture)
}

///|
test "failed actual foreign-domain entry cannot resume after the competing scope leaves" {
  let first = original_read_consumer_fixture("consumer-entry-first")
  let second = original_read_consumer_fixture("consumer-entry-second")
  let owner = first.host
    .prepare_domain_original_read_consumer(first.read, 8192L, 16384L)
    .unwrap()
  let refused = second.host
    .prepare_domain_original_read_consumer(second.read, 8192L, 16384L)
    .unwrap()
  first.host.enter_domain_original_read_consumer(owner).unwrap()
  assert_true(
    second.host.enter_domain_original_read_consumer(refused) is Err(Domain(_)),
  )
  assert_true(refused.scope == ConsumerScopeCleanupOnly)
  first.host.leave_domain_original_read_consumer(owner).unwrap()
  assert_true(
    second.host.require_domain_original_read_consumer_current(refused)
    is Err(Read(@resources.CleanupPending)),
  )
  assert_true(
    second.host.resume_domain_original_read_consumer_scope(refused) is Err(_),
  )
  assert_true(
    second.host.enter_domain_original_read_consumer(refused) is Err(_),
  )
  original_read_consumer_finish(second)
  original_read_consumer_finish(first)
}

///|
test "failed actual leave keeps the same consumer cleanup-only instead of reviving a phase" {
  let fixture = original_read_consumer_fixture("consumer-leave-refused")
  let host = fixture.host
  let consumer = host
    .prepare_domain_original_read_consumer(fixture.read, 8192L, 16384L)
    .unwrap()
  host.enter_domain_original_read_consumer(consumer).unwrap()
  // Fault counter: retire only this fixture's actual C scope behind the view.
  // The subsequent original leave must refuse; it cannot supply another ACK.
  host.leave_domain_read(fixture.domain).unwrap()
  assert_true(host.leave_domain_original_read_consumer(consumer) is Err(_))
  assert_true(consumer.scope == ConsumerScopeCleanupOnly)
  assert_true(
    host.resume_domain_original_read_consumer_scope(consumer) is Err(_),
  )
  assert_true(
    host.borrow_domain_original_read_consumer_workspace(consumer) is Err(_),
  )
  original_read_consumer_finish(fixture)
}

///|
test "managed aliases remain on the same original loan across resumed physical scopes" {
  let fixture = original_read_consumer_fixture("consumer-serial-alias")
  let host = fixture.host
  let consumer = host
    .prepare_domain_original_read_consumer(fixture.read, 8192L, 16384L)
    .unwrap()
  let held : Ref[Bytes?] = Ref(None)
  host.enter_domain_original_read_consumer(consumer).unwrap()
  held.val = Some(@utf8.encode(fixture.label))
  host.leave_domain_original_read_consumer(consumer).unwrap()
  host.resume_domain_original_read_consumer_scope(consumer).unwrap()
  assert_eq(held.val.unwrap(), @utf8.encode(fixture.label))
  host.leave_domain_original_read_consumer(consumer).unwrap()
  assert_true(host.close_domain_original_read(fixture.read) is Err(_))
  assert_false(fixture.read.closed || fixture.read.physical_retired.val)
  assert_true(
    fixture.read.consumer is Some(original) &&
    physical_equal(original, consumer),
  )
  assert_true(
    host.resume_domain_original_read_consumer_scope(consumer) is Err(_),
  )
  held.val = None
  original_read_consumer_finish(fixture)
}

///|
test "same original Native Read grows its reservation and retains actual returned storage" {
  println("Native Read working diagnostic: before fixture")
  let fixture = original_read_consumer_fixture("consumer-working-growth")
  println("Native Read working diagnostic: fixture ready")
  let host = fixture.host
  let consumer = host
    .prepare_domain_original_read_consumer(fixture.read, 16384L, 32768L)
    .unwrap()
  println("Native Read working diagnostic: consumer prepared")
  assert_false(consumer.working_snapshot_pending)
  let claim = fixture.read.claim.unwrap()
  let workspace = consumer.workspace
  let held : Ref[Bytes?] = Ref(None)
  guard host.enter_domain_original_read_consumer(consumer) is Ok(_) else {
    fail("Native Read working diagnostic: physical enter refused")
  }
  // This actual Bytes constructor runs in the SAME selected physical Read.
  // The fixture has an already acquired finite domain; it does not prove
  // acquisition beyond that domain or the complete variable Journal recipe.
  let growth = host.grow_domain_original_read_consumer_capacity(
    consumer, 98304L, 98304L,
  )
  if growth is Err(_) {
    host.leave_domain_original_read_consumer(consumer).unwrap()
    match growth {
      Err(Read(@resources.Resource(@resources.RetentionLimit))) =>
        fail("Native Read working diagnostic: retention refused")
      Err(Read(@resources.Resource(@resources.ExecutionLimit))) =>
        fail("Native Read working diagnostic: execution refused")
      Err(Read(@resources.ChangedOriginalState)) =>
        fail("Native Read working diagnostic: original snapshot changed")
      _ => fail("Native Read working diagnostic: other grow refusal")
    }
  }
  let pending = consumer.working_snapshot_pending
  held.val = Some(Bytes::make(70000, 73))
  host.leave_domain_original_read_consumer(consumer).unwrap()
  assert_true(physical_equal(fixture.read.claim.unwrap(), claim))
  assert_true(physical_equal(consumer.workspace, workspace))
  assert_eq(
    (consumer.retained_bytes, consumer.execution_bytes),
    (98304L, 98304L),
  )
  host.resume_domain_original_read_consumer_scope(consumer).unwrap()
  let preserved = held.val.unwrap().length() == 70000 &&
    held.val.unwrap()[69999] == 73
  host.leave_domain_original_read_consumer(consumer).unwrap()
  assert_true(preserved && pending)
  assert_true(host.close_domain_original_read(fixture.read) is Err(_))
  assert_false(consumer.working_snapshot_pending)
  assert_false(fixture.read.physical_retired.val || fixture.read.closed)
  assert_true(
    host.grow_domain_original_read_consumer_capacity(consumer, 98304L, 98304L)
    is Err(_),
  )
  held.val = None
  original_read_consumer_finish(fixture)
}

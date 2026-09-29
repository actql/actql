///|
fn resident_cid(fill : String) -> String {
  "sha256:" + fill.repeat(64)
}

///|
fn resident_delegation() -> @remote_resident_site.ResidentSiteDelegation {
  {
    coordinator_authority: "cloud-coordinator",
    site_key: "resident-site",
    runtime_bundle_cid: resident_cid("a"),
    connector_registration: "local",
    connector_revision: "local/1",
    strategy_revision: "strategy/1",
    grant_cid: resident_cid("4"),
    evidence_issuer_capability_cid: resident_cid("b"),
    budget_cids: [resident_cid("3")],
  }
}

///|
fn resident_request(
  coordinator : String,
  generation : Int,
  runtime : String,
  connector_revision : String,
  budget : String,
  issuer : String,
  grant : String,
) -> @remote.DispatchRequest {
  @remote.prepare_dispatch_request(
    coordinator,
    resident_cid("0"),
    "task-a",
    1,
    "dispatch-a",
    "resident-site",
    generation,
    runtime,
    "local",
    connector_revision,
    "strategy/1",
    resident_cid("1"),
    resident_cid("2"),
    budget,
    issuer,
    grant,
  ).unwrap()
}

///|
test "resident delegation admits only dispatches inside every delegated scope" {
  let delegation = resident_delegation()
  let check = fn(request) {
    @remote_resident_site.check_resident_dispatch_delegation(
      delegation, request, 2,
    )
  }
  let good = resident_request(
    "cloud-coordinator",
    2,
    resident_cid("a"),
    "local/1",
    resident_cid("3"),
    resident_cid("b"),
    resident_cid("4"),
  )
  assert_true(check(good) is Ok(_))
  assert_true(
    check(
      resident_request(
        "other-coordinator",
        2,
        resident_cid("a"),
        "local/1",
        resident_cid("3"),
        resident_cid("b"),
        resident_cid("4"),
      ),
    )
    is Err(ForeignCoordinator),
  )
  assert_true(
    check(
      resident_request(
        "cloud-coordinator",
        1,
        resident_cid("a"),
        "local/1",
        resident_cid("3"),
        resident_cid("b"),
        resident_cid("4"),
      ),
    )
    is Err(StaleGeneration),
  )
  assert_true(
    check(
      resident_request(
        "cloud-coordinator",
        2,
        resident_cid("c"),
        "local/1",
        resident_cid("3"),
        resident_cid("b"),
        resident_cid("4"),
      ),
    )
    is Err(ForeignRuntime),
  )
  assert_true(
    check(
      resident_request(
        "cloud-coordinator",
        2,
        resident_cid("a"),
        "local/2",
        resident_cid("3"),
        resident_cid("b"),
        resident_cid("4"),
      ),
    )
    is Err(ForeignConnector),
  )
  // A matching grant alone is not enough.
  assert_true(
    check(
      resident_request(
        "cloud-coordinator",
        2,
        resident_cid("a"),
        "local/1",
        resident_cid("3"),
        resident_cid("e"),
        resident_cid("4"),
      ),
    )
    is Err(ForeignIssuer),
  )
  assert_true(
    check(
      resident_request(
        "cloud-coordinator",
        2,
        resident_cid("a"),
        "local/1",
        resident_cid("3"),
        resident_cid("b"),
        resident_cid("5"),
      ),
    )
    is Err(ForeignGrant),
  )
  assert_true(
    check(
      resident_request(
        "cloud-coordinator",
        2,
        resident_cid("a"),
        "local/1",
        resident_cid("9"),
        resident_cid("b"),
        resident_cid("4"),
      ),
    )
    is Err(UnsupportedBudget),
  )
}

///|
test "resident accepted queue is bounded and reserves an attempt once" {
  assert_true(@remote_resident_site.ResidentAcceptedQueue::new(0) is None)
  let queue = @remote_resident_site.ResidentAcceptedQueue::new(2).unwrap()
  assert_true(queue.reserve("attempt-a") is Ok(_))
  assert_true(queue.reserve("attempt-a") is Ok(_))
  assert_true(queue.reserve("attempt-b") is Ok(_))
  assert_true(queue.reserve("attempt-c") is Err(QueueFull))
  assert_eq(queue.length(), 2)
  assert_eq(queue.next(), Some("attempt-a"))
  assert_true(queue.remove("attempt-a"))
  assert_false(queue.remove("attempt-a"))
  assert_true(queue.reserve("attempt-c") is Ok(_))
  assert_eq(queue.next(), Some("attempt-b"))
}

///|
fn retained_delegated_request() -> @transfer.RemoteTransferRequest {
  let physical = @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    resident_cid("1"),
    resident_cid("2"),
    resident_cid("3"),
    1,
    [resident_cid("d")],
    [8L],
    [1],
    4,
    4096,
    8L,
  ).unwrap()
  @transfer.prepare_request(
    "cloud-coordinator",
    "handoff-a",
    @transfer.DirectStream,
    "resident-site",
    2,
    "resident-site",
    2,
    "material-a",
    physical,
    8L,
    4102444800000L,
    resident_cid("7"),
    resident_cid("8"),
    resident_cid("9"),
  ).unwrap()
}

///|
fn retained_local_delegation() -> @remote_resident_site.ResidentRetainedInputDelegation {
  {
    dispatch: resident_delegation(),
    source_grant_cid: resident_cid("7"),
    destination_grant_cid: resident_cid("8"),
    route_capability_cid: resident_cid("9"),
  }
}

///|
test "resident internal movement keeps each delegated grant role separate" {
  let delegation = retained_local_delegation()
  let producer = resident_request(
    "cloud-coordinator",
    2,
    resident_cid("a"),
    "local/1",
    resident_cid("3"),
    resident_cid("b"),
    resident_cid("4"),
  )
  let transfer = retained_delegated_request()
  let check = fn(value) {
    @remote_resident_site.check_resident_retained_input_delegation(
      value, producer, transfer, 2,
    )
  }
  assert_true(check(delegation) is Ok(_))
  assert_true(
    check({ ..delegation, source_grant_cid: delegation.dispatch.grant_cid, })
    is Err(@remote_resident_site.ForeignGrant),
  )
  assert_true(
    check({
      ..delegation,
      destination_grant_cid: delegation.dispatch.evidence_issuer_capability_cid,
    })
    is Err(@remote_resident_site.ForeignGrant),
  )
  assert_true(
    check({ ..delegation, route_capability_cid: resident_cid("0"), })
    is Err(@remote_resident_site.ForeignGrant),
  )
}

///|
test "resident internal movement rechecks producer delegation and live generation" {
  let delegation = retained_local_delegation()
  let transfer = retained_delegated_request()
  let producer = resident_request(
    "cloud-coordinator",
    2,
    resident_cid("a"),
    "local/1",
    resident_cid("3"),
    resident_cid("b"),
    resident_cid("4"),
  )
  assert_true(
    @remote_resident_site.check_resident_retained_input_delegation(
      delegation, producer, transfer, 3,
    )
    is Err(@remote_resident_site.StaleGeneration),
  )
  let foreign = resident_request(
    "another-coordinator",
    2,
    resident_cid("a"),
    "local/1",
    resident_cid("3"),
    resident_cid("b"),
    resident_cid("4"),
  )
  assert_true(
    @remote_resident_site.check_resident_retained_input_delegation(
      delegation, foreign, transfer, 2,
    )
    is Err(@remote_resident_site.ForeignCoordinator),
  )
}

///|
test "dispatch binding preserves denial and exact delegated context" {
  let configuration = delegating()
  let allowed = bind_dispatch_authorization(
    configuration,
    tuple("customers", "read"),
    Activation,
    cid("a"),
    cid("b"),
  ).unwrap()
  assert_true(
    dispatch_authorization_matches(
      allowed,
      configuration,
      tuple("customers", "read"),
      Activation,
      cid("a"),
      cid("b"),
    ),
  )
  assert_true(
    !dispatch_authorization_matches(
      allowed,
      configuration,
      tuple("payroll", "read"),
      Activation,
      cid("a"),
      cid("b"),
    ),
  )
  let request = prepare_decision_request(
    delegated_match("customers"),
    configuration_cid=configuration.configuration_cid(),
    boundary=Activation,
    subject_cid=cid("a"),
    context_cid=cid("b"),
    answering_authorities=["approver-a"],
  ).unwrap()
  let permit = admit_host_answer(
    request,
    Permit({ subject: request.subject(), authority: "approver-a", }, []),
  ).unwrap()
  assert_true(
    bind_dispatch_authorization(
      configuration,
      tuple("customers", "write"),
      Activation,
      cid("a"),
      cid("b"),
      delegated_action=Some(permit),
    )
    is Ok(_),
  )
  assert_true(
    bind_dispatch_authorization(
      configuration,
      tuple("payroll", "write"),
      Activation,
      cid("a"),
      cid("b"),
      delegated_action=Some(permit),
    )
    is Err(Denied),
  )
  assert_true(
    bind_dispatch_authorization(
      configuration,
      tuple("customers", "write"),
      Activation,
      cid("c"),
      cid("b"),
      delegated_action=Some(permit),
    )
    is Err(ForeignDecision),
  )
  assert_true(
    bind_dispatch_authorization(
      configuration,
      tuple("customers", "write"),
      Acquisition,
      cid("a"),
      cid("b"),
      delegated_action=Some(permit),
    )
    is Err(ForeignDecision),
  )
  assert_true(
    bind_dispatch_authorization(
      configuration,
      tuple("customers", "write"),
      Activation,
      cid("a"),
      cid("b"),
    )
    is Err(UnresolvedDelegation),
  )
}

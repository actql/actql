///|
fn authorization_cid(fill : String) -> String {
  "sha256:" + fill.repeat(64)
}

///|
fn authorization_request(site : String) -> @remote.DispatchRequest {
  @remote.prepare_dispatch_request(
    "native-coordinator",
    authorization_cid("0"),
    "task-native-remote",
    1,
    "dispatch-native-remote",
    site,
    1,
    authorization_cid("a"),
    "local",
    "local/1",
    "strategy/1",
    "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
    authorization_cid("2"),
    authorization_cid("3"),
    authorization_cid("b"),
    authorization_cid("4"),
  ).unwrap()
}

///|
fn authorization_configuration(
  outcome : @authorization.ConfiguredOutcome,
) -> @authorization.AdmittedAccountConfiguration {
  @authorization.admit_account_configuration({
    account_id: "coordinator-account",
    entries: [
      {
        entry_id: "remote-sites",
        outcome,
        scope: {
          principal: All,
          connection: AnyOf(["native-site"]),
          resource: All,
          operation: AnyOf(["write"]),
        },
        exclusions: [],
      },
    ],
    bootstrap: None,
  }).unwrap()
}

///|
fn remote_dispatch_allow_action(
  request : @remote.DispatchRequest,
) -> @authorization.RuntimeAction {
  @authorization.runtime_action_for(
    @authorization.evaluate_account(
      authorization_configuration(Allow),
      remote_dispatch_access_tuple("run-owner", request),
    ),
  ).unwrap()
}

///|
fn remote_dispatch_permit(
  request : @remote.DispatchRequest,
) -> @authorization.RuntimeAction {
  remote_dispatch_answer(
    request,
    Permit(
      {
        subject: remote_dispatch_decision(request).subject(),
        authority: "reviewer",
      },
      [],
    ),
  )
}

///|
fn remote_dispatch_answer(
  request : @remote.DispatchRequest,
  answer : @authorization.HostAnswer,
) -> @authorization.RuntimeAction {
  @authorization.admit_host_answer(remote_dispatch_decision(request), answer).unwrap()
}

///|
fn remote_dispatch_decision(
  request : @remote.DispatchRequest,
) -> @authorization.DecisionRequest {
  guard @authorization.evaluate_account(
      authorization_configuration(Delegate),
      remote_dispatch_access_tuple("run-owner", request),
    )
    is Delegate(delegated) else {
    abort("expected a delegated remote dispatch")
  }
  @authorization.prepare_decision_request(
    delegated,
    configuration_cid=authorization_cid("c"),
    boundary=Activation,
    subject_cid=@remote.dispatch_request_task_scope(request).0,
    context_cid=authorization_cid("d"),
    answering_authorities=["reviewer"],
  ).unwrap()
}

///|
test "remote dispatch requires an evaluated dispatch authorization" {
  let request = authorization_request("native-site")
  assert_eq(remote_dispatch_access_tuple("run-owner", request), {
    principal: "run-owner",
    connection: "native-site",
    resource: "local",
    operation: "write",
  })
  assert_true(
    remote_dispatch_authorized(remote_dispatch_allow_action(request), request),
  )
  let foreign = authorization_request("other-site")
  guard @authorization.runtime_action_for(
      @authorization.evaluate_account(
        authorization_configuration(Allow),
        remote_dispatch_access_tuple("run-owner", foreign),
      ),
    )
    is Some(no_match) else {
    abort("expected an account outcome")
  }
  assert_true(no_match is Deny(Account(NoMatch)))
  assert_false(remote_dispatch_authorized(no_match, foreign))
  guard @authorization.runtime_action_for(
      @authorization.evaluate_account(
        authorization_configuration(Deny),
        remote_dispatch_access_tuple("run-owner", request),
      ),
    )
    is Some(denied) else {
    abort("expected an account outcome")
  }
  assert_false(remote_dispatch_authorized(denied, request))
}

///|
test "a Host permit authorizes only its exact remote dispatch scope" {
  let request = authorization_request("native-site")
  let permit = remote_dispatch_permit(request)
  assert_true(remote_dispatch_authorized(permit, request))
  assert_false(
    remote_dispatch_authorized(
      remote_dispatch_answer(request, Failure(Timeout)),
      request,
    ),
  )
  // The same permit cannot widen to another Site.
  assert_false(
    remote_dispatch_authorized(permit, authorization_request("other-site")),
  )
}

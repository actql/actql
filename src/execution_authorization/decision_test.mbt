///|
fn cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn delegating() -> AdmittedAccountConfiguration {
  match
    admit_account_configuration({
      account_id: "cloud-service",
      entries: [
        {
          entry_id: "delegate-writes",
          outcome: Delegate,
          scope: {
            principal: All,
            connection: All,
            resource: All,
            operation: AnyOf(["write"]),
          },
          exclusions: [
            {
              principal: All,
              connection: All,
              resource: AnyOf(["payroll"]),
              operation: All,
            },
          ],
        },
        {
          entry_id: "deny-payroll",
          outcome: Deny,
          scope: {
            principal: All,
            connection: All,
            resource: AnyOf(["payroll"]),
            operation: All,
          },
          exclusions: [],
        },
        {
          entry_id: "allow-reads",
          outcome: Allow,
          scope: {
            principal: All,
            connection: All,
            resource: All,
            operation: AnyOf(["read"]),
          },
          exclusions: [
            {
              principal: All,
              connection: All,
              resource: AnyOf(["payroll"]),
              operation: All,
            },
          ],
        },
      ],
      bootstrap: None,
    }) {
    Ok(value) => value
    Err(_) => abort("admission")
  }
}

///|
fn tuple(resource : String, operation : String) -> AccessTuple {
  { principal: "svc", connection: "crm", resource, operation, }
}

///|
fn delegated_match(resource : String) -> DelegatedMatch {
  match evaluate_account(delegating(), tuple(resource, "write")) {
    Delegate(value) => value
    _ => abort("expected delegate")
  }
}

///|
fn make_request(required_claims? : Array[String] = []) -> DecisionRequest {
  match
    prepare_decision_request(
      delegated_match("accounts"),
      configuration_cid=cid("1"),
      boundary=EffectCommit,
      subject_cid=cid("2"),
      context_cid=cid("3"),
      answering_authorities=["approver-b", "approver-a"],
      required_claims~,
    ) {
    Ok(value) => value
    Err(_) => abort("request")
  }
}

///|
fn binding(request : DecisionRequest, authority : String) -> AnswerBinding {
  { subject: request.subject(), authority, }
}

///|
test "design 1 and 8: allow dispatches directly without callback or claims" {
  let outcome = evaluate_account(delegating(), tuple("accounts", "read"))
  assert_true(outcome is Allow("allow-reads"))
  guard runtime_action_for(outcome) is Some(action) else { abort("action") }
  assert_true(action is AuthorizedForDispatch(AccountAllow("allow-reads")))
}

///|
test "design 2: deny never yields a decision request" {
  let outcome = evaluate_account(delegating(), tuple("payroll", "write"))
  assert_true(outcome is Deny(Explicit("deny-payroll")))
  guard runtime_action_for(outcome) is Some(action) else { abort("action") }
  assert_true(action is Deny(Account(Explicit("deny-payroll"))))
  // No DelegatedMatch exists for a deny outcome, so no request (and hence no
  // Host answer) can be formed for it.
  let unmatched = evaluate_account(delegating(), tuple("accounts", "delete"))
  guard runtime_action_for(unmatched) is Some(Deny(Account(NoMatch))) else {
    abort("no match")
  }
}

///|
test "delegate has no direct runtime action" {
  let outcome = evaluate_account(delegating(), tuple("accounts", "write"))
  assert_true(runtime_action_for(outcome) is None)
}

///|
test "request binds the exact subject" {
  let request = make_request()
  let subject = request.subject()
  assert_eq(subject.account_id, "cloud-service")
  assert_eq(subject.entry_id, "delegate-writes")
  assert_eq(subject.tuple, tuple("accounts", "write"))
  assert_eq(subject.boundary, EffectCommit)
  assert_eq(subject.configuration_cid, cid("1"))
  assert_eq(request.answering_authorities(), ["approver-a", "approver-b"])
  assert_eq(request.required_claims(), [])
}

///|
test "design 3: immediate permit dispatches without a checkpoint" {
  let request = make_request()
  guard admit_host_answer(request, Permit(binding(request, "approver-a"), []))
    is Ok(AuthorizedForDispatch(HostPermit(subject, "approver-a", []))) else {
    abort("permit")
  }
  assert_eq(subject, request.subject())
}

///|
test "design 4: immediate reject denies as rejected by host" {
  let request = make_request()
  guard admit_host_answer(request, Reject(binding(request, "approver-b")))
    is Ok(Deny(RejectedByHost(subject, "approver-b"))) else {
    abort("reject")
  }
  assert_eq(subject, request.subject())
}

///|
test "design 5: defer requires a checkpoint of the same request" {
  let request = make_request()
  guard admit_host_answer(request, Defer(request.subject()))
    is Ok(Checkpoint(held)) else {
    abort("defer")
  }
  assert_eq(held, request)
  let other = { ..request.subject(), subject_cid: cid("4"), }
  assert_eq(
    admit_host_answer(request, Defer(other)).map(_ => ()),
    Err(SubjectMismatch),
  )
}

///|
test "adapter failure is a decision failure, not a rejection" {
  let request = make_request()
  let reasons : Array[DecisionFailureReason] = [
    Timeout,
    Unavailable,
    MalformedAnswer,
    AdapterError("socket closed"),
  ]
  for reason in reasons {
    guard admit_host_answer(request, Failure(reason))
      is Ok(DecisionFailure(found)) else {
      abort("failure")
    }
    assert_eq(found, reason)
  }
}

///|
test "design 10: changed subject or wrong authority is not admitted" {
  let request = make_request()
  let subject = request.subject()
  let changed = [
    { ..subject, account_id: "other", },
    { ..subject, configuration_cid: cid("9"), },
    { ..subject, entry_id: "allow-reads", },
    { ..subject, tuple: tuple("accounts2", "write"), },
    { ..subject, boundary: Transfer, },
    { ..subject, subject_cid: cid("9"), },
    { ..subject, context_cid: cid("9"), },
  ]
  for wrong in changed {
    assert_eq(
      admit_host_answer(
        request,
        Permit({ subject: wrong, authority: "approver-a", }, []),
      ).map(_ => ()),
      Err(SubjectMismatch),
    )
    assert_eq(
      admit_host_answer(
        request,
        Reject({ subject: wrong, authority: "approver-a", }),
      ).map(_ => ()),
      Err(SubjectMismatch),
    )
  }
  assert_eq(
    admit_host_answer(request, Permit(binding(request, "intruder"), [])).map(_ => {
      ()
    }),
    Err(UnauthorizedAuthority("intruder")),
  )
  assert_eq(
    admit_host_answer(request, Reject(binding(request, "intruder"))).map(_ => ()),
    Err(UnauthorizedAuthority("intruder")),
  )
}

///|
test "design 9: a host-required claim must be satisfied by the permit" {
  let request = make_request(required_claims=["partial_application_accepted"])
  assert_eq(
    admit_host_answer(request, Permit(binding(request, "approver-a"), [])).map(_ => {
      ()
    }),
    Err(MissingRequiredClaim("partial_application_accepted")),
  )
  assert_eq(
    admit_host_answer(
      request,
      Permit(binding(request, "approver-a"), [
        "partial_application_accepted", "partial_application_accepted",
      ]),
    ).map(_ => ()),
    Err(DuplicateClaim("partial_application_accepted")),
  )
  assert_eq(
    admit_host_answer(
      request,
      Permit(binding(request, "approver-a"), [
        "partial_application_accepted", "extra",
      ]),
    ).map(_ => ()),
    Err(UnrequestedClaim("extra")),
  )
  guard admit_host_answer(
      request,
      Permit(binding(request, "approver-a"), ["partial_application_accepted"]),
    )
    is Ok(AuthorizedForDispatch(HostPermit(_, _, claims))) else {
    abort("permit with claim")
  }
  assert_eq(claims, ["partial_application_accepted"])
  // A reject needs no claims.
  assert_true(
    admit_host_answer(request, Reject(binding(request, "approver-a")))
    is Ok(Deny(RejectedByHost(_, _))),
  )
  // Without a Host requirement, claims are not requested.
  let plain = make_request()
  assert_eq(
    admit_host_answer(
      plain,
      Permit(binding(plain, "approver-a"), ["partial_application_accepted"]),
    ).map(_ => ()),
    Err(UnrequestedClaim("partial_application_accepted")),
  )
}

///|
test "design 6: a shared account can receive different authority answers" {
  let request = make_request()
  assert_true(
    admit_host_answer(request, Permit(binding(request, "approver-a"), []))
    is Ok(AuthorizedForDispatch(_)),
  )
  assert_true(
    admit_host_answer(request, Reject(binding(request, "approver-b")))
    is Ok(Deny(_)),
  )
}

///|
test "request preparation validates its bound identities" {
  let delegated = delegated_match("accounts")
  let prepare = fn(
    configuration_cid : String,
    subject_cid : String,
    context_cid : String,
    authorities : Array[String],
    claims : Array[String],
  ) {
    prepare_decision_request(
      delegated,
      configuration_cid~,
      boundary=Acquisition,
      subject_cid~,
      context_cid~,
      answering_authorities=authorities,
      required_claims=claims,
    ).map(_ => ())
  }
  assert_eq(
    prepare("cfg", cid("2"), cid("3"), ["a"], []),
    Err(InvalidConfigurationCid),
  )
  assert_eq(
    prepare(cid("1"), cid("A"), cid("3"), ["a"], []),
    Err(InvalidSubjectCid),
  )
  assert_eq(prepare(cid("1"), cid("2"), "", ["a"], []), Err(InvalidContextCid))
  assert_eq(
    prepare(cid("1"), cid("2"), cid("3"), [], []),
    Err(NoAnsweringAuthority),
  )
  assert_eq(
    prepare(cid("1"), cid("2"), cid("3"), ["a", ""], []),
    Err(InvalidAnsweringAuthority),
  )
  assert_eq(
    prepare(cid("1"), cid("2"), cid("3"), ["a", "a"], []),
    Err(DuplicateAnsweringAuthority("a")),
  )
  assert_eq(
    prepare(cid("1"), cid("2"), cid("3"), ["a"], ["c", "c"]),
    Err(DuplicateRequiredClaim("c")),
  )
  assert_eq(
    prepare(cid("1"), cid("2"), cid("3"), ["a"], [""]),
    Err(InvalidRequiredClaim),
  )
  assert_eq(prepare(cid("1"), cid("2"), cid("3"), ["a"], ["c"]), Ok(()))
}

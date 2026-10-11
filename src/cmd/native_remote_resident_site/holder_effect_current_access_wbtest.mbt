///|
/// Authored Host ports test decision binding only. They do not prove a real
/// authenticated installation, Native Provider read or public Effect execution.
fn evidence_account() -> @authorization.AdmittedAccountConfiguration {
  @authorization.admit_account_configuration({
    account_id: "original-account",
    bootstrap: None,
    entries: [
      {
        entry_id: "original-read",
        outcome: @authorization.Allow,
        exclusions: [],
        scope: {
          principal: @authorization.AnyOf(["original-principal"]),
          connection: @authorization.AnyOf(["private-evidence"]),
          resource: @authorization.AnyOf(["original-run"]),
          operation: @authorization.AnyOf(["read"]),
        },
      },
    ],
  }).unwrap()
}

///|
fn evidence_subject() -> HolderEffectHostSubject {
  {
    principal: "original-principal",
    account_id: "original-account",
    configuration_cid: evidence_account().configuration_cid(),
    authorization_context_cid: "sha256:" + "b".repeat(64),
    read_connection: "private-evidence",
    read_resource: "original-run",
    publication_connection: "coordinator",
    publication_resource: "original-receiver",
  }
}

///|
test "current evidence decision keeps read and publication separate" {
  let subject = evidence_subject()
  let read = (_ : HolderEffectEvidencePurpose) => {
    Some({
      configuration: evidence_account(),
      delegated_action: None,
      current: () => true,
    })
  }
  assert_true(
    holder_effect_current_decision(
      subject,
      "sha256:" + "a".repeat(64),
      Read,
      read,
    ),
  )
  assert_true(
    !holder_effect_current_decision(
      subject,
      "sha256:" + "a".repeat(64),
      Publication,
      read,
    ),
  )
}

///|
test "current evidence decision refuses another principal resource and original policy" {
  let subject = evidence_subject()
  let read = (_ : HolderEffectEvidencePurpose) => {
    Some({
      configuration: evidence_account(),
      delegated_action: None,
      current: () => true,
    })
  }
  for
    foreign in [
      { ..subject, principal: "site-operator", },
      { ..subject, read_resource: "another-run", },
      { ..subject, account_id: "another-account", },
      { ..subject, configuration_cid: "sha256:" + "c".repeat(64), },
    ] {
    assert_true(
      !holder_effect_current_decision(
        foreign,
        "sha256:" + "a".repeat(64),
        Read,
        read,
      ),
    )
  }
}

///|
test "current evidence decision refuses missing or revoked admission without retry" {
  let reads = [0]
  let read = (_ : HolderEffectEvidencePurpose) => {
    reads[0] += 1
    None
  }
  assert_true(
    !holder_effect_current_decision(
      evidence_subject(),
      "sha256:" + "a".repeat(64),
      Read,
      read,
    ),
  )
  assert_eq(reads[0], 1)
  let revoked = (_ : HolderEffectEvidencePurpose) => {
    Some({
      configuration: evidence_account(),
      delegated_action: None,
      current: () => false,
    })
  }
  assert_true(
    !holder_effect_current_decision(
      evidence_subject(),
      "sha256:" + "a".repeat(64),
      Read,
      revoked,
    ),
  )
}

///|
test "current evidence decision rechecks permission after binding" {
  let checks = [0]
  let read = (_ : HolderEffectEvidencePurpose) => {
    Some({
      configuration: evidence_account(),
      delegated_action: None,
      current: () => {
        checks[0] += 1
        checks[0] == 1
      },
    })
  }
  assert_true(
    !holder_effect_current_decision(
      evidence_subject(),
      "sha256:" + "a".repeat(64),
      Read,
      read,
    ),
  )
  assert_eq(checks[0], 2)
}

///|
/// Native compile-only caller fences; these authored callbacks do not install
/// a real Host admission or claim physical HTTP/Account acceptance.
test "current evidence decision rejects original identity loss after permission selection" {
  let reads = [0]
  let read = (_ : HolderEffectEvidencePurpose) => {
    Some({
      configuration: evidence_account(),
      delegated_action: None,
      current: () => true,
    })
  }
  assert_false(
    holder_effect_current_decision(
      evidence_subject(),
      "sha256:" + "a".repeat(64),
      Read,
      read,
      current_original=() => {
        reads[0] += 1
        reads[0] == 1
      },
    ),
  )
  assert_eq(reads[0], 2)
}

///|
test "current evidence decision rechecks Account revocation after final original identity read" {
  let current = [true]
  let reads = [0]
  let read = (_ : HolderEffectEvidencePurpose) => {
    Some({
      configuration: evidence_account(),
      delegated_action: None,
      current: () => current[0],
    })
  }
  assert_false(
    holder_effect_current_decision(
      evidence_subject(),
      "sha256:" + "a".repeat(64),
      Read,
      read,
      current_original=() => {
        reads[0] += 1
        if reads[0] == 2 {
          current[0] = false
        }
        true
      },
    ),
  )
  assert_eq(reads[0], 2)
}

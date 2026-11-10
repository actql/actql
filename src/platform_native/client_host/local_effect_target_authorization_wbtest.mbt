///|
fn saved_effect_target_account_fixture(
  target? : (String, String)? = Some(("salesforce", "Opportunity")),
) -> @authorization.AdmittedAccountConfiguration {
  @authorization.admit_account_configuration_json(
    @authorization.local_mock_account_configuration({
      account_id: "operator-account",
      principal: "operator",
      control_connection: "local-host",
      sources: [("salesforce", "Opportunity")],
      model_tasks: [],
      request_target: None,
      update_target: target,
      signing_key_resource: None,
    }).unwrap(),
  ).unwrap()
}

///|
test "saved target binds delegated Effect to the original reviewer claims and exact subject" {
  let account = saved_effect_target_account_fixture()
  let tuple : @authorization.AccessTuple = {
    principal: "operator",
    connection: "salesforce",
    resource: "Opportunity",
    operation: "effect",
  }
  let preview = "sha256:" + "4".repeat(64)
  let context = "sha256:" + "5".repeat(64)
  let approval = @checkpoint.resumed_approval(
    @env.get_env_var("ACTQL_TEST_SAVED_EFFECT_APPROVAL_SINGLE_WIRE").unwrap(),
    native_checkpoint_limits(),
  ).unwrap()
  // This is only the private pure binding seam. Production obtains approval
  // from its cryptographically admitted original claim, not this fixture DATA.
  assert_true(
    @authorization.evaluate_account(account, tuple)
    is @authorization.Delegate(_),
  )
  assert_true(
    @authorization.evaluate_account(account, { ..tuple, operation: "write", })
    is @authorization.Deny(@authorization.NoMatch),
  )
  assert_true(
    @authorization.bind_dispatch_authorization(
      account,
      tuple,
      @authorization.EffectCommit,
      preview,
      context,
    )
    is Err(@authorization.UnresolvedDelegation),
  )
  let bound = bind_saved_effect_target_authorization(
    account,
    tuple,
    preview,
    context,
    approval,
    "native-reviewer",
    [@checkpoint.EffectScopeApproved],
  ).unwrap()
  assert_true(
    @authorization.dispatch_authorization_matches(
      bound,
      account,
      tuple,
      @authorization.EffectCommit,
      preview,
      context,
    ),
  )
  assert_false(
    @authorization.dispatch_authorization_matches(
      bound,
      account,
      { ..tuple, resource: "Contact", },
      @authorization.EffectCommit,
      preview,
      context,
    ),
  )
  assert_false(
    @authorization.dispatch_authorization_matches(
      bound,
      account,
      tuple,
      @authorization.EffectCommit,
      "sha256:" + "6".repeat(64),
      context,
    ),
  )
  assert_false(
    @authorization.dispatch_authorization_matches(
      bound,
      account,
      tuple,
      @authorization.EffectCommit,
      preview,
      "sha256:" + "6".repeat(64),
    ),
  )
  assert_true(
    bind_saved_effect_target_authorization(
      account,
      tuple,
      preview,
      context,
      approval,
      "another-reviewer",
      [@checkpoint.EffectScopeApproved],
    )
    is Err(@authorization.ForeignDecision),
  )
  assert_true(
    bind_saved_effect_target_authorization(
      account,
      tuple,
      preview,
      context,
      approval,
      "native-reviewer",
      [@checkpoint.EffectScopeApproved, @checkpoint.PartialApplicationAccepted],
    )
    is Err(@authorization.ForeignDecision),
  )
  let partial = @checkpoint.resumed_approval(
    @env.get_env_var("ACTQL_TEST_SAVED_EFFECT_APPROVAL_PARTIAL_WIRE").unwrap(),
    native_checkpoint_limits(),
  ).unwrap()
  assert_true(
    bind_saved_effect_target_authorization(
      account,
      tuple,
      preview,
      context,
      partial,
      "native-reviewer",
      [@checkpoint.EffectScopeApproved],
    )
    is Err(@authorization.ForeignDecision),
  )
  assert_true(
    bind_saved_effect_target_authorization(
      saved_effect_target_account_fixture(target=None),
      tuple,
      preview,
      context,
      approval,
      "native-reviewer",
      [@checkpoint.EffectScopeApproved],
    )
    is Err(@authorization.Denied),
  )
}

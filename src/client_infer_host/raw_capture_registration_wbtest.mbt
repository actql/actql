///|
// Ordinary preparation provides the actual compiled/Run/scope provenance.
// Policy applicability, current clock and Store availability are doubles here;
// this is not actual Node installation, nominal saved receipt or public INFER.
fn raw_registration_policy(
  active : Execution,
  prepared : @model.ModelPreparedCallSet,
  changed? : String = "",
) -> @publication.BoundModelRawCapturePolicy raise {
  let originals = [
    (
      "retention_contract", "raw-retention-fixture", "sha256:52b5203f74728093e67d207b2a3c33d0b4b9bc7c10753df1d052eca825cdbc32",
    ),
    (
      "metadata_retention_policy", "raw-metadata-fixture", "sha256:7a8f73a0a50704a2826e26b5a2d7179dcf9d29acb6d354abbc1885f558c7e895",
    ),
    (
      "clock_contract", "raw-clock-fixture", "sha256:d67d8062754216896c89195ae0552d2f80a725455e6d5da88e3211dff0c06479",
    ),
  ].map(entry => {
    let (kind, name, cid) = entry
    @publication.admit_hashed_effect_dependency_body(
      kind,
      cid,
      "{\"name\":\"" +
      name +
      "\",\"version\":\"actql-installed-local-policy/0.1\"}",
      8192,
      128,
      8,
    ).unwrap()
  })
  let compiled = active.run_binding.unwrap().compiled
  let (_, data_cid, data_wire) = @publication_host.client_compiled_run_evaluation_policy_body(
    compiled,
  ).unwrap()
  let data = @publication.admit_captured_effect_dependency_body(
    "data_policy",
    Some(data_cid),
    data_wire,
    8192,
    128,
    8,
  ).unwrap()
  let (_, definition, _) = @publication.model_invocation_scope_run(
    @model.prepared_model_scope(prepared).unwrap(),
  )
  let fields : Map[String, Json] = {
    "version": Json::string("actql-model-raw-capture-policy/0.1"),
    "purpose": Json::string("model_raw_capture"),
    "run_definition_cid": Json::string(definition),
    "scope_cid": Json::string(
      @publication.model_invocation_scope_cid(
        @model.prepared_model_scope(prepared).unwrap(),
      ),
    ),
    "model_task_cid": Json::string(
      @model.prepared_model_identities(prepared).unwrap().1,
    ),
    "response_profile_cid": Json::string(
      @environment.model_response_profile_identity(async_response_profile()),
    ),
    "store_authority_cid": Json::string("sha256:" + "e".repeat(64)),
    "effective_data_policy_cid": Json::string(data_cid),
    "retention_contract_cid": Json::string(
      @publication.captured_effect_dependency_body_cid(originals[0]),
    ),
    "metadata_retention_policy_cid": Json::string(
      @publication.captured_effect_dependency_body_cid(originals[1]),
    ),
    "clock_contract_cid": Json::string(
      @publication.captured_effect_dependency_body_cid(originals[2]),
    ),
    "selected_at": Json::string("2026-10-02T00:00:00.000Z"),
    "available_until": Json::string("2026-10-02T01:00:00.000Z"),
    "delete_by": Json::string("2026-10-02T02:00:00.000Z"),
    "extension_ceiling_at": Json::string("2026-10-02T02:00:00.000Z"),
    "metadata_delete_by": Json::string("2026-10-02T03:00:00.000Z"),
  }
  if !changed.is_empty() {
    fields[changed] = Json::string("sha256:" + "f".repeat(64))
  }
  let policy = @publication.seal_run_evidence_value(
    "model_raw_capture_policy",
    fixture_canonical(Json::object(fields)),
    8192,
    128,
    8,
  ).unwrap()
  @publication.bind_model_raw_capture_policy(
    policy,
    originals[0],
    originals[1],
    originals[2],
    data,
  ).unwrap()
}

///|
test "raw capture registration requires its distinct original account tuple" {
  for capture_allowed in [false, true] {
    let calls = Ref(0)
    let current = Ref(
      evidence_account(
        @authorization.Allow,
        operations=if capture_allowed {
          ["infer", "model_raw_capture"]
        } else {
          ["infer"]
        },
      ),
    )
    let at = Ref("2026-10-02T00:00:00.000Z")
    let (active, prepared, dispatch, work) = entry_gate_fixture(
      calls,
      current,
      at,
      Ref(Some(egress_fixture_observation())),
    )
    let scope = @model.prepared_model_scope(prepared).unwrap()
    let result = @publication_host.register_client_model_raw_capture(
      dispatch,
      scope,
      raw_registration_policy(active, prepared),
      async_response_profile(),
      async_response_installation(),
      None,
      current.val,
      at.val,
      "sha256:" + "e".repeat(64),
      () => true,
      () => Ok((current.val, at.val)),
    )
    if capture_allowed {
      let registration = result.unwrap()
      assert_true(
        @publication_host.client_model_raw_capture_matches(
          registration, dispatch, scope,
        ),
      )
      assert_true(
        @publication_host.check_client_model_raw_capture_current(registration)
        is Ok(_),
      )
    } else {
      assert_true(
        result is Err(@publication_host.Authorization(@authorization.Denied)),
      )
    }
    assert_eq(calls.val, 0)
    assert_true(cancel(active))
    assert_true(fixture_finish(active, initial_work=work) is Stopped(..))
    assert_true(cleanup(active).unwrap())
  }
}

///|
test "raw capture registration retains fixed selection and rechecks current facts" {
  let calls = Ref(0)
  let current = Ref(
    evidence_account(@authorization.Allow, operations=[
      "infer", "model_raw_capture",
    ]),
  )
  let at = Ref("2026-10-02T00:00:00.000Z")
  let available = Ref(true)
  let (active, prepared, dispatch, work) = entry_gate_fixture(
    calls,
    current,
    at,
    Ref(Some(egress_fixture_observation())),
  )
  let scope = @model.prepared_model_scope(prepared).unwrap()
  let policy = raw_registration_policy(active, prepared)
  let register = selected => {
    @publication_host.register_client_model_raw_capture(
      dispatch,
      scope,
      selected,
      async_response_profile(),
      async_response_installation(),
      None,
      current.val,
      at.val,
      "sha256:" + "e".repeat(64),
      () => available.val,
      () => Ok((current.val, at.val)),
    )
  }
  for
    field in [
      "run_definition_cid", "scope_cid", "model_task_cid", "response_profile_cid",
      "store_authority_cid",
    ] {
    assert_true(
      register(raw_registration_policy(active, prepared, changed=field))
      is Err(@publication_host.ForeignPolicy),
    )
  }
  let registration = register(policy).unwrap()
  let original_wire = @publication.run_evidence_value_json(
    @publication.model_raw_capture_policy_value(policy),
  )
  available.val = false
  assert_true(
    @publication_host.check_client_model_raw_capture_current(registration)
    is Err(@publication_host.UnavailableSelection),
  )
  available.val = true
  at.val = "2026-10-02T01:00:00.000Z"
  assert_true(
    @publication_host.check_client_model_raw_capture_current(registration)
    is Err(@publication_host.Expired),
  )
  at.val = "2026-10-02T00:00:00.000Z"
  current.val = evidence_account(@authorization.Deny, operations=[
    "infer", "model_raw_capture",
  ])
  assert_true(
    @publication_host.check_client_model_raw_capture_current(registration)
    is Err(@publication_host.Authorization(@authorization.ForeignDecision)),
  )
  assert_eq(
    @publication.run_evidence_value_json(
      @publication.model_raw_capture_policy_value(
        @publication_host.client_model_raw_capture_policy(registration),
      ),
    ),
    original_wire,
  )
  assert_eq(calls.val, 0)
  assert_true(cancel(active))
  assert_true(fixture_finish(active, initial_work=work) is Stopped(..))
  assert_true(cleanup(active).unwrap())
}

///|
test "raw capture registration policy issuer preserves the registered body without granting capture" {
  let calls = Ref(0)
  let current = Ref(
    evidence_account(@authorization.Allow, operations=["infer"]),
  )
  let at = Ref("2026-10-02T00:00:00.000Z")
  let (active, prepared, dispatch, work) = entry_gate_fixture(
    calls,
    current,
    at,
    Ref(Some(egress_fixture_observation())),
  )
  let scope = @model.prepared_model_scope(prepared).unwrap()
  // Existing independently assembled fixture fields/preimage remain unchanged.
  // Its originals only double installed applicability and physical Store custody.
  let expected = raw_registration_policy(active, prepared)
  let originals = @publication.model_raw_capture_policy_originals(expected)
  let issued = @publication_host.issue_client_model_raw_capture_policy(
    dispatch,
    scope,
    async_response_profile(),
    async_response_installation(),
    None,
    "sha256:" + "e".repeat(64),
    originals[0],
    originals[1],
    originals[2],
    originals[3],
    at.val,
    "2026-10-02T01:00:00.000Z",
    "2026-10-02T02:00:00.000Z",
    "2026-10-02T02:00:00.000Z",
    "2026-10-02T03:00:00.000Z",
  ).unwrap()
  assert_eq(
    @publication.run_evidence_value_json(
      @publication.model_raw_capture_policy_value(issued),
    ),
    @publication.run_evidence_value_json(
      @publication.model_raw_capture_policy_value(expected),
    ),
  )
  assert_eq(
    @publication.run_evidence_value_identity(
      @publication.model_raw_capture_policy_value(issued),
    ),
    @publication.run_evidence_value_identity(
      @publication.model_raw_capture_policy_value(expected),
    ),
  )
  assert_true(
    @publication_host.register_client_model_raw_capture(
      dispatch,
      scope,
      issued,
      async_response_profile(),
      async_response_installation(),
      None,
      current.val,
      at.val,
      "sha256:" + "e".repeat(64),
      () => true,
      () => Ok((current.val, at.val)),
    )
    is Err(@publication_host.Authorization(@authorization.Denied)),
  )
  assert_eq(calls.val, 0)
  assert_true(cancel(active))
  assert_true(fixture_finish(active, initial_work=work) is Stopped(..))
  assert_true(cleanup(active).unwrap())
}

///|
test "raw capture registration policy issuer refuses mismatched originals and fixed intervals" {
  let calls = Ref(0)
  let current = Ref(evidence_account(@authorization.Allow))
  let at = Ref("2026-10-02T00:00:00.000Z")
  let (active, prepared, dispatch, work) = entry_gate_fixture(
    calls,
    current,
    at,
    Ref(Some(egress_fixture_observation())),
  )
  let scope = @model.prepared_model_scope(prepared).unwrap()
  let originals = @publication.model_raw_capture_policy_originals(
    raw_registration_policy(active, prepared),
  )
  let issue = (installation, retention, data, available) => {
    @publication_host.issue_client_model_raw_capture_policy(
      dispatch,
      scope,
      async_response_profile(),
      installation,
      None,
      "sha256:" + "e".repeat(64),
      retention,
      originals[1],
      originals[2],
      data,
      at.val,
      available,
      "2026-10-02T02:00:00.000Z",
      "2026-10-02T02:00:00.000Z",
      "2026-10-02T03:00:00.000Z",
    )
  }
  let installed = async_response_installation()
  assert_true(
    issue(
      { ..installed, endpoint: "https://foreign.invalid/", },
      originals[0],
      originals[3],
      "2026-10-02T01:00:00.000Z",
    )
    is Err(@publication_host.ForeignProfile),
  )
  assert_true(
    issue(installed, originals[0], originals[2], "2026-10-02T01:00:00.000Z")
    is Err(@publication_host.ForeignPolicy),
  )
  assert_true(
    issue(installed, originals[1], originals[3], "2026-10-02T01:00:00.000Z")
    is Err(@publication_host.Evidence(_)),
  )
  for
    invalid in [
      "not-a-clock", "2026-10-01T23:59:59.000Z", "2026-10-02T03:00:00.000Z",
    ] {
    assert_true(
      issue(installed, originals[0], originals[3], invalid)
      is Err(@publication_host.Evidence(_)),
    )
  }
  assert_eq(calls.val, 0)
  assert_true(cancel(active))
  assert_true(fixture_finish(active, initial_work=work) is Stopped(..))
  assert_true(cleanup(active).unwrap())
}

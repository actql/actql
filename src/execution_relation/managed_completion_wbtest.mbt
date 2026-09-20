///|
fn managed_test_profile() -> ManagedExecutionProfile raise {
  admit_managed_execution_profile(managed_profile_body(), registry_limits()).unwrap()
}

///|
test "managed profile admits only the complete pinned contract within budget" {
  let body = managed_profile_body()
  let profile = admit_managed_execution_profile(body, registry_limits()).unwrap()
  assert_eq(
    managed_execution_profile_cid(profile),
    "sha256:161b405aa85064521a44076212bb266d93f166fa1b383ca8948a87923d797527",
  )
  assert_true(
    admit_managed_execution_profile(body, {
      ..registry_limits(),
      max_body_bytes: -1,
    })
    is Err(InvalidLimits),
  )
  assert_true(
    admit_managed_execution_profile(body, {
      ..registry_limits(),
      max_body_bytes: 1,
    })
    is Err(BodyLimit),
  )
  assert_true(
    admit_managed_execution_profile(registered_body(), registry_limits())
    is Err(UnsupportedProfile),
  )
}

///|
fn managed_test_material(
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  live : Ref[Bool],
) -> ManagedRetainedOutput[Int] {
  let stream = prepare_managed_output_values(
    owner,
    target,
    0,
    stream_value_limits(),
    100,
    managed_test_measure_limits(),
  ).unwrap()
  let port = prepare_managed_output_retention_port(stream, (
    receipt : ManagedOutputValueReceipt,
  ) => Some((receipt, 1, 0L, fn() { live.val }))).unwrap()
  retain_managed_output(port, finish_managed_output_values(stream).unwrap()).unwrap()
}

///|
test "managed completion requires execution verification and exact output rather than value receipt alone" {
  let owner = capture_fixture()
  let preparation = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(owner),
    ["select_1"],
    10000,
    1000,
  ).unwrap()
  let profile = managed_test_profile()
  let live = Ref(true)
  let material = managed_test_material(owner, Step(1), live)
  for mode in 0..<4 {
    let selected = if mode == 1 {
      managed_test_material(capture_fixture(), Step(1), Ref(true))
    } else {
      material
    }
    let port = prepare_managed_completion_port(
      profile,
      preparation,
      Step(1),
      1000,
      10000,
      (_ : Unit) => if mode == 0 { None } else { Some(selected) },
    ).unwrap()
    if mode == 2 {
      cancel_managed_completion_port(port) |> ignore
    }
    let result = complete_managed_output(port, ())
    match mode {
      0 | 2 => assert_true(result is Err(Unverified))
      1 => assert_true(result is Err(ForeignOutput))
      _ => {
        let output = result.unwrap()
        assert_eq(managed_completed_output_row_count(output), 0)
        assert_true(
          managed_completed_output_matches_port(output, owner, Step(1)),
        )
        assert_true(managed_completed_output_matches_material(output, material))
        assert_true(managed_completed_same_occurrence(output, output))
        let reference = managed_completed_reference(output)
        assert_true(managed_completed_reference_available(reference))
        assert_true(managed_completed_reference_matches(reference, output))
        assert_eq(managed_completed_output_storage_bytes(output), Some(0L))
        let another_port = prepare_managed_completion_port(
          profile,
          preparation,
          Step(1),
          1000,
          10000,
          (_ : Unit) => Some(material),
        ).unwrap()
        let another = complete_managed_output(another_port, ()).unwrap()
        assert_false(managed_completed_same_occurrence(output, another))
        assert_false(managed_completed_reference_matches(reference, another))
        assert_eq(
          managed_completed_profile_cid(output),
          managed_execution_profile_cid(profile),
        )
        live.val = false
        assert_false(managed_completed_output_available(output))
        assert_false(managed_completed_reference_available(reference))
        assert_false(managed_completed_reference_matches(reference, output))
        assert_true(managed_completed_output_storage_bytes(output) is None)
        assert_eq(managed_completed_output_row_count(output), 0)
      }
    }
    assert_true(complete_managed_output(port, ()) is Err(Unverified))
  }
}

///|
test "managed completion distinguishes delayed identity from source lifetime" {
  let owner = capture_fixture()
  let preparation = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(owner),
    ["select_1"],
    10000,
    1000,
  ).unwrap()
  let live = Ref(true)
  let material = managed_test_material(owner, Step(1), live)
  let contract = ordered_rows_canonical_contract_cid()
  let cid = "sha256:" + "2".repeat(64)
  let obligations = prepare_managed_obligations(
    owner,
    [
      {
        domain: OrderedRows,
        subject: TaskOutput,
        occurrence: None,
        need: EstablishedBy(BeforeDiscard),
      },
    ],
    ManagedUse,
    MaterialBinding,
    1,
  ).unwrap()
  let capability = register_managed_identity_issuance_capability(
    OrderedRows,
    TaskOutput,
    None,
    contract,
  ).unwrap()
  assert_true(managed_identity_issuance_capability_same(capability, capability))
  let requirement = managed_obligations_identities(obligations)[0]
  let execution_attempt = issue_managed_execution_attempt()
  let permit = authorize_managed_identity_execution_attempt(
    capability, execution_attempt, preparation, requirement,
  ).unwrap()
  let issuer = try_bind_managed_identity_issuer(permit, material, source => {
    if physical_equal(source, material) {
      Some(cid)
    } else {
      None
    }
  }).unwrap()
  let port = prepare_managed_completion_port(
    managed_test_profile(),
    preparation,
    Step(1),
    1000,
    10000,
    (_ : Unit) => Some(material),
    obligations~,
    identity_issuer=issuer,
  ).unwrap()
  let output = complete_managed_output(port, ()).unwrap()
  assert_eq(
    managed_completed_identity_status(output, OrderedRows, TaskOutput),
    Some(UnestablishedSourceRetained),
  )
  assert_false(managed_completed_deadline_satisfied(output, BeforeDiscard))
  assert_true(managed_completed_output_available(output))
  establish_managed_completed_identity(output, OrderedRows, TaskOutput).unwrap()
  assert_true(managed_completed_deadline_satisfied(output, BeforeDiscard))
  assert_eq(
    managed_completed_identity_status(output, OrderedRows, TaskOutput),
    Some(EstablishedSourceRetained(contract, cid)),
  )
  establish_managed_completed_identity(output, OrderedRows, TaskOutput).unwrap()
  live.val = false
  assert_eq(
    managed_completed_identity_status(output, OrderedRows, TaskOutput),
    Some(EstablishedSourceUnavailable(contract, cid)),
  )

  let unavailable_live = Ref(true)
  let unavailable_material = managed_test_material(
    owner,
    Step(1),
    unavailable_live,
  )
  let unavailable_port = prepare_managed_completion_port(
    managed_test_profile(),
    preparation,
    Step(1),
    1000,
    10000,
    (_ : Unit) => Some(unavailable_material),
  ).unwrap()
  let unavailable = complete_managed_output(unavailable_port, ()).unwrap()
  assert_true(
    establish_managed_completed_identity(unavailable, OrderedRows, TaskOutput)
    is Err(IssuerUnavailable),
  )
  assert_true(managed_completed_output_available(unavailable))
  unavailable_live.val = false
  assert_eq(
    managed_completed_identity_status(unavailable, OrderedRows, TaskOutput),
    Some(UnestablishedSourceUnavailable),
  )
  assert_true(
    establish_managed_completed_identity(unavailable, OrderedRows, TaskOutput)
    is Err(SourceUnavailable),
  )
}

///|
test "managed completion establishes plural Named Result occurrences independently" {
  let owner = result_export_owner()
  let preparation = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(owner),
    ["select_1"],
    10000,
    1000,
  ).unwrap()
  let body = "{\"first\":{\"from\":\"selected\",\"fields\":[\"s\"]},\"second\":{\"from\":\"selected\",\"fields\":[\"n\"]}}"
  let first = result_export_occurrence(owner, "first", body)
  let second = result_export_occurrence(owner, "second", body)
  let first_requirement : ManagedIdentityRequirement = {
    domain: LogicalRelation,
    subject: NamedResult,
    occurrence: Some(first),
    need: EstablishedBy(BeforePublication),
  }
  let second_requirement : ManagedIdentityRequirement = {
    domain: LogicalRelation,
    subject: NamedResult,
    occurrence: Some(second),
    need: EstablishedBy(BeforePublication),
  }
  let obligations = prepare_managed_obligations(
    owner,
    [first_requirement, second_requirement],
    LogicalContentAddressed,
    MaterialBinding,
    2,
  ).unwrap()
  let material = managed_test_material(owner, Step(1), Ref(true))
  let attempt = issue_managed_execution_attempt()
  let contract = logical_relation_canonical_contract_cid()
  let first_capability = register_managed_identity_issuance_capability(
    LogicalRelation,
    NamedResult,
    Some(first),
    contract,
  ).unwrap()
  let second_capability = register_managed_identity_issuance_capability(
    LogicalRelation,
    NamedResult,
    Some(second),
    contract,
  ).unwrap()
  let first_issuer = try_bind_managed_identity_issuer(
    authorize_managed_identity_execution_attempt(
      first_capability, attempt, preparation, first_requirement,
    ).unwrap(),
    material,
    _ => Some("sha256:" + "1".repeat(64)),
  ).unwrap()
  let second_issuer = try_bind_managed_identity_issuer(
    authorize_managed_identity_execution_attempt(
      second_capability, attempt, preparation, second_requirement,
    ).unwrap(),
    material,
    _ => Some("sha256:" + "2".repeat(64)),
  ).unwrap()
  let port = prepare_managed_completion_port(
    managed_test_profile(),
    preparation,
    Step(1),
    1000,
    10000,
    (_ : Unit) => Some(material),
    obligations~,
    identity_issuers=[first_issuer, second_issuer],
    attempt~,
  ).unwrap()
  let output = complete_managed_output(port, ()).unwrap()
  assert_eq(
    managed_completed_identity_requirement_status(output, first_requirement),
    Some(UnestablishedSourceRetained),
  )
  assert_eq(
    managed_completed_identity_requirement_status(output, second_requirement),
    Some(UnestablishedSourceRetained),
  )
  establish_managed_completed_identity_requirement(output, first_requirement).unwrap()
  assert_eq(
    managed_completed_identity_requirement_status(output, first_requirement),
    Some(EstablishedSourceRetained(contract, "sha256:" + "1".repeat(64))),
  )
  assert_eq(
    managed_completed_identity_requirement_status(output, second_requirement),
    Some(UnestablishedSourceRetained),
  )
  assert_false(managed_completed_deadline_satisfied(output, BeforePublication))
  establish_managed_completed_identity_requirement(output, second_requirement).unwrap()
  assert_true(managed_completed_deadline_satisfied(output, BeforePublication))
  assert_eq(
    managed_completed_identity_requirement_status(output, second_requirement),
    Some(EstablishedSourceRetained(contract, "sha256:" + "2".repeat(64))),
  )
  assert_true(
    managed_completed_identity_status(output, LogicalRelation, NamedResult)
    is None,
  )
}

///|
test "managed identity authority rejects another attempt generation and canonical contract" {
  let owner = capture_fixture()
  let sequence = prepared_sequence(owner)
  let preparation = prepare_completion(
    registered_relation_contracts(),
    sequence,
    ["select_1"],
    10000,
    1000,
  ).unwrap()
  let another_attempt = prepare_completion(
    registered_relation_contracts(),
    sequence,
    ["select_1"],
    10000,
    1000,
  ).unwrap()
  let material = managed_test_material(owner, Step(1), Ref(true))
  let another_generation = managed_test_material(owner, Step(1), Ref(true))
  let requirement : ManagedIdentityRequirement = {
    domain: OrderedRows,
    subject: TaskOutput,
    occurrence: None,
    need: EstablishedBy(BeforeDiscard),
  }
  let obligations = prepare_managed_obligations(
    owner,
    [requirement],
    ManagedUse,
    MaterialBinding,
    1,
  ).unwrap()
  assert_true(
    register_managed_identity_issuance_capability(
      OrderedRows,
      TaskOutput,
      None,
      "sha256:" + "9".repeat(64),
    )
    is Err(InvalidCapability),
  )
  let capability = register_managed_identity_issuance_capability(
    OrderedRows,
    TaskOutput,
    None,
    ordered_rows_canonical_contract_cid(),
  ).unwrap()
  let execution_attempt = issue_managed_execution_attempt()
  let other_execution_attempt = issue_managed_execution_attempt()
  let permit = authorize_managed_identity_execution_attempt(
    capability, execution_attempt, preparation, requirement,
  ).unwrap()
  let issuer = try_bind_managed_identity_issuer(permit, material, _ => {
    Some("sha256:" + "4".repeat(64))
  }).unwrap()
  assert_true(
    try_bind_managed_identity_issuer(permit, another_generation, _ => None)
    is Err(ForeignMaterial),
  )
  let retry_permit = authorize_managed_identity_execution_attempt(
    capability, execution_attempt, preparation, requirement,
  ).unwrap()
  try_bind_managed_identity_issuer(retry_permit, another_generation, _ => {
    Some("sha256:" + "4".repeat(64))
  }).unwrap()
  |> ignore
  let detached_permit = authorize_managed_identity_attempt(
    capability, preparation, requirement,
  ).unwrap()
  let detached_issuer = bind_managed_identity_issuer(
    detached_permit,
    material,
    _ => Some("sha256:" + "4".repeat(64)),
  )
  assert_true(
    prepare_managed_completion_port(
      managed_test_profile(),
      preparation,
      Step(1),
      1000,
      10000,
      (_ : Unit) => Some(material),
      obligations~,
      identity_issuer=detached_issuer,
      attempt=execution_attempt,
    )
    is Err(ForeignOutput),
  )
  assert_true(
    prepare_managed_completion_port(
      managed_test_profile(),
      preparation,
      Step(1),
      1000,
      10000,
      (_ : Unit) => Some(material),
      obligations~,
      identity_issuer=issuer,
      attempt=other_execution_attempt,
    )
    is Err(ForeignOutput),
  )
  assert_true(
    prepare_managed_completion_port(
      managed_test_profile(),
      another_attempt,
      Step(1),
      1000,
      10000,
      (_ : Unit) => Some(material),
      obligations~,
      identity_issuer=issuer,
    )
    is Err(ForeignOutput),
  )
  let another_deadline = prepare_managed_obligations(
    owner,
    [
      {
        domain: OrderedRows,
        subject: TaskOutput,
        occurrence: None,
        need: EstablishedBy(BeforePublication),
      },
    ],
    ManagedUse,
    MaterialBinding,
    1,
  ).unwrap()
  assert_true(
    prepare_managed_completion_port(
      managed_test_profile(),
      preparation,
      Step(1),
      1000,
      10000,
      (_ : Unit) => Some(material),
      obligations=another_deadline,
      identity_issuer=issuer,
    )
    is Err(ForeignOutput),
  )
  let generation_port = prepare_managed_completion_port(
    managed_test_profile(),
    preparation,
    Step(1),
    1000,
    10000,
    (_ : Unit) => Some(another_generation),
    obligations~,
    identity_issuer=issuer,
  ).unwrap()
  assert_true(
    complete_managed_output(generation_port, ()) is Err(ForeignOutput),
  )
}

///|
test "managed completion cannot revive cancellation from a verifier callback" {
  let owner = capture_fixture()
  let preparation = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(owner),
    ["select_1"],
    10000,
    1000,
  ).unwrap()
  let material = managed_test_material(owner, Step(1), Ref(true))
  let holder : Ref[ManagedCompletionPort[Unit, Int]?] = Ref(None)
  let cancelled = Ref(false)
  let reentrant_rejected = Ref(false)
  let port = prepare_managed_completion_port(
    managed_test_profile(),
    preparation,
    Step(1),
    1000,
    10000,
    (_ : Unit) => {
      let own_port = holder.val.unwrap()
      reentrant_rejected.val = complete_managed_output(own_port, ())
        is Err(Unverified)
      cancelled.val = cancel_managed_completion_port(own_port)
      Some(material)
    },
  ).unwrap()
  holder.val = Some(port)
  assert_true(complete_managed_output(port, ()) is Err(Unverified))
  assert_true(cancelled.val)
  assert_true(reentrant_rejected.val)
  assert_true(complete_managed_output(port, ()) is Err(Unverified))
  holder.val = None
}

///|
test "managed completion seals exact input bindings without retaining upstream liveness" {
  let owner = capture_fixture()
  let upstream_live = Ref(true)
  let (source, _) = retained_fixture(owner, upstream_live)
  let input = retained_scan_fixture(owner, source)
  let receiver = producer_read_receiver(input)
  let preparation = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    ["select_0"],
    10000,
    1000,
  ).unwrap()
  let material = managed_test_material(receiver, Step(0), Ref(true))
  let profile = managed_test_profile()
  for revoke_during_verification in [false, true] {
    upstream_live.val = true
    let port = prepare_managed_completion_port(
      profile,
      preparation,
      Step(0),
      1000,
      10000,
      (_ : Unit) => {
        if revoke_during_verification {
          upstream_live.val = false
        }
        Some(material)
      },
      inputs=[input],
    ).unwrap()
    let result = complete_managed_output(port, ())
    if revoke_during_verification {
      assert_true(result is Err(ForeignInputs))
    } else {
      let output = result.unwrap()
      upstream_live.val = false
      assert_true(managed_completed_output_available(output))
      assert_true(managed_completed_output_matches_inputs(output, [input]))
      assert_false(managed_completed_output_matches_inputs(output, []))
    }
  }
}

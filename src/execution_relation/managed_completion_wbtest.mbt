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

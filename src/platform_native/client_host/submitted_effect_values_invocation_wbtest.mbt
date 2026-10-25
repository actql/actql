///|
// Real adopted Host, accepted packet and original first-bound captured Run.
// The existing Core test Ledger is explicit, not normal installed funding.
fn submitted_values_invocation_fixture(
  name : String,
  policy? : Bool = true,
  utc? : () -> String = () => "2026-10-10T00:00:01.000Z",
  epoch? : () -> Double = () => 1003.0,
) -> (NativeLocalHostConnection, NativeClientSubmittedEffectValuesWork) raise {
  let host = effect_values_policy_test_host(name)
  let (reference, preparation, request, allowed, definition, issued) = effect_values_policy_test_prepared(
    host, name,
  )
  effect_values_policy_test_ok(
    effect_values_policy_test_accept(
      host,
      reference,
      preparation,
      request,
      allowed,
      definition,
      issued,
      file=if policy { Some("selected.run") } else { None },
    ),
    "invocation.accept",
  )
  |> ignore
  let materials = effect_values_policy_test_ok(
    @host.bind_prepared_client_effect_original_materials(
      allowed,
      definition,
      issued,
      request=Some(request),
    ),
    "invocation.original.materials",
  )
  let (bound, captured) = submitted_effect_values_fixture_capture(materials)
  let (installed, values, fragment) = effect_values_work_test_bodies()
  let work = host.open_submitted_effect_values_work(
      epoch_test_crypto(),
      "operator",
      "cli",
      reference,
      request,
      materials,
      bound,
      captured,
      installed,
      values,
      fragment,
      None,
      64,
      1000,
      utc,
      epoch,
    )
    |> submitted_effect_values_fixture_opened
  (host, work)
}

///|
test "Native submitted Values Invocation uses the saved Policy and original compilation without changing the Run" {
  let (host, work) = submitted_values_invocation_fixture(
    "values-invocation-original",
  )
  defer host.close() |> ignore
  defer work.close() |> ignore
  let request = work.binding.request
  let before = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  let template = @host.client_effect_compilation_template(
    work.binding.materials.compilation,
  )
  let template_cid = @publication.run_evidence_value_identity(template)
  // Independently specified canonical bytes, never the returned Observation.
  let expected = "{\"capture_completed_at\":null,\"capture_started_at\":null,\"captured_input_artifact_cids\":[],\"consistency\":\"no_external_sources\",\"data_policy_cid\":\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\",\"invocation_template_cid\":\"" +
    template_cid +
    "\",\"replayability\":{\"availability_evidence_cids\":[],\"materialized\":false},\"source_evidence_cids\":[],\"version\":\"actql-observation-set/0.1\"}"
  let expected_observation_cid = "sha256:" + @sha.hex(@utf8.encode(expected))
  let expected_invocation = "{\"invocation_template_cid\":\"" +
    template_cid +
    "\",\"observation_set_cid\":\"" +
    expected_observation_cid +
    "\",\"version\":\"actql-run-invocation/0.1\"}"
  let expected_observation_wire = expected.replace(
    old=",\"replayability\"",
    new=",\"observation_set_cid\":\"" +
      expected_observation_cid +
      "\",\"replayability\"",
  )
  let expected_invocation_cid = "sha256:" +
    @sha.hex(@utf8.encode(expected_invocation))
  let expected_invocation_wire = expected_invocation.replace(
    old="{\"invocation_template_cid\"",
    new="{\"invocation_cid\":\"" +
      expected_invocation_cid +
      "\",\"invocation_template_cid\"",
  )
  let (observation, invocation) = effect_values_policy_test_ok(
    work.original_invocation(65536, 8192, 64),
    "invocation.original",
  )
  assert_eq(
    @publication.run_evidence_value_json(observation),
    expected_observation_wire,
  )
  assert_eq(
    @publication.run_evidence_value_identity(observation),
    expected_observation_cid,
  )
  assert_eq(
    @publication.publication_contract_json(invocation),
    expected_invocation_wire,
  )
  assert_eq(
    @publication.publication_contract_identity(invocation),
    expected_invocation_cid,
  )
  let (_, again) = work.original_invocation(65536, 8192, 64).unwrap()
  assert_eq(
    @publication.publication_contract_json(again),
    expected_invocation_wire,
  )
  assert_eq(
    run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
    before,
  )
  assert_true(
    physical_equal(work.run_for_capture().unwrap(), work.work.captured),
  )
  assert_false(host.journal.claim_physical_start(request, true).unwrap())
}

///|
test "Native submitted Values Invocation refuses a missing accepted Policy without backfill or another claim" {
  let (host, work) = submitted_values_invocation_fixture(
    "values-invocation-legacy",
    policy=false,
  )
  defer host.close() |> ignore
  defer work.close() |> ignore
  let request = work.binding.request
  let before = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  assert_true(
    work.original_invocation(65536, 8192, 64)
    is Err(Policy(Journal(PublicationPolicy(@checked.MissingDependency)))),
  )
  assert_eq(
    run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
    before,
  )
  assert_false(host.journal.claim_physical_start(request, true).unwrap())
}

///|
test "Native submitted Values Invocation rechecks saved Policy after the final UTC callback" {
  let armed = Ref(false)
  let calls = Ref(0)
  let original : Ref[
    (NativeLocalHostConnection, NativeClientSubmittedEffectValuesWork)?,
  ] = Ref(None)
  let (host, work) = submitted_values_invocation_fixture(
    "values-invocation-policy-loss",
    utc=() => {
      if armed.val {
        calls.val += 1
        if calls.val == 2 && original.val is Some((host, work)) {
          host.journal
          .transaction(() => {
            let row = host.journal
              .retained(work.binding.request)
              .unwrap()
              .unwrap()
            host.journal
            .save({ ..row, publication_policy_originals: None, })
            .map(_ => ())
          })
          .unwrap()
        }
      }
      "2026-10-10T00:00:01.000Z"
    },
  )
  defer host.close() |> ignore
  defer work.close() |> ignore
  original.val = Some((host, work))
  armed.val = true
  let result = work.original_invocation(65536, 8192, 64)
  original.val = None
  assert_eq(calls.val, 2)
  assert_true(
    result
    is Err(Policy(Journal(PublicationPolicy(@checked.MissingDependency)))),
  )
  let row = host.journal.retained(work.binding.request).unwrap().unwrap()
  assert_true(row.publication_policy_originals is None)
  assert_true(row.physical_start_claimed)
  assert_false(
    host.journal.claim_physical_start(work.binding.request, true).unwrap(),
  )
}

///|
test "Native submitted Values Invocation retains terminal cleanup lifetime and original expiry" {
  for retire in [false, true] {
    let armed = Ref(false)
    let calls = Ref(0)
    let original : Ref[NativeClientSubmittedEffectValuesWork?] = Ref(None)
    let (host, work) = submitted_values_invocation_fixture(
      if retire {
        "values-invocation-retired"
      } else {
        "values-invocation-expired"
      },
      utc=() => {
        if armed.val {
          calls.val += 1
          if calls.val == 2 {
            if retire && original.val is Some(work) {
              work.close() |> ignore
            }
            return if retire {
              "2026-10-10T00:00:01.000Z"
            } else {
              "2026-10-11T00:00:00.000Z"
            }
          }
        }
        "2026-10-10T00:00:01.000Z"
      },
    )
    original.val = Some(work)
    armed.val = true
    let result = work.original_invocation(65536, 8192, 64)
    original.val = None
    assert_true(
      if retire {
        result is Err(Work(Work(Unavailable)))
      } else {
        result is Err(Work(Work(OriginalRunNotCurrent)))
      },
    )
    assert_true(
      host.journal.retained(work.binding.request).unwrap().unwrap().physical_start_claimed,
    )
    assert_true(work.close())
    host.close().unwrap()
  }
}

///|
test "Native submitted Values Invocation preserves encoder refusal and refuses closed Work before callbacks" {
  let calls = Ref(0)
  let (host, work) = submitted_values_invocation_fixture(
    "values-invocation-bounds",
    epoch=() => {
      calls.val += 1
      1003.0
    },
  )
  defer host.close() |> ignore
  assert_true(
    work.original_invocation(1, 1, 1)
    is Err(Evidence(@publication.RunEvidenceEncoding)),
  )
  assert_true(work.original_invocation(65536, 8192, 64) is Ok(_))
  assert_true(work.close())
  let before = calls.val
  assert_true(
    work.original_invocation(65536, 8192, 64) is Err(Work(Work(Unavailable))),
  )
  assert_eq(calls.val, before)
}

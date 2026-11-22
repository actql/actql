///|
fn policy_handoff_originals() -> (
  @checked.CheckedProgram,
  @checked.PublicationSourcePolicy,
) raise {
  let prepared = normalization_source_fixture(true)
  let program = @checked.effect_program_static_checked_computation(
    prepared_client_effect_computation_candidate(prepared),
  )
  let cid = prepared_client_effect_publication_data_policy_cid(prepared).unwrap()
  for unit in 0..<@checked.unit_count(program) {
    for index in 0..<@checked.unit_publication_count(program, unit).unwrap() {
      let publication = @checked.unit_publication_at(program, unit, index).unwrap()
      if @checked.publication_source_policy(publication) is Some(policy) &&
        policy.cid == cid {
        return (program, policy)
      }
    }
  }
  fail("original checked publication policy")
}

///|
test "policy receiver gets complete original admitted bodies with exact preconstruction and parser dimensions" {
  let (program, policy) = policy_handoff_originals()
  let legacy = checked_client_source_policy_bodies(
    program,
    policy,
    65536,
    8192,
    64,
    1000,
    retain_catalog=true,
  ).unwrap()
  let admitted : Array[@publication.CapturedEffectDependencyBody] = []
  let dimensions : Array[(Int, Int, Int)] = []
  let emissions : Array[(Int, Int, Int)] = []
  let prepare_emit = (bytes, nodes, depth) => {
    emissions.push((bytes, nodes, depth))
    true
  }
  let received : Array[
    (@publication.CapturedEffectDependencyBody, Int, (Int, Int, Int)),
  ] = []
  let raw = checked_client_source_policy_bodies(
    program,
    policy,
    65536,
    8192,
    64,
    1000,
    retain_catalog=true,
    before_emit=Some(prepare_emit),
    before_catalog_emit=Some(prepare_emit),
    before_body=Some((bytes, nodes, depth) => {
      dimensions.push((bytes, nodes, depth))
      true
    }),
    admitted_body=Some((body, bytes) => {
      if dimensions.is_empty() {
        return Err(@checked.ForeignBody)
      }
      let last = dimensions[dimensions.length() - 1]
      // Retain the actual opaque body, not a wire proxy or reconstructed value.
      admitted.push(body)
      received.push((body, bytes, last))
      Ok(())
    }),
  ).unwrap()
  assert_true(raw.is_empty())
  assert_eq(emissions, dimensions)
  assert_eq(dimensions.length(), admitted.length())
  for (body, bytes, last) in received {
    let wire = @publication.captured_effect_dependency_body_json(body)
    assert_eq(last.0, bytes)
    assert_eq(bytes, @utf8.encode(wire).length())
    assert_eq(last.1, source_dependency_json_nodes(@json.parse(wire)))
  }
  assert_eq(
    admitted.map(body => {
      (
        @publication.captured_effect_dependency_body_kind(body),
        @publication.captured_effect_dependency_body_cid(body),
        @publication.captured_effect_dependency_body_json(body),
      )
    }),
    legacy,
  )
  // Independently pinned existing public data-policy identity remains exact.
  assert_true(
    admitted.any(body => {
      @publication.captured_effect_dependency_body_kind(body) == "data_policy" &&
      @publication.captured_effect_dependency_body_cid(body) ==
      "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf"
    }),
  )
}

///|
test "policy constructor or parser refusal cannot transfer an admitted body" {
  let (program, policy) = policy_handoff_originals()
  for refuse in [1, 2] {
    let calls = Ref(0)
    let received = Ref(0)
    let result = checked_client_source_policy_bodies(
      program,
      policy,
      65536,
      8192,
      64,
      1000,
      retain_catalog=true,
      before_body=Some((_, _, _) => {
        calls.val += 1
        calls.val != refuse
      }),
      admitted_body=Some((_, _) => {
        received.val += 1
        Ok(())
      }),
    )
    assert_true(result is Err(@checked.BudgetExceeded))
    assert_eq(received.val, 0)
  }
  for lost_after in [1, 2] {
    let phases = Ref(0)
    let received = Ref(0)
    let prepare = (_, _, _) => {
      phases.val += 1
      true
    }
    let result = checked_client_source_policy_bodies(
      program,
      policy,
      65536,
      8192,
      64,
      1000,
      retain_catalog=true,
      before_emit=Some(prepare),
      before_body=Some(prepare),
      current=Some(() => phases.val < lost_after),
      admitted_body=Some((_, _) => {
        received.val += 1
        Ok(())
      }),
    )
    assert_true(result is Err(@checked.ForeignBody))
    assert_eq(phases.val, lost_after)
    assert_eq(received.val, 0)
  }
  let refused = checked_client_source_policy_bodies(
    program,
    policy,
    65536,
    8192,
    64,
    1000,
    retain_catalog=true,
    admitted_body=Some((_, _) => Err(@checked.ForeignBody)),
  )
  assert_true(refused is Err(@checked.ForeignBody))
}

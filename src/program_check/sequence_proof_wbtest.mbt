///|
// Admitted fixture input, not expected conversion output.
fn sequence_fixture_proof(
  law : String,
  step : Int,
  value : Int,
  inputs : Array[String],
  derivation : String,
) -> @wire.ProgramProofClaim {
  let inputs = inputs.copy()
  inputs.sort()
  let quoted = inputs.map(v => "\"" + v + "\"").join(",")
  let subject = "checked-step:" + step.to_string()
  let body = "{\"inputs\":[" +
    quoted +
    "],\"law_id\":\"" +
    law +
    "\",\"semantic_ref\":\"" +
    subject +
    "\",\"unit\":\"rows\",\"value\":" +
    value.to_string() +
    ",\"version\":\"actql-bound-proof/0.1\"}"
  let proof_cid = "sha256:" + @sha.hex(@utf8.encode(body))
  let dependencies = inputs.copy()
  dependencies.push(proof_cid)
  dependencies.sort()
  let distinct : Array[String] = []
  for cid in dependencies {
    if distinct.last() != Some(cid) {
      distinct.push(cid)
    }
  }
  let deps = distinct.map(v => "\"" + v + "\"").join(",")
  let raw = "{\"dependencies\":[" +
    deps +
    "],\"derivation\":" +
    derivation +
    ",\"law_id\":\"" +
    law +
    "\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"" +
    proof_cid +
    "\",\"semantic_ref\":\"" +
    subject +
    "\"},\"unit\":\"rows\",\"value\":" +
    value.to_string() +
    ",\"version\":\"actql-bound-witness/0.1\""
  let cid = "sha256:" + @sha.hex(@utf8.encode(raw + "}"))
  let caps : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }
  let witness = @wire.admit(
    @utf8.encode(raw + ",\"witness_cid\":\"" + cid + "\"}"),
    cid,
    caps,
  ).unwrap()
  @wire.bind_program_proof(@utf8.encode(body), witness, caps).unwrap()
}

///|
test "sequence proof conversion retains Host operands through downstream take" {
  for repetitions in [1, 2] {
    let budget = IdentityBudget::{
      work: 100000000,
      bytes: 10000000,
      nodes: 1000000,
      depth: 100,
    }
    let programs : Array[CheckedProgram] = []
    let (_, _, _, _, units) = local_construction_fixture(
      budget,
      through_check=true,
      checked_results=programs,
      second_stage=true,
      parameters=true,
      tea=true,
      second_sequence_capacity=true,
      second_steps=sequence_test_steps(false, "allow", "adjacent", "").replace(
        old=",{\"select\"",
        new=",{\"take\":4},{\"select\"",
      ),
      second_result_from="selected",
      extra_step_budget=3,
    )
    let selected = sequence_limit_selection(
        unit_sequence_limit_at(programs[0], 1, 0).unwrap(),
      ).limits
    let pipeline = units[1].pipeline
    let policy = @sequence.selected_policy(selected)
    let witnesses : Array[@wire.WireWitness] = []
    let limits : Array[(Bytes, String)] = []
    for scope in [@sequence.MatchesPerKey, OutputRows] {
      let original = @sequence.host_limit(selected, scope)
      let node = @derivation.minimum_candidate_at(
          @wire.limit_minimum(original),
          0,
        ).unwrap().node
      let host = @wire.claim_at(@wire.limit_claims(original), node).unwrap()
      witnesses.push(host)
      let encoded = publication_metadata(
        w => @wire.emit(host, w) catch { e => raise Encoding(e) },
        budget,
      )
      let text = @utf8.decode(encoded) catch {
        _ => fail("invalid fixture encoding")
      }
      let occurrences = Array::make(repetitions, text).join(",")
      let suffix = if scope == MatchesPerKey {
        "matches-per-key"
      } else {
        "output"
      }
      let unit = if scope == MatchesPerKey { "matches_per_key" } else { "rows" }
      let raw = "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[" +
        occurrences +
        "],\"effective_max\":1000,\"enforcement\":\"engine_atomic\",\"subject_ref\":\"sequence:checked-step:0:" +
        suffix +
        "\",\"unit\":\"" +
        unit +
        "\",\"version\":\"actql-resolved-limit/0.1\"}"
      let cid = "sha256:" + @sha.hex(@utf8.encode(raw))
      limits.push(
        (
          @utf8.encode(
            raw.replace(
              old="\"subject_ref\":",
              new="\"resolved_limit_cid\":\"" + cid + "\",\"subject_ref\":",
            ),
          ),
          cid,
        ),
      )
    }
    let host = witnesses[1]
    let host_cid = @wire.cid(host)
    let seq_proof = sequence_fixture_proof(
      "actql.bound.sequence-output",
      0,
      1000,
      Array::make(repetitions, host_cid),
      "{\"op\":\"source\"}",
    )
    let seq_cid = @wire.cid(@wire.program_proof_witness(seq_proof))
    let take_proof = sequence_fixture_proof(
      "actql.bound.take",
      1,
      4,
      [seq_cid],
      "{\"input\":\"" + seq_cid + "\",\"maximum\":4,\"op\":\"clamp\"}",
    )
    witnesses.push(@wire.program_proof_witness(seq_proof))
    witnesses.push(@wire.program_proof_witness(take_proof))
    let mixed = @wire.check_mixed_claims(witnesses, limits, {
      max_entities: 20,
      max_references: 100,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap()
    let claims = @wire.check_mixed_program_claims(
      mixed,
      [seq_proof, take_proof],
      { max_witnesses: 20, max_references: 100, },
    ).unwrap()
    let sources = @host.bind_claim_sources(claims, [policy], {
      max_entries: 20,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap()
    let applications = @step_bounds.resolve_applications(
      pipeline,
      sources,
      policy,
      [
        SequenceApplication(0, seq_proof, 0, 1),
        DeriveApplication(1, take_proof, [PriorApplication(0)], None),
      ],
      max_work=10000,
    ).unwrap()
    let last = @step_bounds.resolved_application_at(applications, 1).unwrap()
    let converted = reidentify_step_graph(units, last, budget)
    let sequence = proof_input_at(converted, 0).unwrap()
    assert_eq(proof_external_input_count(converted), 0)
    assert_eq(proof_external_input_count(sequence), repetitions)
    assert_eq(
      @wire.program_proof_input_count(proof_claim(sequence)),
      repetitions,
    )
    for i in 0..<repetitions {
      assert_eq(
        @wire.program_proof_input_at(proof_claim(sequence), i),
        Some(host_cid),
      )
      assert_true(
        physical_equal(proof_external_input_at(sequence, i).unwrap(), host),
      )
    }
    assert_true(proof_external_input_at(sequence, repetitions) is None)
    let retained = publication_proof_claims([converted], budget)
    assert_eq(retained.length(), 3)
    assert_eq(retained.filter(w => @wire.cid(w) == host_cid).length(), 1)
    assert_eq(
      retained.filter(w => @wire.cid(w) == @wire.cid(witnesses[0])).length(),
      0,
    )
    assert_eq(
      @wire.value(@wire.program_proof_witness(proof_claim(converted))),
      4L,
    )
    let seq_new = @wire.cid(@wire.program_proof_witness(proof_claim(sequence)))
    assert_eq(
      @wire.program_proof_input_at(proof_claim(converted), 0),
      Some(seq_new),
    )
    assert_true(seq_new != seq_cid)
    let seq_bound = @step_bounds.resolved_application_at(applications, 0).unwrap()
    let before = IdentityBudget::{ ..budget, }
    let direct = reidentify_step(units[1], seq_bound, [], budget)
    let exact = IdentityBudget::{ ..before, work: before.work - budget.work, }
    assert_eq(
      @wire.cid(
        @wire.program_proof_witness(
          reidentify_step(units[1], seq_bound, [], { ..exact, }).proof,
        ),
      ),
      seq_new,
    )
    let short = IdentityBudget::{ ..exact, work: exact.work - 1, }
    let short_before = short.work
    try reidentify_step(units[1], seq_bound, [], short) catch {
      UnitBuildFailure::BudgetExceeded => ()
      e => raise e
    } noraise {
      _ => fail("short proof budget exposed a result")
    }
    assert_eq(short.work, short_before)
    assert_eq(proof_external_input_count(direct), repetitions)
    // Same internal ordinal, different Unit: Program witness changes while
    // the independently admitted Host operand stays identical.
    let synthetic = { ..units[1], definition_cid: "sha256:" + "0".repeat(64), }
    let changed = reidentify_step(synthetic, seq_bound, [], budget)
    let inputs = Array::make(repetitions, "\"" + host_cid + "\"").join(",")
    let expected = "{\"inputs\":[" +
      inputs +
      "],\"law_id\":\"actql.bound.sequence-output\",\"semantic_ref\":\"unit:" +
      synthetic.definition_cid +
      "#/steps/0\",\"unit\":\"rows\",\"value\":1000,\"version\":\"actql-bound-proof/0.1\"}"
    let expected_cid = "sha256:" + @sha.hex(@utf8.encode(expected))
    guard @wire.source(@wire.program_proof_witness(changed.proof))
      is @wire.Program(subject, proof_cid) else {
      fail("missing persistent Program source")
    }
    assert_eq(subject, "unit:" + synthetic.definition_cid + "#/steps/0")
    assert_eq(proof_cid, expected_cid)
    assert_true(
      @wire.cid(@wire.program_proof_witness(changed.proof)) != seq_new,
    )
    assert_true(
      physical_equal(proof_external_input_at(changed, 0).unwrap(), host),
    )
  }
}

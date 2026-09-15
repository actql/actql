///|
test "window proof encoding preserves converted input identity and exact multiply semantics" {
  let budget = IdentityBudget::{
    work: 100000000,
    bytes: 10000000,
    nodes: 1000000,
    depth: 100,
  }
  let (_, _, _, _, units) = remote_construction_fixture(budget)
  let candidate = @context.publication_row_limit_program_at(
    units[0].publication_rows[0],
    0,
  ).unwrap()
  let bound = @step_bounds.target_rows_bound(
    @capacity.target_membership_rows(candidate.membership),
  )
  let synthetic = { ..units[0], definition_cid: "sha256:" + "0".repeat(64), }
  let input = reidentify_step_graph([synthetic], bound, budget)
  let input_cid = @wire.cid(@wire.program_proof_witness(input.proof))
  let old_input = @wire.cid(
    @wire.program_proof_witness(@step_bounds.checked_proof(bound)),
  )
  assert_true(input_cid != old_input)
  assert_eq(
    input_cid, "sha256:8aa21a53557ce5864441724f2088a6757e8883e5a2fac0d9cb23a340a5088720",
  )
  for
    (law, factor) in [
      ("actql.bound.row-window", 0L),
      ("actql.bound.window-events", -1L),
      ("actql.bound.row-window", 9007199254740992L),
      ("actql.bound.array-aggregate-input", 1L),
    ] {
    let before = IdentityBudget::{ ..budget, }
    try
      window_input_claim(
        input,
        "unit:sha256:" + "2".repeat(64) + "#/steps/7",
        law,
        factor,
        budget,
      )
    catch {
      UnitBuildFailure::ForeignOwner => ()
      e => raise e
    } noraise {
      _ => fail("invalid window encoder argument accepted")
    }
    assert_eq(
      (budget.work, budget.bytes, budget.nodes),
      (before.work, before.bytes, before.nodes),
    )
  }
  for law in ["actql.bound.row-window", "actql.bound.window-events"] {
    for factor in [1L, 4L, 9007199254740991L] {
      // Fixed synthetic Unit namespace for wire encoding only, not Program closure.
      let subject = "unit:sha256:" + "2".repeat(64) + "#/steps/7"
      let before = IdentityBudget::{ ..budget, }
      let proof = window_input_claim(input, subject, law, factor, budget)
      let witness = @wire.program_proof_witness(proof)
      if factor == 4L {
        // Independently computed from canonical preimages with Node SHA-256.
        assert_eq(
          @wire.cid(witness),
          if law == "actql.bound.row-window" {
            "sha256:fbc17f99bd17869654ece6db7818e98491660019d8e77d898161c54f441943c2"
          } else {
            "sha256:f4e81adb3db47d63ed78e72238bd57afd5e9f77ab8e4d0f7abfd5f1dc535d6a4"
          },
        )
      }
      assert_eq(@wire.value(witness), factor)
      assert_true(@wire.unit(witness) is Rows)
      assert_true(
        @wire.derivation(witness) is Multiply(id, n) &&
        id == input_cid &&
        n == factor,
      )
      assert_eq(@wire.program_proof_input_count(proof), 1)
      assert_eq(@wire.program_proof_input_at(proof, 0), Some(input_cid))
      let expected = "{\"inputs\":[\"" +
        input_cid +
        "\"],\"law_id\":\"" +
        law +
        "\",\"semantic_ref\":\"" +
        subject +
        "\",\"unit\":\"rows\",\"value\":" +
        factor.to_string() +
        ",\"version\":\"actql-bound-proof/0.1\"}"
      let expected_cid = "sha256:" + @sha.hex(@utf8.encode(expected))
      assert_true(
        @wire.source(witness) is Program(reference, cid) &&
        reference == subject &&
        cid == expected_cid,
      )
      let out = @encode.writer(10000, 1000, 100)
      @wire.emit(witness, out)
      let text = @encode.finish(out)
      assert_false(text.contains("checked-step:"))
      assert_false(text.contains(old_input))
      let exact = IdentityBudget::{
        ..before,
        work: before.work - budget.work,
        bytes: before.bytes - budget.bytes,
        nodes: before.nodes - budget.nodes,
      }
      let short = IdentityBudget::{ ..exact, work: exact.work - 1, }
      let repeated = window_input_claim(input, subject, law, factor, exact)
      assert_eq((exact.work, exact.bytes, exact.nodes), (0, 0, 0))
      assert_eq(
        @wire.cid(@wire.program_proof_witness(repeated)),
        @wire.cid(witness),
      )
      let short_before = IdentityBudget::{ ..short, }
      try window_input_claim(input, subject, law, factor, short) catch {
        UnitBuildFailure::BudgetExceeded => ()
        e => raise e
      } noraise {
        _ => fail("short proof budget accepted")
      }
      assert_eq(
        (short.work, short.bytes, short.nodes),
        (short_before.work, short_before.bytes, short_before.nodes),
      )
      let another = window_input_claim(
        input,
        subject.replace(old="#/steps/7", new="#/steps/8"),
        law,
        factor,
        budget,
      )
      assert_true(
        @wire.cid(@wire.program_proof_witness(another)) != @wire.cid(witness),
      )
    }
  }
}

///|
test "window proof reader cannot fabricate a requirement on an ordinary checked operation" {
  let programs : Array[CheckedProgram] = []
  let _ = local_construction_fixture(
    { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
    through_check=true,
    checked_results=programs,
  )
  assert_eq(unit_window_limit_count(programs[0], 0), Some(0))
  for (stage, index) in [(0, 0), (-1, 0), (0, -1), (1, 0)] {
    assert_true(unit_window_limit_at(programs[0], stage, index) is None)
  }
}

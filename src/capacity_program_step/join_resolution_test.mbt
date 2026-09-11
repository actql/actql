///|
test "resolved join output retains its limit and feeds downstream bounds" {
  for family in ["join", "cross_join", "interval_join"] {
    let (left, lb) = join_operand(2)
    let (right, rb) = join_operand(3)
    let p = join_pipeline(left, right, family, "inner", tail=",{\"take\":4}")
    let candidate = @capacity_program_step.check_with_inputs(
      p,
      0,
      proof("actql.bound.join-output", 6, "{\"op\":\"source\"}", inputs=[
        bound_id(lb),
        bound_id(rb),
      ]),
      [lb, rb],
      max_input_work=10,
    ).unwrap()
    let apps = [lb, rb, candidate]
    for host_only in [false, true] {
      let registered = if host_only { [lb, rb] } else { apps }
      let mode = if host_only { 1 } else { 0 }
      let base = join_limit_sources(registered, mode)
      let claims = @host.source_claims(base)
      let arithmetic = @wire.program_claim_arithmetic(claims)
      let minimum = @wire.limit_minimum(
        @wire.mixed_limit_at(@wire.program_claim_mixed(claims).unwrap(), 0).unwrap(),
      )
      let ids : Array[String] = []
      for i in 0..<@arithmetic.minimum_candidate_count(minimum) {
        let node = @arithmetic.minimum_candidate_at(minimum, i).unwrap().node
        ids.push(@wire.cid(@wire.claim_at(arithmetic, node).unwrap()))
      }
      let output = proof(
        "actql.bound.join-resolved-output",
        1,
        "{\"op\":\"source\"}",
        inputs=ids,
      )
      let output_id = @wire.cid(@wire.program_proof_witness(output))
      let downstream = proof(
        "actql.bound.take",
        1,
        "{\"input\":\"" + output_id + "\",\"maximum\":4,\"op\":\"clamp\"}",
        reference="checked-step:1",
        inputs=[output_id],
      )
      let sources = join_limit_sources(registered, mode, extra_proofs=[
        output, downstream,
      ])
      let requests = registered.map(app => {
        @capacity_program_step.ExistingApplication(app)
      })
      let output_position = requests.length()
      requests.push(@capacity_program_step.JoinApplication(0, output, 0))
      requests.push(
        @capacity_program_step.DeriveApplication(
          1,
          downstream,
          [@capacity_program_step.PriorApplication(output_position)],
          None,
        ),
      )
      let resolved = @capacity_program_step.resolve_applications(
        p,
        sources,
        join_policy(),
        requests,
        max_work=1000,
      ).unwrap()
      let program = @capacity_program_step.resolved_program(resolved)
      let wrong_law = requests.copy()
      wrong_law[output_position] = @capacity_program_step.JoinApplication(
        0,
        proof("actql.bound.join-output", 1, "{\"op\":\"source\"}", inputs=ids),
        0,
      )
      assert_true(
        @capacity_program_step.resolve_applications(
          p,
          sources,
          join_policy(),
          wrong_law,
          max_work=1000,
        )
        is Err(InvalidOutputProof(_)),
      )
      let wrong_step = requests.copy()
      wrong_step[output_position] = @capacity_program_step.JoinApplication(
        1, output, 0,
      )
      assert_true(
        @capacity_program_step.resolve_applications(
          p,
          sources,
          join_policy(),
          wrong_step,
          max_work=1000,
        )
        is Err(Join(_, WrongOperation)),
      )
      let app = @capacity_program_step.resolved_application_at(
        resolved, output_position,
      ).unwrap()
      let last = @capacity_program_step.resolved_application_at(
        resolved,
        output_position + 1,
      ).unwrap()
      assert_true(
        physical_equal(@capacity_program_step.input_at(last, 0).unwrap(), app),
      )
      guard @capacity_program_step.checked_enforcement(app)
        is Some(@capacity_program_step.JoinEnforcement(limit)) else {
        fail("missing join enforcement")
      }
      assert_true(
        physical_equal(
          @capacity_program_step.join_limit_program(limit),
          program,
        ),
      )
      @capacity_program_step.check_join_complete(
        p,
        sources,
        program,
        join_policy(),
        [limit],
        max_work=1000,
      ).unwrap()
      |> ignore
      let exact = @capacity_program_step.resolution_work(resolved)
      assert_true(
        @capacity_program_step.resolve_applications(
          p,
          sources,
          join_policy(),
          requests,
          max_work=exact,
        )
        is Ok(_),
      )
      assert_true(
        @capacity_program_step.resolve_applications(
          p,
          sources,
          join_policy(),
          requests,
          max_work=exact - 1,
        )
        is Err(_),
      )
      // A candidate registered after the output still belongs in the minimum.
      if host_only {
        let late = join_limit_sources(apps, 1, extra_proofs=[output, downstream])
        let late_requests = requests.copy()
        late_requests.push(
          @capacity_program_step.ExistingApplication(candidate),
        )
        assert_true(
          @capacity_program_step.resolve_applications(
            p,
            late,
            join_policy(),
            late_requests,
            max_work=1000,
          )
          is Err(Join(_, MissingProgramCandidate(_))),
        )
      }
    }
  }
}

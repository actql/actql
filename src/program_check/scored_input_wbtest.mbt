///|
test "formal scored fusion retains Local declarations keys and semantic roots across imports" {
  let body = "\"output_carrier\":\"relation\",\"schema\":{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"score_contracts\":{\"id\":{\"domain\":\"d\",\"normalization\":\"n\",\"range\":[0,10]}},\"source_ref\":\"source:local/first/rows\",\"version\":\"actql-local-input-schema/0.1\""
  for policy in ["\"max\"", "{\"weighted_sum\":{\"left\":0.5,\"right\":0.5}}"] {
    let definitions : Array[String] = []
    for
      prefix in [
        "",
        "\"completeness\":\"complete\",\"input_cid\":\"sha256:" +
        "0".repeat(64) +
        "\",",
      ] {
      let programs : Array[CheckedProgram] = []
      ignore(
        local_construction_fixture(
          { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
          through_check=true,
          checked_results=programs,
          veca=true,
          second_stage=true,
          snapshot_entries="[{" + prefix + body + "}]",
          producer_expression="id",
          producer_suffix=",{\"merge_rankings\":{\"with\":\"derived\",\"by\":[],\"candidate\":\"id\",\"score\":\"value\",\"score_policy\":" +
            policy +
            ",\"score_contract\":{\"domain\":\"d\",\"normalization\":\"n\",\"range\":[0,10]},\"k\":2}},{\"select\":[\"id\",{\"value\":\"score\"}],\"as\":\"projected\"}",
          producer_result_from="projected",
          extra_step_budget=2,
        ),
      )
      let program = programs[0]
      definitions.push(unit_definition_cid(program, 0).unwrap())
      assert_true(@pipeline.input_key(program.units[0].pipeline, 0) is Some(_))
      let mut roots = 0
      for i in 0..<@context.core_contract_root_count(program.contracts) {
        let root = @context.core_contract_root_at(program.contracts, i).unwrap()
        if root.site is StageLocalInputScores(stage, input) {
          assert_eq((stage, input), (0, 0))
          // Independent canonical JSON + Node SHA-256, not the inventory emitter.
          assert_eq(
            root.body,
            @context.LocalInputScores(
              "sha256:9660f7c87a62ef28b499c372876256ecb4f97f1d5847cf7a18eefbdbb4fabe66",
            ),
          )
          roots += 1
        }
      }
      assert_eq(roots, 1)
      let operations = @context.stage_requirement_operations(
        program.requirements,
      )
      let mut authentication = 0
      let mut range_checks = 0
      for i in 0..<@context.operation_closure_count(operations) {
        if @context.operation_closure_at(operations, i)
          is Some(ExecutionCheck(RankingExecution(check))) {
          if check.rule is AuthenticateRankingScores {
            authentication += 1
            for j in 0..<@context.ranking_execution_input_count(check) {
              let (_, shape) = @context.ranking_execution_input_at(check, j).unwrap()
              let declaration = @evidence.ranking_score_at(
                @evidence.ranking_shape_input(shape),
                Unqualified("value"),
              ).unwrap()
              assert_eq(
                @evidence.declared_score_field(declaration),
                Unqualified("id"),
              )
              assert_eq(
                @evidence.declared_score_contract(declaration).normalization,
                "n",
              )
            }
          }
          if check.rule is AdmitRankingScoreRanges {
            range_checks += 1
          }
        }
      }
      assert_eq(authentication, 3)
      assert_eq(range_checks, 3)
    }
    assert_eq(definitions[0], definitions[1])
  }
}

///|
test "score semantics affect Unit identity without replacing its row type" {
  let definitions : Array[String] = []
  let row_types : Array[@context.CoreContractBody] = []
  for normalization in ["n", "other"] {
    let programs : Array[CheckedProgram] = []
    ignore(
      local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        snapshot_entries="[{\"output_carrier\":\"relation\",\"schema\":{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"score_contracts\":{\"id\":{\"domain\":\"d\",\"normalization\":\"" +
          normalization +
          "\",\"range\":[0,10]}},\"source_ref\":\"source:local/first/rows\",\"version\":\"actql-local-input-schema/0.1\"}]",
      ),
    )
    let program = programs[0]
    definitions.push(unit_definition_cid(program, 0).unwrap())
    for i in 0..<@context.core_contract_root_count(program.contracts) {
      let root = @context.core_contract_root_at(program.contracts, i).unwrap()
      if root.site is StageLocalInputType(0, 0) {
        row_types.push(root.body)
      }
    }
  }
  assert_false(definitions[0] == definitions[1])
  assert_eq(row_types.length(), 2)
  assert_eq(row_types[0], row_types[1])
}

///|
test "formal fusion rejects mismatched declarations and overwritten score origins" {
  for
    (expression, normalization, expected) in [
      ("id", "wrong", @pipeline.Vector(ScoreContractMismatch)),
      ("id + 1", "n", @pipeline.Vector(MissingScoreContract)),
    ] {
    let programs : Array[CheckedProgram] = []
    let rejected = try {
      ignore(
        local_construction_fixture(
          { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
          through_check=true,
          checked_results=programs,
          veca=true,
          snapshot_entries="[{\"output_carrier\":\"relation\",\"schema\":{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"score_contracts\":{\"id\":{\"domain\":\"d\",\"normalization\":\"" +
            normalization +
            "\",\"range\":[0,10]}},\"source_ref\":\"source:local/first/rows\",\"version\":\"actql-local-input-schema/0.1\"}]",
          producer_expression=expression,
          producer_suffix=",{\"merge_rankings\":{\"with\":\"derived\",\"by\":[],\"candidate\":\"id\",\"score\":\"value\",\"score_policy\":\"max\",\"score_contract\":{\"domain\":\"d\",\"normalization\":\"n\",\"range\":[0,10]},\"k\":2}},{\"select\":[\"id\",{\"value\":\"score\"}],\"as\":\"projected\"}",
          producer_result_from="projected",
          extra_step_budget=2,
        ),
      )
      false
    } catch {
      Source(SourceView(Program(Program(Pipeline(0, issue))))) => {
        assert_eq(issue.kind, expected)
        true
      }
      error => raise error
    }
    assert_true(rejected)
    assert_eq(programs.length(), 0)
  }
}

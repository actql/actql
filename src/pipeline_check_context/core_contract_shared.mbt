///|
fn core_contract_stage_environment_roots(
  b : CoreContractBuilder,
  stage : Int,
) -> Unit raise CoreContractStop {
  // The retained identity already owns environment/policy admission,
  // including absent optional components. Never select by concrete values.
  core_contract_root(
    b,
    StageEnvironmentRules(stage),
    CatalogGrammarBody(@environment.EnvironmentBody),
  )
  core_contract_root(b, StageSourceGrammar(stage), ProgramSourceGrammar)
  core_contract_root(
    b,
    StageCanonicalIdentityRules(stage),
    CanonicalIdentityRules,
  )
}

///|
fn core_contract_stage_semantic_roots(
  b : CoreContractBuilder,
  stage : Int,
  semantics : @program_refs.StageSemantics,
) -> Unit raise CoreContractStop {
  for
    rules in [
      @environment.SourceRules,
      @environment.StageLaws,
      @environment.LocalContracts,
      @environment.LocalDependencies,
    ] {
    core_contract_root(
      b,
      StageSemanticRules(stage, rules),
      StageSemantics(rules),
    )
  }
  guard @environment.expression_contract_body(
      @program_refs.stage_semantics_expression_contract(semantics),
    )
    is Some(root) else {
    raise CoreContractStop(UnsupportedExpressionContract(stage))
  }
  core_contract_root(b, StageExpression(stage), ExpressionBody(root))
}

///|
fn core_contract_pipeline_roots(
  b : CoreContractBuilder,
  pipeline : @pipeline.CheckedPipeline,
  stage : Int,
  visit : Int,
  profile_checks? : ProgramOperationCalendar? = None,
) -> Unit raise CoreContractStop {
  for step in 0..<@pipeline.step_count(pipeline) {
    core_contract_charge(b)
    let operation = @pipeline.step_at(pipeline, step).unwrap().operation
    core_contract_root(
      b,
      OperationTransferRules(stage, visit, step),
      BoundTransferRules,
    )
    core_operation_count_root(b, operation, stage, visit, step)
    for profile in 0..<@pipeline.operation_profile_count(operation) {
      core_contract_charge(b)
      let p = @pipeline.operation_profile_at(operation, profile).unwrap()
      let data = match p {
        @pipeline.CalendarProfile => {
          guard operation is @pipeline.Calendar(calendar) else {
            raise CoreContractStop(UnresolvedProfileData(stage, visit, step, p))
          }
          Some(
            CalendarProfileData(
              @calendar_profile.cid(@calendar.profile(calendar)),
            ),
          )
        }
        @pipeline.TextRankProfile => {
          guard operation is @pipeline.TextRank(checked=text_rank, ..) else {
            raise CoreContractStop(UnresolvedProfileData(stage, visit, step, p))
          }
          let selected = match profile_checks {
            Some(checks) =>
              checks.lexical.profile.map(v => {
                @environment.selected_text_rank_profile(v)
              })
            None => @vector.text_rank_profile(text_rank)
          }
          guard selected is Some(selected) else {
            raise CoreContractStop(UnresolvedProfileData(stage, visit, step, p))
          }
          Some(TextRankProfileData(@lexical.cid(selected)))
        }
        @pipeline.RelA
        | @pipeline.SGA
        | @pipeline.GraphProfile
        | @pipeline.TEA
        | @pipeline.VecA => None
      }
      if data is Some(body) {
        core_contract_root(b, OperationDataProfile(stage, visit, step, p), body)
      }
      for law in 0..<@pipeline.operation_profile_adopted_law_count(p) {
        core_contract_root(
          b,
          OperationLaw(stage, visit, step, profile, law),
          AdoptedBody(
            @pipeline.operation_profile_adopted_law_at(p, law).unwrap(),
          ),
        )
      }
    }
  }
}

///|
fn core_contract_complete_dependencies(
  b : CoreContractBuilder,
) -> Unit raise CoreContractStop {
  let mut index = 0
  while index < b.bodies.length() {
    core_contract_charge(b)
    match b.bodies[index] {
      AdoptedBody(_)
      | CatalogContract(_)
      | ModelAcquisitionContract(_)
      | ProgramSourceGrammar
      | StageSemantics(_)
      | CalendarProfileData(_)
      | TextRankProfileData(_) => ()
      NumericReductionBody(_) => ()
      ValuesCountLaw
      | ValuesWireLaw
      | BoundTransferRules
      | RelationCountRules
      | JoinCountRules
      | IntervalSearchRules
      | AsOfSearchRules
      | WindowCountRules
      | GraphCountRules
      | RankingCountRules
      | SeriesCountRules => ()
      GraphConstructionCountRules => {
        let target = AdoptedBody(@pipeline.GraphLaw)
        core_contract_edge(b)
        core_contract_body(b, target)
        core_contract_dependency(b, GraphConstructionCountRules, target)
      }
      LocalSourceReferenceRules
      | CanonicalIdentityRules
      | SourceResponsePolicyRules => ()
      EffectiveDataPolicyRules => {
        core_contract_edge(b)
        core_contract_body(b, SourceResponsePolicyRules)
        core_contract_dependency(
          b,
          EffectiveDataPolicyRules,
          SourceResponsePolicyRules,
        )
      }
      ValuesExecutionRules => {
        let target = CatalogGrammarBody(@environment.ValueGrammarBody)
        core_contract_edge(b)
        core_contract_body(b, target)
        core_contract_dependency(b, ValuesExecutionRules, target)
      }
      LocalInputType(_) | LocalInputScores(_) => {
        core_contract_edge(b)
        core_contract_body(b, LocalSnapshotRules)
        core_contract_dependency(b, b.bodies[index], LocalSnapshotRules)
      }
      LocalSnapshotRules =>
        for
          target in [
            CatalogGrammarBody(@environment.ValueGrammarBody),
            LocalSourceReferenceRules,
          ] {
          core_contract_edge(b)
          core_contract_body(b, target)
          core_contract_dependency(b, b.bodies[index], target)
        }
      CatalogGrammarBody(body) =>
        for edge in 0..<@environment.catalog_grammar_dependency_count(body) {
          core_contract_edge(b)
          let target = core_catalog_grammar(
            @environment.catalog_grammar_dependency_at(body, edge).unwrap().target,
          )
          core_contract_body(b, target)
          core_contract_dependency(b, b.bodies[index], target)
        }
      ExpressionBody(body) => {
        let count = @environment.expression_contract_dependency_count(body)
        for edge in 0..<count {
          core_contract_edge(b)
          let target = ExpressionBody(
            @environment.expression_contract_dependency_at(body, edge).unwrap().target,
          )
          core_contract_body(b, target)
          core_contract_dependency(b, b.bodies[index], target)
        }
      }
    }
    index += 1
  }
}

///|
pub(all) struct CoreContractLimits {
  max_work : Int
  max_roots : Int
  max_bodies : Int
  max_edges : Int
} derive(Eq, Debug)

///|
pub(all) enum CoreContractIssue {
  InvalidLimits
  BudgetExceeded
  UnsupportedExpressionContract(Int)
  SourceInventory(SourceContractIssue)
  CatalogBody(Int, Int, Int, @environment.BodyDependencyIssue)
  UnknownCatalogGrammar(Int, Int, Int)
  UnresolvedProfileData(Int, Int, Int, @pipeline.OperationProfile)
  ForeignProfiles
  IncomingInventory(IncomingIssue)
  UnsupportedIncoming(Int)
  LocalTypeEncoding(Int, Int)
} derive(Eq, Debug)

///|
pub(all) enum CoreContractBody {
  ExpressionBody(@environment.ExpressionContractBody)
  AdoptedBody(@pipeline.AdoptedOperationLaw)
  CatalogContract(String)
  CatalogGrammarBody(@environment.CatalogGrammar)
  ProgramSourceGrammar
  StageSemantics(@environment.StageSemanticContract)
  CalendarProfileData(String)
  TextRankProfileData(String)
  ValuesCountLaw
  BoundTransferRules
  RelationCountRules
  JoinCountRules
  WindowCountRules
  GraphCountRules
  RankingCountRules
  SeriesCountRules
  LocalSnapshotRules
  LocalSourceReferenceRules
  LocalInputType(String)
  CanonicalIdentityRules
} derive(Eq, Debug)

///|
pub(all) enum CoreContractSite {
  StageExpression(Int)
  OperationLaw(Int, Int, Int, Int, Int)
  CatalogReference(Int, Int, Int)
  StageSourceGrammar(Int)
  StageSemanticRules(Int, @environment.StageSemanticContract)
  StageEnvironmentRules(Int)
  OperationDataProfile(Int, Int, Int, @pipeline.OperationProfile)
  IncomingRules(Int)
  OperationCountLaw(Int, Int, Int)
  OperationTransferRules(Int, Int, Int)
  OperationRelationCountRules(Int, Int, Int)
  OperationJoinCountRules(Int, Int, Int)
  OperationWindowCountRules(Int, Int, Int)
  OperationGraphCountRules(Int, Int, Int)
  OperationRankingCountRules(Int, Int, Int)
  OperationSeriesCountRules(Int, Int, Int)
  StageLocalInputRules(Int, Int)
  StageLocalInputType(Int, Int)
  StageCanonicalIdentityRules(Int)
} derive(Eq, Debug)

///|
pub struct CoreContractRoot {
  site : CoreContractSite
  body : CoreContractBody
}

///|
struct CoreContractInventory {
  identity : ProgramSourceIdentity
  roots : Array[CoreContractRoot]
  bodies : Array[CoreContractBody]
  sources : ProgramSourceContracts
  profile_checks : ProgramOperationCalendar?
  incoming : ProgramIncomingRequirements
  stages : Array[Array[CoreContractBody]]
  work : Int
  edges : Int
  hash_bytes : Int
  hash_nodes : Int
}

///|
priv suberror CoreContractStop {
  CoreContractStop(CoreContractIssue)
}

///|
priv struct CoreContractBuilder {
  limits : CoreContractLimits
  roots : Array[CoreContractRoot]
  bodies : Array[CoreContractBody]
  seen : Map[String, Unit]
  dependencies : Map[String, CoreContractDependencies]
  mut work : Int
  mut edges : Int
  hash_limits : @snapshot.Limits
  mut hash_bytes : Int
  mut hash_nodes : Int
}

///|
priv struct CoreContractDependencies {
  targets : Array[CoreContractBody]
  seen : Map[String, Unit]
}

///|
fn core_contract_charge(b : CoreContractBuilder) -> Unit raise CoreContractStop {
  if b.work == b.limits.max_work {
    raise CoreContractStop(BudgetExceeded)
  }
  b.work += 1
}

///|
fn core_contract_body(
  b : CoreContractBuilder,
  body : CoreContractBody,
) -> Unit raise CoreContractStop {
  // Share body storage, never source occurrences or their admitted owners.
  let cid = core_contract_cid(body)
  if !b.seen.contains(cid) {
    if b.bodies.length() == b.limits.max_bodies {
      raise CoreContractStop(BudgetExceeded)
    }
    b.bodies.push(body)
    b.seen.set(cid, ())
  }
}

///|
fn core_contract_root(
  b : CoreContractBuilder,
  site : CoreContractSite,
  body : CoreContractBody,
) -> Unit raise CoreContractStop {
  core_contract_charge(b)
  if b.roots.length() == b.limits.max_roots {
    raise CoreContractStop(BudgetExceeded)
  }
  core_contract_body(b, body)
  b.roots.push({ site, body, })
}

///|
/// Collect expression body references and adopted operation laws from every
/// owned Stage/producer/step and selected Catalog reference. This is not the
/// complete Unit closure or interface identity. Unsupported selected Catalog
/// bodies reject collection; the supported roots retain their Stage selection.
pub fn collect_core_contracts(
  identity : ProgramSourceIdentity,
  limits : CoreContractLimits,
  profile_checks? : ProgramOperationCalendar? = None,
  hash_limits? : @snapshot.Limits? = None,
) -> Result[CoreContractInventory, CoreContractIssue] {
  let hash_limits = hash_limits.unwrap_or({
    max_bytes: limits.max_work,
    max_nodes: limits.max_work,
    max_depth: limits.max_work,
  })
  if limits.max_work < 0 ||
    limits.max_roots < 0 ||
    limits.max_bodies < 0 ||
    limits.max_edges < 0 ||
    hash_limits.max_bytes < 0 ||
    hash_limits.max_nodes < 0 ||
    hash_limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let prefix = match profile_checks {
    None => identity.work
    Some(checks) => {
      let owner = checks.lexical.cells.queries.ranges.fills.frames.scalars.orders.requirements.expressions.identity
      if !physical_equal(owner, identity) {
        return Err(ForeignProfiles)
      }
      checks.work
    }
  }
  if prefix >= limits.max_work {
    return Err(BudgetExceeded)
  }
  let context = identity.sources.operations.preparation.sources.capacity.context.rows.requests.inputs
  // Only the remaining Program work may be spent on the source branch.
  // Reserve the owner join before the branch can allocate its inventory.
  let source_work_limit = context.usage.work + (limits.max_work - prefix - 1)
  let requirements = match
    collect_source_contracts(context, {
      max_work: source_work_limit,
      max_inputs: limits.max_work,
      max_references: limits.max_roots,
    }) {
    Ok(value) => value
    Err(issue) => return Err(SourceInventory(issue))
  }
  let sources = match
    bind_program_source_contracts(identity, requirements, limits.max_work) {
    Ok(value) => value
    Err(issue) => return Err(SourceInventory(issue))
  }
  let used = sources.work + (prefix - identity.work)
  let incoming = match
    collect_program_incoming(identity, {
      max_work: identity.work + (limits.max_work - used),
      max_name_units: limits.max_work - used,
      max_requirements: limits.max_roots,
    }) {
    Ok(value) => value
    Err(issue) => return Err(IncomingInventory(issue))
  }
  let b : CoreContractBuilder = {
    limits,
    roots: [],
    bodies: [],
    seen: {},
    dependencies: {},
    work: used + (incoming.work - identity.work),
    edges: 0,
    hash_limits,
    hash_bytes: 0,
    hash_nodes: 0,
  }
  try {
    core_contract_charge(b)
    for index in 0..<incoming.entries.length() {
      core_contract_charge(b)
      let rules = match incoming.entries[index].requirement {
        Success(_, _) => @environment.GateRequirement
        Result(_, _, _) => @environment.ResultImportInterface
        Receipt(_, _, _) => raise CoreContractStop(UnsupportedIncoming(index))
      }
      core_contract_root(b, IncomingRules(index), StageSemantics(rules))
    }
    for stage in 0..<source_contract_stage_count(requirements) {
      core_contract_charge(b)
      for input in 0..<source_contract_input_count(requirements, stage).unwrap() {
        core_contract_charge(b)
        let selected = source_contract_input_at(requirements, stage, input).unwrap()
        for reference in 0..<@sourceviews.selected_reference_count(selected) {
          core_contract_charge(b)
          let body = match
            program_source_contract_body_at(sources, stage, input, reference) {
            Ok(Some(body)) => body
            Ok(None) =>
              raise CoreContractStop(
                CatalogBody(
                  stage,
                  input,
                  reference,
                  @environment.MissingBodyAdmission,
                ),
              )
            Err(issue) =>
              raise CoreContractStop(
                CatalogBody(stage, input, reference, issue),
              )
          }
          let cid = @environment.contract_identity(
              @environment.catalog_body_contract(body),
            ).2
          core_contract_root(
            b,
            CatalogReference(stage, input, reference),
            CatalogContract(cid),
          )
          for edge in 0..<@environment.catalog_body_dependency_count(body) {
            core_contract_edge(b)
            let dependency = @environment.catalog_body_dependency_at(body, edge).unwrap()
            guard @environment.catalog_dependency_grammar(dependency)
              is Some(grammar) else {
              raise CoreContractStop(
                UnknownCatalogGrammar(stage, input, reference),
              )
            }
            core_contract_body(b, core_catalog_grammar(grammar))
            core_contract_dependency(
              b,
              CatalogContract(cid),
              core_catalog_grammar(grammar),
            )
          }
        }
      }
    }
    for stage in 0..<program_identity_stage_count(identity) {
      let source = program_identity_stage_at(identity, stage).unwrap()
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
      core_contract_charge(b)
      let locals = @local_inputs.snapshot_inputs(
        @local_inputs.environment_assertions(
          @local_inputs.reconciled_inputs(context.locals[stage]),
        ),
      )
      let assertions = @local_inputs.snapshot_assertions(
        @local_inputs.environment_assertions(
          @local_inputs.reconciled_inputs(context.locals[stage]),
        ),
      )
      for input in 0..<@local_inputs.count(locals) {
        core_contract_root(
          b,
          StageLocalInputRules(stage, input),
          LocalSnapshotRules,
        )
        let (name, declaration) = @local_inputs.entry_at(locals, input).unwrap()
        let schema = match
          @local_inputs.schema_agreement_at(assertions, input) {
          Some(agreement) => Some(@local_input.supplied_schema(agreement))
          None =>
            @carrier.complete_schema(
              @carrier.relation_rows(@local_input.carrier(declaration)).unwrap(),
            )
        }
        // A partial declaration remains represented by its source body. Never
        // manufacture a complete empty object or a json type for unknown fields.
        guard schema is Some(schema) else { continue }
        core_contract_local_type(
          b,
          stage,
          input,
          @stages.stage_at(@local_inputs.source(locals), stage).unwrap().id,
          name,
          @schema.as_object(schema).unwrap(),
        )
      }
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
      guard stage_identity_expression_body(source) is Some(root) else {
        raise CoreContractStop(UnsupportedExpressionContract(stage))
      }
      core_contract_root(b, StageExpression(stage), ExpressionBody(root))
      for visit in 0..<program_identity_producer_count(identity, stage).unwrap() {
        core_contract_charge(b)
        let pipeline = program_identity_producer_at(identity, stage, visit).unwrap()
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
                  raise CoreContractStop(
                    UnresolvedProfileData(stage, visit, step, p),
                  )
                }
                Some(
                  CalendarProfileData(
                    @calendar_profile.cid(@calendar.profile(calendar)),
                  ),
                )
              }
              @pipeline.TextRankProfile => {
                guard operation is @pipeline.TextRank(checked=text_rank, ..) else {
                  raise CoreContractStop(
                    UnresolvedProfileData(stage, visit, step, p),
                  )
                }
                let selected = match profile_checks {
                  Some(checks) =>
                    checks.lexical.profile.map(v => {
                      @environment.selected_text_rank_profile(v)
                    })
                  None => @vector.text_rank_profile(text_rank)
                }
                guard selected is Some(selected) else {
                  raise CoreContractStop(
                    UnresolvedProfileData(stage, visit, step, p),
                  )
                }
                Some(TextRankProfileData(@lexical.cid(selected)))
              }
              @pipeline.RelA | @pipeline.SGA | @pipeline.TEA | @pipeline.VecA =>
                None
            }
            if data is Some(body) {
              core_contract_root(
                b,
                OperationDataProfile(stage, visit, step, p),
                body,
              )
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
    }
    let mut index = 0
    while index < b.bodies.length() {
      core_contract_charge(b)
      match b.bodies[index] {
        AdoptedBody(_)
        | CatalogContract(_)
        | ProgramSourceGrammar
        | StageSemantics(_)
        | CalendarProfileData(_)
        | TextRankProfileData(_) => ()
        ValuesCountLaw
        | BoundTransferRules
        | RelationCountRules
        | JoinCountRules
        | WindowCountRules
        | GraphCountRules
        | RankingCountRules
        | SeriesCountRules => ()
        LocalSourceReferenceRules | CanonicalIdentityRules => ()
        LocalInputType(_) => {
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
    let stages = core_contract_stages(b, incoming, identity.stages.length())
    Ok({
      identity,
      sources,
      profile_checks,
      incoming,
      stages,
      roots: b.roots,
      bodies: b.bodies,
      work: b.work,
      edges: b.edges,
      hash_bytes: b.hash_bytes,
      hash_nodes: b.hash_nodes,
    })
  } catch {
    CoreContractStop(issue) => Err(issue)
  }
}

///|
pub fn core_contract_identity(
  v : CoreContractInventory,
) -> ProgramSourceIdentity {
  v.identity
}

///|
pub fn core_contract_root_count(v : CoreContractInventory) -> Int {
  v.roots.length()
}

///|
pub fn core_contract_root_at(
  v : CoreContractInventory,
  index : Int,
) -> CoreContractRoot? {
  v.roots.get(index)
}

///|
pub fn core_contract_body_count(v : CoreContractInventory) -> Int {
  v.bodies.length()
}

///|
pub fn core_contract_body_at(
  v : CoreContractInventory,
  index : Int,
) -> CoreContractBody? {
  v.bodies.get(index)
}

///|
pub fn core_contract_usage(v : CoreContractInventory) -> (Int, Int) {
  (v.work, v.edges)
}

///|
pub fn core_contract_cid(v : CoreContractBody) -> String {
  match v {
    ExpressionBody(body) => @environment.expression_contract_body_cid(body)
    AdoptedBody(law) => @pipeline.adopted_operation_law_cid(law)
    CatalogContract(cid) => cid
    CatalogGrammarBody(body) => @environment.catalog_grammar_cid(body)
    ProgramSourceGrammar => @environment.program_source_grammar_cid()
    StageSemantics(rules) => @environment.stage_semantic_contract_cid(rules)
    CalendarProfileData(cid) | TextRankProfileData(cid) => cid
    ValuesCountLaw =>
      "sha256:0e0f9b4b6585ab7b17bafe484e82f44cd8f3acc9eec5ef9329cea200237a7971"
    BoundTransferRules =>
      "sha256:014682262d00c8435f300731e823e5b267ec66b78f980c765c4fd3772c68c911"
    RelationCountRules =>
      "sha256:163a0d75d56310803ac755d5f4f02069f442651711209037d6e3f512954c97ab"
    JoinCountRules =>
      "sha256:75f9c5ce5188d28a2e3b42213e0fb3a479475c06e280eb02ef7b001a355d1600"
    WindowCountRules =>
      "sha256:a5045688150b6b5aaf0c992b2e528ba3b5f1dd49e0db14e5673c9515af82ac3a"
    GraphCountRules =>
      "sha256:5e9a00ff401f42059f037c52babb40f8440201b3dccaffa90da297058d6adc89"
    RankingCountRules =>
      "sha256:655fa88f2d24a15794a12abdbdc967f51517f5f92aa1316f74f6df1617fcf0c7"
    SeriesCountRules =>
      "sha256:c85b84631add903652807808fc4faa9015e59cf9bfd0fb11bf170c85139dcf05"
    LocalSnapshotRules =>
      "sha256:60e8136aea733421e75fa3dcef4934c87ce98959b36f8a56da93ccfbf03d81b2"
    LocalSourceReferenceRules =>
      "sha256:9be664306a6a91a8e5bfca53d579e6dac77baf4567eb241ceeedc3216ffe47d9"
    LocalInputType(cid) => cid
    CanonicalIdentityRules =>
      "sha256:5a79d6cb9b012d0c3871c72e496eec7183948ac81d8ebff91b4f7ee6a59ae19d"
  }
}

///|
/// Emitted projection bytes/nodes, charged per occurrence even when CIDs match.
/// The caller must also retain the cumulative core_contract_usage work charge.
pub fn core_contract_hash_usage(v : CoreContractInventory) -> (Int, Int) {
  (v.hash_bytes, v.hash_nodes)
}

///|
fn core_catalog_grammar(body : @environment.CatalogGrammar) -> CoreContractBody {
  match body {
    @environment.ExpressionGrammar(expression) => ExpressionBody(expression)
    @environment.RelationLawBody => AdoptedBody(@pipeline.RelaPrimitive)
    @environment.GraphLawBody => AdoptedBody(@pipeline.SgaIdentity)
    @environment.EnvironmentBody
    | @environment.ValueGrammarBody
    | @environment.TextPolicyGrammarBody
    | @environment.CapacityGrammarBody => CatalogGrammarBody(body)
  }
}

///|
fn core_contract_edge(b : CoreContractBuilder) -> Unit raise CoreContractStop {
  core_contract_charge(b)
  if b.edges == b.limits.max_edges {
    raise CoreContractStop(BudgetExceeded)
  }
  b.edges += 1
}

///|
pub fn core_contract_sources(
  v : CoreContractInventory,
) -> ProgramSourceContracts {
  v.sources
}

///|
pub fn core_contract_profile_checks(
  v : CoreContractInventory,
) -> ProgramOperationCalendar? {
  v.profile_checks
}

///|
/// Exact source-derived sites, not completed predecessors or interface identities.
pub fn core_contract_incoming(
  v : CoreContractInventory,
) -> ProgramIncomingRequirements {
  v.incoming
}

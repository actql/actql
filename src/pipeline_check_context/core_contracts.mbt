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
  work : Int
  edges : Int
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
  mut work : Int
  mut edges : Int
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
/// complete Unit closure: declaration, profile data, publication and import
/// roots are separate. Unsupported selected Catalog bodies reject collection.
pub fn collect_core_contracts(
  identity : ProgramSourceIdentity,
  limits : CoreContractLimits,
  profile_checks? : ProgramOperationCalendar? = None,
) -> Result[CoreContractInventory, CoreContractIssue] {
  if limits.max_work < 0 ||
    limits.max_roots < 0 ||
    limits.max_bodies < 0 ||
    limits.max_edges < 0 {
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
  let b : CoreContractBuilder = {
    limits,
    roots: [],
    bodies: [],
    seen: {},
    work: sources.work + (prefix - identity.work),
    edges: 0,
  }
  try {
    core_contract_charge(b)
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
      for rules in [@environment.SourceRules, @environment.StageLaws] {
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
        CatalogGrammarBody(body) =>
          for edge in 0..<@environment.catalog_grammar_dependency_count(body) {
            core_contract_edge(b)
            core_contract_body(
              b,
              core_catalog_grammar(
                @environment.catalog_grammar_dependency_at(body, edge).unwrap().target,
              ),
            )
          }
        ExpressionBody(body) => {
          let count = @environment.expression_contract_dependency_count(body)
          for edge in 0..<count {
            core_contract_edge(b)
            core_contract_body(
              b,
              ExpressionBody(
                @environment.expression_contract_dependency_at(body, edge).unwrap().target,
              ),
            )
          }
        }
      }
      index += 1
    }
    Ok({
      identity,
      sources,
      profile_checks,
      roots: b.roots,
      bodies: b.bodies,
      work: b.work,
      edges: b.edges,
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
  }
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

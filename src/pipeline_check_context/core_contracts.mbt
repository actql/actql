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
} derive(Eq, Debug)

///|
pub(all) enum CoreContractBody {
  ExpressionBody(@environment.ExpressionContractBody)
  AdoptedBody(@pipeline.AdoptedOperationLaw)
} derive(Eq, Debug)

///|
pub(all) enum CoreContractSite {
  StageExpression(Int)
  OperationLaw(Int, Int, Int, Int, Int)
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
  // The interpreted vocabulary is a fixed small set; occurrences are not
  // compared with each other and body equality never substitutes Program owners.
  if !b.bodies.contains(body) {
    if b.bodies.length() == b.limits.max_bodies {
      raise CoreContractStop(BudgetExceeded)
    }
    b.bodies.push(body)
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
/// owned Stage/producer/step. This is not the complete Unit contract closure:
/// Catalog, declaration, profile data, publication and import roots are separate.
pub fn collect_core_contracts(
  identity : ProgramSourceIdentity,
  limits : CoreContractLimits,
) -> Result[CoreContractInventory, CoreContractIssue] {
  if limits.max_work < 0 ||
    limits.max_roots < 0 ||
    limits.max_bodies < 0 ||
    limits.max_edges < 0 {
    return Err(InvalidLimits)
  }
  if identity.work > limits.max_work {
    return Err(BudgetExceeded)
  }
  let b : CoreContractBuilder = {
    limits,
    roots: [],
    bodies: [],
    work: identity.work,
    edges: 0,
  }
  try {
    core_contract_charge(b)
    for stage in 0..<program_identity_stage_count(identity) {
      let source = program_identity_stage_at(identity, stage).unwrap()
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
        AdoptedBody(_) => ()
        ExpressionBody(body) => {
          let count = @environment.expression_contract_dependency_count(body)
          for edge in 0..<count {
            core_contract_charge(b)
            if b.edges == limits.max_edges {
              raise CoreContractStop(BudgetExceeded)
            }
            b.edges += 1
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
  }
}

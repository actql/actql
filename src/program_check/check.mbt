///|
struct CheckedProgram {
  identity : @context.ProgramSourceIdentity
  requirements : @context.StageRequirementClosure
  gates : @context.ProgramIncomingGates
  contracts : @context.CoreContractInventory
  units : Array[BuiltUnit]
}

///|
// Initial source-driven integration domain. This is an implementation boundary,
// not a restriction on the language's operation grammar. Broader paths continue
// to require their full semantic and execution closure before entry here.
fn check_supported_source(
  program : @syntax.Program,
  budget : IdentityBudget,
) -> Unit raise LocalConstructionFailure {
  try {
    identity_charge(budget, @syntax.stage_count(program))
    let stages = @syntax.stages(program)
    for stage in 0..<@syntax.stage_count(program) {
      identity_charge(budget, 1)
      let body = @syntax.stage_body(stages[stage])
      for field in 0..<@decode.object_length(body).unwrap() {
        identity_charge(budget, 1)
        let (name, value) = @decode.field_at(body, field).unwrap()
        if name != "steps" {
          continue
        }
        for index in 0..<@decode.array_length(value).unwrap() {
          identity_charge(budget, 1)
          let step = @decode.element_at(value, index).unwrap()
          guard @decode.object_length(step) is Some(members) else {
            raise UnitBuildFailure::UnsupportedStaticPath(step)
          }
          for member_index in 0..<members {
            identity_charge(budget, 1)
            let (key, _) = @decode.field_at(step, member_index).unwrap()
            match key {
              "from"
              | "as"
              | "meta"
              | "derive"
              | "filter"
              | "select"
              | "rename"
              | "drop"
              | "values" => ()
              _ => raise UnitBuildFailure::UnsupportedStaticPath(step)
            }
          }
        }
      }
    }
  } catch {
    error => raise Units(error)
  }
}

///|
/// Check the supported Local/Result-import integration domain from source and
/// admission material. Runtime checks are retained; success does not authorize
/// execution. Other static paths currently fail explicitly.
pub fn check(
  program : @syntax.Program,
  environment : @environment.WireEnvironment,
  supplied : @decode.Cursor?,
  material : Array[Array[@context.CapacityMaterial]],
  expression_profiles : @context.ExpressionProfiles,
  operation_profiles : @context.PureOperationProfiles,
  limits : SourceLimits,
  max_work~ : Int,
  max_bytes~ : Int,
  max_nodes~ : Int,
  max_depth~ : Int,
) -> CheckedProgram raise LocalConstructionFailure {
  if max_work < 0 || max_bytes < 0 || max_nodes < 0 || max_depth < 0 {
    raise InvalidLimits
  }
  let budget = IdentityBudget::{
    work: max_work,
    bytes: max_bytes,
    nodes: max_nodes,
    depth: max_depth,
  }
  check_supported_source(program, budget)
  let (identity, requirements, gates, contracts, units) = construct_local(
    program,
    supplied,
    { wire: environment, locations: None, },
    material,
    expression_profiles,
    operation_profiles,
    limits,
    budget,
  )
  audit_source_execution(contracts, budget) catch {
    error => raise Units(error)
  }
  { identity, requirements, gates, contracts, units, }
}

///|
// Registration is shared with the Catalog path even for the Local entry.
// Mode support alone does not bind authorization, acquisition and response
// admission. Until their execution closure is connected, selected SourceViews
// cannot escape through an otherwise supported operation sequence.
fn audit_source_execution(
  inventory : @context.CoreContractInventory,
  budget : IdentityBudget,
) -> Unit raise UnitBuildFailure {
  let requirements = @context.program_source_contract_requirements(
    @context.core_contract_sources(inventory),
  )
  let stages = @context.source_contract_stage_count(requirements)
  identity_charge(budget, stages)
  for stage in 0..<stages {
    let count = @context.source_contract_input_count(requirements, stage).unwrap()
    if count > 0 {
      raise UnclosedSourceExecution(stage, 0)
    }
  }
}

///|
pub fn unit_count(program : CheckedProgram) -> Int {
  program.units.length()
}

///|
pub fn unit_definition_cid(program : CheckedProgram, index : Int) -> String? {
  program.units.get(index).map(unit => unit.definition_cid)
}

///|
pub fn unit_pipeline(
  program : CheckedProgram,
  index : Int,
) -> @pipeline.CheckedPipeline? {
  program.units.get(index).map(unit => unit.pipeline)
}

///|
pub fn requirements(
  program : CheckedProgram,
) -> @context.StageRequirementClosure {
  program.requirements
}

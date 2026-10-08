///|
pub enum AuthoringCoreContractIssue {
  InvalidLimits
  BudgetExceeded
  ForeignSemantics
  StageInventory
  ForeignPublication(Int)
  UnsupportedIncoming(Int)
  UnsupportedLocalInputs(Int)
  UnsupportedTableInputs(Int)
  Collection(CoreContractIssue)
}

///|
/// Interpretation contracts retained from the exact prebinding Program and
/// closed publication owners. Other Program obligations remain separate; this
/// inventory is neither a template certificate nor execution permission.
struct AuthoringCoreContracts {
  source : SourceViewDeclarationPreparation
  semantics : @program_refs.ProgramSemantics
  publications : Array[AuthoringPublicationChecks]
  roots : Array[CoreContractRoot]
  bodies : Array[CoreContractBody]
  work : Int
  edges : Int
}

///|
/// Charge only this collection, as in CoreContractLimits. Retained input work
/// must be joined by the complete Program owner without resetting its budget.
pub fn collect_authoring_core_contracts(
  source : SourceViewDeclarationPreparation,
  semantics : @program_refs.ProgramSemantics,
  publications : Array[AuthoringPublicationChecks],
  limits : CoreContractLimits,
) -> Result[AuthoringCoreContracts, AuthoringCoreContractIssue] {
  if limits.max_work < 0 ||
    limits.max_roots < 0 ||
    limits.max_bodies < 0 ||
    limits.max_edges < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(
      @program_refs.program_semantics_usage(semantics),
      source.declarations,
    ) {
    return Err(ForeignSemantics)
  }
  let wiring = source.wiring
  let stages = @stage_results.wiring_source(wiring)
  let count = @stages.stage_count(stages)
  if publications.length() != count ||
    @program_refs.program_semantics_stage_count(semantics) != count {
    return Err(StageInventory)
  }
  let retained : Array[AuthoringPublicationChecks] = []
  let b : CoreContractBuilder = {
    limits,
    roots: [],
    bodies: [],
    seen: {},
    dependencies: {},
    work: 0,
    edges: 0,
    // These shared roots do not emit Local type/scores metadata. No fake hash
    // allowance or encoded Local input is admitted along this continuation.
    hash_limits: { max_bytes: 0, max_nodes: 0, max_depth: 0, },
    hash_bytes: 0,
    hash_nodes: 0,
  }
  try {
    core_contract_charge(b)
    for stage in 0..<count {
      core_contract_charge(b)
      let ports = @stage_results.wiring_stage_at(wiring, stage).unwrap()
      let publication = publications[stage]
      if !physical_equal(
          publication.ports,
          @stage_results.stage_port_publications(ports),
        ) {
        return Err(ForeignPublication(stage))
      }
      let syntax = @stages.stage_at(stages, stage).unwrap()
      if @syntax.import_count(syntax) != 0 ||
        syntax.predecessor != @syntax.Initial {
        return Err(UnsupportedIncoming(stage))
      }
      guard @stage_results.wiring_reconciled_input_at(wiring, stage)
        is Some(locals) else {
        return Err(UnsupportedLocalInputs(stage))
      }
      if @local_inputs.count(
          @local_inputs.snapshot_inputs(
            @local_inputs.environment_assertions(
              @local_inputs.reconciled_inputs(locals),
            ),
          ),
        ) !=
        0 {
        return Err(UnsupportedLocalInputs(stage))
      }
      if @stage_results.stage_port_table_inputs(ports) is Some(inputs) &&
        @results.table_input_count(inputs) != 0 {
        return Err(UnsupportedTableInputs(stage))
      }
      let pipeline = @parameter_slots.pipeline(
        @stages.collection(@stage_results.stage_port_source(ports)),
      )
      if !physical_equal(
          publication.owner.authoring.profiles.pipeline,
          pipeline,
        ) {
        return Err(ForeignPublication(stage))
      }
      retained.push(publication)
      core_contract_stage_environment_roots(b, stage)
      // Bound collection bills this visit before its Local inventory, even
      // when that inventory is empty. Preserve the same empty-stage boundary.
      core_contract_charge(b)
      core_contract_stage_semantic_roots(
        b,
        stage,
        @program_refs.stage_semantics_at(source.declarations, stage).unwrap(),
      )
      for result_index in 0..<@results.port_count(publication.ports) {
        core_contract_root(
          b,
          StagePublicationRules(stage, result_index),
          AdoptedBody(@pipeline.RelaPrimitive),
        )
      }
      core_contract_charge(b)
      core_contract_pipeline_roots(b, pipeline, stage, 0)
    }
    core_contract_complete_dependencies(b)
    Ok({
      source,
      semantics,
      publications: retained,
      roots: b.roots,
      bodies: b.bodies,
      work: b.work,
      edges: b.edges,
    })
  } catch {
    CoreContractStop(BudgetExceeded) => Err(BudgetExceeded)
    CoreContractStop(issue) => Err(Collection(issue))
  }
}

///|
pub fn authoring_core_contract_source(
  v : AuthoringCoreContracts,
) -> SourceViewDeclarationPreparation {
  v.source
}

///|
pub fn authoring_core_contract_semantics(
  v : AuthoringCoreContracts,
) -> @program_refs.ProgramSemantics {
  v.semantics
}

///|
pub fn authoring_core_contract_publication_at(
  v : AuthoringCoreContracts,
  stage : Int,
) -> AuthoringPublicationChecks? {
  v.publications.get(stage)
}

///|
pub fn authoring_core_contract_root_count(v : AuthoringCoreContracts) -> Int {
  v.roots.length()
}

///|
pub fn authoring_core_contract_root_at(
  v : AuthoringCoreContracts,
  index : Int,
) -> CoreContractRoot? {
  v.roots.get(index)
}

///|
pub fn authoring_core_contract_body_count(v : AuthoringCoreContracts) -> Int {
  v.bodies.length()
}

///|
pub fn authoring_core_contract_body_at(
  v : AuthoringCoreContracts,
  index : Int,
) -> CoreContractBody? {
  v.bodies.get(index)
}

///|
pub fn authoring_core_contract_usage(v : AuthoringCoreContracts) -> (Int, Int) {
  (v.work, v.edges)
}

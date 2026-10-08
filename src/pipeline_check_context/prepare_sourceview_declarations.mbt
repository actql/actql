///|
pub(all) struct SourceViewDeclarationLimits {
  max_work : Int
  max_bindings : Int
  max_slots : Int
  max_order_keys : Int
  inputs : @local_inputs.Limits
  topology : @stage_results.LocalProgramLimits
  body : @stage_body.Limits
  uses : @parameter_slots.Limits
  references : @program_refs.Limits
}

///|
pub enum SourceViewDeclarationIssue {
  InvalidLimits
  BudgetExceeded
  Registration(SourceRegistrationIssue)
  Program(SourceViewContextIssue)
  Requests(PrepareSourcesIssue)
  Identity(SourcePreparationIssue)
}

///|
struct SourceViewDeclarationPreparation {
  catalog : @environment.SourceRequestContracts
  wiring : @stage_results.ResultWiring
  topology : @stage_results.LocalProgramUsage
  declarations : @program_refs.DeclarationUsage
  work : Int
}

///|
/// Preserve the exact unbound topology and whole declaration-use inventory.
/// This preparation does not certify other static obligations or execution.
pub fn prepare_sourceview_declarations(
  source : @stages.Source,
  catalog : @environment.SourceRequestContracts,
  limits : SourceViewDeclarationLimits,
  calendar? : @environment.SelectedCalendarProfile? = None,
  model_tasks? : @environment.ModelTasks? = None,
) -> Result[SourceViewDeclarationPreparation, SourceViewDeclarationIssue] {
  if limits.max_work < 0 ||
    limits.max_bindings < 0 ||
    limits.max_slots < 0 ||
    limits.max_order_keys < 0 {
    return Err(InvalidLimits)
  }
  let (views, locals) = match
    prepare_source_registrations(
      source,
      catalog,
      {
        ..limits.inputs,
        max_work: limits.inputs.max_work.min(limits.max_work),
      },
      max_inputs=limits.max_slots,
      max_views=limits.max_slots,
      max_order_keys=limits.max_order_keys,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Registration(issue))
  }
  let (wiring, topology) = match
    prepare_sourceview_program(
      views,
      locals,
      {
        ..limits.topology,
        max_work: limits.topology.max_work.min(limits.max_work),
      },
      calendar~,
      model_tasks~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Program(Program(issue)))
  }
  // Topology already retains both registration and Local environment prefixes.
  // Charge that exact combined owner once, never the Local prefix again.
  let mut remaining = limits.max_work - topology.work
  let bindings = match
    @binding_declarations.prepare(@stages.program(source), {
      max_work: remaining,
      max_bindings: limits.max_bindings,
    }) {
    Ok(value) => value
    Err(issue) => return Err(Requests(Declarations(issue)))
  }
  let requests = match
    @request_slots.collect(source, bindings, {
      max_work: remaining,
      max_slots: limits.max_slots,
    }) {
    Ok(value) => value
    Err(issue) => return Err(Requests(Slots(issue)))
  }
  let count = @stages.stage_count(source)
  if count > remaining {
    return Err(BudgetExceeded)
  }
  let collected = Array::makei(count, stage => {
    @stage_results.stage_port_source(
      @stage_results.wiring_stage_at(wiring, stage).unwrap(),
    )
  })
  remaining -= count
  let declarations = match
    @program_refs.prepare_declaration_usage(
      requests,
      collected,
      limits.body,
      limits.uses,
      limits.references,
      max_work=remaining,
    ) {
    Ok(value) => value
    Err(issue) => {
      let retained : PreparedReferencesIssue = match issue {
        InvalidLimits => InvalidLimits
        BudgetExceeded => BudgetExceeded
        Body(stage, issue) => Body(stage, issue)
        Uses(stage, issue) => Uses(stage, issue)
        Inventory(issue) => Inventory(issue)
        Usage(issue) => Usage(issue)
      }
      return Err(Identity(References(retained)))
    }
  }
  remaining -= @program_refs.usage_work(declarations)
  Ok({
    catalog,
    wiring,
    topology,
    declarations,
    work: limits.max_work - remaining,
  })
}

///|
pub fn sourceview_declaration_catalog(
  value : SourceViewDeclarationPreparation,
) -> @environment.SourceRequestContracts {
  value.catalog
}

///|
pub fn sourceview_declaration_wiring(
  value : SourceViewDeclarationPreparation,
) -> @stage_results.ResultWiring {
  value.wiring
}

///|
pub fn sourceview_declaration_usage(
  value : SourceViewDeclarationPreparation,
) -> @program_refs.DeclarationUsage {
  value.declarations
}

///|
pub fn sourceview_declaration_work(
  value : SourceViewDeclarationPreparation,
) -> Int {
  value.work
}

///|
pub fn sourceview_declaration_topology_usage(
  value : SourceViewDeclarationPreparation,
) -> @stage_results.LocalProgramUsage {
  value.topology
}

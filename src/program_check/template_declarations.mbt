///|
/// Retained prebinding declaration, reference and topology owners. This phase
/// does not close resources, incoming/publication or all static obligations.
/// It cannot produce a CheckedProgram or complete template verification.
struct TemplateDeclarationPreparation {
  program : @syntax.Program
  environment : CheckEnvironment
  limits : CheckLimits
  catalog_references : @environment.CatalogReferences
  source : @context.SourceViewDeclarationPreparation
  work : Int
  bytes : Int
  nodes : Int
}

///|
/// Continue the existing common declaration and pipeline owners without
/// effective execution values. Authoring failures use the original typed
/// diagnostic causes, not messages or a second validation implementation.
pub fn prepare_template_declarations(
  program : @syntax.Program,
  environment : CheckEnvironment,
  limits : CheckLimits,
  source_preparation? : @stages.Source? = None,
) -> Result[TemplateDeclarationPreparation, LocalConstructionFailure] {
  if !compile_limits_valid(limits.compilation) {
    return Err(InvalidLimits)
  }
  match @syntax.validate_reuse(program, limits.input) {
    Ok(_) => ()
    Err(issue) => return Err(Program(issue))
  }
  let compilation = limits.compilation
  let selected_limits = limits
  let limits = compile_source_limits(compilation)
  let budget = IdentityBudget::{
    work: compilation.work,
    bytes: compilation.artifacts.bytes,
    nodes: compilation.artifacts.nodes,
    depth: compilation.artifacts.depth,
  }
  let declaration_work = audit_declarations(program, budget.work) catch {
    issue => return Err(Source(issue))
  }
  budget.work -= declaration_work
  let (catalog, catalog_references) = prepare_environment(
    environment.wire,
    budget,
  ) catch {
    issue => return Err(Environment(issue))
  }
  let source = match
    @stages.prepare(
      program,
      {
        max_parameters: limits.max_parameters,
        max_nodes: limits.requests.values.max_nodes,
        max_depth: limits.requests.values.max_depth,
        max_text_bytes: limits.requests.values.max_text_bytes,
      },
      original=source_preparation,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Source(Declarations(issue)))
  }
  let source = match
    @context.prepare_sourceview_declarations(
      source,
      catalog,
      {
        max_work: budget.work,
        max_bindings: limits.max_bindings,
        max_slots: limits.max_slots,
        max_order_keys: limits.max_slots,
        inputs: {
          max_work: budget.work,
          max_nodes: limits.context.max_local_input_nodes,
          max_depth: limits.max_policy_depth,
          max_text_bytes: limits.topology.max_text_bytes,
        },
        topology: limits.topology,
        body: limits.identity.body,
        uses: limits.identity.uses,
        references: limits.identity.references,
      },
      calendar=environment.calendar,
      model_tasks=environment.model_tasks,
    ) {
    Ok(value) => value
    Err(InvalidLimits) => return Err(InvalidLimits)
    Err(BudgetExceeded) => return Err(Source(DeclarationWorkLimit))
    Err(Registration(issue)) => return Err(Source(Registration(issue)))
    Err(Program(issue)) => return Err(Source(SourceView(issue)))
    Err(Requests(issue)) => return Err(Source(Requests(issue)))
    Err(Identity(issue)) => return Err(Source(Identity(issue)))
  }
  budget.work -= @context.sourceview_declaration_work(source)
  Ok({
    program,
    environment,
    limits: selected_limits,
    catalog_references,
    source,
    work: compilation.work - budget.work,
    bytes: compilation.artifacts.bytes - budget.bytes,
    nodes: compilation.artifacts.nodes - budget.nodes,
  })
}

///|
pub fn template_declarations_program(
  value : TemplateDeclarationPreparation,
) -> @syntax.Program {
  value.program
}

///|
pub fn template_declarations_environment(
  value : TemplateDeclarationPreparation,
) -> CheckEnvironment {
  value.environment
}

///|
pub fn template_declarations_source(
  value : TemplateDeclarationPreparation,
) -> @context.SourceViewDeclarationPreparation {
  value.source
}

///|
pub fn template_declarations_catalog(
  value : TemplateDeclarationPreparation,
) -> @environment.SourceRequestContracts {
  @context.sourceview_declaration_catalog(value.source)
}

///|
pub fn template_declarations_catalog_references(
  value : TemplateDeclarationPreparation,
) -> @environment.CatalogReferences {
  value.catalog_references
}

///|
pub fn template_declarations_wiring(
  value : TemplateDeclarationPreparation,
) -> @results.ResultWiring {
  @context.sourceview_declaration_wiring(value.source)
}

///|
pub fn template_declarations_usage(
  value : TemplateDeclarationPreparation,
) -> @references.DeclarationUsage {
  @context.sourceview_declaration_usage(value.source)
}

///|
pub fn template_declarations_preparation_usage(
  value : TemplateDeclarationPreparation,
) -> (Int, Int, Int) {
  (value.work, value.bytes, value.nodes)
}

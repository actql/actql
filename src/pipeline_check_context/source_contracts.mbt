///|
pub(all) struct SourceContractLimits {
  max_work : Int
  max_inputs : Int
  max_references : Int
} derive(Eq, Debug)

///|
pub(all) enum SourceContractIssue {
  InvalidLimits
  BudgetExceeded
  ForeignContext
} derive(Eq, Debug)

///|
struct SourceContractRequirements {
  context : ReconciledContexts
  stages : Array[Array[@sourceviews.ResolvedInput]]
  work : Int
  inputs : Int
  references : Int
}

///|
struct ProgramSourceContracts {
  identity : ProgramSourceIdentity
  requirements : SourceContractRequirements
  work : Int
}

///|
/// Retain selected SourceView declarations, including unused inputs. This is
/// an occurrence inventory, not a mode-specific or transitive contract closure.
pub fn collect_source_contracts(
  context : ReconciledContexts,
  limits : SourceContractLimits,
) -> Result[SourceContractRequirements, SourceContractIssue] {
  if limits.max_work < 0 || limits.max_inputs < 0 || limits.max_references < 0 {
    return Err(InvalidLimits)
  }
  let count = context.wired.stages.contexts.length()
  if context.usage.work >= limits.max_work ||
    count > limits.max_work - context.usage.work - 1 {
    return Err(BudgetExceeded)
  }
  let mut work = context.usage.work + 1 + count
  let mut inputs = 0
  let mut references = 0
  let stages = []
  for stage in 0..<count {
    let selected = []
    if context.sourceviews is Some(views) {
      let n = @sourceviews.pipeline_input_count(views, stage).unwrap()
      if n > limits.max_inputs - inputs || n > limits.max_work - work {
        return Err(BudgetExceeded)
      }
      work += n
      inputs += n
      for i in 0..<n {
        let input = @sourceviews.pipeline_input_source(views, stage, i).unwrap()
        let refs = @sourceviews.selected_reference_count(input)
        if refs > limits.max_references - references {
          return Err(BudgetExceeded)
        }
        references += refs
        selected.push(input)
      }
    }
    stages.push(selected)
  }
  Ok({ context, stages, work, inputs, references, })
}

///|
/// Join only at the exact input context already retained by the identity.
/// Equal Program/contract CIDs cannot substitute another admitted environment.
pub fn bind_program_source_contracts(
  identity : ProgramSourceIdentity,
  requirements : SourceContractRequirements,
  max_work : Int,
) -> Result[ProgramSourceContracts, SourceContractIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let context = identity.sources.operations.preparation.sources.capacity.context.rows.requests.inputs
  if !physical_equal(context, requirements.context) {
    return Err(ForeignContext)
  }
  let added = requirements.work - context.usage.work
  if identity.work >= max_work || added > max_work - identity.work - 1 {
    return Err(BudgetExceeded)
  }
  Ok({ identity, requirements, work: identity.work + added + 1, })
}

///|
pub fn source_contract_context(
  v : SourceContractRequirements,
) -> ReconciledContexts {
  v.context
}

///|
pub fn source_contract_usage(v : SourceContractRequirements) -> (Int, Int, Int) {
  (v.work, v.inputs, v.references)
}

///|
pub fn source_contract_stage_count(v : SourceContractRequirements) -> Int {
  v.stages.length()
}

///|
pub fn source_contract_input_count(
  v : SourceContractRequirements,
  stage : Int,
) -> Int? {
  v.stages.get(stage).map(xs => xs.length())
}

///|
pub fn source_contract_input_at(
  v : SourceContractRequirements,
  stage : Int,
  index : Int,
) -> @sourceviews.ResolvedInput? {
  v.stages.get(stage).bind(xs => xs.get(index))
}

///|
/// Interpret a selected reference through its own admitted Catalog, never a
/// caller-supplied replacement environment. None is only an absent occurrence;
/// an unsupported body is an error, not a dependency-free leaf.
pub fn source_contract_body_at(
  v : SourceContractRequirements,
  stage : Int,
  input : Int,
  reference : Int,
) -> Result[
  @environment.CatalogBodyDependencies?,
  @environment.BodyDependencyIssue,
] {
  guard source_contract_input_at(v, stage, input) is Some(selected) else {
    return Ok(None)
  }
  guard @sourceviews.selected_reference_at(selected, reference)
    is Some(selected_ref) else {
    return Ok(None)
  }
  let schemas = @environment.source_request_carriers(
    @sourceviews.catalog_owner(selected),
  )
  match
    @environment.check_catalog_body_dependencies(
      schemas,
      @environment.reference_contract(selected_ref),
    ) {
    Ok(body) => Ok(Some(body))
    Err(issue) => Err(issue)
  }
}

///|
pub fn program_source_contract_identity(
  v : ProgramSourceContracts,
) -> ProgramSourceIdentity {
  v.identity
}

///|
pub fn program_source_contract_requirements(
  v : ProgramSourceContracts,
) -> SourceContractRequirements {
  v.requirements
}

///|
pub fn program_source_contract_work(v : ProgramSourceContracts) -> Int {
  v.work
}

///|
/// Includes the lookup-facts admission from this identity's request checks.
/// Component admission cannot cover other fact extensions implicitly.
pub fn program_source_contract_body_at(
  v : ProgramSourceContracts,
  stage : Int,
  input : Int,
  reference : Int,
) -> Result[
  @environment.CatalogBodyDependencies?,
  @environment.BodyDependencyIssue,
] {
  guard source_contract_input_at(v.requirements, stage, input) is Some(selected) else {
    return Ok(None)
  }
  guard @sourceviews.selected_reference_at(selected, reference)
    is Some(selected_ref) else {
    return Ok(None)
  }
  let envelope = @environment.reference_contract(selected_ref)
  if @environment.contract_role(envelope) != "carrier_facts" {
    return source_contract_body_at(v.requirements, stage, input, reference)
  }
  let requests = v.identity.sources.operations.preparation.sources.capacity.context.rows.requests
  guard requests.facts is Some(facts) else {
    return Err(@environment.MissingBodyAdmission)
  }
  match @environment.check_lookup_body_dependencies(facts, envelope) {
    Ok(body) => Ok(Some(body))
    Err(issue) => Err(issue)
  }
}

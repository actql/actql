///|
pub(all) enum LocalCommonNormalizationIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOriginal
  CompletionObserved
  UnsupportedRequirement
} derive(Eq, Debug)

///|
/// Normalization custody only. The original operation/execution requirements
/// remain mandatory; this value is neither backend support nor permission.
struct LocalCommonNormalizationInventory {
  owner : CheckedProgram
  requirements : @context.StageRequirementClosure
  parameters : @parameters.BoundValues
  entries : Array[LocalSortNormalizationEntry]
  audited_work : Int
}

///|
priv struct LocalCommonAuditBudget {
  mut remaining : Int
}

///|
priv suberror LocalCommonAuditFailure {
  LocalCommonAuditFailure(LocalCommonNormalizationIssue)
}

///|
fn local_common_charge(
  budget : LocalCommonAuditBudget,
  work : Int,
) -> Unit raise LocalCommonAuditFailure {
  if work < 0 || work > budget.remaining {
    raise LocalCommonAuditFailure(BudgetExceeded)
  }
  budget.remaining -= work
}

///|
fn local_common_entry(
  entries : Array[LocalSortNormalizationEntry],
  entry : LocalSortNormalizationEntry,
  budget : LocalCommonAuditBudget,
) -> Unit raise LocalCommonAuditFailure {
  for prior in entries {
    local_common_charge(budget, 1)
    budget.remaining = local_sort_text_work(prior.path, budget.remaining).unwrap_or_else(() => {
        raise LocalCommonAuditFailure(BudgetExceeded)
      },
    )
    budget.remaining = local_sort_text_work(entry.path, budget.remaining).unwrap_or_else(() => {
        raise LocalCommonAuditFailure(BudgetExceeded)
      },
    )
    if prior.path == entry.path {
      if !physical_equal(prior.operation, entry.operation) ||
        prior.authored != entry.authored ||
        prior.canonical != entry.canonical {
        raise LocalCommonAuditFailure(ForeignOriginal)
      }
      // A shared original producer can be visited more than once. It still
      // denotes one completion occurrence, never two equal foreign bodies.
      return
    }
  }
  local_common_charge(budget, 1)
  entries.push(entry)
}

///|
/// Visit the already checked original occurrences. Fixed-operation meaning is
/// owned by typing, lowering and execution, not another normalization tag list.
/// All resource/numeric/time/backend requirements remain in the retained closure.
pub fn local_program_common_normalization_inventory(
  owner : CheckedProgram,
  max_work : Int,
) -> Result[LocalCommonNormalizationInventory, LocalCommonNormalizationIssue] {
  if owner.has_effects {
    return Err(UnsupportedRequirement)
  }
  audit_local_common_normalization_inventory(owner, max_work)
}

///|
// The Effect entry is called only after its original static Mapping closure.
// Share the same occurrence walk; do not duplicate an operation tag table.
fn audit_local_common_normalization_inventory(
  owner : CheckedProgram,
  max_work : Int,
) -> Result[LocalCommonNormalizationInventory, LocalCommonNormalizationIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let budget = { remaining: max_work, }
  try {
    local_common_charge(budget, 1)
    if owner.units.is_empty() {
      return Err(UnsupportedRequirement)
    }
    // Host Invocation Bindings are a distinct completion domain. Until their
    // actual entries are connected, their mere checked presence is insufficient.
    let root = @syntax.program_body(owner.source)
    local_common_charge(budget, @decode.object_length(root).unwrap())
    if @decode.lookup(@decode.open_object(root).unwrap(), "bindings")
      is Some(bindings) &&
      @decode.object_length(bindings).unwrap() > 0 {
      return Err(CompletionObserved)
    }
    let identity = owner.identity
    if @context.program_identity_stage_count(identity) != owner.units.length() {
      return Err(ForeignOriginal)
    }
    let operations = @context.stage_requirement_operations(owner.requirements)
    let index = @context.operation_closure_index(operations)
    let requirements = @context.operation_resolution_requirements(index)
    let expressions = @context.operation_requirements_expressions(requirements)
    if !physical_equal(
        @context.expression_closure_identity(expressions),
        identity,
      ) {
      return Err(ForeignOriginal)
    }
    // Keep every closed static resolution and mandatory execution check. None
    // is discharged by the normalization inventory or its empty journal.
    local_common_charge(budget, @context.operation_closure_count(operations))
    local_common_charge(budget, @context.expression_closure_count(expressions))
    let first = @context.program_identity_stage_at(identity, 0).unwrap()
    let parameters = @parameter_refs.bound_values(
      @context.stage_identity_parameter_values(first),
    )
    let declarations = @parameters.bound_declarations(parameters)
    if @parameters.bound_value_count(parameters) !=
      @parameters.declaration_count(declarations) {
      return Err(ForeignOriginal)
    }
    for parameter in 0..<@parameters.bound_value_count(parameters) {
      local_common_charge(budget, 1)
      let original = @parameters.bound_value_at(parameters, parameter).unwrap()
      local_common_charge(budget, original.name.length())
      if original.origin is @parameters.Default &&
        @parameters.bound_value_declaration(parameters, parameter) is None {
        return Err(ForeignOriginal)
      }
    }
    let entries : Array[LocalSortNormalizationEntry] = []
    for stage, unit in owner.units {
      local_common_charge(budget, 1)
      let original = @context.program_identity_stage_at(identity, stage).unwrap()
      let references = @context.stage_identity_parameter_values(original)
      if !physical_equal(unit.source, original) ||
        !physical_equal(@parameter_refs.bound_values(references), parameters) ||
        !physical_equal(
          @parameter_refs.declarations(@parameter_refs.bound_index(references)),
          declarations,
        ) {
        return Err(ForeignOriginal)
      }
      for execution in unit.source_execution {
        local_common_charge(budget, 1)
        if @sourceviews.completion_rule(execution.subject.source) is Some(_) {
          return Err(CompletionObserved)
        }
      }
      let visits = @context.program_identity_producer_count(identity, stage).unwrap()
      for visit in 0..<visits {
        local_common_charge(budget, 1)
        let pipeline = @context.program_identity_producer_at(
          identity, stage, visit,
        ).unwrap()
        for step in 0..<@pipeline.step_count(pipeline) {
          local_common_charge(budget, 1)
          let occurrence = @pipeline.step_at(pipeline, step).unwrap()
          match occurrence.operation {
            @pipeline.Unary(operation) =>
              match @relation.operation(operation) {
                Sort => {
                  let selected : Array[LocalSortNormalizationEntry] = []
                  match
                    audit_local_sort(
                      operation,
                      pipeline,
                      step,
                      budget.remaining,
                      Some(selected),
                    ) {
                    Ok(left) => budget.remaining = left
                    Err(CompletionObserved) => return Err(CompletionObserved)
                    Err(ProfileNotInstalled) =>
                      return Err(UnsupportedRequirement)
                  }
                  for entry in selected {
                    local_common_entry(entries, entry, budget)
                  }
                }
                Rename | Drop => {
                  guard local_projection_normalization_entry(
                      operation,
                      step,
                      budget.remaining,
                    )
                    is Some((entry, left)) else {
                    return Err(BudgetExceeded)
                  }
                  budget.remaining = left
                  local_common_entry(entries, entry, budget)
                }
                Group =>
                  if @relation.group_has_additional_prefix(
                      @relation.group(operation).unwrap(),
                    ) {
                    return Err(CompletionObserved)
                  }
                // Only source-changing cases are classified here. Existing
                // typed execution owners decide support for all fixed cases.
                _ => ()
              }
            _ => ()
          }
        }
        let slots = match
          @pipeline.collect_expression_slots(
            pipeline,
            max_work=budget.remaining,
            max_slots=budget.remaining,
          ) {
          Ok(value) => value
          Err(_) => return Err(BudgetExceeded)
        }
        local_common_charge(budget, @pipeline.expression_slots_work(slots))
        for slot in 0..<@pipeline.expression_slot_count(slots) {
          local_common_charge(budget, 1)
          let expression = @pipeline.expression_slot_at(slots, slot).unwrap().expression
          for node in 0..<@typing.node_count(expression) {
            local_common_charge(budget, 1)
            match @typing.node_form(expression, node).unwrap() {
              ImplicitNull | Expression("template", _) =>
                return Err(CompletionObserved)
              Expression("$param", source) => {
                let name = @decode.text(source).unwrap()
                let mut found = false
                for parameter in 0..<@parameters.bound_value_count(parameters) {
                  local_common_charge(budget, 1)
                  let original_name = @parameters.bound_value_at(
                      parameters, parameter,
                    ).unwrap().name
                  local_common_charge(budget, original_name.length())
                  local_common_charge(budget, name.length())
                  if original_name == name {
                    found = true
                    break
                  }
                }
                if !found {
                  return Err(ForeignOriginal)
                }
              }
              _ => ()
            }
          }
        }
      }
    }
    guard canonical_local_sort_entries(entries, budget.remaining) is Some(left) else {
      return Err(BudgetExceeded)
    }
    budget.remaining = left
    Ok({
      owner,
      requirements: owner.requirements,
      parameters,
      entries,
      audited_work: max_work - budget.remaining,
    })
  } catch {
    LocalCommonAuditFailure(issue) => Err(issue)
  }
}

///|
pub fn local_common_normalization_inventory_matches(
  inventory : LocalCommonNormalizationInventory,
  owner : CheckedProgram,
) -> Bool {
  physical_equal(inventory.owner, owner) &&
  physical_equal(inventory.requirements, owner.requirements) &&
  !owner.units.is_empty() &&
  physical_equal(
    inventory.parameters,
    @parameter_refs.bound_values(
      @context.stage_identity_parameter_values(owner.units[0].source),
    ),
  )
}

///|
pub fn local_common_normalization_inventory_work(
  inventory : LocalCommonNormalizationInventory,
) -> Int {
  inventory.audited_work
}

///|
pub fn local_common_normalization_inventory_requirements(
  inventory : LocalCommonNormalizationInventory,
) -> @context.StageRequirementClosure {
  inventory.requirements
}

///|
pub fn local_common_normalization_entry_count(
  inventory : LocalCommonNormalizationInventory,
) -> Int {
  inventory.entries.length()
}

///|
pub fn local_common_normalization_entry_at(
  inventory : LocalCommonNormalizationInventory,
  index : Int,
) -> (String, String, String, String)? {
  guard inventory.entries.get(index) is Some(entry) &&
    local_sort_entry_rule(entry) is Some(rule) else {
    return None
  }
  Some((entry.path, rule, entry.authored, entry.canonical))
}

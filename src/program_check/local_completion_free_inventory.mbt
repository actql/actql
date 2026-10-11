///|
/// A separate nominal inventory for the installed Effect-free Local profile.
/// It retains the original checker owner; equal Program CIDs do not grant custody.
struct LocalCompletionFreeInventory {
  owner : CheckedProgram
  audited_work : Int
}

///|
/// The original check audits existing typed owners without evaluating values,
/// rewriting input, fetching Source data or broadening the Resident profile.
fn audit_local_completion_free_units(
  program : @syntax.Program,
  units : Array[BuiltUnit],
) -> CompletionFreeAudit {
  if units.length() < 1 || units.length() > 3 {
    return ProfileNotInstalled
  }
  // This installed slice does not certify declaration defaults or templates.
  if !@syntax.program_parameter_names(program).is_empty() ||
    !@syntax.program_binding_names(program).is_empty() {
    return ProfileNotInstalled
  }
  let mut remaining = 10000
  let sources : Array[(Int, Int)] = []
  let mut roots = 0
  for unit in units {
    remaining -= 1
    for execution in unit.source_execution {
      if remaining <= 0 {
        return ProfileNotInstalled
      }
      remaining -= 1
      let subject = execution.subject
      // Sole-view selection is a real semantic completion recorded by its
      // resolver. A valid Source contract alone cannot certify this profile.
      if @sourceviews.completion_rule(subject.source) is Some(_) {
        return CompletionObserved
      }
      let key = (subject.stage, subject.input)
      if !sources.contains(key) {
        sources.push(key)
        roots += 1
        if roots > 1 {
          return ProfileNotInstalled
        }
      }
    }
    let pipeline = unit.pipeline
    for index in 0..<@pipeline.step_count(pipeline) {
      if remaining <= 0 {
        return ProfileNotInstalled
      }
      remaining -= 1
      let step = @pipeline.step_at(pipeline, index).unwrap()
      match step.operation {
        @pipeline.Values(_) => {
          roots += 1
          if roots > 1 {
            return ProfileNotInstalled
          }
        }
        @pipeline.Unary(operation) => {
          match @relation.operation(operation) {
            Filter | Select | Derive => ()
            _ => return ProfileNotInstalled
          }
          for binding in 0..<@relation.binding_count(operation) {
            if remaining <= 0 {
              return ProfileNotInstalled
            }
            remaining -= 1
            let expression = @relation.binding_expression_at(operation, binding).unwrap()
            for node in 0..<@typing.node_count(expression) {
              if remaining <= 0 {
                return ProfileNotInstalled
              }
              remaining -= 1
              match @typing.node_form(expression, node).unwrap() {
                ImplicitNull => return CompletionObserved
                Expression("template", _) => return CompletionObserved
                Expression(tag, _) =>
                  match tag {
                    "field"
                    | "literal"
                    | "typed_literal"
                    | "add"
                    | "subtract"
                    | "multiply"
                    | "eq"
                    | "neq"
                    | "lt"
                    | "lte"
                    | "gt"
                    | "gte"
                    | "and"
                    | "or"
                    | "not" => ()
                    _ => return ProfileNotInstalled
                  }
                _ => return ProfileNotInstalled
              }
            }
          }
        }
        _ => return ProfileNotInstalled
      }
    }
  }
  if roots != 1 {
    return ProfileNotInstalled
  }
  Complete(10000 - remaining)
}

///|
pub fn local_program_completion_free_inventory(
  owner : CheckedProgram,
) -> Result[LocalCompletionFreeInventory, CompletionFreeInventoryIssue] {
  if owner.has_effects {
    return Err(ProfileNotInstalled)
  }
  match owner.local_completion_free_audit {
    Complete(work) => Ok({ owner, audited_work: work, })
    ProfileNotInstalled => Err(ProfileNotInstalled)
    CompletionObserved => Err(CompletionObserved)
  }
}

///|
pub fn local_completion_free_inventory_matches(
  inventory : LocalCompletionFreeInventory,
  owner : CheckedProgram,
) -> Bool {
  physical_equal(inventory.owner, owner)
}

///|
pub fn local_completion_free_inventory_work(
  inventory : LocalCompletionFreeInventory,
) -> Int {
  inventory.audited_work
}

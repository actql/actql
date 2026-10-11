///|
/// A separate audit result retained by the original checked Program. Absence,
/// unsupported paths and observed completions never mean an empty inventory.
priv enum CompletionFreeAudit {
  Complete(Int)
  ProfileNotInstalled
  CompletionObserved
}

///|
pub(all) enum CompletionFreeInventoryIssue {
  ProfileNotInstalled
  CompletionObserved
  ForeignPreparation
} derive(Eq, Debug)

///|
/// This nominal projection retains the original checked owner, not caller
/// supplied counters, source shape or a reconstructed Program.
struct CompletionFreeInventory {
  owner : CheckedProgram
  audited_work : Int
}

///|
/// Audit actual selected Source owners and typed operation/expression owners.
/// This finite profile has no semantic rewrite site: Values admission, field
/// projection and ordinary predicates retain their authored semantic tree.
/// The bounded walk is independent of the checker's success and diagnostics.
fn audit_completion_free_units(units : Array[BuiltUnit]) -> CompletionFreeAudit {
  if units.length() < 1 || units.length() > 2 {
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
            Filter | Select => ()
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
                    | "$param"
                    | "literal"
                    | "typed_literal"
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
/// Read the inventory established during the original computation check.
/// Static Effect closure must also belong to that same checked owner.
pub fn effect_program_completion_free_inventory(
  candidate : EffectProgramStaticCandidate,
) -> Result[CompletionFreeInventory, CompletionFreeInventoryIssue] {
  let owner = candidate.computation.checked
  let headers = candidate.computation.headers
  if @syntax.effect_header_count(headers) != 1 {
    return Err(ProfileNotInstalled)
  }
  let header = @syntax.effect_header_at(headers, 0).unwrap()
  if @syntax.effect_header_kind(header) != "create" ||
    !@syntax.effect_header_contract_ref(header).has_prefix("mapping:") {
    return Err(ProfileNotInstalled)
  }
  match owner.completion_free_audit {
    Complete(work) => Ok({ owner, audited_work: work, })
    ProfileNotInstalled => Err(ProfileNotInstalled)
    CompletionObserved => Err(CompletionObserved)
  }
}

///|
pub fn completion_free_inventory_matches(
  inventory : CompletionFreeInventory,
  candidate : EffectProgramStaticCandidate,
) -> Bool {
  physical_equal(inventory.owner, candidate.computation.checked)
}

///|
pub fn completion_free_inventory_work(
  inventory : CompletionFreeInventory,
) -> Int {
  inventory.audited_work
}

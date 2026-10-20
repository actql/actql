///|
priv enum LocalCompletionFreeAudit {
  Complete(Int, @parameters.BoundValues?, Bool, Bool)
  ProfileNotInstalled
  CompletionObserved
}

///|
/// A separate nominal inventory for the installed Effect-free Local profile.
/// It retains the original checker owner; equal Program CIDs do not grant custody.
struct LocalCompletionFreeInventory {
  owner : CheckedProgram
  audited_work : Int
  supplied_parameters : @parameters.BoundValues?
  explicit_cast : Bool
  checked_expressions : Bool
}

///|
// Closed context-free operations already lowered and executed by the existing
// checked expression owners. This is not permission inferred from checker
// success: new tags and Run-bound time still require a separate connection.
fn local_completion_free_checked_expression(tag : String) -> Bool {
  match tag {
    "abs"
    | "acos"
    | "acosh"
    | "array"
    | "asin"
    | "asinh"
    | "atan"
    | "atan2"
    | "atanh"
    | "between"
    | "byte_length"
    | "case"
    | "cbrt"
    | "chr"
    | "coalesce"
    | "concat"
    | "concat_strict"
    | "contains"
    | "cos"
    | "cosh"
    | "date_add"
    | "date_diff"
    | "date_trunc"
    | "decimal_divide"
    | "divide"
    | "empty_array"
    | "ends_with"
    | "exp"
    | "floor"
    | "greatest"
    | "if"
    | "in"
    | "instr"
    | "is_distinct_from"
    | "is_false"
    | "is_null"
    | "is_true"
    | "is_unknown"
    | "least"
    | "left"
    | "len"
    | "ln"
    | "log"
    | "log10"
    | "lower"
    | "lpad"
    | "ltrim"
    | "modulo"
    | "negate"
    | "not_in"
    | "not_null"
    | "nullif"
    | "object"
    | "pow"
    | "property"
    | "quantize"
    | "repeat"
    | "replace"
    | "reverse"
    | "right"
    | "round"
    | "rpad"
    | "rtrim"
    | "safe_add"
    | "safe_divide"
    | "safe_multiply"
    | "safe_negate"
    | "safe_subtract"
    | "sign"
    | "sin"
    | "sinh"
    | "split"
    | "sqrt"
    | "starts_with"
    | "strpos"
    | "subscript"
    | "substring"
    | "tan"
    | "tanh"
    | "timestamp_add"
    | "timestamp_sub"
    | "translate"
    | "trim"
    | "trunc"
    | "try_decimal"
    | "try_number"
    | "unicode"
    | "upper"
    | "utf8_truncate" => true
    _ => false
  }
}

///|
/// The original check audits existing typed owners without evaluating values,
/// rewriting input, fetching Source data or broadening the Resident profile.
fn audit_local_completion_free_units(
  program : @syntax.Program,
  identity : @context.ProgramSourceIdentity,
  units : Array[BuiltUnit],
) -> LocalCompletionFreeAudit {
  if units.length() < 1 || units.length() > 3 {
    return ProfileNotInstalled
  }
  // Invocation Bindings remain a separate completion domain.
  if !@syntax.program_binding_names(program).is_empty() {
    return ProfileNotInstalled
  }
  let mut remaining = 10000
  let names = @syntax.program_parameter_names(program)
  let supplied_parameters = if names.is_empty() {
    None
  } else {
    if names.length() >= remaining ||
      @context.program_identity_stage_count(identity) != units.length() {
      return ProfileNotInstalled
    }
    remaining -= names.length()
    let first = @context.program_identity_stage_at(identity, 0).unwrap()
    let values = @parameter_refs.bound_values(
      @context.stage_identity_parameter_values(first),
    )
    let declarations = @parameters.bound_declarations(values)
    if @parameters.declaration_count(declarations) != names.length() ||
      @parameters.bound_value_count(values) != names.length() {
      return ProfileNotInstalled
    }
    // These are the original complete bindings, including unused declarations.
    // Equal effective values intentionally do not establish Supplied origin.
    for index in 0..<@parameters.bound_value_count(values) {
      if remaining <= 0 {
        return ProfileNotInstalled
      }
      remaining -= 1
      let value = @parameters.bound_value_at(values, index).unwrap()
      if !(value.origin is @parameters.Supplied) {
        return ProfileNotInstalled
      }
    }
    for index, unit in units {
      if remaining <= 0 {
        return ProfileNotInstalled
      }
      remaining -= 1
      let stage = @context.program_identity_stage_at(identity, index).unwrap()
      let references = @context.stage_identity_parameter_values(stage)
      if !physical_equal(unit.source, stage) ||
        !physical_equal(@parameter_refs.bound_values(references), values) ||
        !physical_equal(
          @parameter_refs.declarations(@parameter_refs.bound_index(references)),
          declarations,
        ) {
        return ProfileNotInstalled
      }
    }
    Some(values)
  }
  let mut explicit_cast = false
  let mut checked_expressions = false
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
                Expression("cast", _) => explicit_cast = true
                Expression("$param", _) =>
                  if supplied_parameters is None {
                    return ProfileNotInstalled
                  }
                MembershipList(_) => checked_expressions = true
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
                    _ =>
                      if local_completion_free_checked_expression(tag) {
                        checked_expressions = true
                      } else {
                        return ProfileNotInstalled
                      }
                  }
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
  Complete(
    10000 - remaining,
    supplied_parameters,
    explicit_cast,
    checked_expressions,
  )
}

///|
pub fn local_program_completion_free_inventory(
  owner : CheckedProgram,
) -> Result[LocalCompletionFreeInventory, CompletionFreeInventoryIssue] {
  if owner.has_effects {
    return Err(ProfileNotInstalled)
  }
  match owner.local_completion_free_audit {
    Complete(work, supplied_parameters, explicit_cast, checked_expressions) =>
      Ok({
        owner,
        audited_work: work,
        supplied_parameters,
        explicit_cast,
        checked_expressions,
      })
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

///|
/// Profile metadata from the retained original audit, never an input permission.
pub fn local_completion_free_inventory_parameters_supplied(
  inventory : LocalCompletionFreeInventory,
) -> Bool {
  inventory.supplied_parameters is Some(_)
}

///|
/// Metadata from the original checked expression traversal, not caller input.
pub fn local_completion_free_inventory_uses_explicit_cast(
  inventory : LocalCompletionFreeInventory,
) -> Bool {
  inventory.explicit_cast
}

///|
/// Output metadata from the full original audit, never caller-supplied consent.
pub fn local_completion_free_inventory_uses_checked_expressions(
  inventory : LocalCompletionFreeInventory,
) -> Bool {
  inventory.checked_expressions
}

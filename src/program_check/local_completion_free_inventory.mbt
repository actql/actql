///|
priv enum LocalCompletionFreeAudit {
  Complete(Int, @parameters.BoundValues?, Bool, Bool, Bool, Bool, Bool)
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
  groups : Bool
  takes : Bool
  sorts : Bool
}

///|
priv enum LocalSortAuditIssue {
  ProfileNotInstalled
  CompletionObserved
}

///|
// A resolved order is not permission to manufacture a completion-free journal.
// Only original identity sorts, covered candidate keys, and retained total-order
// witnesses require no appended source terms. Real key completion stays explicit.
fn audit_local_completion_free_sort(
  operation : @relation.CheckedOperation,
  pipeline : @pipeline.CheckedPipeline,
  step : Int,
  available : Int,
) -> Result[Int, LocalSortAuditIssue] {
  if available <= 0 || @relation.operation(operation) != @relation.Sort {
    return Err(ProfileNotInstalled)
  }
  guard @pipeline.step_at(pipeline, step)
    is Some({ operation: @pipeline.Unary(original), .. }) &&
    physical_equal(original, operation) else {
    return Err(ProfileNotInstalled)
  }
  let mut remaining = available - 1
  let terms = @relation.sort_term_count(operation)
  for index in 0..<terms {
    if remaining <= 0 || @relation.sort_term_at(operation, index) is None {
      return Err(ProfileNotInstalled)
    }
    remaining -= 1
  }
  // The checked empty operation preserves its input and creates no new order.
  if terms == 0 {
    return Ok(remaining)
  }
  if remaining <= 0 {
    return Err(ProfileNotInstalled)
  }
  remaining -= 1
  guard @pipeline.sort_order(pipeline, step) is Some(order) &&
    physical_equal(@pipeline.sort_order_pipeline(order), pipeline) &&
    @pipeline.sort_order_step(order) == step else {
    return Err(ProfileNotInstalled)
  }
  match @pipeline.sort_order_strategy(order) {
    CandidateKey(completion) => {
      if @pipeline.sort_completion_count(completion) != 0 {
        return Err(CompletionObserved)
      }
      let key = @pipeline.sort_completion_key(completion)
      for index in 0..<@evidence.key_field_count(key) {
        if remaining <= 0 || @evidence.key_field_at(key, index) is None {
          return Err(ProfileNotInstalled)
        }
        remaining -= 1
      }
    }
    ExistingTotal(prior) => {
      guard @pipeline.order_tie_break(@pipeline.sort_order_evidence(order))
        is Some(original) &&
        physical_equal(original, prior) else {
        return Err(ProfileNotInstalled)
      }
    }
  }
  Ok(remaining)
}

///|
// Inspect the original checked Take and its already closed operation-scalar
// resolutions. This does not interpret a Number/String or rebind Parameters.
fn audit_local_completion_free_take(
  operation : @relation.CheckedOperation,
  pipeline : @pipeline.CheckedPipeline,
  step : Int,
  values : @parameters.BoundValues?,
  closure : @context.ProgramOperationClosure,
  available : Int,
) -> Int? {
  guard @relation.row_operation(operation) is Some(Take(count~, offset~)) else {
    return None
  }
  let mut remaining = available
  for (role, minimum) in [(count, 1L), (offset, 0L)] {
    if remaining <= 0 {
      return None
    }
    remaining -= 1
    match role {
      Literal(n) => if n < minimum || n > 9007199254740991L { return None }
      Parameter(name) => {
        guard values is Some(values) &&
          @relation.parameters(operation) is Some(declarations) &&
          physical_equal(declarations, @parameters.bound_declarations(values)) else {
          return None
        }
        let mut selected : @parameters.BoundParameter? = None
        for index in 0..<@parameters.bound_value_count(values) {
          if remaining <= 0 {
            return None
          }
          remaining -= 1
          let original = @parameters.bound_value_at(values, index).unwrap()
          if original.name == name {
            selected = Some(original)
            break
          }
        }
        guard selected is Some(original) &&
          original.origin is @parameters.Supplied else {
          return None
        }
        let mut found = false
        for index in 0..<@context.operation_closure_count(closure) {
          if remaining <= 0 {
            return None
          }
          remaining -= 1
          guard @context.operation_closure_at(closure, index)
            is Some(StaticResolution(Scalar(resolved))) &&
            physical_equal(resolved.site.pipeline, pipeline) &&
            resolved.site.step == step &&
            physical_equal(resolved.parameter, original) else {
            continue
          }
          guard @pipeline.operation_scalar_demand(resolved.site.requirement)
            is Some(SafeInteger(wanted, minimum=required)) &&
            wanted == name &&
            required == minimum &&
            resolved.value is Integer(n) &&
            n >= minimum &&
            n <= 9007199254740991L else {
            continue
          }
          found = true
          break
        }
        if !found {
          return None
        }
      }
    }
  }
  Some(remaining)
}

///|
// Audit the existing count and extrema reduction family. Ordered, collection and
// numeric-policy reductions keep their separate completion/resource owners.
// Returning a remaining budget never grants execution or validates an input row.
fn audit_local_completion_free_group(
  operation : @relation.CheckedOperation,
  available : Int,
) -> Int? {
  guard @relation.group(operation) is Some(group) else { return None }
  if @relation.group_has_additional_prefix(group) {
    return None
  }
  let mut remaining = available
  for index in 0..<@relation.group_key_count(group) {
    if remaining <= 0 {
      return None
    }
    remaining -= 1
    let key = @relation.group_key_at(group, index).unwrap()
    // The original ordinary Group owner retains each authored key cursor.
    if !(@decode.view(key.source) is @decode.TextValue(_)) {
      return None
    }
  }
  for index in 0..<@relation.aggregate_count(group) {
    if remaining <= 0 {
      return None
    }
    remaining -= 1
    let call = @relation.aggregate_at(group, index).unwrap()
    match @relation.aggregate_function(call) {
      Count | CountIf | Min | Max => ()
      _ => return None
    }
    if @relation.aggregate_order_count(call) != 0 ||
      @relation.aggregate_item_limit(call) is Some(_) ||
      @relation.aggregate_byte_limit(call) is Some(_) ||
      @relation.aggregate_fraction(call) is Some(_) ||
      @relation.aggregate_delimiter(call) is Some(_) {
      return None
    }
    match @relation.aggregate_argument(call) {
      Rows => ()
      Field(key) =>
        if !(@decode.view(key.source) is @decode.TextValue(_)) {
          return None
        }
      Expression(binding) =>
        if binding < 0 || binding >= @relation.binding_count(operation) {
          return None
        }
    }
    if @relation.aggregate_filter(call) is Some(binding) &&
      (binding < 0 || binding >= @relation.binding_count(operation)) {
      return None
    }
  }
  Some(remaining)
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
  requirements : @context.StageRequirementClosure,
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
  let mut groups = false
  let mut takes = false
  let mut sorts = false
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
            Sort => {
              match
                audit_local_completion_free_sort(
                  operation, pipeline, index, remaining,
                ) {
                Ok(left) => remaining = left
                Err(CompletionObserved) => return CompletionObserved
                Err(ProfileNotInstalled) => return ProfileNotInstalled
              }
              sorts = true
            }
            Take => {
              guard audit_local_completion_free_take(
                  operation,
                  pipeline,
                  index,
                  supplied_parameters,
                  @context.stage_requirement_operations(requirements),
                  remaining,
                )
                is Some(left) else {
                return ProfileNotInstalled
              }
              remaining = left
              takes = true
            }
            Group => {
              guard audit_local_completion_free_group(operation, remaining)
                is Some(left) else {
                return ProfileNotInstalled
              }
              remaining = left
              groups = true
            }
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
    groups,
    takes,
    sorts,
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
    Complete(
      work,
      supplied_parameters,
      explicit_cast,
      checked_expressions,
      groups,
      takes,
      sorts
    ) =>
      Ok({
        owner,
        audited_work: work,
        supplied_parameters,
        explicit_cast,
        checked_expressions,
        groups,
        takes,
        sorts,
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

///|
/// Original audited Group metadata, not a caller-selected profile or permission.
pub fn local_completion_free_inventory_uses_groups(
  inventory : LocalCompletionFreeInventory,
) -> Bool {
  inventory.groups
}

///|
/// Metadata from original checked Take roles, never a caller-supplied profile.
pub fn local_completion_free_inventory_uses_take(
  inventory : LocalCompletionFreeInventory,
) -> Bool {
  inventory.takes
}

///|
/// Original order evidence, without an invented tie-break or a completion ACK.
pub fn local_completion_free_inventory_uses_sort(
  inventory : LocalCompletionFreeInventory,
) -> Bool {
  inventory.sorts
}

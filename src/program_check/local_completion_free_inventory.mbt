///|
priv enum LocalCompletionFreeAudit {
  Complete(Int, @parameters.BoundValues?, Bool, Bool, Bool, Bool, Bool)
  DistinctComplete(Int, @parameters.BoundValues?, Bool, Bool, Bool, Bool, Bool)
  SortCompleted(Int, Array[LocalSortNormalizationEntry])
  DistinctSortCompleted(Int, Array[LocalSortNormalizationEntry])
  SetComplete(Int, @parameters.BoundValues?, Bool, Bool, Bool, Bool, Bool, Bool)
  SetSortCompleted(Int, Array[LocalSortNormalizationEntry], Bool)
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
  distincts : Bool
  sets : Bool
}

///|
fn local_audit_uses_distinct(audit : LocalCompletionFreeAudit) -> Bool {
  match audit {
    DistinctComplete(_, _, _, _, _, _, _) | DistinctSortCompleted(_, _) => true
    SetComplete(_, _, _, _, _, _, _, distincts)
    | SetSortCompleted(_, _, distincts) => distincts
    _ => false
  }
}

///|
fn local_audit_uses_set(audit : LocalCompletionFreeAudit) -> Bool {
  match audit {
    SetComplete(_, _, _, _, _, _, _, _) | SetSortCompleted(_, _, _) => true
    _ => false
  }
}

///|
// Inspect only the original checked occurrence. Whole-row DISTINCT preserves
// the input schema; keyed DISTINCT projects its original Required references.
// Complete row admission, equality, first occurrence and presence remain with
// their existing execution owners, not this normalization inventory.
fn audit_local_completion_free_distinct(
  operation : @relation.CheckedOperation,
  pipeline : @pipeline.CheckedPipeline,
  step : Int,
  available : Int,
) -> Int? {
  guard available > 0 &&
    @relation.operation(operation) == @relation.Distinct &&
    @pipeline.step_at(pipeline, step) is Some(original) &&
    original.operation is @pipeline.Unary(checked) &&
    physical_equal(checked, operation) else {
    return None
  }
  let input = @relation.input_schema(operation)
  let output = @relation.output_schema(operation)
  guard @pipeline.step_schema(original) is Some(schema) &&
    physical_equal(schema, output) else {
    return None
  }
  let mut remaining = available - 1
  match @relation.row_operation(operation) {
    Some(DistinctRows) => {
      guard physical_equal(input, output) &&
        @relation.projection_field_count(operation) == 0 else {
        return None
      }
      for index in 0..<@schema.field_count(input) {
        if remaining <= 0 || @schema.field_at(input, index) is None {
          return None
        }
        remaining -= 1
      }
    }
    Some(DistinctKeys(keys)) => {
      guard !keys.is_empty() &&
        keys.length() == @schema.field_count(output) &&
        keys.length() == @relation.projection_field_count(operation) else {
        return None
      }
      for index in 0..<keys.length() {
        if remaining <= 0 {
          return None
        }
        remaining -= 1
        let key = keys[index]
        guard @relation.projection_field_at(operation, index)
          is Some(projection) &&
          projection.input == key.field &&
          projection.output == key.field else {
          return None
        }
        let name = @schema.reference_name(key.field)
        let mut width = @schema.field_count(input)
        while width > 0 {
          if remaining <= 0 || name.length() > remaining - 1 {
            return None
          }
          remaining -= name.length() + 1
          width /= 2
        }
        width = @schema.field_count(output)
        while width > 0 {
          if remaining <= 0 || name.length() > remaining - 1 {
            return None
          }
          remaining -= name.length() + 1
          width /= 2
        }
        // Schema storage is canonical, while the authored key priority may
        // differ. Resolve both original schema members by their checked name.
        guard @schema.lookup_reference(input, name) is Some(original_field) &&
          @schema.lookup_reference(output, name) is Some(field) &&
          original_field.presence is @schema.Required &&
          field.presence is @schema.Required &&
          physical_equal(field.contract, original_field.contract) else {
          return None
        }
      }
    }
    _ => return None
  }
  Some(remaining)
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
  audit_local_sort(operation, pipeline, step, available, None)
}

///|
fn audit_local_sort(
  operation : @relation.CheckedOperation,
  pipeline : @pipeline.CheckedPipeline,
  step : Int,
  available : Int,
  entries : Array[LocalSortNormalizationEntry]?,
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
  let evidence = @pipeline.sort_order_evidence(order)
  guard @pipeline.order_origin(evidence) == @pipeline.Step(step) &&
    @pipeline.order_producer(evidence)
    is Some({ operation: @pipeline.Unary(producer), .. }) &&
    physical_equal(producer, operation) else {
    return Err(ProfileNotInstalled)
  }
  match @pipeline.sort_order_strategy(order) {
    CandidateKey(completion) => {
      if @pipeline.sort_completion_count(completion) != 0 && entries is None {
        return Err(CompletionObserved)
      }
      let key = @pipeline.sort_completion_key(completion)
      for index in 0..<@evidence.key_field_count(key) {
        if remaining <= 0 || @evidence.key_field_at(key, index) is None {
          return Err(ProfileNotInstalled)
        }
        remaining -= 1
      }
      if @pipeline.sort_completion_count(completion) != 0 {
        guard entries is Some(entries) else { return Err(CompletionObserved) }
        match local_sort_normalization_entry(operation, order, remaining) {
          Some((entry, left)) => {
            remaining = left
            entries.push(entry)
          }
          None => return Err(ProfileNotInstalled)
        }
      }
    }
    ExistingTotal(prior) => {
      guard @pipeline.order_dependency_count(evidence) == 1 &&
        @pipeline.order_dependency_at(evidence, 0) ==
        Some(@pipeline.sort_order_input(order)) &&
        @pipeline.order_tie_break(evidence) is Some(original) &&
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
  if units.is_empty() {
    return ProfileNotInstalled
  }
  // Invocation Bindings remain a separate completion domain.
  if !@syntax.program_binding_names(program).is_empty() {
    return ProfileNotInstalled
  }
  let mut remaining = 10000
  // The earlier catalogues retain their three-unit scope. A binary set query
  // can have separate original seed, operand, merge and publication units.
  // Audit that original shape, never a flattened or substituted Program.
  if units.length() > 3 {
    if units.length() > remaining {
      return ProfileNotInstalled
    }
    remaining -= units.length()
    let mut original_binary = false
    for unit in units {
      for index in 0..<@pipeline.step_count(unit.pipeline) {
        if remaining <= 0 {
          return ProfileNotInstalled
        }
        remaining -= 1
        match @pipeline.step_at(unit.pipeline, index).unwrap().operation {
          @pipeline.Append(..) | @pipeline.Set(..) => original_binary = true
          _ => ()
        }
      }
    }
    if !original_binary {
      return ProfileNotInstalled
    }
  }
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
  let mut distincts = false
  let mut sets = false
  let sort_entries : Array[LocalSortNormalizationEntry] = []
  let sources : Array[(Int, Int)] = []
  let mut roots = 0
  for unit in units {
    if remaining <= 0 {
      return ProfileNotInstalled
    }
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
        if sources.length() > 1 {
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
        @pipeline.Values(_) => roots += 1
        @pipeline.Append(..) | @pipeline.Set(..) => {
          guard audit_local_completion_free_binary(
              step.operation,
              pipeline,
              index,
              remaining,
            )
            is Some(left) else {
            return ProfileNotInstalled
          }
          remaining = left
          sets = true
        }
        @pipeline.Unary(operation) => {
          match @relation.operation(operation) {
            Filter | Select | Derive => ()
            Distinct => {
              guard audit_local_completion_free_distinct(
                  operation, pipeline, index, remaining,
                )
                is Some(left) else {
                return ProfileNotInstalled
              }
              remaining = left
              distincts = true
            }
            Sort => {
              match
                audit_local_sort(
                  operation,
                  pipeline,
                  index,
                  remaining,
                  Some(sort_entries),
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
  if roots < 1 || (roots != 1 && !sets) {
    return ProfileNotInstalled
  }
  if !sort_entries.is_empty() {
    guard canonical_local_sort_entries(sort_entries, remaining) is Some(left) else {
      return ProfileNotInstalled
    }
    return if sets {
      SetSortCompleted(10000 - left, sort_entries, distincts)
    } else if distincts {
      DistinctSortCompleted(10000 - left, sort_entries)
    } else {
      SortCompleted(10000 - left, sort_entries)
    }
  }
  if sets {
    return SetComplete(
      10000 - remaining,
      supplied_parameters,
      explicit_cast,
      checked_expressions,
      groups,
      takes,
      sorts,
      distincts,
    )
  }
  if distincts {
    return DistinctComplete(
      10000 - remaining,
      supplied_parameters,
      explicit_cast,
      checked_expressions,
      groups,
      takes,
      sorts,
    )
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
    )
    | DistinctComplete(
      work,
      supplied_parameters,
      explicit_cast,
      checked_expressions,
      groups,
      takes,
      sorts
    )
    | SetComplete(
      work,
      supplied_parameters,
      explicit_cast,
      checked_expressions,
      groups,
      takes,
      sorts,
      _
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
        distincts: local_audit_uses_distinct(owner.local_completion_free_audit),
        sets: local_audit_uses_set(owner.local_completion_free_audit),
      })
    ProfileNotInstalled => Err(ProfileNotInstalled)
    CompletionObserved
    | SortCompleted(_, _)
    | DistinctSortCompleted(_, _)
    | SetSortCompleted(_, _, _) => Err(CompletionObserved)
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

///|
/// Original audited DISTINCT metadata; not a caller profile or row-admission fact.
pub fn local_completion_free_inventory_uses_distinct(
  inventory : LocalCompletionFreeInventory,
) -> Bool {
  inventory.distincts
}

///|
/// Metadata of original checked Append/Set inputs, never row or Source authority.
pub fn local_completion_free_inventory_uses_set(
  inventory : LocalCompletionFreeInventory,
) -> Bool {
  inventory.sets
}

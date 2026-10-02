///|
/// Association with the exact checked owner, not merely matching parameter
/// names or equal-looking declarations from another invocation.
struct BoundPrepared {
  prepared : Prepared
  bindings : @parameter.BoundValues?
  by_name : Map[String, @value.CheckedValue]
  expression_profiles : ExpressionProfileAdmission
}

///|
/// Profiles already selected by the enclosing checked Program. This is a
/// lowering input, not proof of backend capability or an execution permit.
pub(all) struct ExpressionProfileAdmission {
  text_time : Bool
  veca : Bool
} derive(Eq, Debug)

///|
pub(all) enum BindingIssueKind {
  InvalidBindingLimits
  BindingOwnerMismatch
  MissingBindings
  BindingBudgetExceeded
} derive(Eq, Debug)

///|
pub struct BindingIssue {
  kind : BindingIssueKind
  source : @decode.Cursor
}

///|
pub fn bind_parameters(
  prepared : Prepared,
  bindings : @parameter.BoundValues?,
  max_parameters~ : Int,
  max_name_bytes~ : Int,
  expression_profiles? : ExpressionProfileAdmission = {
    text_time: false,
    veca: false,
  },
) -> Result[BoundPrepared, BindingIssue] {
  let source = @pipeline.source(prepared.owner)
  resolve_expression_bindings(
    source,
    @pipeline.parameters(prepared.owner),
    bindings,
    max_parameters,
    max_name_bytes,
  ).map(resolved => {
    prepared,
    bindings,
    by_name: resolved.0,
    expression_profiles,
  })
}

///|
/// Shared exact declaration binding; this is not execution admission.
fn resolve_expression_bindings(
  source : @decode.Cursor,
  declared : @parameter.Declarations?,
  bindings : @parameter.BoundValues?,
  max_parameters : Int,
  max_name_bytes : Int,
) -> Result[(Map[String, @value.CheckedValue], Int, Int), BindingIssue] {
  if max_parameters < 0 || max_name_bytes < 0 {
    return Err({ kind: InvalidBindingLimits, source, })
  }
  let by_name : Map[String, @value.CheckedValue] = Map([])
  let mut count = 0
  let mut remaining = max_name_bytes
  match bindings {
    None =>
      if declared is Some(d) && @parameter.declaration_count(d) > 0 {
        return Err({ kind: MissingBindings, source, })
      }
    Some(bound) => {
      guard declared is Some(d) &&
        physical_equal(d, @parameter.bound_declarations(bound)) else {
        return Err({ kind: BindingOwnerMismatch, source, })
      }
      count = @parameter.bound_value_count(bound)
      if count > max_parameters {
        return Err({ kind: BindingBudgetExceeded, source, })
      }
      for i = 0; i < count; i = i + 1 {
        // BoundValues is opaque and only built by parameter_binding.bind.
        let parameter = @parameter.bound_value_at(bound, i).unwrap()
        // Bound admission already validated Unicode. Avoid encoding a name
        // that cannot fit even its UTF-16 length, then measure exact UTF-8.
        if parameter.name.length() > remaining {
          return Err({ kind: BindingBudgetExceeded, source, })
        }
        let bytes = @utf8.encode(parameter.name).length()
        if bytes > remaining {
          return Err({ kind: BindingBudgetExceeded, source, })
        }
        remaining -= bytes
        by_name[parameter.name] = parameter.value
      }
    }
  }
  Ok((by_name, count, max_name_bytes - remaining))
}

///|
fn expression_profile_admitted(value : BoundPrepared, profile : String) -> Bool {
  selected_expression_profile_admitted(value.expression_profiles, profile)
}

///|
fn selected_expression_profile_admitted(
  value : ExpressionProfileAdmission,
  profile : String,
) -> Bool {
  match profile {
    "actql-text-time/0.1" => value.text_time
    "actql-veca/0.1" => value.veca
    _ => false
  }
}

///|
pub fn bound_preparation(value : BoundPrepared) -> Prepared {
  value.prepared
}

///|
pub fn parameter_bindings(value : BoundPrepared) -> @parameter.BoundValues? {
  value.bindings
}

///|
pub fn parameter_value(
  value : BoundPrepared,
  name : String,
) -> @value.CheckedValue? {
  value.by_name.get(name)
}

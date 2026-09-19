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
  if max_parameters < 0 || max_name_bytes < 0 {
    return Err({ kind: InvalidBindingLimits, source, })
  }
  let declared = @pipeline.parameters(prepared.owner)
  let by_name : Map[String, @value.CheckedValue] = Map([])
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
      let count = @parameter.bound_value_count(bound)
      if count > max_parameters {
        return Err({ kind: BindingBudgetExceeded, source, })
      }
      let mut remaining = max_name_bytes
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
  Ok({ prepared, bindings, by_name, expression_profiles, })
}

///|
fn expression_profile_admitted(value : BoundPrepared, profile : String) -> Bool {
  match profile {
    "actql-text-time/0.1" => value.expression_profiles.text_time
    "actql-veca/0.1" => value.expression_profiles.veca
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

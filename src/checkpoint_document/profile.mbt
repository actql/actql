///|
/// Required-artifact DATA in the existing Checkpoint protocol, not a grant.
pub fn artifact_type(kind : String) -> String? {
  match kind {
    "run_scope" => Some("prepared_invocation")
    "read_access" => Some("read_scope")
    "data_egress" => Some("egress_scope")
    "cost_scope" => Some("budget_scope")
    "model_invocation" => Some("model_invocation_scope")
    "effect_set" => Some("effect_set_preview")
    _ => None
  }
}

///|
/// One closed subject/phase/kind law shared by Host admission and candidates.
pub fn combination_valid(
  subject : String,
  phase : String,
  kind : String,
) -> Bool {
  match (subject, phase, kind) {
    ("prepare_attempt", "preflight", "run_scope") => true
    ("prepare_attempt" | "run_unit", "preflight", "read_access") => true
    ("run_unit", "preflight", "data_egress" | "cost_scope" | "model_invocation") =>
      true
    ("run_unit", "commit", "effect_set") => true
    _ => false
  }
}

///|
/// Maximum original claim-view arity, not permission to omit or substitute a
/// claim. Callers can reject oversized foreign vectors before projecting them.
pub fn requirement_max_arity(kind : String) -> Int? {
  if artifact_type(kind) is None {
    None
  } else {
    Some(if kind == "effect_set" { 2 } else { 1 })
  }
}

///|
/// Lists retain their normative order. Unknown kinds do not inherit a profile.
pub fn requirements_valid(kind : String, requirements : Array[String]) -> Bool {
  if artifact_type(kind) is None {
    return false
  }
  if kind == "effect_set" {
    requirements == ["effect_scope_approved"] ||
    requirements == ["effect_scope_approved", "partial_application_accepted"]
  } else {
    requirements == ["invocation_scope_approved"]
  }
}

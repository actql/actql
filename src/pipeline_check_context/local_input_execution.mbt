///|
pub(all) enum LocalInputExecutionKind {
  RawBinding
  PrimaryKeyComponents
  PrimaryKeyUniqueness
} derive(Eq, Debug)

///|
pub(all) enum LocalInputExecutionPhase {
  BeforeLocalInputUse
} derive(Eq, Debug)

///|
pub(all) enum LocalInputExecutionFailure {
  RejectLocalInput
} derive(Eq, Debug)

///|
/// An enforcement requirement, not a receipt or permission to use input rows.
/// Its subject includes the exact pipeline, registration and selected evidence.
pub struct LocalInputExecutionCheck {
  subject : LocalInputRequirement
  kind : LocalInputExecutionKind
}

///|
/// None means static order resolution is missing, not zero runtime obligations.
/// An unkeyed input still requires admission of its Carrier and known fields.
pub fn local_input_execution_count(v : LocalInputRequirement) -> Int? {
  match v.disposition {
    DuplicateOrderUnresolved => None
    RejectDuplicatesAdmission =>
      Some(
        if @local_input.primary_key(v.declaration) is Some(_) {
          3
        } else {
          1
        },
      )
  }
}

///|
/// Constant-time access; no schema, key or expected-column array is copied.
pub fn local_input_execution_at(
  v : LocalInputRequirement,
  index : Int,
) -> LocalInputExecutionCheck? {
  guard local_input_execution_count(v) is Some(count) else { return None }
  if index < 0 || index >= count {
    return None
  }
  let kind = match index {
    0 => RawBinding
    1 => PrimaryKeyComponents
    _ => PrimaryKeyUniqueness
  }
  Some({ subject: v, kind, })
}

///|
pub fn local_input_execution_phase(
  v : LocalInputExecutionCheck,
) -> LocalInputExecutionPhase {
  match v.kind {
    RawBinding | PrimaryKeyComponents | PrimaryKeyUniqueness =>
      BeforeLocalInputUse
  }
}

///|
pub fn local_input_execution_failure(
  v : LocalInputExecutionCheck,
) -> LocalInputExecutionFailure {
  match v.kind {
    RawBinding | PrimaryKeyComponents | PrimaryKeyUniqueness => RejectLocalInput
  }
}

///|
/// Predecessor in the same subject's indexed enforcement sequence. The entire
/// raw binding is checked before key validity, then canonical tuple uniqueness.
pub fn local_input_execution_predecessor(
  v : LocalInputExecutionCheck,
) -> LocalInputExecutionCheck? {
  match v.kind {
    RawBinding => None
    PrimaryKeyComponents => Some({ subject: v.subject, kind: RawBinding, })
    PrimaryKeyUniqueness =>
      Some({ subject: v.subject, kind: PrimaryKeyComponents, })
  }
}

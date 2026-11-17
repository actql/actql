///|
/// Read only the actual accepted Model behind this SAME original Run/Read.
/// Store confirmation and destination authorization belong to the existing
/// capture/projection caller; this operation cannot dispatch or restore it.
pub fn project_original_infer_capture_usage(
  active : Execution,
  capacity : @model.OriginalModelPublicationCapacity,
  capture : @model.VerifiedModelCapture,
  slot : Int,
  retained_prefix : Int64,
  execution_prefix : Int64,
  max_bytes : Int,
) -> Result[(String, Int64, Int64), Issue] {
  if !original_infer_publication_owner_current(active) {
    return Err(Model(@model.OutputIdentity))
  }
  let projected = match
    @model.project_original_model_capture_usage(
      active.model.unwrap(),
      capacity,
      capture,
      slot,
      retained_prefix,
      execution_prefix,
      max_bytes,
    ) {
    Err(issue) => return Err(Model(issue))
    Ok(value) => value
  }
  if !original_infer_publication_owner_current(active) {
    return Err(Model(@model.OutputIdentity))
  }
  Ok(projected)
}

///|
/// Admit the fixed usage control window on the same original Run before Host
/// inventory/callback construction; this neither copies nor discloses usage.
pub fn prepare_original_infer_capture_usage(
  active : Execution,
  capacity : @model.OriginalModelPublicationCapacity,
  capture : @model.VerifiedModelCapture,
  retained_prefix : Int64,
  execution_prefix : Int64,
) -> Result[(Int64, Int64), Issue] {
  if !original_infer_publication_owner_current(active) {
    return Err(Model(@model.OutputIdentity))
  }
  let prepared = match
    @model.prepare_original_model_capture_usage(
      active.model.unwrap(),
      capacity,
      capture,
      retained_prefix,
      execution_prefix,
    ) {
    Err(issue) => return Err(Model(issue))
    Ok(value) => value
  }
  if !original_infer_publication_owner_current(active) {
    return Err(Model(@model.OutputIdentity))
  }
  Ok(prepared)
}

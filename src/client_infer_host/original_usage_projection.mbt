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

///|
/// The existing INFER owner retains its original Read fence around the Model
/// child. This facade carries no separate capacity, Ledger or authority.
pub struct OriginalInferUsagePublication {
  mut active : Execution?
  mut publication : @model.ModelUsagePublication?
  mut advancing : Bool
}

///|
pub fn begin_original_infer_usage_publication(
  active : Execution,
  capacity : @model.OriginalModelPublicationCapacity,
  capture : @model.VerifiedModelCapture,
  retained_prefix : Int64,
  execution_prefix : Int64,
  max_bytes : Int,
) -> Result[OriginalInferUsagePublication, Issue] {
  if !original_infer_publication_owner_current(active) {
    return Err(Model(@model.OutputIdentity))
  }
  let publication = match
    @model.begin_original_model_usage_publication(
      active.model.unwrap(),
      capacity,
      capture,
      retained_prefix,
      execution_prefix,
      max_bytes,
    ) {
    Err(issue) => return Err(Model(issue))
    Ok(value) => value
  }
  Ok({ active: Some(active), publication: Some(publication), advancing: false, })
}

///|
pub fn next_original_infer_usage_action(
  value : OriginalInferUsagePublication,
) -> Result[@model.ModelUsageAction?, Issue] {
  if value.advancing {
    return Err(Model(@model.OutputIdentity))
  }
  value.advancing = true
  defer {
    value.advancing = false
  }
  guard value.active is Some(active) && value.publication is Some(publication) else {
    return Ok(None)
  }
  // A current Model/Scope does not prove the original Read is still claimed.
  if !original_infer_publication_owner_current(active) {
    @model.stop_original_model_usage_publication(publication)
  }
  @model.next_original_model_usage_action(publication).map_err(issue => {
    Model(issue)
  })
}

///|
pub fn original_infer_usage_binding_matches(
  value : OriginalInferUsagePublication,
  action : @model.ModelUsageAction,
  slot_cid : String,
  attempt_cid : String,
) -> Bool {
  if value.advancing {
    return false
  }
  value.advancing = true
  defer {
    value.advancing = false
  }
  value.active is Some(active) &&
  value.publication is Some(publication) &&
  original_infer_publication_owner_current(active) &&
  @model.original_model_usage_action_belongs_to(publication, action) &&
  @model.original_model_usage_binding_matches(action, slot_cid, attempt_cid)
}

///|
pub fn observe_original_infer_usage_action(
  value : OriginalInferUsagePublication,
  action : @model.ModelUsageAction,
  observation : @model.ModelUsageObservation,
) -> Result[Unit, Issue] {
  if value.advancing {
    return Err(Model(@model.OutputIdentity))
  }
  guard value.publication is Some(publication) &&
    @model.original_model_usage_action_belongs_to(publication, action) else {
    return Err(Model(@model.OutputIdentity))
  }
  match @model.observe_original_model_usage_action(action, observation) {
    Err(issue) => return Err(Model(issue))
    Ok(_) => ()
  }
  if @model.original_model_usage_finished(publication) {
    value.active = None
    value.publication = None
  }
  Ok(())
}

///|
pub fn stop_original_infer_usage_publication(
  value : OriginalInferUsagePublication,
) -> Unit {
  if value.publication is Some(publication) {
    @model.stop_original_model_usage_publication(publication)
  }
}

///|
pub fn original_infer_usage_completion(
  value : OriginalInferUsagePublication,
) -> @model.ModelUsageCompletion {
  match value.publication {
    Some(publication) => @model.original_model_usage_completion(publication)
    None => @model.RequiredUnavailable
  }
}

///|
pub fn original_infer_usage_item_count(
  value : OriginalInferUsagePublication,
) -> Int {
  match value.publication {
    Some(publication) => @model.original_model_usage_item_count(publication)
    None => 0
  }
}

///|
pub fn original_infer_usage_item(
  value : OriginalInferUsagePublication,
  index : Int,
) -> (Int, @model.ModelUsageCompletion)? {
  match value.publication {
    Some(publication) => @model.original_model_usage_item(publication, index)
    None => None
  }
}

///|
pub fn original_infer_usage_item_attempt(
  value : OriginalInferUsagePublication,
  index : Int,
) -> String? {
  match value.publication {
    Some(publication) =>
      @model.original_model_usage_item_attempt(publication, index)
    None => None
  }
}

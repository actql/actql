///|
/// The original execution supplies its actual Model/CallScope to this existing
/// Common issuer. Byte DATA neither exports a Ledger nor grants Model dispatch.
#export_name("clientProgramReserveOriginalInferPublicationCapacity")
pub fn client_program_reserve_original_infer_publication_capacity(
  active : @infer_host.Execution,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[@model.OriginalModelPublicationCapacity, @infer_host.Issue] {
  @infer_host.reserve_original_infer_publication_capacity(
    active, retained_bytes, execution_bytes,
  )
}

///|
#export_name("clientProgramOriginalInferPublicationRetainedBytes")
pub fn client_program_original_infer_publication_retained_bytes(
  capacity : @model.OriginalModelPublicationCapacity,
) -> Int64 {
  @model.original_model_publication_retained_bytes(capacity)
}

///|
#export_name("clientProgramOriginalInferPublicationExecutionBytes")
pub fn client_program_original_infer_publication_execution_bytes(
  capacity : @model.OriginalModelPublicationCapacity,
) -> Int64 {
  @model.original_model_publication_execution_bytes(capacity)
}

///|
#export_name("clientProgramGrowOriginalInferPublicationCapacity")
pub fn client_program_grow_original_infer_publication_capacity(
  active : @infer_host.Execution,
  capacity : @model.OriginalModelPublicationCapacity,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, @infer_host.Issue] {
  @infer_host.grow_original_infer_publication_capacity(
    active, capacity, retained_bytes, execution_bytes,
  )
}

///|
/// Physical publication retirement remains the caller's responsibility. No
/// caller Bool or journal observation is used to fabricate this nominal loan.
#export_name("clientProgramReleaseOriginalInferPublicationCapacity")
pub fn client_program_release_original_infer_publication_capacity(
  capacity : @model.OriginalModelPublicationCapacity,
) -> Result[Bool, @infer_host.Issue] {
  @infer_host.release_original_infer_publication_capacity(capacity)
}

///|
#export_name("clientProgramStartOriginalInferObservationIssuance")
pub fn client_program_start_original_infer_observation_issuance(
  active : @infer_host.Execution,
  capacity : @model.OriginalModelPublicationCapacity,
  max_slots : Int,
  max_wire_bytes : Int,
  max_work : Int,
  generations : Array[@publication_host.ClientSerializationGeneration],
) -> Result[@infer_host.ObservationIssuance, @infer_host.Issue] {
  @infer_host.start_original_observation_issuance(
    active,
    capacity,
    { max_slots, max_wire_bytes, max_work, },
    generations~,
  )
}

///|
#export_name("clientProgramStartCompleteOriginalInferObservationIssuance")
pub fn client_program_start_complete_original_infer_observation_issuance(
  active : Array[@infer_host.Execution],
  capacity : @model.OriginalModelPublicationCapacity,
  max_slots : Int,
  max_wire_bytes : Int,
  max_work : Int,
  generations : Array[@publication_host.ClientSerializationGeneration],
) -> Result[@infer_host.ObservationIssuance, @infer_host.Issue] {
  @infer_host.start_complete_original_observation_issuance(
    active,
    capacity,
    { max_slots, max_wire_bytes, max_work, },
    generations~,
  )
}

///|
#export_name("clientProgramInferFundedStoppedAttemptCount")
pub fn client_program_infer_funded_stopped_attempt_count(
  active : @infer_host.Execution,
) -> Int {
  @infer_host.funded_stopped_attempt_count(active).unwrap_or(-1)
}

///|
#export_name("clientProgramOriginalInferCaptureInventoryCapacity")
pub fn client_program_original_infer_capture_inventory_capacity(
  active : @infer_host.Execution,
  capacity : @model.OriginalModelPublicationCapacity,
) -> Result[(Int, Int64, Int64), @infer_host.Issue] {
  @infer_host.original_infer_capture_inventory_capacity(active, capacity)
}

///|
#export_name("clientProgramPrepareOriginalRestoredInferSendMask")
pub fn client_program_prepare_original_restored_infer_send_mask(
  active : @infer_host.Execution,
) -> Result[Int, @infer_host.Issue] {
  @infer_host.prepare_original_restored_send_mask(active)
}

///|
#export_name("clientProgramBeginOriginalInferUsagePublication")
pub fn client_program_begin_original_infer_usage_publication(
  active : @infer_host.Execution,
  capacity : @model.OriginalModelPublicationCapacity,
  capture : @model.VerifiedModelCapture,
  retained_prefix : Int64,
  execution_prefix : Int64,
  max_bytes : Int,
) -> Result[@infer_host.OriginalInferUsagePublication, @infer_host.Issue] {
  @infer_host.begin_original_infer_usage_publication(
    active, capacity, capture, retained_prefix, execution_prefix, max_bytes,
  )
}

///|
#export_name("clientProgramNextOriginalInferUsageAction")
pub fn client_program_next_original_infer_usage_action(
  value : @infer_host.OriginalInferUsagePublication,
) -> Result[@model.ModelUsageAction?, @infer_host.Issue] {
  @infer_host.next_original_infer_usage_action(value)
}

///|
#export_name("clientProgramOriginalInferUsageActionKind")
pub fn client_program_original_infer_usage_action_kind(
  action : @model.ModelUsageAction,
) -> String? {
  @model.original_model_usage_action_kind(action)
}

///|
#export_name("clientProgramOriginalInferUsageActionSlot")
pub fn client_program_original_infer_usage_action_slot(
  action : @model.ModelUsageAction,
) -> Int? {
  @model.original_model_usage_action_slot(action)
}

///|
#export_name("clientProgramOriginalInferUsageActionWire")
pub fn client_program_original_infer_usage_action_wire(
  action : @model.ModelUsageAction,
) -> String? {
  @model.original_model_usage_action_wire(action)
}

///|
#export_name("clientProgramOriginalInferUsageBindingMatches")
pub fn client_program_original_infer_usage_binding_matches(
  value : @infer_host.OriginalInferUsagePublication,
  action : @model.ModelUsageAction,
  slot_cid : String,
  attempt_cid : String,
) -> Bool {
  @infer_host.original_infer_usage_binding_matches(
    value, action, slot_cid, attempt_cid,
  )
}

///|
// Closed physical observation codec for the Node binding. The nominal issued
// action, not this DATA discriminant, selects the child and legal transition.
#export_name("clientProgramObserveOriginalInferUsageAction")
pub fn client_program_observe_original_infer_usage_action(
  value : @infer_host.OriginalInferUsagePublication,
  action : @model.ModelUsageAction,
  observation : String,
) -> Result[Unit, @infer_host.Issue] {
  let observed = match observation {
    "retained" => @model.CopyRetained
    "refused" => @model.CopyRefused
    "authorized" => @model.Authorized
    "denied" => @model.Denied
    "unavailable" => @model.Unavailable
    "captured" => @model.CaptureComplete
    "incomplete" => @model.CaptureIncomplete
    "recorded" => @model.Recorded
    "failed" => @model.CallbackFailed
    "pending" => @model.CleanupPending
    "cleaned" => @model.CleanupComplete
    _ => return Err(@infer_host.Model(@model.OutputIdentity))
  }
  @infer_host.observe_original_infer_usage_action(value, action, observed)
}

///|
#export_name("clientProgramStopOriginalInferUsagePublication")
pub fn client_program_stop_original_infer_usage_publication(
  value : @infer_host.OriginalInferUsagePublication,
) -> Unit {
  @infer_host.stop_original_infer_usage_publication(value)
}

///|
fn model_usage_completion_name(value : @model.ModelUsageCompletion) -> String {
  match value {
    @model.Complete => "complete"
    @model.RequiredUnavailable => "RequiredEvidenceUnavailable"
    @model.ReadDenied => "EvidenceReadDenied"
    @model.SinkFailure => "EvidenceSinkFailure"
    @model.BudgetExceeded => "EvaluationBudgetExceeded"
  }
}

///|
#export_name("clientProgramOriginalInferUsageCompletion")
pub fn client_program_original_infer_usage_completion(
  value : @infer_host.OriginalInferUsagePublication,
) -> String {
  model_usage_completion_name(
    @infer_host.original_infer_usage_completion(value),
  )
}

///|
#export_name("clientProgramOriginalInferUsageItemCount")
pub fn client_program_original_infer_usage_item_count(
  value : @infer_host.OriginalInferUsagePublication,
) -> Int {
  @infer_host.original_infer_usage_item_count(value)
}

///|
#export_name("clientProgramOriginalInferUsageItem")
pub fn client_program_original_infer_usage_item(
  value : @infer_host.OriginalInferUsagePublication,
  index : Int,
) -> (Int, String)? {
  @infer_host.original_infer_usage_item(value, index).map(item => {
    (item.0, model_usage_completion_name(item.1))
  })
}

///|
#export_name("clientProgramOriginalInferUsageItemAttempt")
pub fn client_program_original_infer_usage_item_attempt(
  value : @infer_host.OriginalInferUsagePublication,
  index : Int,
) -> String? {
  @infer_host.original_infer_usage_item_attempt(value, index)
}

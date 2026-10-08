///|
/// Optional observation custody, separate from Run admission and completion.
#export_name("clientValuesHostObservationScope")
pub fn client_values_host_observation_scope(
  workspace : String,
  authority : String,
  destination_revision : String,
  disclosure_revision : String,
  customer : Bool,
) -> @observation.ObservationScope? {
  @observation.admit_observation_scope(
    workspace,
    authority,
    destination_revision,
    disclosure_revision,
    if customer {
      @observation.CustomerTelemetry
    } else {
      @observation.ServiceOperations
    },
  )
}

///|
#export_name("clientValuesHostObservationScopeKey")
pub fn client_values_host_observation_scope_key(
  scope : @observation.ObservationScope,
) -> String {
  @observation.observation_scope_key(scope)
}

///|
#export_name("clientValuesHostObservationBudget")
pub fn client_values_host_observation_budget(
  scope : @observation.ObservationScope,
  request_key : String,
  max_records : Int,
  max_bytes : Int,
  fresh_request : Bool,
  saved_scope_key : String?,
  saved_request_key : String,
  saved_max_records : Int,
  saved_max_bytes : Int,
  saved_records : Int,
  saved_bytes : Int,
  saved_fact : String?,
) -> Result[@observation.ObservationBudget, @observation.ObservationIssue] {
  let saved = saved_scope_key.map(scope_key => @observation.ObservationBudgetSnapshot::{
    scope_key,
    request_key: saved_request_key,
    max_records: saved_max_records,
    max_bytes: saved_max_bytes,
    records: saved_records,
    bytes: saved_bytes,
    last_fact: saved_fact,
  })
  @observation.open_observation_budget(
    scope, request_key, max_records, max_bytes, fresh_request, saved,
  )
}

///|
#export_name("clientValuesHostChargeObservation")
pub fn client_values_host_charge_observation(
  budget : @observation.ObservationBudget,
  scope : @observation.ObservationScope,
  request_key : String,
  fact : String?,
  record_bytes : Int,
) -> Result[Bool, @observation.ObservationIssue] {
  @observation.charge_observation(
    budget, scope, request_key, fact, record_bytes,
  ).map(charge => charge == @observation.ObservationCharged)
}

///|
#export_name("clientValuesHostObservationBudgetSnapshot")
pub fn client_values_host_observation_budget_snapshot(
  budget : @observation.ObservationBudget,
) -> (String, String, Int, Int, Int, Int, String?) {
  let saved = @observation.observation_budget_snapshot(budget)
  (
    saved.scope_key,
    saved.request_key,
    saved.max_records,
    saved.max_bytes,
    saved.records,
    saved.bytes,
    saved.last_fact,
  )
}

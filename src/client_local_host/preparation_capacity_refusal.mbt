///|
/// Immutable explanation DATA. It conveys no owner, reservation or authority.
pub(all) struct ClientPreparationCapacityRefusal {
  phase : String
  dimension : String
  required_retention : Int64
  required_execution : Int64
  available_retention : Int64
  available_execution : Int64
} derive(Eq, Debug)

///|
/// Fixed bridge projection; the returned tuple contains scalar diagnostic data
/// only. A supplied/copied explanation cannot select or mutate a resource owner.
pub fn closed_values_preparation_capacity_refusal(
  issue : ClientClosedValuesPreparationIssue,
) -> (String, String, Int64, Int64, Int64, Int64)? {
  match issue {
    CapacityExceeded(value) =>
      Some(
        (
          value.phase,
          value.dimension,
          value.required_retention,
          value.required_execution,
          value.available_retention,
          value.available_execution,
        ),
      )
    _ => None
  }
}

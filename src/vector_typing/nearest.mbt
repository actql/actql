///|
pub type NearestRoles = @evidence.NearestRoles

///|
pub type NearestOptions = @evidence.NearestOptions

///|
pub type NearestSide = @evidence.NearestSide

///|
pub type NearestInput = @evidence.NearestInput

///|
pub type NearestSource = @evidence.NearestSource

///|
pub type NearestObligation = @evidence.NearestObligation

///|
pub type NearestPair = @evidence.NearestPair

///|
pub type CheckedNearest = @evidence.CheckedNearest

///|
pub using @evidence {
  read_nearest_options,
  nearest_source,
  nearest_query_name,
  nearest_candidate_roles,
  nearest_query_roles,
  nearest_metric,
  nearest_k,
  nearest_options_usage,
  check_nearest_input,
  check_nearest_source,
  nearest_input_source,
  nearest_input_vectors,
  nearest_completed_vector,
  nearest_completed_identity,
  nearest_input_usage,
  check_nearest_pair,
  check_nearest_pair_sources,
  nearest_pair_options,
  nearest_pair_input,
  nearest_pair_usage,
  nearest_pair_pending,
  check_nearest,
  check_nearest_sources,
  nearest_output,
  nearest_pair,
  nearest_usage,
  nearest_pending,
}

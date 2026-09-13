///|
/// Rechecked against bound egress requirements immediately before access.
/// These axes are not inferred grants or evidence of completed validation.
pub(all) enum SourceEgressAxis {
  Sensitivity
  Completeness
  Mime
  Bytes
  Availability
  ProviderAccountBoundary
  Region
  CurrentHostPolicy
} derive(Eq, Debug)

///|
pub fn source_egress_axis_count(value : SourceExecution) -> Int {
  match value.kind {
    RequestEgress | KeyedEgress(_) => 8
    _ => 0
  }
}

///|
pub fn source_egress_axis_at(
  value : SourceExecution,
  index : Int,
) -> SourceEgressAxis? {
  if source_egress_axis_count(value) == 0 {
    return None
  }
  match index {
    0 => Some(Sensitivity)
    1 => Some(Completeness)
    2 => Some(Mime)
    3 => Some(Bytes)
    4 => Some(Availability)
    5 => Some(ProviderAccountBoundary)
    6 => Some(Region)
    7 => Some(CurrentHostPolicy)
    _ => None
  }
}

///|
/// Static authored fields only. KeyedEgress additionally retains the exact
/// correlation producer through KeyedExecution; those values do not exist yet.
pub fn source_egress_field_count(value : SourceExecution) -> Int {
  if source_egress_axis_count(value) == 0 {
    return 0
  }
  match value.subject.request {
    @sourceviews.Direct(_, request) =>
      @sourceviews.parameterized_request_field_count(request)
    @sourceviews.Keyed(_, request) =>
      @sourceviews.parameterized_keyed_request_field_count(request)
  }
}

///|
pub fn source_egress_field_at(
  value : SourceExecution,
  index : Int,
) -> @sourceviews.ParameterizedRequestField? {
  if source_egress_axis_count(value) == 0 {
    return None
  }
  match value.subject.request {
    @sourceviews.Direct(_, request) =>
      @sourceviews.parameterized_request_field_at(request, index)
    @sourceviews.Keyed(_, request) =>
      @sourceviews.parameterized_keyed_request_field_at(request, index)
  }
}

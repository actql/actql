///|
/// Closed physical preparation choice on one original Source input. Neither
/// case is a provider grant, completed read or resource/capacity owner.
pub(all) enum SourceAcquisitionRoute {
  QueryRoute(QueryAcquisition)
  WholeInputRoute(SourceAcquisition)
}

///|
pub(all) enum SourceAcquisitionRouteIssue {
  QueryShape(QueryAcquisitionIssue)
  SourceInput(SourceAcquisitionIssue)
}

///|
/// Inspect the existing Query profile before constructing a whole-input
/// original. This preserves Query's original admitted domain. In particular,
/// a Query clock/binding/resource error never selects the other constructor.
pub fn select_source_acquisition_route(
  requests : PipelineRequests,
  source_index : Int,
  max_work : Int,
) -> Result[SourceAcquisitionRoute, SourceAcquisitionRouteIssue] {
  let remaining = Ref(0)
  match
    inspect_query_acquisition_context(
      requests,
      source_index,
      max_work,
      None,
      true,
      remaining_out=Some(remaining),
    ) {
    Ok(Some(query)) => Ok(QueryRoute(query))
    Ok(None) =>
      derive_source_acquisition(requests, source_index, remaining.val)
      .map(value => {
        WholeInputRoute({
          ..value,
          work: max_work - remaining.val + value.work,
        })
      })
      .map_err(issue => SourceInput(issue))
    Err(issue) => Err(QueryShape(issue))
  }
}

///|
/// Use the same exclusive Query shape inspection as Query derivation itself.
/// A structural non-selection can choose whole-input acquisition. All work,
/// binding and malformed-original errors remain errors, never fallback.
pub fn source_acquisition_route(
  original : SourceAcquisition,
  max_work : Int,
) -> Result[SourceAcquisitionRoute, QueryAcquisitionIssue] {
  match
    inspect_query_acquisition_context(
      original.owner,
      original.source_index,
      max_work,
      None,
      true,
    ) {
    Ok(Some(query)) => Ok(QueryRoute(query))
    Ok(None) => Ok(WholeInputRoute(original))
    Err(issue) => Err(issue)
  }
}

///|
pub(all) struct OperationResolutionLimits {
  max_work : Int
  max_requirements : Int
  max_resolutions : Int
} derive(Eq, Debug)

///|
pub enum ProgramOperationResolutionIssue {
  InvalidLimits
  Expressions(ExpressionClosureIssue)
  Inventory(OperationRequirementsIssue)
  Orders(OperationOrderIssue)
  Scalars(OperationScalarIssue)
  Frames(OperationFrameIssue)
  Fills(OperationFillIssue)
  Ranges(OperationRangeIssue)
  Queries(OperationQueryIssue)
  Cells(OperationCellIssue)
  Lexical(OperationLexicalIssue)
  Calendar(OperationCalendarIssue)
  Profiles(OperationProfileLinksIssue)
  Index(OperationResolutionIndexIssue)
}

///|
/// Orchestrate existing checks from one owned identity, not independently
/// supplied checker results. Work is cumulative; entry limits cover the sum of
/// retained requirements/resolutions, not a fresh allowance for each phase.
/// Unresolved index entries remain unresolved. Success here is not a successful
/// CheckedProgram, runtime enforcement, or authorization to lower the Program.
pub fn resolve_program_operations(
  identity : ProgramSourceIdentity,
  limits : OperationResolutionLimits,
  text_rank? : @environment.SelectedTextRankProfile? = None,
  calendar? : @environment.SelectedCalendarProfile? = None,
) -> Result[ProgramOperationResolutionIndex, ProgramOperationResolutionIssue] {
  if limits.max_work < 0 ||
    limits.max_requirements < 0 ||
    limits.max_resolutions < 0 {
    return Err(InvalidLimits)
  }
  let expressions = match
    close_program_expressions(
      identity,
      limits.max_work,
      limits.max_requirements,
    ) {
    Ok(v) => v
    Err(e) => return Err(Expressions(e))
  }
  let requirements = match
    collect_program_operation_requirements(
      expressions,
      limits.max_work,
      limits.max_requirements - expressions.entries.length(),
    ) {
    Ok(v) => v
    Err(e) => return Err(Inventory(e))
  }
  let mut remaining = limits.max_resolutions
  let orders = match
    link_program_operation_orders(requirements, limits.max_work, remaining) {
    Ok(v) => v
    Err(e) => return Err(Orders(e))
  }
  remaining -= orders.links.length()
  let scalars = match
    check_program_operation_scalars(orders, limits.max_work, remaining) {
    Ok(v) => v
    Err(e) => return Err(Scalars(e))
  }
  remaining -= scalars.entries.length()
  let frames = match
    check_program_operation_frames(scalars, limits.max_work, remaining) {
    Ok(v) => v
    Err(e) => return Err(Frames(e))
  }
  remaining -= frames.entries.length()
  let fills = match
    check_program_operation_fills(frames, limits.max_work, remaining) {
    Ok(v) => v
    Err(e) => return Err(Fills(e))
  }
  remaining -= fills.entries.length()
  let ranges = match
    check_program_operation_ranges(fills, limits.max_work, remaining) {
    Ok(v) => v
    Err(e) => return Err(Ranges(e))
  }
  remaining -= ranges.entries.length()
  let queries = match
    check_program_operation_queries(ranges, limits.max_work, remaining) {
    Ok(v) => v
    Err(e) => return Err(Queries(e))
  }
  remaining -= queries.entries.length()
  let cells = match
    check_program_operation_cells(queries, limits.max_work, remaining) {
    Ok(v) => v
    Err(e) => return Err(Cells(e))
  }
  remaining -= cells.entries.length()
  let lexical = match
    check_program_operation_lexical(
      cells,
      text_rank,
      limits.max_work,
      remaining,
    ) {
    Ok(v) => v
    Err(e) => return Err(Lexical(e))
  }
  remaining -= lexical.entries.length()
  let calendar = match
    check_program_operation_calendar(
      lexical,
      calendar,
      limits.max_work,
      remaining,
    ) {
    Ok(v) => v
    Err(e) => return Err(Calendar(e))
  }
  remaining -= calendar.entries.length()
  let profiles = match
    link_program_operation_profiles(calendar, limits.max_work, remaining) {
    Ok(v) => v
    Err(e) => return Err(Profiles(e))
  }
  match
    index_program_operation_resolutions(
      profiles,
      limits.max_work,
      requirements.entries.length(),
    ) {
    Ok(v) => Ok(v)
    Err(e) => Err(Index(e))
  }
}

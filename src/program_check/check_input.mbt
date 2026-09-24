///|
/// Input admission limits and semantic preparation limits measure different
/// resources. Reusing an admitted Program does not repeat input admission.
pub(all) struct CheckLimits {
  input : @syntax.Limits
  compilation : CompileLimits
} derive(Eq, Debug)

///|
// Configuration owns exact admitted handles. It is not an admitted execution
// environment or a claim that any particular Program passes checking.
struct CheckEnvironment {
  wire : @environment.WireEnvironment
  expressions : @context.ExpressionProfiles
  operations : @context.PureOperationProfiles
  numeric : @numeric.Profile?
  calendar : @environment.SelectedCalendarProfile?
  text_rank : @environment.SelectedTextRankProfile?
}

///|
/// Configure available contracts and complete checker profile declarations.
/// These declarations do not assert backend capability. Profile data and exact
/// environment ownership are still verified when the Program is checked.
pub fn checking_environment(
  wire : @environment.WireEnvironment,
  expression_profiles : @context.ExpressionProfiles,
  operation_profiles : @context.PureOperationProfiles,
  numeric_profile? : @numeric.Profile? = None,
  calendar? : @environment.SelectedCalendarProfile? = None,
  text_rank? : @environment.SelectedTextRankProfile? = None,
) -> CheckEnvironment {
  {
    wire,
    expressions: expression_profiles,
    operations: operation_profiles,
    numeric: numeric_profile,
    calendar,
    text_rank,
  }
}

///|
/// Return the exact admitted Check Environment selected for this checker.
/// This CID is preparation evidence, not a later Host execution decision.
pub fn checking_environment_cid(value : CheckEnvironment) -> String {
  @environment.cid(value.wire)
}

///|
/// Check an admitted Program using its original immutable admission. Current
/// input restrictions still apply; semantic checking uses the current values,
/// environment and compilation budget. No parser or Host I/O is invoked.
pub fn check_parsed(
  program : @syntax.Program,
  environment : CheckEnvironment,
  supplied : @decode.Cursor?,
  limits : CheckLimits,
) -> CheckOutcome {
  check_parsed_with_evidence(program, environment, supplied, [], limits)
}

///|
/// Document admission and checking, without file or network access. Source
/// syntax errors retain their original typed cause and locations.
pub fn check_document(
  document : String,
  environment : CheckEnvironment,
  supplied : @decode.Cursor?,
  limits : CheckLimits,
  format? : @syntax.Format = Auto,
  source_path? : String = "<memory>",
) -> CheckOutcome {
  check_document_with_evidence(
    document,
    environment,
    supplied,
    [],
    limits,
    format~,
    source_path~,
  )
}

///|
/// Advanced document entry for external definition evidence. Evidence does not
/// replace application checks and cannot be supplied as a successful result.
pub fn check_document_with_evidence(
  document : String,
  environment : CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : CheckLimits,
  format? : @syntax.Format = Auto,
  source_path? : String = "<memory>",
) -> CheckOutcome {
  if !compile_limits_valid(limits.compilation) {
    return rejected(InvalidLimits)
  }
  let program = match
    @syntax.parse(document, limits.input, format~, source_path~) {
    Ok(program) => program
    Err(issue) => return rejected(Program(issue))
  }
  check_parsed_with_evidence(program, environment, supplied, evidence, limits)
}

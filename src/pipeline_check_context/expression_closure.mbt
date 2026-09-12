///|
pub(all) enum ExpressionClosureIssue {
  InvalidLimits
  BudgetExceeded
  IncompleteResolution(Int)
} derive(Eq, Debug)

///|
/// References existing owned resolutions, not independently attachable proofs.
pub(all) enum ExpressionDischarge {
  Profile(String)
  Pattern(PatternResolution)
  Envelope(TextBoundResolution)
}

///|
pub struct ResolvedExpressionRequirement {
  site : ExpressionValidationSite
  resolution : ExpressionDischarge
}

///|
struct ProgramExpressionClosure {
  identity : ProgramSourceIdentity
  entries : Array[ResolvedExpressionRequirement]
  work : Int
}

///|
/// Exhaustively account for typed-expression obligations. Runtime enforcement
/// and operation-level obligations are not discharged by this boundary.
pub fn close_program_expressions(
  identity : ProgramSourceIdentity,
  max_work : Int,
  max_requirements : Int,
) -> Result[ProgramExpressionClosure, ExpressionClosureIssue] {
  if max_work < 0 || max_requirements < 0 {
    return Err(InvalidLimits)
  }
  let preparation = identity.sources.operations.preparation
  let bounds = preparation.expressions
  let patterns = bounds.patterns
  let context = patterns.context
  let count = expression_validation_count(context)
  if identity.work >= max_work ||
    count > max_requirements ||
    count > max_work - identity.work - 1 {
    return Err(BudgetExceeded)
  }
  let entries = []
  let mut profiles_seen = 0
  let mut patterns_seen = 0
  let mut bounds_seen = 0
  for i in 0..<count {
    let site = expression_validation_at(context, i).unwrap()
    // No wildcard: adding a new kind must extend this closing boundary.
    let resolution = match validation_site_requirement(site).obligation.kind {
      @typing.ProfileAdmission(profile) => {
        profiles_seen += 1
        Profile(profile)
      }
      @typing.PatternValidation(_) => {
        let checked = match pattern_at(patterns, patterns_seen) {
          Some(v) => v
          None => return Err(IncompleteResolution(i))
        }
        if !same_expression_site(site, pattern_site(checked)) {
          return Err(IncompleteResolution(i))
        }
        patterns_seen += 1
        Pattern(checked)
      }
      @typing.HostEnvelope => {
        let checked = match text_bound_at(bounds, bounds_seen) {
          Some(v) => v
          None => return Err(IncompleteResolution(i))
        }
        if !same_expression_site(site, text_bound_site(checked)) {
          return Err(IncompleteResolution(i))
        }
        bounds_seen += 1
        Envelope(checked)
      }
    }
    entries.push({ site, resolution, })
  }
  if profiles_seen != preparation.profiles.count ||
    patterns_seen != pattern_count(patterns) ||
    bounds_seen != text_bound_count(bounds) {
    return Err(IncompleteResolution(count))
  }
  Ok({ identity, entries, work: identity.work + count + 1, })
}

///|
fn same_expression_site(
  a : ExpressionValidationSite,
  b : ExpressionValidationSite,
) -> Bool {
  physical_equal(a.owner, b.owner) && a.stage == b.stage && a.index == b.index
}

///|
pub fn expression_closure_identity(
  v : ProgramExpressionClosure,
) -> ProgramSourceIdentity {
  v.identity
}

///|
pub fn expression_closure_count(v : ProgramExpressionClosure) -> Int {
  v.entries.length()
}

///|
pub fn expression_closure_at(
  v : ProgramExpressionClosure,
  index : Int,
) -> ResolvedExpressionRequirement? {
  v.entries.get(index)
}

///|
pub fn expression_closure_work(v : ProgramExpressionClosure) -> Int {
  v.work
}

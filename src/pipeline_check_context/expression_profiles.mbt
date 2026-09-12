///|
/// Checker declarations, not Host capabilities or a conformance certificate.
/// Each flag declares the complete named profile, never partial op support.
/// This boundary checks only the demands carried by typed expressions.
pub(all) struct ExpressionProfiles {
  text_time : Bool
  veca : Bool
} derive(Eq, Debug)

///|
pub(all) enum ExpressionProfilesIssue {
  InvalidLimits
  BudgetExceeded
  UnsupportedProfile(Int, String)
} derive(Eq, Debug)

///|
struct ExpressionProfileChecks {
  context : ExpressionValidationContext
  profiles : ExpressionProfiles
  count : Int
  work : Int
}

///|
/// Check every retained occurrence, including unselected branches and repeated
/// producer visits. Other static and runtime requirements remain outstanding.
pub fn check_expression_profiles(
  context : ExpressionValidationContext,
  profiles : ExpressionProfiles,
  max_work : Int,
) -> Result[ExpressionProfileChecks, ExpressionProfilesIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let before = context.usage.work
  if before >= max_work || context.sites.length() > max_work - before - 1 {
    return Err(BudgetExceeded)
  }
  let mut count = 0
  for i in 0..<context.sites.length() {
    let site = expression_validation_at(context, i).unwrap()
    match validation_site_requirement(site).obligation.kind {
      @typing.ProfileAdmission(profile) => {
        let admitted = match profile {
          "actql-text-time/0.1" => profiles.text_time
          "actql-veca/0.1" => profiles.veca
          _ => false
        }
        if !admitted {
          return Err(UnsupportedProfile(i, profile))
        }
        count += 1
      }
      _ => ()
    }
  }
  Ok({ context, profiles, count, work: before + 1 + context.sites.length(), })
}

///|
pub fn expression_profiles_context(
  v : ExpressionProfileChecks,
) -> ExpressionValidationContext {
  v.context
}

///|
pub fn expression_profiles_declared(
  v : ExpressionProfileChecks,
) -> ExpressionProfiles {
  v.profiles
}

///|
pub fn expression_profiles_count(v : ExpressionProfileChecks) -> Int {
  v.count
}

///|
pub fn expression_profiles_work(v : ExpressionProfileChecks) -> Int {
  v.work
}

///|
/// Stable unsupported-profile classification; occurrence coordinates are local.
pub fn expression_profiles_diagnostic(v : ExpressionProfilesIssue) -> String? {
  match v {
    UnsupportedProfile(_, _) => Some("ACTQL_E_PROFILE_UNSUPPORTED")
    _ => None
  }
}

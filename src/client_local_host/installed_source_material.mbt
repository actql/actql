///|
/// Read the same prepared Environment from the existing Resource body's
/// original Source installation aggregate. The first tuple member is the
/// actual initialized Source/profile aggregate, never its static manifest,
/// CID, copied JSON or a newly installed counterpart.
///
/// The initial carrier must reserve construction before completing this body.
/// It retains the actual Source graph and this Environment across Requests;
/// existing Resource sibling borrows, returns and retirement own that lifetime.
/// This accessor adds no reservation, current/Account decision, permission or
/// cleanup acknowledgement. A retiring borrow still exposes DATA for cleanup;
/// the Resource owner separately refuses new sibling borrows.
pub fn[S] borrowed_installed_source_environment(
  holder : @resources.PreparationBodyBorrow[
    (S, @source_publication.PreparedPublishedQueryEnvironment),
  ],
  source_original : S,
) -> Result[
  @source_publication.PreparedPublishedQueryEnvironment,
  @resources.PreparationCapacityIssue,
] {
  guard @resources.preparation_body_borrow_value(holder)
    is Some((original, environment)) else {
    return Err(@resources.BorrowReturned)
  }
  if !physical_equal(original, source_original) {
    return Err(@resources.ForeignOriginal)
  }
  Ok(environment)
}

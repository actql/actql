///|
// Static closed cause projection only. The typed primary remains original;
// these literals contain no Source, SQL, path, provider or cleanup capability.
fn local_file_work_preparation_message(
  issue : @local_host.NativeClientSourceWorkIssue,
) -> String {
  match issue {
    FileWorkSourceBinding => "LocalSourceWorkEntryUnavailable:source-binding"
    FileWorkControlQuote => "LocalSourceWorkEntryUnavailable:control-quote"
    FileWorkEntry(Unavailable) =>
      "LocalSourceWorkEntryUnavailable:entry-unavailable"
    FileWorkEntry(Resource(_)) =>
      "LocalSourceWorkEntryUnavailable:entry-resource"
    FileWorkEntry(Domain(_)) => "LocalSourceWorkEntryUnavailable:entry-domain"
    FileWorkPreparedCapacity(Unavailable) =>
      "LocalSourceWorkEntryUnavailable:prepared-unavailable"
    FileWorkPreparedCapacity(Unknown) =>
      "LocalSourceWorkEntryUnavailable:prepared-unknown"
    FileWorkPreparedCapacity(ForeignOriginal) =>
      "LocalSourceWorkEntryUnavailable:prepared-foreign-original"
    FileWorkPreparedCapacity(AlreadyConsumed) =>
      "LocalSourceWorkEntryUnavailable:prepared-already-consumed"
    FileWorkPreparedCapacity(InvalidOriginal) =>
      "LocalSourceWorkEntryUnavailable:prepared-invalid-original"
    FileWorkPreparedCapacity(Resource(RetentionLimit)) =>
      "LocalSourceWorkEntryUnavailable:prepared-retention"
    FileWorkPreparedCapacity(Resource(ExecutionLimit)) =>
      "LocalSourceWorkEntryUnavailable:prepared-execution"
    FileWorkPreparedCapacity(Resource(InvalidLimits)) =>
      "LocalSourceWorkEntryUnavailable:prepared-resource-invalid-limits"
    FileWorkPreparedCapacity(Resource(PlanningLimit)) =>
      "LocalSourceWorkEntryUnavailable:prepared-resource-planning-limit"
    FileWorkPreparedCapacity(Resource(AttemptLimit)) =>
      "LocalSourceWorkEntryUnavailable:prepared-resource-attempt-limit"
    FileWorkPreparedCapacity(Resource(HoldingLimit)) =>
      "LocalSourceWorkEntryUnavailable:prepared-resource-holding-limit"
    FileWorkPreparedCapacity(Resource(TransferLimit)) =>
      "LocalSourceWorkEntryUnavailable:prepared-resource-transfer-limit"
    FileWorkPreparedCapacity(Resource(ForeignOwner)) =>
      "LocalSourceWorkEntryUnavailable:prepared-resource-foreign-owner"
    FileWorkPreparedCapacity(Resource(ClosedReservation)) =>
      "LocalSourceWorkEntryUnavailable:prepared-resource-closed-reservation"
    FileWorkPreparedCapacity(Resource(ClosedHolding)) =>
      "LocalSourceWorkEntryUnavailable:prepared-resource-closed-holding"
    FileWorkPreparedCapacity(Resource(InvalidCharge)) =>
      "LocalSourceWorkEntryUnavailable:prepared-resource-invalid-charge"
    FileWorkPreparedCapacity(Resource(IdentityOverflow)) =>
      "LocalSourceWorkEntryUnavailable:prepared-resource-identity-overflow"
    FileWorkPreparedCapacity(Resource(TokenLimit)) =>
      "LocalSourceWorkEntryUnavailable:prepared-resource-token-limit"
    FileWorkPreparedCapacity(Resource(CostLimit)) =>
      "LocalSourceWorkEntryUnavailable:prepared-resource-cost-limit"
    FileWorkPreparedCapacity(Resource(DurationLimit)) =>
      "LocalSourceWorkEntryUnavailable:prepared-resource-duration-limit"
    FileWorkPreparedCapacity(Resource(ResourceParked)) =>
      "LocalSourceWorkEntryUnavailable:prepared-resource-parked"
    FileWorkPreparedCapacity(Resource(ChildFundingUnavailable)) =>
      "LocalSourceWorkEntryUnavailable:prepared-resource-child-funding-unavailable"
    _ => "LocalSourceWorkEntryUnavailable"
  }
}

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
    FileWorkPreparedCapacity(Resource(cause)) =>
      match cause {
        RetentionLimit => "LocalSourceWorkEntryUnavailable:prepared-retention"
        ExecutionLimit => "LocalSourceWorkEntryUnavailable:prepared-execution"
        InvalidLimits =>
          "LocalSourceWorkEntryUnavailable:prepared-resource-invalid-limits"
        PlanningLimit =>
          "LocalSourceWorkEntryUnavailable:prepared-resource-planning-limit"
        AttemptLimit =>
          "LocalSourceWorkEntryUnavailable:prepared-resource-attempt-limit"
        HoldingLimit =>
          "LocalSourceWorkEntryUnavailable:prepared-resource-holding-limit"
        TransferLimit =>
          "LocalSourceWorkEntryUnavailable:prepared-resource-transfer-limit"
        ForeignOwner =>
          "LocalSourceWorkEntryUnavailable:prepared-resource-foreign-owner"
        ClosedReservation =>
          "LocalSourceWorkEntryUnavailable:prepared-resource-closed-reservation"
        ClosedHolding =>
          "LocalSourceWorkEntryUnavailable:prepared-resource-closed-holding"
        InvalidCharge =>
          "LocalSourceWorkEntryUnavailable:prepared-resource-invalid-charge"
        IdentityOverflow =>
          "LocalSourceWorkEntryUnavailable:prepared-resource-identity-overflow"
        TokenLimit =>
          "LocalSourceWorkEntryUnavailable:prepared-resource-token-limit"
        CostLimit =>
          "LocalSourceWorkEntryUnavailable:prepared-resource-cost-limit"
        DurationLimit =>
          "LocalSourceWorkEntryUnavailable:prepared-resource-duration-limit"
        ResourceParked =>
          "LocalSourceWorkEntryUnavailable:prepared-resource-parked"
        ChildFundingUnavailable =>
          "LocalSourceWorkEntryUnavailable:prepared-resource-child-funding-unavailable"
      }
    _ => "LocalSourceWorkEntryUnavailable"
  }
}

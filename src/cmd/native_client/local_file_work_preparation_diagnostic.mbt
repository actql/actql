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
    FileWorkPreparedCapacity(Resource(_)) =>
      "LocalSourceWorkEntryUnavailable:prepared-resource"
    _ => "LocalSourceWorkEntryUnavailable"
  }
}

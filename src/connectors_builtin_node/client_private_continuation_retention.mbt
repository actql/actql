///|
/// Data-only private metadata prevalidation. Empty text means valid shape,
/// never a resource/Store acknowledgement or permission to resume/send.
#export_name("clientProgramPrivateContinuationRetentionShape")
pub fn client_program_private_continuation_retention_shape(
  bytes : Bytes,
  prepare_attempt_id : String,
  max_wire_bytes : Int,
  max_entries : Int,
) -> String {
  match
    @publication_host.check_client_private_continuation_retention(
      bytes, prepare_attempt_id, max_wire_bytes, max_entries,
    ) {
    Ok(_) => ""
    Err(EntriesLimit) => "ContinuationLedgerEntriesLimit"
    Err(InvalidLedger) => "InvalidContinuationLedger"
  }
}

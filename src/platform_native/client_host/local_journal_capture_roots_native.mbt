///|
/// Named roots for one same-provider C transport. Actual regular C must prove
/// callback types and borrowed-input/owned-output rules before qualification.
extern "C" fn register_local_journal_capture_roots_ffi(
  prepare : FuncRef[
    (
      NativeLocalAdoptionSession,
      @sqlite.Library,
      @crypto.Library,
      Double,
      Int,
      Int64,
    ) -> NativeLocalJournalCapture,
  ],
  open : FuncRef[(NativeLocalJournalCapture) -> NativeLocalJournalCaptureReply],
  current : FuncRef[
    (NativeLocalJournalCapture) -> NativeLocalJournalCaptureReply,
  ],
  close : FuncRef[(NativeLocalJournalCapture) -> NativeLocalJournalCaptureReply],
  capture : FuncRef[
    (NativeLocalJournalCaptureReply) -> NativeLocalJournalCapture,
  ],
  session : FuncRef[(NativeLocalJournalCapture) -> NativeLocalAdoptionSession],
  host : FuncRef[(NativeLocalJournalCapture) -> NativeLocalHostConnection?],
  failure : FuncRef[
    (NativeLocalJournalCapture) -> NativeLocalJournalOpenFailure?,
  ],
  cleanup_ack : FuncRef[(NativeLocalJournalCapture) -> Bool],
  operation : FuncRef[(NativeLocalJournalCaptureReply) -> Int],
  issue : FuncRef[(NativeLocalJournalCaptureReply) -> Int],
  original_issue : FuncRef[(NativeLocalJournalCapture) -> Int],
) -> Unit = "actql_native_control_register_local_journal_roots"

///|
/// Code registration only. It does not initialize a Host, select a Library or
/// provide current/funded origins. The installed caller owns those originals.
pub fn register_native_local_journal_capture_roots() -> Unit {
  register_local_journal_capture_roots_ffi(
    fn(session, library, crypto, ttl, max_records, max_snapshot) {
      prepare_native_local_journal_capture(
        session, library, crypto, ttl, max_records, max_snapshot,
      )
    },
    fn(capture) { capture.open() },
    fn(capture) { capture.check_current() },
    fn(capture) { capture.close() },
    fn(reply) { reply.original_capture() },
    fn(capture) { capture.original_session() },
    fn(capture) { capture.original_host() },
    fn(capture) { capture.original_failure() },
    fn(capture) { capture.descriptor_cleanup_acknowledged() },
    fn(reply) { reply.operation_tag() },
    fn(reply) { reply.issue_family() },
    fn(capture) { capture.original_issue_family() },
  )
}

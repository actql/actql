///|
// The optional CLI request-id asserts the original public nonce, not the
// derived journal request ID. Read only the existing Owner-admitted reference;
// this check neither authenticates its epoch nor authorizes submission.
fn local_submission_nonce_matches(
  reference : @local_host.NativeClientSubmissionReference,
  requested : String?,
) -> Bool {
  guard requested is Some(nonce) else { return true }
  let original = @json.parse(
    @local_host.native_client_submission_reference_wire(reference),
  ) catch {
    _ => return false
  }
  guard original is Object(fields) else { return false }
  json_text(fields, "nonce") == Some(nonce)
}

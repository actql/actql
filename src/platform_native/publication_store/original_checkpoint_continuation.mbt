///|
/// Admit the original authenticated Store plaintext against the trusted sealed
/// Checkpoint. This issues no new Checkpoint, continuation, permission or CID.
fn original_effect_checkpoint_continuation(
  checkpoint : @checkpoint.SealedCheckpoint,
  plain : Bytes,
  max_bytes : Int64,
) -> Result[String, NativePublicationStoreIssue] {
  guard checkpoint.checkpoint.subject is @checkpoint.RunUnit(..) &&
    checkpoint.checkpoint.kind == @checkpoint.EffectSet &&
    max_bytes > 0L &&
    plain.length().to_int64() <= max_bytes else {
    return Err(InvalidConfiguration)
  }
  if "sha256:" + @sha.hex(plain) != checkpoint.checkpoint.continuation_state_cid {
    return Err(DigestMismatch)
  }
  Ok(@utf8.decode(plain)) catch {
    _ => Err(StateCollision)
  }
}

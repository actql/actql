///|
/// Portable owner of sink-confirmed delivery progress. Reading bytes from a
/// retained Result is not evidence that a sink accepted them. Environment
/// adapters offer one bounded chunk, perform the physical write, and then
/// report the exact confirmed prefix through this state machine.
pub(all) enum DeliverySinkProgressIssue {
  DeliverySinkInvalidLimit
  DeliverySinkClosed
  DeliverySinkChunkOutstanding
  DeliverySinkNoOutstandingChunk
  DeliverySinkConfirmationMismatch
  DeliverySinkLimitExceeded
  DeliverySinkSourceIncomplete
  DeliverySinkHashFailure
} derive(Eq, Debug)

///|
pub(all) struct DeliverySinkSummary {
  confirmed_bytes : Int64
  delivered_sha256 : String
} derive(Eq, Debug)

///|
struct DeliverySinkProgress {
  max_bytes : Int64
  hash : @sha.Hasher
  mut confirmed_bytes : Int64
  mut outstanding : Bytes
  mut has_outstanding : Bool
  mut source_eof : Bool
  mut failed : Bool
  mut closed : Bool
  mut delivered_sha256 : String?
}

///|
pub fn prepare_delivery_sink_progress(
  max_bytes : Int64,
) -> Result[DeliverySinkProgress, DeliverySinkProgressIssue] {
  if max_bytes < 0L {
    return Err(DeliverySinkInvalidLimit)
  }
  Ok({
    max_bytes,
    hash: @sha.hasher(),
    confirmed_bytes: 0L,
    outstanding: b"",
    has_outstanding: false,
    source_eof: false,
    failed: false,
    closed: false,
    delivered_sha256: None,
  })
}

///|
pub fn DeliverySinkProgress::offer(
  self : DeliverySinkProgress,
  bytes : Bytes,
  eof : Bool,
) -> Result[Unit, DeliverySinkProgressIssue] {
  if self.closed || self.failed || self.source_eof {
    return Err(DeliverySinkClosed)
  }
  if self.has_outstanding {
    return Err(DeliverySinkChunkOutstanding)
  }
  let size = bytes.length().to_int64()
  if size > self.max_bytes - self.confirmed_bytes {
    return Err(DeliverySinkLimitExceeded)
  }
  self.source_eof = eof
  if size > 0L {
    self.outstanding = bytes
    self.has_outstanding = true
  }
  Ok(())
}

///|
pub fn DeliverySinkProgress::prepare_next(
  self : DeliverySinkProgress,
) -> Result[Unit, DeliverySinkProgressIssue] {
  if self.closed || self.failed || self.source_eof {
    return Err(DeliverySinkClosed)
  }
  if self.has_outstanding {
    return Err(DeliverySinkChunkOutstanding)
  }
  Ok(())
}

///|
pub fn DeliverySinkProgress::confirm_chunk(
  self : DeliverySinkProgress,
) -> Result[Int64, DeliverySinkProgressIssue] {
  if self.closed || self.failed {
    return Err(DeliverySinkClosed)
  }
  if !self.has_outstanding {
    return Err(DeliverySinkNoOutstandingChunk)
  }
  @sha.update(self.hash, self.outstanding) catch {
    _ => return Err(DeliverySinkHashFailure)
  }
  self.confirmed_bytes += self.outstanding.length().to_int64()
  self.outstanding = b""
  self.has_outstanding = false
  Ok(self.confirmed_bytes)
}

///|
/// Record the exact prefix confirmed by a failed physical write. The attempt
/// becomes terminal, so the unconfirmed suffix can never be reused as success.
pub fn DeliverySinkProgress::fail_chunk(
  self : DeliverySinkProgress,
  confirmed_prefix_bytes : Int,
) -> Result[Int64, DeliverySinkProgressIssue] {
  if self.closed || self.failed {
    return Err(DeliverySinkClosed)
  }
  if !self.has_outstanding {
    return Err(DeliverySinkNoOutstandingChunk)
  }
  if confirmed_prefix_bytes < 0 ||
    confirmed_prefix_bytes > self.outstanding.length() {
    return Err(DeliverySinkConfirmationMismatch)
  }
  if confirmed_prefix_bytes > 0 {
    @sha.update(
      self.hash,
      self.outstanding[0:confirmed_prefix_bytes].to_owned(),
    ) catch {
      _ => return Err(DeliverySinkHashFailure)
    }
    self.confirmed_bytes += confirmed_prefix_bytes.to_int64()
  }
  self.outstanding = b""
  self.has_outstanding = false
  self.failed = true
  Ok(self.confirmed_bytes)
}

///|
pub fn DeliverySinkProgress::fail(
  self : DeliverySinkProgress,
) -> Result[Int64, DeliverySinkProgressIssue] {
  if self.closed || self.failed {
    return Err(DeliverySinkClosed)
  }
  if self.has_outstanding {
    return Err(DeliverySinkChunkOutstanding)
  }
  self.failed = true
  Ok(self.confirmed_bytes)
}

///|
/// Confirm the sink's explicit successful end operation. This call is
/// required even when an empty representation produced no write calls.
pub fn DeliverySinkProgress::confirm_finished(
  self : DeliverySinkProgress,
) -> Result[DeliverySinkSummary, DeliverySinkProgressIssue] {
  if self.failed {
    return Err(DeliverySinkClosed)
  }
  match self.delivered_sha256 {
    Some(value) =>
      return Ok({
        confirmed_bytes: self.confirmed_bytes,
        delivered_sha256: value,
      })
    None => ()
  }
  if self.closed {
    return Err(DeliverySinkClosed)
  }
  if self.has_outstanding || !self.source_eof {
    return Err(DeliverySinkSourceIncomplete)
  }
  let digest = @sha.finish_hex(self.hash) catch {
    _ => return Err(DeliverySinkHashFailure)
  }
  let delivered_sha256 = "sha256:" + digest
  self.delivered_sha256 = Some(delivered_sha256)
  self.closed = true
  Ok({ confirmed_bytes: self.confirmed_bytes, delivered_sha256, })
}

///|
pub fn DeliverySinkProgress::confirmed_bytes(
  self : DeliverySinkProgress,
) -> Int64 {
  self.confirmed_bytes
}

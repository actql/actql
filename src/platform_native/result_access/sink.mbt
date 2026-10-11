///|
/// Physical sink facts. A failed write distinguishes its confirmed prefix
/// from bounded possible exposure; neither is inferred from bytes read.
pub(all) enum NativeResultSinkWrite {
  SinkChunkConfirmed
  SinkChunkFailed(Int, Int)
}

///|
pub(all) enum NativeResultSinkIssue {
  InvalidSinkLimits
  InvalidSinkWrite
  SinkWriteFailed
  SinkFinishFailed
  SinkOutputLimit
  Access(NativeResultAccessIssue)
}

///|
pub(all) enum NativeResultSinkStep {
  SinkProgress
  SinkComplete(@store.NativeResultDeliverySuccess)
  SinkFailed(NativeResultSinkIssue, @store.NativeResultDeliveryFailure)
}

///|
priv enum NativeResultSinkPhase {
  Read
  ConfirmChunk(Bool)
  FinishSink
  Receipt
  Terminate(NativeResultSinkIssue, Int?, Int?)
  Complete(@store.NativeResultDeliverySuccess)
  Failed(NativeResultSinkIssue, @store.NativeResultDeliveryFailure)
  Closing
  Closed
}

///|
/// A sink adapter over one existing admitted session, not a new delivery or
/// Run owner. Retry retains this exact session/phase; it never opens an attempt
/// or repeats a physical write while confirming its chunk or terminal receipt.
struct NativeResultSink {
  session : NativeResultAccessSession
  chunk_bytes : Int
  max_output_bytes : Int
  write : (Bytes) -> NativeResultSinkWrite
  finish : () -> Bool
  mut written : Int
  mut phase : NativeResultSinkPhase
}

///|
pub fn install_native_result_sink(
  session : NativeResultAccessSession,
  chunk_bytes : Int,
  max_output_bytes : Int,
  write : (Bytes) -> NativeResultSinkWrite,
  finish : () -> Bool,
) -> Result[NativeResultSink, NativeResultSinkIssue] {
  if chunk_bytes < 1 || max_output_bytes < 0 {
    return Err(InvalidSinkLimits)
  }
  Ok({
    session,
    chunk_bytes,
    max_output_bytes,
    write,
    finish,
    written: 0,
    phase: Read,
  })
}

///|
pub fn NativeResultSink::attempt_cid(self : NativeResultSink) -> String {
  self.session.attempt_cid()
}

///|
/// Perform one finite phase. Failures at Owner confirmation keep this phase
/// retryable. A caller may stop polling without cancelling the original Run.
pub fn NativeResultSink::poll(
  self : NativeResultSink,
) -> Result[NativeResultSinkStep, NativeResultSinkIssue] {
  match self.phase {
    Closing | Closed => Err(Access(InvalidProgress))
    Complete(receipt) => Ok(SinkComplete(receipt))
    Failed(issue, record) => Ok(SinkFailed(issue, record))
    Read => {
      let remaining = self.max_output_bytes - self.written
      // A one-byte read may observe EOF at an exact output boundary. An extra
      // byte remains private and is never written or confirmed to the sink.
      let next_bytes = if remaining == 0 {
        1
      } else {
        Int::min(self.chunk_bytes, remaining)
      }
      match self.session.next(next_bytes) {
        Err(issue) => {
          self.phase = Terminate(Access(issue), None, None)
          Ok(SinkProgress)
        }
        Ok(chunk) => {
          if chunk.bytes.length() > remaining {
            self.phase = Terminate(SinkOutputLimit, Some(0), None)
          } else if chunk.bytes.length() == 0 {
            if chunk.eof {
              self.phase = FinishSink
            }
          } else {
            match (self.write)(chunk.bytes) {
              SinkChunkConfirmed => {
                self.written += chunk.bytes.length()
                self.phase = ConfirmChunk(chunk.eof)
              }
              SinkChunkFailed(prefix, possible) =>
                if prefix < 0 ||
                  possible < 0 ||
                  prefix > chunk.bytes.length() ||
                  possible > chunk.bytes.length() - prefix {
                  // Invalid sink claims cannot become evidence. No part of
                  // this chunk is confirmed; possible exposure stays bounded.
                  self.phase = Terminate(
                    InvalidSinkWrite,
                    Some(0),
                    Some(chunk.bytes.length()),
                  )
                } else {
                  self.phase = Terminate(
                    SinkWriteFailed,
                    Some(prefix),
                    if possible == 0 {
                      None
                    } else {
                      Some(possible)
                    },
                  )
                }
            }
          }
          Ok(SinkProgress)
        }
      }
    }
    ConfirmChunk(eof) =>
      match self.session.confirm_chunk() {
        Err(issue) => Err(Access(issue))
        Ok(_) => {
          self.phase = if eof { FinishSink } else { Read }
          Ok(SinkProgress)
        }
      }
    FinishSink => {
      self.phase = if (self.finish)() {
        Receipt
      } else {
        Terminate(SinkFinishFailed, None, None)
      }
      Ok(SinkProgress)
    }
    Receipt =>
      match self.session.confirm_sink_finished() {
        Err(issue) => Err(Access(issue))
        Ok(receipt) => {
          self.phase = Complete(receipt)
          Ok(SinkComplete(receipt))
        }
      }
    Terminate(issue, prefix, possible) =>
      match
        self.session.terminate(
          prefix,
          false,
          if possible is Some(_) {
            "unknown_additional"
          } else {
            "exact"
          },
          possible,
          None,
        ) {
        Err(failure) => Err(Access(failure))
        Ok(record) => {
          self.phase = Failed(issue, record)
          Ok(SinkFailed(issue, record))
        }
      }
  }
}

///|
/// Retry only the existing session's close. A failure retains this handle;
/// close itself neither proves delivery completion nor cancels the Run.
pub fn NativeResultSink::close(
  self : NativeResultSink,
) -> Result[Unit, NativeResultAccessIssue] {
  let terminal = match self.phase {
    Complete(_) | Failed(_, _) => true
    _ => false
  }
  if !terminal {
    self.phase = Closing
  }
  match self.session.close() {
    Err(issue) => Err(issue)
    Ok(_) => {
      if !terminal {
        self.phase = Closed
      }
      Ok(())
    }
  }
}

///|
/// Implicit private workspace for publication evidence convenience callers.
/// Fixed bounded stream buffers are independent of canonical node limits.
/// Explicit preparation budgets remain caller-owned and are not enlarged.
pub fn publication_evidence_workspace(max_nodes : Int) -> Int {
  if max_nodes < 1 {
    0
  } else if max_nodes > (2147483647 - 4096) / 8 {
    2147483647
  } else {
    4096 + max_nodes * 8
  }
}

///|
priv enum EvidenceStreamTarget {
  Wire(String)
  Pair(@json.CanonicalValue)
  Identity(String)
}

///|
priv enum EvidenceStreamPhase {
  Begin
  Scan
  Done(Bool)
}

///|
/// Exact canonical stream comparison. Each emitter is drained after one step;
/// buffered text never grows with the input. Hash equality is used only for
/// an identity check, never as a substitute for exact value equality.
priv struct EvidenceStreamPreparation {
  mut value : @json.CanonicalValue?
  mut target : EvidenceStreamTarget?
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_workspace : Int
  mut left : @json.CanonicalEmit?
  mut right : @json.CanonicalEmit?
  mut left_writer : @encode.Writer?
  mut right_writer : @encode.Writer?
  mut left_text : String
  mut right_text : String
  mut left_offset : Int
  mut right_offset : Int
  mut left_done : Bool
  mut right_done : Bool
  mut equal : Bool
  mut phase : EvidenceStreamPhase
  mut live : Int
  mut peak : Int
  mut closed : Bool
}

///|
fn start_evidence_stream(
  value : @json.CanonicalValue,
  target : EvidenceStreamTarget,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
) -> EvidenceStreamPreparation {
  {
    value: Some(value),
    target: Some(target),
    max_wire_bytes,
    max_nodes,
    max_depth,
    max_workspace,
    left: None,
    right: None,
    left_writer: None,
    right_writer: None,
    left_text: "",
    right_text: "",
    left_offset: 0,
    right_offset: 0,
    left_done: false,
    right_done: false,
    equal: true,
    phase: Begin,
    live: 12,
    peak: 12,
    closed: false,
  }
}

///|
fn EvidenceStreamPreparation::reserve(
  self : EvidenceStreamPreparation,
  slots : Int,
) -> Unit raise @encode.EncodeFailure {
  if slots < 0 || slots > self.max_workspace - self.live {
    raise @encode.OutputLimit
  }
  self.live += slots
  self.peak = Int::max(self.peak, self.live)
}

///|
fn EvidenceStreamPreparation::step(
  self : EvidenceStreamPreparation,
) -> Unit raise @encode.EncodeFailure {
  match self.phase {
    Begin => {
      self.reserve(0)
      let target = self.target.unwrap()
      // A 512-byte writer buffer and its drained fragment may coexist. Reserve
      // both before writer creation; an emitter step emits at most 64 units.
      self.reserve(if target is Identity(_) { 1 } else { 1025 })
      let writer = match target {
        Identity(_) =>
          @encode.hashing_writer(
            self.max_wire_bytes,
            self.max_nodes,
            self.max_depth,
          )
        Wire(expected) =>
          @encode.comparing_writer(
            expected,
            self.max_wire_bytes,
            self.max_nodes,
            self.max_depth,
          )
        _ =>
          @encode.buffered_writer(
            self.max_wire_bytes,
            self.max_nodes,
            self.max_depth,
            512,
          )
      }
      self.left_writer = Some(writer)
      self.left = Some(@json.start_emit(self.value.unwrap(), writer))
      if target is Pair(other) {
        self.reserve(1025)
        let writer = @encode.buffered_writer(
          self.max_wire_bytes,
          self.max_nodes,
          self.max_depth,
          512,
        )
        self.right_writer = Some(writer)
        self.right = Some(@json.start_emit(other, writer))
      }
      self.phase = Scan
    }
    Scan => {
      let target = self.target.unwrap()
      if self.left_offset == self.left_text.length() && !self.left_done {
        let cursor = self.left.unwrap()
        let before = @json.emit_pending_frames(cursor)
        self.reserve(1)
        self.left_done = @json.advance_emit(cursor)
        self.live += @json.emit_pending_frames(cursor) - before - 1
        if target is Pair(_) {
          self.left_text = @encode.drain_buffered_output(
            self.left_writer.unwrap(),
          )
          self.left_offset = 0
        }
        if self.left_done {
          if target is Identity(expected) {
            let (digest, _, _) = @encode.finish_hash_usage(
              self.left_writer.unwrap(),
            )
            self.phase = Done("sha256:" + digest == expected)
          } else if target is Wire(_) {
            let (equal, _, _, _) = @encode.finish_comparison_usage(
              self.left_writer.unwrap(),
            )
            self.phase = Done(equal)
          } else {
            ignore(@encode.finish_buffered_usage(self.left_writer.unwrap()))
          }
          self.left_writer = None
        }
        return
      }
      if target is Pair(_) &&
        self.right_offset == self.right_text.length() &&
        !self.right_done {
        let cursor = self.right.unwrap()
        let before = @json.emit_pending_frames(cursor)
        self.reserve(1)
        self.right_done = @json.advance_emit(cursor)
        self.live += @json.emit_pending_frames(cursor) - before - 1
        self.right_text = @encode.drain_buffered_output(
          self.right_writer.unwrap(),
        )
        self.right_offset = 0
        if self.right_done {
          ignore(@encode.finish_buffered_usage(self.right_writer.unwrap()))
          self.right_writer = None
        }
        return
      }
      match target {
        Identity(_) => self.phase = Done(false)
        Wire(expected) => {
          let remaining = self.left_text.length() - self.left_offset
          if remaining == 0 && self.left_done {
            self.phase = Done(
              self.equal && self.right_offset == expected.length(),
            )
          } else {
            let count = Int::min(64, remaining)
            for index in 0..<count {
              if self.right_offset + index >= expected.length() ||
                self.left_text[self.left_offset + index] !=
                expected[self.right_offset + index] {
                self.equal = false
              }
            }
            self.left_offset += count
            self.right_offset += count
          }
        }
        Pair(_) => {
          let a = self.left_text.length() - self.left_offset
          let b = self.right_text.length() - self.right_offset
          if a == 0 && b == 0 && self.left_done && self.right_done {
            self.phase = Done(self.equal)
          } else if a == 0 && self.left_done {
            self.equal = false
            self.right_offset = self.right_text.length()
          } else if b == 0 && self.right_done {
            self.equal = false
            self.left_offset = self.left_text.length()
          } else {
            let count = Int::min(64, Int::min(a, b))
            for index in 0..<count {
              if self.left_text[self.left_offset + index] !=
                self.right_text[self.right_offset + index] {
                self.equal = false
              }
            }
            self.left_offset += count
            self.right_offset += count
          }
        }
      }
    }
    Done(_) => ()
  }
}

///|
fn EvidenceStreamPreparation::advance(
  self : EvidenceStreamPreparation,
  quantum : Int,
) -> Result[(Bool, Int), RunEvidenceChainIssue] {
  if self.closed || quantum < 1 {
    return Err(EvidenceEncoding)
  }
  let mut used = 0
  while used < quantum && !(self.phase is Done(_)) {
    try {
      self.step()
      used += 1
    } catch {
      _ => {
        self.cancel()
        return Err(EvidenceEncoding)
      }
    }
  }
  Ok((self.phase is Done(_), used))
}

///|
fn EvidenceStreamPreparation::finish(
  self : EvidenceStreamPreparation,
) -> Result[Bool, RunEvidenceChainIssue] {
  guard !self.closed && self.phase is Done(equal) else {
    return Err(EvidenceEncoding)
  }
  self.cancel()
  Ok(equal)
}

///|
fn EvidenceStreamPreparation::cancel(self : EvidenceStreamPreparation) -> Unit {
  if self.left is Some(cursor) {
    @json.cancel_emit(cursor)
  }
  if self.right is Some(cursor) {
    @json.cancel_emit(cursor)
  }
  if self.left_writer is Some(writer) {
    @encode.cancel_writer(writer)
  }
  if self.right_writer is Some(writer) {
    @encode.cancel_writer(writer)
  }
  self.left = None
  self.right = None
  self.left_writer = None
  self.right_writer = None
  self.value = None
  self.target = None
  self.left_text = ""
  self.right_text = ""
  self.phase = Done(false)
  self.live = 0
  self.closed = true
}

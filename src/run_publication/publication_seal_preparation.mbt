///|
priv enum PublicationSealPhase {
  Parse(@source.JsonParse)
  Decode(@decode.Admission)
  Canonical(@json.CursorAdmission)
  Issued
  Shape(ProtocolValidationCursor, Bool)
  Hash(@json.CanonicalEmit)
  Encode(@json.CanonicalEmit)
  Done
}

///|
/// Child of the existing capture issuer, not a separate evidence issuer.
/// Parser, canonical admission, schema visits and hashing retain continuation
/// state. Schema scalar/unique checks retain their existing blocking semantics.
priv struct PublicationSealPreparation {
  spec : ContractSpec
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_workspace : Int
  mut phase : PublicationSealPhase
  mut value : @json.CanonicalValue?
  mut writer : @encode.Writer?
  mut identity : String?
  mut contract : PublicationContract?
  mut live : Int
  mut peak : Int
  mut closed : Bool
}

///|
fn start_publication_seal_preparation(
  name : String,
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
) -> Result[PublicationSealPreparation, PublicationContractIssue] {
  guard contract_spec(name) is Some(spec) else { return Err(UnknownContract) }
  if max_wire_bytes < 1 || max_nodes < 2 || max_depth < 1 {
    return Err(InvalidLimits)
  }
  // These private consumers have fixed-size root envelopes and no separate
  // nested-identity postcondition. Do not silently extend this to other specs.
  if name != "captured_run" && name != "result_delivery_receipt" {
    return Err(UnknownContract)
  }
  if max_workspace < 8 {
    return Err(Encoding)
  }
  let parser = match
    @source.start_json_parse(
      wire,
      { max_input_bytes: max_wire_bytes, max_nodes: max_nodes - 1, max_depth, },
      data_keys=name == "captured_run",
    ) {
    Ok(parser) => parser
    Err(_) => return Err(InvalidWire)
  }
  Ok({
    spec,
    max_wire_bytes,
    max_nodes,
    max_depth,
    max_workspace,
    phase: Parse(parser),
    value: None,
    writer: None,
    identity: None,
    contract: None,
    live: 8,
    peak: 8,
    closed: false,
  })
}

///|
/// Same-owner handoff from an emitter that has just measured this immutable
/// issued value. External text still enters through parse/decode/admission.
fn start_issued_publication_seal_preparation(
  name : String,
  value : @json.CanonicalValue,
  usage : (Int, Int, Int),
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
) -> Result[PublicationSealPreparation, PublicationContractIssue] {
  guard contract_spec(name) is Some(spec) else { return Err(UnknownContract) }
  if max_wire_bytes < 1 || max_nodes < 2 || max_depth < 1 {
    return Err(InvalidLimits)
  }
  if name != "captured_run" && name != "result_delivery_receipt" {
    return Err(UnknownContract)
  }
  if max_workspace < 8 {
    return Err(Encoding)
  }
  let (bytes, nodes, depth) = usage
  // Reserve the identity node exactly as the external preimage parser does.
  if bytes < 1 ||
    bytes > max_wire_bytes ||
    nodes < 1 ||
    nodes > max_nodes - 1 ||
    depth < 0 ||
    depth > max_depth {
    return Err(InvalidWire)
  }
  Ok({
    spec,
    max_wire_bytes,
    max_nodes,
    max_depth,
    max_workspace,
    phase: Issued,
    value: Some(value),
    writer: None,
    identity: None,
    contract: None,
    live: 8,
    peak: 8,
    closed: false,
  })
}

///|
fn PublicationSealPreparation::reserve(
  self : PublicationSealPreparation,
  count : Int,
) -> Result[Unit, PublicationContractIssue] {
  if count < 0 || count > self.max_workspace - self.live {
    return Err(Encoding)
  }
  self.live += count
  self.peak = Int::max(self.peak, self.live)
  Ok(())
}

///|
fn PublicationSealPreparation::shape(
  self : PublicationSealPreparation,
  complete : Bool,
) -> Result[Unit, PublicationContractIssue] {
  let value = self.value.unwrap()
  match validate_protocol_envelope(self.spec, value, complete) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard generated_protocol_schema_root(self.spec.name, complete) is Some(root) else {
    return Err(InvalidField("protocol_schema"))
  }
  let max_nodes = self.max_nodes - (if complete { 0 } else { 1 })
  let remaining = if max_nodes > 268435455 { 2147483647 } else { max_nodes * 8 }
  match self.reserve(1) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.phase = Shape(
    start_protocol_validation(value, root, protocol_schema_nodes(), {
      remaining,
      max_wire_bytes: self.max_wire_bytes,
      max_nodes,
      max_depth: self.max_depth,
    }),
    complete,
  )
  Ok(())
}

///|
fn PublicationSealPreparation::emitter(
  self : PublicationSealPreparation,
  hash : Bool,
) -> Result[Unit, PublicationContractIssue] {
  match self.reserve(1) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  try {
    let writer = if hash {
      @encode.hashing_writer(
        self.max_wire_bytes,
        self.max_nodes - 1,
        self.max_depth,
      )
    } else {
      @encode.writer(self.max_wire_bytes, self.max_nodes, self.max_depth)
    }
    self.writer = Some(writer)
    let cursor = @json.start_emit(self.value.unwrap(), writer)
    self.phase = if hash { Hash(cursor) } else { Encode(cursor) }
    Ok(())
  } catch {
    _ => Err(Encoding)
  }
}

///|
fn PublicationSealPreparation::step(
  self : PublicationSealPreparation,
) -> Result[Unit, PublicationContractIssue] {
  match self.phase {
    Issued => self.shape(false)
    Parse(parser) =>
      match @source.advance_json_parse(parser, 1) {
        Ok(@source.JsonParseContinue(..)) => Ok(())
        Ok(@source.JsonParseComplete(parsed, ..)) =>
          match
            @decode.start_admission(parsed.node, {
              max_nodes: self.max_nodes - 1,
              max_depth: self.max_depth,
              max_string_bytes: self.max_wire_bytes,
              max_total_string_bytes: self.max_wire_bytes,
            }) {
            Ok(admission) => {
              self.phase = Decode(admission)
              Ok(())
            }
            Err(_) => Err(InvalidWire)
          }
        Ok(@source.JsonParseFailed(_, ..)) | Err(_) => Err(InvalidWire)
      }
    Decode(admission) =>
      match @decode.advance_admission(admission, 1) {
        Ok(@decode.AdmissionContinue(..)) => Ok(())
        Ok(@decode.AdmissionComplete(cursor, ..)) =>
          match
            @json.start_cursor_admission(
              cursor,
              self.max_nodes - 1,
              self.max_depth,
              self.max_wire_bytes,
              self.max_wire_bytes,
              data_keys=self.spec.name == "captured_run",
            ) {
            Some(admission) => {
              self.phase = Canonical(admission)
              Ok(())
            }
            None => Err(InvalidWire)
          }
        Ok(@decode.AdmissionFailed(_, ..)) | Err(_) => Err(InvalidWire)
      }
    Canonical(admission) =>
      match @json.advance_cursor_admission(admission) {
        @json.CursorAdmissionContinue => Ok(())
        @json.CursorAdmissionComplete(value, _, _) => {
          self.value = Some(value)
          self.shape(false)
        }
        _ => Err(InvalidWire)
      }
    Shape(cursor, complete) => {
      let before = cursor.pending.length()
      // A rule visit installs at most a continuation and one child visit.
      match self.reserve(2) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      let (done, _) = cursor.advance(1)
      self.live += cursor.pending.length() - before - 2
      if !done {
        return Ok(())
      }
      let valid = cursor.result
      cursor.cancel()
      if !valid {
        return Err(InvalidField("protocol_schema"))
      }
      self.emitter(!complete)
    }
    Hash(cursor) | Encode(cursor) => {
      let hash = self.phase is Hash(_)
      let before = @json.emit_pending_frames(cursor)
      match self.reserve(1) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      try {
        let done = @json.advance_emit(cursor)
        self.live += @json.emit_pending_frames(cursor) - before - 1
        if !done {
          return Ok(())
        }
        let writer = self.writer.unwrap()
        if hash {
          let (digest, _, _) = @encode.finish_hash_usage(writer)
          self.writer = None
          let identity = "sha256:" + digest
          guard @json.object_with_string_field(
              self.value.unwrap(),
              self.spec.identity,
              identity,
            )
            is Some(value) else {
            return Err(InvalidObject)
          }
          self.value = Some(value)
          self.identity = Some(identity)
          self.shape(true)
        } else {
          let wire = @encode.finish(writer)
          self.writer = None
          self.contract = Some({
            name: self.spec.name,
            identity_field: self.spec.identity,
            identity: self.identity.unwrap(),
            wire,
            value: self.value.unwrap(),
          })
          self.value = None
          self.phase = Done
          Ok(())
        }
      } catch {
        _ => Err(Encoding)
      }
    }
    Done => Ok(())
  }
}

///|
fn PublicationSealPreparation::advance(
  self : PublicationSealPreparation,
  quantum : Int,
) -> Result[(Bool, Int), PublicationContractIssue] {
  if self.closed || quantum < 1 {
    return Err(Encoding)
  }
  let mut used = 0
  while used < quantum && !(self.phase is Done) {
    match self.step() {
      Err(issue) => {
        self.cancel()
        return Err(issue)
      }
      Ok(_) => used += 1
    }
  }
  Ok((self.phase is Done, used))
}

///|
fn PublicationSealPreparation::finish(
  self : PublicationSealPreparation,
) -> Result[PublicationContract, PublicationContractIssue] {
  guard !self.closed && self.phase is Done && self.contract is Some(contract) else {
    return Err(Encoding)
  }
  self.contract = None
  self.cancel()
  Ok(contract)
}

///|
fn PublicationSealPreparation::cancel(
  self : PublicationSealPreparation,
) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  match self.phase {
    Parse(parser) => @source.cancel_json_parse(parser)
    Decode(admission) => @decode.cancel_admission(admission)
    Canonical(admission) => @json.cancel_cursor_admission(admission)
    Shape(cursor, _) => cursor.cancel()
    Hash(cursor) | Encode(cursor) => @json.cancel_emit(cursor)
    Issued | Done => ()
  }
  if self.writer is Some(writer) {
    @encode.cancel_writer(writer)
  }
  self.writer = None
  self.value = None
  self.identity = None
  self.contract = None
  self.phase = Done
  self.live = 0
}

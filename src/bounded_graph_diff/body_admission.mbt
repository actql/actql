///|
priv enum BodyPhase {
  StartBody
  ParseBody
  StartDecode
  DecodeBody
  StartValue
  AdmitBody
  BodyFinished
}

///|
priv struct BodyAdmission {
  chunks : Array[String]
  limits : Limits
  mut phase : BodyPhase
  mut parser : @source.JsonParse?
  mut source_node : @source.Node?
  mut decoder : @decode.Admission?
  mut decoded : @decode.Cursor?
  mut admission : @value.JsonAdmission?
}

///|
priv enum BodyPoll {
  BodyContinue(work~ : Int)
  BodyComplete(@value.CheckedValue, @decode.Cursor, work~ : Int)
  BodyFailed(Issue, work~ : Int)
}

///|
fn start_body(chunks : Array[String], limits : Limits) -> BodyAdmission {
  {
    chunks,
    limits,
    phase: StartBody,
    parser: None,
    source_node: None,
    decoder: None,
    decoded: None,
    admission: None,
  }
}

///|
/// Retire streamed fragments and their backing after ownership transfers to
/// the parser or cleanup. On non-JS targets, clear alone retains removed roots.
fn retire_body_chunks(chunks : Array[String]) -> Unit {
  chunks.clear()
  chunks.shrink_to_fit()
}

///|
/// Conservative logical workspace for source nodes/fields, owned decode
/// indexes, JSON construction, per-object name/sort indexes and their nested
/// continuations. Text retention remains separately bounded by identity bytes.
/// This preparation admission is not a machine proof of total Graph memory.
fn body_workspace_slots(limits : Limits) -> Int? {
  guard checked_add(limits.max_identity_nodes, limits.max_identity_nodes)
    is Some(n2) &&
    checked_add(n2, n2) is Some(n4) &&
    checked_add(n4, n4) is Some(n8) &&
    checked_add(n8, n8) is Some(n16) &&
    checked_add(limits.max_identity_depth, limits.max_identity_depth)
    is Some(d2) &&
    checked_add(d2, d2) is Some(d4) &&
    checked_add(d4, d4) is Some(d8) &&
    checked_add(n16, d8) is Some(body) else {
    return None
  }
  checked_add(body, 64)
}

///|
/// Decode only wire bytes emitted by the admitted snapshot owner. Each stage
/// uses the existing data owner and reports actual resumed work; no quantum
/// accounting is deferred to later polls after a synchronous tree traversal.
fn advance_body(body : BodyAdmission, quantum : Int) -> BodyPoll {
  let mut used = 0
  while used < quantum {
    match body.phase {
      StartBody => {
        used += 1
        let text = body.chunks.join("")
        retire_body_chunks(body.chunks)
        body.parser = match
          @source.start_json_parse(text, {
            max_input_bytes: body.limits.max_identity_bytes,
            max_nodes: body.limits.max_identity_nodes,
            max_depth: body.limits.max_identity_depth,
          }) {
          Ok(parser) => Some(parser)
          Err(_) => return BodyFailed(InvalidGraph, work=used)
        }
        body.phase = ParseBody
      }
      ParseBody => {
        guard body.parser is Some(parser) else {
          return BodyFailed(Terminal, work=used)
        }
        match @source.advance_json_parse(parser, quantum - used) {
          Ok(@source.JsonParseContinue(work~)) => used += work
          Ok(@source.JsonParseComplete(parsed, work~)) => {
            used += work
            body.source_node = Some(parsed.node)
            body.parser = None
            body.phase = StartDecode
          }
          Ok(@source.JsonParseFailed(_, work~)) =>
            return BodyFailed(InvalidGraph, work=used + work)
          Err(_) => return BodyFailed(Terminal, work=used)
        }
      }
      StartDecode => {
        used += 1
        guard body.source_node is Some(node) else {
          return BodyFailed(Terminal, work=used)
        }
        body.decoder = match
          @decode.start_admission(node, {
            max_nodes: body.limits.max_identity_nodes,
            max_depth: body.limits.max_identity_depth,
            max_string_bytes: body.limits.max_identity_bytes,
            max_total_string_bytes: body.limits.max_identity_bytes,
          }) {
          Ok(decoder) => Some(decoder)
          Err(_) => return BodyFailed(InvalidGraph, work=used)
        }
        body.source_node = None
        body.phase = DecodeBody
      }
      DecodeBody => {
        guard body.decoder is Some(decoder) else {
          return BodyFailed(Terminal, work=used)
        }
        match @decode.advance_admission(decoder, quantum - used) {
          Ok(@decode.AdmissionContinue(work~)) => used += work
          Ok(@decode.AdmissionComplete(cursor, work~)) => {
            used += work
            if @decode.array_length(cursor) != Some(5) {
              return BodyFailed(InvalidGraph, work=used)
            }
            body.decoded = Some(cursor)
            body.decoder = None
            body.phase = StartValue
          }
          Ok(@decode.AdmissionFailed(_, work~)) =>
            return BodyFailed(InvalidGraph, work=used + work)
          Err(_) => return BodyFailed(Terminal, work=used)
        }
      }
      StartValue => {
        used += 1
        guard body.decoded is Some(cursor) else {
          return BodyFailed(Terminal, work=used)
        }
        body.admission = match
          @value.start_json_admission(cursor, {
            max_nodes: body.limits.max_identity_nodes,
            max_depth: body.limits.max_identity_depth,
            max_text_bytes: body.limits.max_identity_bytes,
          }) {
          Ok(admission) => Some(admission)
          Err(_) => return BodyFailed(InvalidGraph, work=used)
        }
        // Keep the same owned decode index for Apply's record access. Retained
        // cursors do not acquire reference rights or require a second parse.
        body.phase = AdmitBody
      }
      AdmitBody => {
        used += 1
        guard body.admission is Some(admission) else {
          return BodyFailed(Terminal, work=used)
        }
        match @value.advance_json_admission(admission) {
          @value.JsonAdmissionContinue => ()
          @value.JsonAdmissionComplete(checked, _, _) => {
            let decoded = body.decoded.unwrap()
            body.decoded = None
            body.admission = None
            body.phase = BodyFinished
            return BodyComplete(checked, decoded, work=used)
          }
          @value.JsonAdmissionFailed(_) =>
            return BodyFailed(InvalidGraph, work=used)
          @value.JsonAdmissionTerminal => return BodyFailed(Terminal, work=used)
        }
      }
      BodyFinished => return BodyFailed(Terminal, work=used)
    }
  }
  BodyContinue(work=used)
}

///|
fn cleanup_body(body : BodyAdmission) -> Unit {
  if body.parser is Some(parser) {
    @source.cancel_json_parse(parser)
  }
  if body.decoder is Some(decoder) {
    @decode.cancel_admission(decoder)
  }
  if body.admission is Some(admission) {
    @value.cancel_json_admission(admission)
  }
  retire_body_chunks(body.chunks)
  body.parser = None
  body.decoder = None
  body.source_node = None
  body.decoded = None
  body.admission = None
  body.phase = BodyFinished
}

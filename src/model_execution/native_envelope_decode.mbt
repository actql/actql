///|
// A child of DecodePhysicalResponse. The root and selected facts overlap until
// alias projection retires it; the saved raw terminal owns its own lifetime.
priv enum NativeEnvelopePhase {
  ParseNativeEnvelope(@source.JsonParse)
  AdmitNativeEnvelope(@decode.Admission)
  ScanNativeEnvelope(@decode.Cursor)
  NativeEnvelopeReady
  NativeEnvelopeRetired
}

///|
priv struct NativeEnvelopeDecode {
  mut phase : NativeEnvelopePhase
  limits : @environment.ModelResponseProfileLimits
  mut remaining : Int
  mut facts : ChatEnvelopeFacts?
  frames : Array[ChatEnvelopeFrame]
}

///|
fn start_native_envelope_decode(
  body : String,
  limits : @environment.ModelResponseProfileLimits,
) -> Result[NativeEnvelopeDecode, ModelExecutionIssue] {
  if limits.parse_work <= 0 {
    return Err(WorkLimit)
  }
  let parse = match
    @source.start_json_parse(
      body,
      {
        max_input_bytes: limits.response_bytes,
        max_nodes: limits.parse_nodes,
        max_depth: limits.parse_depth,
      },
      data_keys=true,
    ) {
    Ok(parse) => parse
    Err(_) => return Err(OutputValue)
  }
  Ok({
    phase: ParseNativeEnvelope(parse),
    limits,
    remaining: limits.parse_work,
    facts: None,
    frames: [],
  })
}

///|
fn cancel_native_envelope_decode(child : NativeEnvelopeDecode) -> Unit {
  match child.phase {
    ParseNativeEnvelope(parse) => @source.cancel_json_parse(parse)
    AdmitNativeEnvelope(admit) => @decode.cancel_admission(admit)
    ScanNativeEnvelope(_) | NativeEnvelopeReady | NativeEnvelopeRetired => ()
  }
  child.frames.clear()
  child.facts = None
  child.phase = NativeEnvelopeRetired
}

///|
fn scan_native_envelope_field(
  child : NativeEnvelopeDecode,
  facts : ChatEnvelopeFacts,
  role : ChatEnvelopeRole,
  name : String,
  value : @decode.Cursor,
) -> Unit {
  match role {
    RootEnvelope =>
      match name {
        "model" | "id" =>
          match chat_optional_text(value) {
            Ok(text) =>
              if name == "model" {
                facts.provider_model = text
              } else {
                facts.provider_request_id = text
              }
            Err(_) => facts.malformed = true
          }
        "usage" =>
          if !@decode.is_null(value) {
            if @decode.object_length(value) is Some(_) {
              child.frames.push({ source: value, role: UsageEnvelope, next: 0, })
            } else {
              facts.malformed = true
            }
          }
        _ => ()
      }
    UsageEnvelope =>
      match name {
        "input_tokens" | "output_tokens" =>
          match chat_optional_tokens(value) {
            Ok(tokens) =>
              if name == "input_tokens" {
                facts.input_tokens = tokens
              } else {
                facts.output_tokens = tokens
              }
            Err(_) => facts.malformed = true
          }
        _ => ()
      }
    _ => facts.malformed = true
  }
}

///|
fn advance_native_envelope_decode(
  child : NativeEnvelopeDecode,
) -> Result[@decode.Cursor?, ModelExecutionIssue] {
  if child.phase is NativeEnvelopeRetired {
    return Err(OutputIdentity)
  }
  if child.remaining <= 0 {
    cancel_native_envelope_decode(child)
    return Err(WorkLimit)
  }
  child.remaining -= 1
  match child.phase {
    ParseNativeEnvelope(parse) =>
      match @source.advance_json_parse(parse, 1) {
        Ok(@source.JsonParseContinue(..)) => ()
        Ok(@source.JsonParseComplete(source, ..)) => {
          let admit = match
            @decode.start_admission(source.node, {
              max_nodes: child.limits.parse_nodes,
              max_depth: child.limits.parse_depth,
              max_string_bytes: child.limits.response_bytes,
              max_total_string_bytes: child.limits.response_bytes,
            }) {
            Ok(admit) => admit
            Err(_) => {
              cancel_native_envelope_decode(child)
              return Err(OutputValue)
            }
          }
          child.phase = AdmitNativeEnvelope(admit)
        }
        _ => {
          cancel_native_envelope_decode(child)
          return Err(OutputValue)
        }
      }
    AdmitNativeEnvelope(admit) =>
      match @decode.advance_admission(admit, 1) {
        Ok(@decode.AdmissionContinue(..)) => ()
        Ok(@decode.AdmissionComplete(root, ..)) => {
          if @decode.object_length(root) is None {
            cancel_native_envelope_decode(child)
            return Err(OutputValue)
          }
          child.facts = Some({
            answer: None,
            provider_model: None,
            provider_request_id: None,
            input_tokens: None,
            output_tokens: None,
            finish_reason: None,
            choices_seen: false,
            index_seen: false,
            message_seen: false,
            role_seen: false,
            refused: false,
            malformed: false,
          })
          child.frames.push({ source: root, role: RootEnvelope, next: 0, })
          child.phase = ScanNativeEnvelope(root)
        }
        _ => {
          cancel_native_envelope_decode(child)
          return Err(OutputValue)
        }
      }
    ScanNativeEnvelope(root) => {
      guard child.facts is Some(facts) else { return Err(OutputIdentity) }
      guard child.frames.last() is Some(frame) else {
        child.phase = NativeEnvelopeReady
        return Ok(Some(root))
      }
      match @decode.field_at(frame.source, frame.next) {
        Some((name, value)) => {
          frame.next += 1
          scan_native_envelope_field(child, facts, frame.role, name, value)
        }
        None => child.frames.pop() |> ignore
      }
    }
    // Completion is a single transfer. It is not a restartable parse loop.
    NativeEnvelopeReady | NativeEnvelopeRetired => return Err(OutputIdentity)
  }
  Ok(None)
}

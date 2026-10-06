///|
priv enum PropertyIdentityPhase {
  CheckIdentityKeys
  PrepareIdentityWriter
  IdentityHeader
  IdentityKeys
  IdentityTypes
  FinishIdentityWriter
  ParseIdentity
  StartIdentityDecode
  DecodeIdentity
  StartIdentityValue
  AdmitIdentity
  IdentityFinished
} derive(Eq)

///|
/// Resumable implementation of this storage owner's existing identity
/// projection. It owns only temporary conversion state, never a second Graph
/// builder or reference authority. Synchronous constructors drain this same
/// implementation; managed snapshot admission can resume it between stages.
priv struct PropertyIdentityPreparation {
  builder : Builder
  profile : @carrier.GraphDefinition
  definition : @carrier.GraphNodeDefinition
  mut input_keys : Array[@value.CheckedValue]?
  keys : Array[@value.CheckedValue]
  pending_work : Int
  mut phase : PropertyIdentityPhase
  mut index : Int
  mut absent : Bool
  mut cap : Int
  mut node_limit : Int
  mut nodes : Int
  mut writer : @encode.Writer?
  mut parser : @source.JsonParse?
  mut source : @source.Node?
  mut decoder : @decode.Admission?
  mut decoded : @decode.Cursor?
  mut admission : @value.JsonAdmission?
}

///|
priv enum PropertyIdentityPoll {
  PropertyIdentityContinue(work~ : Int)
  PropertyIdentityComplete(
    @value.CheckedValue?,
    construction_work~ : Int,
    work~ : Int
  )
  PropertyIdentityFailed(Issue, work~ : Int)
}

///|
fn start_property_identity(
  builder : Builder,
  profile : @carrier.GraphDefinition,
  definition : @carrier.GraphNodeDefinition,
  keys : Array[@value.CheckedValue],
  pending_work : Int,
) -> Result[PropertyIdentityPreparation, Issue] {
  if @carrier.graph_element_definition_key_count(definition) != keys.length() {
    return Err(InvalidIdentity)
  }
  Ok({
    builder,
    profile,
    definition,
    input_keys: Some(keys),
    keys: [],
    pending_work,
    phase: CheckIdentityKeys,
    index: 0,
    absent: false,
    cap: 0,
    node_limit: 0,
    nodes: 0,
    writer: None,
    parser: None,
    source: None,
    decoder: None,
    decoded: None,
    admission: None,
  })
}

///|
fn identity_encoding_issue(value : PropertyIdentityPreparation) -> Issue {
  if value.node_limit < value.builder.limits.max_value_nodes {
    WorkLimit
  } else {
    ValueLimit
  }
}

///|
fn advance_property_identity(
  value : PropertyIdentityPreparation,
  quantum : Int,
) -> PropertyIdentityPoll {
  if quantum < 1 {
    return PropertyIdentityFailed(InvalidLimits, work=0)
  }
  if value.phase == IdentityFinished {
    return PropertyIdentityFailed(Closed, work=0)
  }
  let poll = advance_property_identity_steps(value, quantum)
  if poll is PropertyIdentityFailed(_, ..) {
    // Failure is terminal, but temporary custody remains with this handle
    // until the existing operation owner explicitly cleans it up.
    value.phase = IdentityFinished
  }
  poll
}

///|
fn advance_property_identity_steps(
  value : PropertyIdentityPreparation,
  quantum : Int,
) -> PropertyIdentityPoll {
  let mut used = 0
  while used < quantum {
    let limits = value.builder.limits
    match value.phase {
      CheckIdentityKeys => {
        used += 1
        guard value.input_keys is Some(input_keys) else {
          return PropertyIdentityFailed(Closed, work=used)
        }
        if value.index < input_keys.length() {
          let key = input_keys[value.index]
          let contract = @carrier.graph_element_definition_key_at(
            value.definition,
            value.index,
          ).unwrap()
          if !contract_equal(
              value.builder,
              contract,
              @contract.with_nullability(key.contract, false),
            ) {
            return PropertyIdentityFailed(InvalidIdentity, work=used)
          }
          match key.value {
            @value.Null => value.absent = true
            @value.Reference(reference) =>
              if !@value.reference_available(reference) {
                return PropertyIdentityFailed(InvalidIdentity, work=used)
              }
            _ => ()
          }
          value.keys.push(key)
          value.index += 1
        } else {
          value.input_keys = None
          value.phase = PrepareIdentityWriter
          value.index = 0
        }
      }
      PrepareIdentityWriter => {
        used += 1
        if value.pending_work < 0 ||
          value.pending_work > limits.max_work - value.builder.work {
          return PropertyIdentityFailed(WorkLimit, work=used)
        }
        let remaining = limits.max_work -
          value.builder.work -
          value.pending_work
        if value.keys.length() > remaining {
          return PropertyIdentityFailed(WorkLimit, work=used)
        }
        if value.absent {
          value.phase = IdentityFinished
          return PropertyIdentityComplete(
            None,
            construction_work=value.keys.length(),
            work=used,
          )
        }
        value.node_limit = Int::min(
          limits.max_value_nodes,
          remaining - value.keys.length(),
        )
        value.cap = Int::min(
          limits.max_value_bytes,
          limits.max_total_value_bytes - value.builder.value_bytes,
        )
        value.writer = Some(
          @encode.writer(value.cap, value.node_limit, limits.max_value_depth),
        ) catch {
          _ =>
            return PropertyIdentityFailed(
              identity_encoding_issue(value),
              work=used,
            )
        }
        value.phase = IdentityHeader
      }
      IdentityHeader => {
        used += 1
        guard value.writer is Some(out) else {
          return PropertyIdentityFailed(Closed, work=used)
        }
        try {
          // A fixed header, independent of tuple or property cardinality.
          @encode.begin_object(out)
          @encode.key(out, "definition")
          @encode.string_value(
            out,
            @carrier.graph_element_definition_name(value.definition),
          )
          @encode.key(out, "domain")
          @encode.string_value(out, @carrier.graph_domain(value.profile))
          @encode.key(out, "key")
          @encode.begin_array(out)
        } catch {
          _ =>
            return PropertyIdentityFailed(
              identity_encoding_issue(value),
              work=used,
            )
        }
        value.phase = IdentityKeys
      }
      IdentityKeys => {
        used += 1
        guard value.writer is Some(out) else {
          return PropertyIdentityFailed(Closed, work=used)
        }
        try {
          if value.keys.get(value.index) is Some(key) {
            // Graph keys are admitted scalar contracts; reference projection
            // emits only its identity CID, never the retained evidence envelope.
            emit_property_key(key, out)
            value.index += 1
          } else {
            @encode.end_array(out)
            @encode.key(out, "key_types")
            @encode.begin_array(out)
            value.index = 0
            value.phase = IdentityTypes
          }
        } catch {
          _ =>
            return PropertyIdentityFailed(
              identity_encoding_issue(value),
              work=used,
            )
        }
      }
      IdentityTypes => {
        used += 1
        guard value.writer is Some(out) else {
          return PropertyIdentityFailed(Closed, work=used)
        }
        try {
          match
            @carrier.graph_element_definition_key_at(
              value.definition,
              value.index,
            ) {
            Some(contract) => {
              emit_property_key_type(contract, out)
              value.index += 1
            }
            None => {
              @encode.end_array(out)
              @encode.end_object(out)
              value.phase = FinishIdentityWriter
            }
          }
        } catch {
          _ =>
            return PropertyIdentityFailed(
              identity_encoding_issue(value),
              work=used,
            )
        }
      }
      FinishIdentityWriter => {
        used += 1
        guard value.writer is Some(out) else {
          return PropertyIdentityFailed(Closed, work=used)
        }
        let text = try {
          let (text, _, nodes, _) = @encode.finish_text_usage(out)
          value.nodes = nodes
          text
        } catch {
          _ =>
            return PropertyIdentityFailed(
              identity_encoding_issue(value),
              work=used,
            )
        }
        value.writer = None
        let remaining = limits.max_work -
          value.builder.work -
          value.pending_work
        // Retain the original constructor's four-pass construction ceiling.
        // Resumed poll work is reported separately, where it actually occurs.
        if value.nodes > (remaining - value.keys.length()) / 4 {
          return PropertyIdentityFailed(WorkLimit, work=used)
        }
        value.parser = match
          @source.start_json_parse(text, {
            max_input_bytes: value.cap,
            max_nodes: value.nodes,
            max_depth: limits.max_value_depth,
          }) {
          Ok(parser) => Some(parser)
          Err(_) => return PropertyIdentityFailed(ValueLimit, work=used)
        }
        value.phase = ParseIdentity
      }
      ParseIdentity => {
        guard value.parser is Some(parser) else {
          return PropertyIdentityFailed(Closed, work=used)
        }
        match @source.advance_json_parse(parser, quantum - used) {
          Ok(@source.JsonParseContinue(work~)) => used += work
          Ok(@source.JsonParseComplete(source, work~)) => {
            used += work
            value.parser = None
            value.source = Some(source.node)
            value.phase = StartIdentityDecode
          }
          Ok(@source.JsonParseFailed(_, work~)) =>
            return PropertyIdentityFailed(ValueLimit, work=used + work)
          Err(_) => return PropertyIdentityFailed(Closed, work=used)
        }
      }
      StartIdentityDecode => {
        used += 1
        guard value.source is Some(source) else {
          return PropertyIdentityFailed(Closed, work=used)
        }
        value.decoder = match
          @decode.start_admission(source, {
            max_nodes: value.nodes,
            max_depth: limits.max_value_depth,
            max_string_bytes: value.cap,
            max_total_string_bytes: value.cap,
          }) {
          Ok(decoder) => Some(decoder)
          Err(_) => return PropertyIdentityFailed(ValueLimit, work=used)
        }
        value.source = None
        value.phase = DecodeIdentity
      }
      DecodeIdentity => {
        guard value.decoder is Some(decoder) else {
          return PropertyIdentityFailed(Closed, work=used)
        }
        match @decode.advance_admission(decoder, quantum - used) {
          Ok(@decode.AdmissionContinue(work~)) => used += work
          Ok(@decode.AdmissionComplete(cursor, work~)) => {
            used += work
            value.decoder = None
            value.decoded = Some(cursor)
            value.phase = StartIdentityValue
          }
          Ok(@decode.AdmissionFailed(_, work~)) =>
            return PropertyIdentityFailed(ValueLimit, work=used + work)
          Err(_) => return PropertyIdentityFailed(Closed, work=used)
        }
      }
      StartIdentityValue => {
        used += 1
        guard value.decoded is Some(cursor) else {
          return PropertyIdentityFailed(Closed, work=used)
        }
        value.admission = match
          @value.start_json_admission(cursor, {
            max_nodes: value.nodes,
            max_depth: limits.max_value_depth,
            max_text_bytes: value.cap,
          }) {
          Ok(admission) => Some(admission)
          Err(_) => return PropertyIdentityFailed(ValueLimit, work=used)
        }
        value.decoded = None
        value.phase = AdmitIdentity
      }
      AdmitIdentity => {
        used += 1
        guard value.admission is Some(admission) else {
          return PropertyIdentityFailed(Closed, work=used)
        }
        match @value.advance_json_admission(admission) {
          @value.JsonAdmissionContinue => ()
          @value.JsonAdmissionComplete(checked, _, _) => {
            value.admission = None
            value.phase = IdentityFinished
            return PropertyIdentityComplete(
              Some(checked),
              construction_work=value.nodes * 4 + value.keys.length(),
              work=used,
            )
          }
          @value.JsonAdmissionFailed(_) =>
            return PropertyIdentityFailed(ValueLimit, work=used)
          @value.JsonAdmissionTerminal =>
            return PropertyIdentityFailed(Closed, work=used)
        }
      }
      IdentityFinished => return PropertyIdentityFailed(Closed, work=used)
    }
  }
  PropertyIdentityContinue(work=used)
}

///|
fn cleanup_property_identity(value : PropertyIdentityPreparation) -> Unit {
  if value.writer is Some(writer) {
    @encode.cancel_writer(writer)
  }
  if value.parser is Some(parser) {
    @source.cancel_json_parse(parser)
  }
  if value.decoder is Some(decoder) {
    @decode.cancel_admission(decoder)
  }
  if value.admission is Some(admission) {
    @value.cancel_json_admission(admission)
  }
  value.writer = None
  value.parser = None
  value.source = None
  value.decoder = None
  value.decoded = None
  value.admission = None
  value.input_keys = None
  value.keys.clear()
  value.phase = IdentityFinished
}

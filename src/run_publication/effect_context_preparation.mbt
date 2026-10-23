///|
priv struct EffectContextInputs {
  snapshots : Array[CapturedResultSnapshot]
  sources : Array[CapturedEffectSourceArtifact]
  local_sources : Array[CapturedLocalEffectSourceEvidence]
  dependencies : CapturedEffectDependencyInventory
  advances : Array[PendingSourceStateAdvance]
  authoring : RunEvidenceValue
  models : Array[RunEvidenceValue]
  content_generations : Array[BoundContentGeneration]
  preview : EffectPreviewIdentity?
  plans : Array[(String, @json.CanonicalValue)]
}

///|
priv enum EffectContextPhase {
  CollectIds(Int)
  SortIds(@sort.Sort)
  Root
  Field(Int)
  Key(@encode.OrderedKeyEmitCursor)
  Value(@json.CanonicalEmit)
  Text(@encode.StringEmitCursor)
  SectionStart(Int)
  SectionNext(Int, Int)
  SectionValue(Int, Int)
  ArrayStart(Int, Int)
  ArrayNext(Int, Int, Int)
  ContentField(Int, Int)
  ContentValue(Int, Int)
  Parse(@source.JsonParse, Bool)
  Decode(@decode.Admission, Bool)
  Canonical(@json.CursorAdmission, Bool)
  Hash(@json.CanonicalEmit)
  Done
}

///|
/// Private preparation inside the existing issuer. Borrowed admitted evidence
/// remains with its original owner; cancellation retires only this child.
priv struct EffectContextPreparation {
  mut inputs : EffectContextInputs?
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_workspace : Int
  ids : Array[Array[String]]
  mut sorted : @sort.Sort?
  mut writer : @encode.Writer?
  mut value : @json.CanonicalValue?
  mut phase : EffectContextPhase
  mut continuation : EffectContextPhase?
  mut live : Int
  mut peak : Int
  mut closed : Bool
}

///|
fn start_effect_context_preparation(
  snapshots : Array[CapturedResultSnapshot],
  sources : Array[CapturedEffectSourceArtifact],
  local_sources : Array[CapturedLocalEffectSourceEvidence],
  dependencies : CapturedEffectDependencyInventory,
  advances : Array[PendingSourceStateAdvance],
  authoring : RunEvidenceValue,
  models : Array[RunEvidenceValue],
  preview : EffectPreviewIdentity?,
  plans : Array[(String, @json.CanonicalValue)],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
  content_generations? : Array[BoundContentGeneration] = [],
) -> Result[EffectContextPreparation, CapturedRunIssuanceIssue] {
  if max_workspace < 12 {
    return Err(CaptureIssuanceEncoding)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(CaptureIssuanceEncoding)
  }
  Ok({
    inputs: Some({
      snapshots,
      sources,
      local_sources,
      dependencies,
      advances,
      authoring,
      models,
      content_generations,
      preview,
      plans,
    }),
    max_wire_bytes,
    max_nodes,
    max_depth,
    max_workspace,
    ids: [],
    sorted: None,
    writer: Some(writer),
    value: None,
    phase: CollectIds(0),
    continuation: None,
    live: 12,
    peak: 12,
    closed: false,
  })
}

///|
fn EffectContextPreparation::reserve(
  self : EffectContextPreparation,
  count : Int,
) -> Unit raise @encode.EncodeFailure {
  if count < 0 || count > self.max_workspace - self.live {
    raise @encode.OutputLimit
  }
  self.live += count
  self.peak = Int::max(self.peak, self.live)
}

///|
fn EffectContextPreparation::key(
  self : EffectContextPreparation,
  name : String,
  next : EffectContextPhase,
) -> Unit raise @encode.EncodeFailure {
  self.reserve(1)
  self.continuation = Some(next)
  self.phase = Key(@encode.start_ordered_key(self.writer.unwrap(), name))
}

///|
fn EffectContextPreparation::emit(
  self : EffectContextPreparation,
  value : @json.CanonicalValue,
  next : EffectContextPhase,
) -> Unit raise @encode.EncodeFailure {
  self.reserve(1)
  self.continuation = Some(next)
  self.phase = Value(@json.start_emit(value, self.writer.unwrap()))
}

///|
fn EffectContextPreparation::parse(
  self : EffectContextPreparation,
  wire : String,
  body : Bool,
) -> Unit raise @encode.EncodeFailure {
  guard @source.start_json_parse(
      wire,
      {
        max_input_bytes: self.max_wire_bytes,
        max_nodes: self.max_nodes,
        max_depth: self.max_depth,
      },
      data_keys=body,
    )
    is Ok(parser) else {
    raise @encode.OutputLimit
  }
  self.phase = Parse(parser, body)
}

///|
fn EffectContextPreparation::text(
  self : EffectContextPreparation,
  value : String,
  next : EffectContextPhase,
) -> Unit raise @encode.EncodeFailure {
  self.reserve(1)
  self.continuation = Some(next)
  self.phase = Text(@encode.start_string_value(self.writer.unwrap(), value))
}

///|
fn effect_context_field(index : Int) -> String {
  match index {
    0 => "authoring_context"
    1 => "effect_dependency_inventory"
    2 => "effect_plan_logical_cids"
    3 => "effect_plans"
    4 => "effect_source_artifacts"
    5 => "effect_source_holding_cids"
    6 => "effect_source_local_inventory"
    7 => "effects"
    8 => "model_invocation_evidence"
    9 => "model_invocation_evidence_cids"
    10 => "pending_source_state_advances"
    11 => "result_artifacts"
    12 => "result_fields"
    13 => "result_values"
    16 => "content_generations"
    _ => "version"
  }
}

///|
fn EffectContextPreparation::step(
  self : EffectContextPreparation,
) -> Unit raise @encode.EncodeFailure {
  let inputs = self.inputs.unwrap()
  let writer = self.writer.unwrap()
  match self.phase {
    CollectIds(index) => {
      let count = inputs.preview
        .map(p => p.member_effect_ids.length())
        .unwrap_or(0)
      if index == count {
        guard @sort.prepare_deferred(self.ids, self.ids.length() * 2)
          is Ok(sort) else {
          raise @encode.OutputLimit
        }
        self.sorted = Some(sort)
        self.phase = SortIds(sort)
      } else {
        // Singleton tuple, its component, and two deferred-sort indices.
        self.reserve(4)
        self.ids.push([inputs.preview.unwrap().member_effect_ids[index]])
        self.phase = CollectIds(index + 1)
      }
    }
    SortIds(sort) =>
      match @sort.advance(sort, 1) {
        Ok(@sort.Continue(..)) => ()
        Ok(@sort.Complete(..)) => self.phase = Root
        Err(_) => raise @encode.OutputLimit
      }
    Root => {
      @encode.begin_ordered_object(writer)
      self.phase = Field(0)
    }
    Field(index) =>
      if index == 15 {
        @encode.end_object(writer)
        let document = @encode.finish_document(writer)
        guard @source.start_json_document_parse(
            document,
            {
              max_input_bytes: self.max_wire_bytes,
              max_nodes: self.max_nodes,
              max_depth: self.max_depth,
            },
            data_keys=true,
          )
          is Ok(parser) else {
          raise @encode.OutputLimit
        }
        self.phase = Parse(parser, true)
      } else {
        self.key(effect_context_field(index), SectionStart(index))
      }
    Key(cursor) =>
      if @encode.advance_ordered_key(cursor) {
        self.live -= 1
        self.phase = self.continuation.unwrap()
        self.continuation = None
      }
    Text(cursor) =>
      if @encode.advance_string_value(cursor) {
        self.live -= 1
        self.phase = self.continuation.unwrap()
        self.continuation = None
      }
    Value(cursor) => {
      let before = @json.emit_pending_frames(cursor)
      // One canonical transition can grow its stack by at most one entry.
      self.reserve(1)
      let done = @json.advance_emit(cursor)
      let after = @json.emit_pending_frames(cursor)
      self.live += after - before - 1
      if done {
        self.phase = self.continuation.unwrap()
        self.continuation = None
      }
    }
    SectionStart(kind) =>
      match kind {
        0 =>
          self.emit(
            inputs.authoring.value,
            Field(if inputs.content_generations.is_empty() { 1 } else { 16 }),
          )
        1 => self.parse(inputs.dependencies.wire, false)
        8 | 9 | 10 | 16 => self.phase = ArrayStart(kind, 0)
        14 => self.text("actql-run-effect-context/0.1", Field(15))
        _ => {
          @encode.begin_ordered_object(writer)
          self.phase = SectionNext(kind, 0)
        }
      }
    SectionNext(kind, index) => {
      let count = match kind {
        2 | 7 => self.ids.length()
        3 => inputs.plans.length()
        4 | 5 => inputs.sources.length()
        6 => inputs.local_sources.length()
        _ => inputs.snapshots.length()
      }
      if index == count {
        @encode.end_object(writer)
        self.phase = Field(kind + 1)
      } else {
        let name = match kind {
          2 | 7 =>
            self.ids[@sort.index_at(self.sorted.unwrap(), index).unwrap()][0]
          3 => inputs.plans[index].0
          4 | 5 => inputs.sources[index].effect_id
          6 => inputs.local_sources[index].effect_id
          _ => inputs.snapshots[index].name
        }
        if kind == 2 {
          let preview = inputs.preview.unwrap()
          let position = @sort.index_at(self.sorted.unwrap(), index).unwrap()
          if preview.member_effect_plan_cids[position] is None {
            self.phase = SectionNext(kind, index + 1)
            return
          }
        }
        self.key(name, SectionValue(kind, index))
      }
    }
    SectionValue(kind, index) => {
      let next = SectionNext(kind, index + 1)
      match kind {
        2 => {
          let position = @sort.index_at(self.sorted.unwrap(), index).unwrap()
          self.text(
            inputs.preview.unwrap().member_effect_plan_cids[position].unwrap(),
            next,
          )
        }
        3 => self.emit(inputs.plans[index].1, next)
        4 => self.emit(inputs.sources[index].artifact.value, next)
        5 => self.text(inputs.sources[index].holding_cid, next)
        6 => self.emit(inputs.local_sources[index].value, next)
        7 => {
          @encode.begin_ordered_object(writer)
          @encode.end_object(writer)
          self.phase = next
        }
        11 => self.emit(inputs.snapshots[index].artifact.value, next)
        12 => self.phase = ArrayStart(kind, index)
        13 => self.emit(inputs.snapshots[index].rows, next)
        _ => raise @encode.InvalidStructure
      }
    }
    ArrayStart(kind, snapshot) => {
      @encode.begin_array(writer)
      self.phase = ArrayNext(kind, 0, snapshot)
    }
    ArrayNext(kind, index, snapshot) => {
      let count = match kind {
        8 | 9 => inputs.models.length()
        10 => inputs.advances.length()
        16 => inputs.content_generations.length()
        _ => inputs.snapshots[snapshot].fields.length()
      }
      if index == count {
        @encode.end_array(writer)
        self.phase = if kind == 12 {
          SectionNext(kind, snapshot + 1)
        } else if kind == 16 {
          Field(1)
        } else {
          Field(kind + 1)
        }
      } else {
        let next = EffectContextPhase::ArrayNext(kind, index + 1, snapshot)
        match kind {
          8 => self.emit(inputs.models[index].value, next)
          9 => self.text(inputs.models[index].identity, next)
          10 => self.emit(inputs.advances[index].value, next)
          16 => {
            @encode.begin_ordered_object(writer)
            self.phase = ContentField(index, 0)
          }
          _ => self.text(inputs.snapshots[snapshot].fields[index], next)
        }
      }
    }
    ContentField(index, field) =>
      if field == 5 {
        @encode.end_object(writer)
        self.phase = ArrayNext(16, index + 1, 0)
      } else {
        self.key(
          match field {
            0 => "content_evidence"
            1 => "content_generation"
            2 => "content_input_artifact"
            3 => "content_reference"
            _ => "invocation_template"
          },
          ContentValue(index, field),
        )
      }
    ContentValue(index, field) => {
      guard content_generation_capture_field(
          inputs.content_generations[index],
          field,
        )
        is Some(value) else {
        raise @encode.InvalidStructure
      }
      self.emit(value, ContentField(index, field + 1))
    }
    Parse(parser, body) =>
      match @source.advance_json_parse(parser, 1) {
        Ok(@source.JsonParseContinue(..)) => ()
        Ok(@source.JsonParseComplete(parsed, ..)) => {
          guard @decode.start_admission(parsed.node, {
              max_nodes: self.max_nodes,
              max_depth: self.max_depth,
              max_string_bytes: self.max_wire_bytes,
              max_total_string_bytes: self.max_wire_bytes,
            })
            is Ok(admission) else {
            raise @encode.OutputLimit
          }
          self.phase = Decode(admission, body)
        }
        _ => raise @encode.OutputLimit
      }
    Decode(admission, body) =>
      match @decode.advance_admission(admission, 1) {
        Ok(@decode.AdmissionContinue(..)) => ()
        Ok(@decode.AdmissionComplete(cursor, ..)) => {
          guard @json.start_cursor_admission(
              cursor,
              self.max_nodes,
              self.max_depth,
              self.max_wire_bytes,
              self.max_wire_bytes,
              data_keys=body,
            )
            is Some(admission) else {
            raise @encode.OutputLimit
          }
          self.phase = Canonical(admission, body)
        }
        _ => raise @encode.OutputLimit
      }
    Canonical(admission, body) =>
      match @json.advance_cursor_admission(admission) {
        @json.CursorAdmissionContinue => ()
        @json.CursorAdmissionComplete(value, _, _) =>
          if body {
            self.value = Some(value)
            let writer = @encode.hashing_writer(
              self.max_wire_bytes,
              self.max_nodes,
              self.max_depth,
            )
            self.writer = Some(writer)
            self.reserve(1)
            self.phase = Hash(@json.start_emit(value, writer))
          } else {
            self.emit(value, Field(2))
          }
        _ => raise @encode.OutputLimit
      }
    Hash(cursor) => {
      let before = @json.emit_pending_frames(cursor)
      self.reserve(1)
      let done = @json.advance_emit(cursor)
      self.live += @json.emit_pending_frames(cursor) - before - 1
      if done {
        let (digest, _, _) = @encode.finish_hash_usage(writer)
        self.writer = None
        guard @json.object_with_string_field(
            self.value.unwrap(),
            "effect_context_cid",
            "sha256:" + digest,
          )
          is Some(value) else {
          raise @encode.InvalidStructure
        }
        self.value = Some(value)
        self.phase = Done
      }
    }
    Done => ()
  }
}

///|
fn EffectContextPreparation::advance(
  self : EffectContextPreparation,
  quantum : Int,
) -> Result[(Bool, Int), CapturedRunIssuanceIssue] {
  if self.closed || quantum < 1 {
    return Err(CaptureIssuanceEncoding)
  }
  let mut used = 0
  while used < quantum && !(self.phase is Done) {
    self.step() catch {
      _ => {
        self.cancel()
        return Err(CaptureIssuanceEncoding)
      }
    }
    used += 1
  }
  Ok((self.phase is Done, used))
}

///|
fn EffectContextPreparation::finish(
  self : EffectContextPreparation,
) -> Result[@json.CanonicalValue, CapturedRunIssuanceIssue] {
  guard !self.closed && self.phase is Done && self.value is Some(value) else {
    return Err(CaptureIssuanceEncoding)
  }
  self.value = None
  self.cancel()
  Ok(value)
}

///|
fn EffectContextPreparation::cancel(self : EffectContextPreparation) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  match self.phase {
    Key(cursor) => @encode.cancel_ordered_key(cursor)
    Text(cursor) => @encode.cancel_string_value(cursor)
    Value(cursor) | Hash(cursor) => @json.cancel_emit(cursor)
    Parse(parser, _) => @source.cancel_json_parse(parser)
    Decode(admission, _) => @decode.cancel_admission(admission)
    Canonical(admission, _) => @json.cancel_cursor_admission(admission)
    _ => ()
  }
  if self.writer is Some(writer) {
    @encode.cancel_writer(writer)
  }
  if self.sorted is Some(sort) {
    ignore(@sort.cleanup(sort))
  }
  self.inputs = None
  self.writer = None
  self.sorted = None
  self.value = None
  self.continuation = None
  self.ids.clear()
  self.phase = Done
  self.live = 0
}

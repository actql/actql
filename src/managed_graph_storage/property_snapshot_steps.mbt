///|
priv enum SnapshotAppendPhase {
  OpenSnapshotRecord
  FindSnapshotDefinition
  ReadSnapshotIdentity
  BeginSnapshotKeys
  NextSnapshotKey
  BeginSnapshotProperties
  NextSnapshotProperty
  ReadSnapshotSource
  ReadSnapshotTarget
  AdmitSnapshotValue
  NextRuntimeKey
  NextRuntimeProperty
  RecheckRuntimeValue
  EncodeSnapshotValue
  ProjectSnapshotIdentity
  CommitSnapshotRecord
  SnapshotAppendFinished
} derive(Eq)

///|
priv enum SnapshotValueRole {
  SnapshotIdentity
  SnapshotKey
  SnapshotProperty
  SnapshotSource
  SnapshotTarget
}

///|
priv enum SnapshotEncodingRole {
  ReceivedIdentityToken
  ReceivedSourceToken
  ReceivedTargetToken
  ProjectedIdentityToken
  ProjectedSourceToken
  ProjectedTargetToken
  SnapshotPayload
} derive(Eq)

///|
priv enum SnapshotProjectionRole {
  ProjectRecordIdentity
  ProjectSourceIdentity
  ProjectTargetIdentity
} derive(Eq)

///|
/// A resumable operation of the existing private Builder. The caller retains
/// exclusive access to that builder until completion or cleanup. Only one
/// complete, validated record is appended; no partial record is published.
struct PropertySnapshotAppend {
  builder : Builder
  profile : @carrier.PropertyGraphDefinition
  edge : Bool
  mut input : @decode.Cursor?
  mut record : @decode.ObjectView?
  mut issuer : @value.ReferenceIssuer?
  mut phase : SnapshotAppendPhase
  mut definition_name : String
  mut definition_index : Int
  mut definition : @carrier.PropertyNodeDefinition?
  mut index : Int
  mut keys : Array[@value.CheckedValue]
  mut properties : Array[@value.CheckedValue]
  mut identity : @value.CheckedValue?
  mut source_identity : @value.CheckedValue?
  mut target_identity : @value.CheckedValue?
  mut token : String
  mut source_token : String
  mut target_token : String
  mut source_index : Int
  mut target_index : Int
  mut value_role : SnapshotValueRole
  mut admission : @value.TypedAdmission?
  mut admission_work_limited : Bool
  runtime_record : Bool
  runtime_keys : Array[@value.CheckedValue]
  runtime_properties : Array[@value.CheckedValue]
  mut runtime_identity : @value.CheckedValue?
  mut runtime_source : @value.CheckedValue?
  mut runtime_target : @value.CheckedValue?
  mut runtime_recheck : @value.RecheckCursor?
  mut encoding_role : SnapshotEncodingRole
  mut encoding : ValueEncoding?
  mut projection_role : SnapshotProjectionRole
  mut projection : PropertyIdentityPreparation?
  mut construction_work : Int
  mut bytes : Int
  mut key_bytes : Int
  mut payload_bytes : Int
  mut payload : String
}

///|
pub enum PropertySnapshotAppendPoll {
  PropertySnapshotAppendContinue(work~ : Int)
  PropertySnapshotAppendComplete(work~ : Int)
  PropertySnapshotAppendFailed(Issue, work~ : Int)
}

///|
/// Configuration ceiling for this operation's transient slots, separate from
/// retained Builder records. The enclosing operation includes both components
/// in its existing workspace admission. Values/frames, three projected
/// identities, sort/decode/emission state, and retained staged columns are
/// bounded by the existing per-value and declaration limits. This is not a
/// total Graph capacity or physical-byte proof.
pub fn property_snapshot_append_workspace_slots(
  graph : @carrier.Graph,
  limits : Limits,
) -> Int? {
  if !valid_limits(limits) {
    return None
  }
  let profile = @carrier.graph_property_definition(graph)
  let mut columns = 0L
  for index in 0..<@carrier.property_graph_node_count(profile) {
    let definition = @carrier.property_graph_node_at(profile, index).unwrap()
    columns = Int64::max(
      columns,
      @carrier.property_definition_key_count(definition).to_int64() +
      @carrier.field_count(@carrier.property_definition_properties(definition)).to_int64(),
    )
  }
  for index in 0..<@carrier.property_graph_edge_count(profile) {
    let definition = @carrier.property_edge_element(
      @carrier.property_graph_edge_at(profile, index).unwrap(),
    )
    columns = Int64::max(
      columns,
      @carrier.property_definition_key_count(definition).to_int64() +
      @carrier.field_count(@carrier.property_definition_properties(definition)).to_int64(),
    )
  }
  // Reject each product before arithmetic can overflow; the result is an Int
  // slot bound, so no unrepresentable intermediate can produce a valid result.
  let max = 2147483647L
  let nodes = limits.max_value_nodes.to_int64()
  let depth = limits.max_value_depth.to_int64()
  if columns > max / 2L ||
    nodes > max / 32L ||
    depth > max / 8L ||
    (columns > 0L && nodes > max / 4L / columns) {
    return None
  }
  let bound = 32L * nodes +
    8L * depth +
    4L * nodes * columns +
    2L * columns +
    160L
  if bound > max {
    None
  } else {
    Some(bound.to_int())
  }
}

///|
pub fn start_property_snapshot_append(
  builder : Builder,
  input : @decode.Cursor,
  edge~ : Bool,
  reference_issuer? : @value.ReferenceIssuer? = None,
) -> Result[PropertySnapshotAppend, Issue] {
  new_property_append(builder, Some(input), edge~, reference_issuer~)
}

///|
fn new_property_append(
  builder : Builder,
  input : @decode.Cursor?,
  edge~ : Bool,
  reference_issuer? : @value.ReferenceIssuer? = None,
  runtime_record? : Bool = false,
  runtime_keys? : Array[@value.CheckedValue] = [],
  runtime_properties? : Array[@value.CheckedValue] = [],
  runtime_identity? : @value.CheckedValue? = None,
  runtime_source? : @value.CheckedValue? = None,
  runtime_target? : @value.CheckedValue? = None,
) -> Result[PropertySnapshotAppend, Issue] {
  if !builder.open || !builder.owns_private {
    return Err(Closed)
  }
  Ok({
    builder,
    profile: @carrier.graph_property_definition(builder.graph),
    edge,
    input,
    record: None,
    issuer: reference_issuer,
    phase: OpenSnapshotRecord,
    definition_name: "",
    definition_index: 0,
    definition: None,
    index: 0,
    keys: [],
    properties: [],
    identity: None,
    source_identity: None,
    target_identity: None,
    token: "",
    source_token: "",
    target_token: "",
    source_index: -1,
    target_index: -1,
    value_role: SnapshotIdentity,
    admission: None,
    admission_work_limited: false,
    runtime_record,
    runtime_keys,
    runtime_properties,
    runtime_identity,
    runtime_source,
    runtime_target,
    runtime_recheck: None,
    encoding_role: ReceivedIdentityToken,
    encoding: None,
    projection_role: ProjectRecordIdentity,
    projection: None,
    construction_work: 0,
    bytes: 0,
    key_bytes: 0,
    payload_bytes: 0,
    payload: "",
  })
}

///|
/// Transfer private staging arrays to the same record append cursor used by
/// snapshot reload. This is not an unchecked append: every value is rechecked,
/// identities are projected from typed keys, and endpoint tokens are checked
/// against the already retained nodes. No reference evidence is reconstructed.
pub fn start_property_record_append(
  builder : Builder,
  definition_index : Int,
  identity : @value.CheckedValue,
  keys : Array[@value.CheckedValue],
  properties : Array[@value.CheckedValue],
  edge~ : Bool,
  source? : @value.CheckedValue? = None,
  target? : @value.CheckedValue? = None,
) -> Result[PropertySnapshotAppend, Issue] {
  let profile = @carrier.graph_property_definition(builder.graph)
  let definition = if edge {
    @carrier.property_graph_edge_at(profile, definition_index).map(
      @carrier.property_edge_element,
    )
  } else {
    @carrier.property_graph_node_at(profile, definition_index)
  }
  guard definition is Some(definition) &&
    keys.length() == @carrier.property_definition_key_count(definition) &&
    properties.length() ==
    @carrier.field_count(@carrier.property_definition_properties(definition)) else {
    return Err(InvalidProperties)
  }
  let has_source = source is Some(_)
  let has_target = target is Some(_)
  if edge != has_source || edge != has_target {
    return Err(InvalidProperties)
  }
  let state = match
    new_property_append(
      builder,
      None,
      edge~,
      runtime_record=true,
      runtime_keys=keys,
      runtime_properties=properties,
      runtime_identity=Some(identity),
      runtime_source=source,
      runtime_target=target,
    ) {
    Ok(state) => state
    Err(issue) => return Err(issue)
  }
  state.definition = Some(definition)
  state.definition_index = definition_index
  state.phase = ReadSnapshotIdentity
  Ok(state)
}

///|
fn start_runtime_record_value(
  state : PropertySnapshotAppend,
  role : SnapshotValueRole,
  contract : @contract.Contract,
  value : @value.CheckedValue,
) -> Issue? {
  let remaining = state.builder.limits.max_work - state.builder.work
  state.admission_work_limited = remaining <
    state.builder.limits.max_value_nodes
  state.runtime_recheck = @value.start_recheck_runtime_value(
    value.value,
    contract,
    {
      max_nodes: Int::min(state.builder.limits.max_value_nodes, remaining),
      max_depth: state.builder.limits.max_value_depth,
      max_text_bytes: state.builder.limits.max_value_bytes,
    },
  )
  if state.runtime_recheck is None {
    return Some(InvalidIdentity)
  }
  state.value_role = role
  state.phase = RecheckRuntimeValue
  None
}

///|
fn start_snapshot_value(
  state : PropertySnapshotAppend,
  role : SnapshotValueRole,
  contract : @contract.Contract,
  input : @decode.Cursor,
  host : Bool,
) -> Issue? {
  let builder = state.builder
  let remaining = builder.limits.max_work - builder.work
  let limits : @value.Limits = {
    max_nodes: Int::min(builder.limits.max_value_nodes, remaining),
    max_depth: builder.limits.max_value_depth,
    max_text_bytes: builder.limits.max_value_bytes,
  }
  state.admission_work_limited = remaining < builder.limits.max_value_nodes
  let admission = match (host, state.issuer) {
    (true, Some(issuer)) =>
      @value.start_host_typed_admission(
        issuer,
        contract,
        input,
        limits,
        {
          max_bytes: builder.limits.max_value_bytes,
          max_nodes: limits.max_nodes,
          max_depth: limits.max_depth,
          max_text_units: builder.limits.max_value_bytes,
        },
        wire=host,
      )
    _ => @value.start_typed_admission(contract, input, limits, wire=host)
  }
  match admission {
    Ok(admission) => {
      state.admission = Some(admission)
      state.value_role = role
      state.phase = AdmitSnapshotValue
      None
    }
    Err(_) =>
      Some(
        if state.admission_work_limited {
          WorkLimit
        } else {
          InvalidIdentity
        },
      )
  }
}

///|
fn start_snapshot_encoding(
  state : PropertySnapshotAppend,
  role : SnapshotEncodingRole,
  values : Array[@value.CheckedValue],
  bytes : Int,
  work : Int,
) -> Unit {
  state.encoding = Some(
    start_value_encoding(
      state.builder,
      values,
      bytes,
      work,
      identity_body=role != SnapshotPayload,
    ),
  )
  state.encoding_role = role
  state.phase = EncodeSnapshotValue
}

///|
fn start_snapshot_projection(
  state : PropertySnapshotAppend,
  role : SnapshotProjectionRole,
) -> Issue? {
  let (definition, keys) = match role {
    ProjectRecordIdentity => (state.definition.unwrap(), state.keys)
    ProjectSourceIdentity | ProjectTargetIdentity => {
      let edge = @carrier.property_graph_edge_at(
        state.profile,
        state.definition_index,
      ).unwrap()
      let (source_name, target_name) = @carrier.property_edge_endpoints(edge)
      let name = if role == ProjectSourceIdentity {
        source_name
      } else {
        target_name
      }
      let index = if role == ProjectSourceIdentity {
        state.source_index
      } else {
        state.target_index
      }
      // Retained typed keys, not identity JSON, carry endpoint evidence.
      (
        @carrier.property_graph_node_named(state.profile, name).unwrap(),
        state.builder.nodes[index].typed_key,
      )
    }
  }
  match
    start_property_identity(
      state.builder,
      state.profile,
      definition,
      keys,
      state.construction_work + 1,
    ) {
    Ok(projection) => {
      state.projection = Some(projection)
      state.projection_role = role
      state.phase = ProjectSnapshotIdentity
      None
    }
    Err(issue) => Some(issue)
  }
}

///|
fn snapshot_append_failed(
  state : PropertySnapshotAppend,
  issue : Issue,
  work : Int,
) -> PropertySnapshotAppendPoll {
  state.builder.open = false
  state.phase = SnapshotAppendFinished
  // Private construction and child custody remain with the original owners
  // until explicit cleanup, including failures after successful value reads.
  PropertySnapshotAppendFailed(issue, work~)
}

///|
pub fn advance_property_snapshot_append(
  state : PropertySnapshotAppend,
  quantum : Int,
) -> PropertySnapshotAppendPoll {
  if quantum < 1 {
    return PropertySnapshotAppendFailed(InvalidLimits, work=0)
  }
  if state.phase == SnapshotAppendFinished ||
    !state.builder.open ||
    !state.builder.owns_private {
    return PropertySnapshotAppendFailed(Closed, work=0)
  }
  let builder = state.builder
  let mut used = 0
  while used < quantum {
    match state.phase {
      OpenSnapshotRecord => {
        used += 1
        let names = if state.edge {
          ["dst", "id", "key", "props", "src"]
        } else {
          ["id", "key", "props"]
        }
        let record = snapshot_object(state.input.unwrap(), names) catch {
          PropertySnapshotStop(issue) =>
            return snapshot_append_failed(state, issue, used)
        }
        let identity = @decode.lookup(record, "id").unwrap()
        guard @decode.object_length(identity) == Some(4) &&
          @decode.closed_object(identity, [
            "definition", "domain", "key", "key_types",
          ])
          is Ok(fields) &&
          @decode.lookup(fields, "definition") is Some(name_at) &&
          @decode.text(name_at) is Ok(name) else {
          return snapshot_append_failed(state, InvalidIdentity, used)
        }
        state.record = Some(record)
        state.input = None
        state.definition_name = name
        state.phase = FindSnapshotDefinition
      }
      FindSnapshotDefinition => {
        used += 1
        let definition = if state.edge {
          @carrier.property_graph_edge_at(state.profile, state.definition_index).map(
            @carrier.property_edge_element,
          )
        } else {
          @carrier.property_graph_node_at(state.profile, state.definition_index)
        }
        guard definition is Some(definition) else {
          return snapshot_append_failed(state, InvalidIdentity, used)
        }
        snapshot_charge(builder, 1) catch {
          PropertySnapshotStop(issue) =>
            return snapshot_append_failed(state, issue, used)
        }
        if @carrier.property_definition_name(definition) ==
          state.definition_name {
          state.definition = Some(definition)
          state.phase = ReadSnapshotIdentity
        } else {
          state.definition_index += 1
        }
      }
      ReadSnapshotIdentity | ReadSnapshotSource | ReadSnapshotTarget => {
        used += 1
        let (name, role) = match state.phase {
          ReadSnapshotSource => ("src", SnapshotSource)
          ReadSnapshotTarget => ("dst", SnapshotTarget)
          _ => ("id", SnapshotIdentity)
        }
        let issue = if state.runtime_record {
          let value = match role {
            SnapshotIdentity => state.runtime_identity
            SnapshotSource => state.runtime_source
            _ => state.runtime_target
          }
          guard value is Some(value) else {
            return snapshot_append_failed(state, InvalidIdentity, used)
          }
          start_runtime_record_value(
            state,
            role,
            @carrier.graph_identity(builder.graph),
            value,
          )
        } else {
          start_snapshot_value(
            state,
            role,
            @carrier.graph_identity(builder.graph),
            @decode.lookup(state.record.unwrap(), name).unwrap(),
            false,
          )
        }
        if issue is Some(issue) {
          return snapshot_append_failed(state, issue, used)
        }
      }
      BeginSnapshotKeys => {
        used += 1
        let keys = @decode.lookup(state.record.unwrap(), "key").unwrap()
        if @decode.array_length(keys) !=
          Some(
            @carrier.property_definition_key_count(state.definition.unwrap()),
          ) {
          return snapshot_append_failed(state, InvalidIdentity, used)
        }
        state.index = 0
        state.phase = NextSnapshotKey
      }
      NextRuntimeKey | NextRuntimeProperty => {
        used += 1
        let definition = state.definition.unwrap()
        let value = if state.phase == NextRuntimeKey {
          state.runtime_keys.get(state.index)
        } else {
          state.runtime_properties.get(state.index)
        }
        if value is Some(value) {
          let (role, contract) = if state.phase == NextRuntimeKey {
            (
              SnapshotKey,
              @carrier.property_definition_key_at(definition, state.index).unwrap(),
            )
          } else {
            (
              SnapshotProperty,
              @carrier.field_at(
                @carrier.property_definition_properties(definition),
                state.index,
              ).unwrap().contract.unwrap(),
            )
          }
          if start_runtime_record_value(state, role, contract, value)
            is Some(issue) {
            return snapshot_append_failed(state, issue, used)
          }
        } else if state.phase == NextRuntimeKey {
          state.index = 0
          state.phase = NextRuntimeProperty
        } else if state.edge {
          state.phase = ReadSnapshotSource
        } else if start_snapshot_projection(state, ProjectRecordIdentity)
          is Some(issue) {
          return snapshot_append_failed(state, issue, used)
        }
      }
      RecheckRuntimeValue => {
        used += 1
        let recheck = state.runtime_recheck.unwrap()
        match @value.advance_recheck_runtime_value(recheck) {
          @value.RecheckContinue => ()
          @value.RecheckFailed =>
            return snapshot_append_failed(
              state,
              if state.admission_work_limited {
                WorkLimit
              } else {
                InvalidIdentity
              },
              used,
            )
          @value.RecheckComplete(value, nodes, _) => {
            snapshot_charge(builder, nodes) catch {
              PropertySnapshotStop(issue) =>
                return snapshot_append_failed(state, issue, used)
            }
            state.runtime_recheck = None
            match state.value_role {
              SnapshotIdentity | SnapshotSource | SnapshotTarget => {
                let role = match state.value_role {
                  SnapshotSource => ReceivedSourceToken
                  SnapshotTarget => ReceivedTargetToken
                  _ => ReceivedIdentityToken
                }
                start_snapshot_encoding(state, role, [value], 0, 0)
              }
              SnapshotKey => {
                state.keys.push(value)
                state.index += 1
                state.phase = NextRuntimeKey
              }
              SnapshotProperty => {
                state.properties.push(value)
                state.index += 1
                state.phase = NextRuntimeProperty
              }
            }
          }
        }
      }
      NextSnapshotKey => {
        used += 1
        let definition = state.definition.unwrap()
        if @carrier.property_definition_key_at(definition, state.index)
          is Some(contract) {
          let keys = @decode.lookup(state.record.unwrap(), "key").unwrap()
          if start_snapshot_value(
              state,
              SnapshotKey,
              contract,
              @decode.element_at(keys, state.index).unwrap(),
              true,
            )
            is Some(issue) {
            return snapshot_append_failed(state, issue, used)
          }
        } else {
          state.phase = BeginSnapshotProperties
        }
      }
      BeginSnapshotProperties => {
        used += 1
        let properties = @decode.lookup(state.record.unwrap(), "props").unwrap()
        let schema = @carrier.property_definition_properties(
          state.definition.unwrap(),
        )
        if @decode.object_length(properties) !=
          Some(@carrier.field_count(schema)) {
          return snapshot_append_failed(state, InvalidProperties, used)
        }
        state.index = 0
        state.phase = NextSnapshotProperty
      }
      NextSnapshotProperty => {
        used += 1
        let schema = @carrier.property_definition_properties(
          state.definition.unwrap(),
        )
        if @carrier.field_at(schema, state.index) is Some(field) {
          let properties = @decode.lookup(state.record.unwrap(), "props").unwrap()
          guard @decode.field_at(properties, state.index) is Some((name, input)) &&
            name == @schema.reference_name(field.name) else {
            return snapshot_append_failed(state, InvalidProperties, used)
          }
          if start_snapshot_value(
              state,
              SnapshotProperty,
              field.contract.unwrap(),
              input,
              true,
            )
            is Some(issue) {
            return snapshot_append_failed(state, issue, used)
          }
        } else if state.edge {
          state.phase = ReadSnapshotSource
        } else if start_snapshot_projection(state, ProjectRecordIdentity)
          is Some(issue) {
          return snapshot_append_failed(state, issue, used)
        }
      }
      AdmitSnapshotValue => {
        used += 1
        let admission = state.admission.unwrap()
        match @value.advance_typed_admission(admission) {
          @value.TypedAdmissionContinue => ()
          @value.TypedAdmissionComplete(value, nodes, _) => {
            snapshot_charge(builder, nodes) catch {
              PropertySnapshotStop(issue) =>
                return snapshot_append_failed(state, issue, used)
            }
            @value.cancel_typed_admission(admission)
            state.admission = None
            match state.value_role {
              SnapshotIdentity | SnapshotSource | SnapshotTarget => {
                let role = match state.value_role {
                  SnapshotSource => ReceivedSourceToken
                  SnapshotTarget => ReceivedTargetToken
                  _ => ReceivedIdentityToken
                }
                start_snapshot_encoding(state, role, [value], 0, 0)
              }
              SnapshotKey => {
                state.keys.push(value)
                state.index += 1
                state.phase = NextSnapshotKey
              }
              SnapshotProperty => {
                state.properties.push(value)
                state.index += 1
                state.phase = NextSnapshotProperty
              }
            }
          }
          @value.TypedAdmissionFailed(_) =>
            return snapshot_append_failed(
              state,
              if state.admission_work_limited {
                WorkLimit
              } else {
                InvalidIdentity
              },
              used,
            )
          @value.TypedAdmissionTerminal =>
            return snapshot_append_failed(state, Closed, used)
        }
      }
      ProjectSnapshotIdentity => {
        let projection = state.projection.unwrap()
        match advance_property_identity(projection, quantum - used) {
          PropertyIdentityContinue(work~) => used += work
          PropertyIdentityFailed(issue, work~) =>
            return snapshot_append_failed(state, issue, used + work)
          PropertyIdentityComplete(identity, construction_work~, work~) => {
            used += work
            cleanup_property_identity(projection)
            state.projection = None
            guard identity is Some(identity) else {
              return snapshot_append_failed(state, InvalidIdentity, used)
            }
            state.construction_work += construction_work
            match state.projection_role {
              ProjectRecordIdentity => {
                state.identity = Some(identity)
                start_snapshot_encoding(
                  state,
                  ProjectedIdentityToken,
                  [identity],
                  0,
                  state.construction_work + 1,
                )
              }
              ProjectSourceIdentity => {
                state.source_identity = Some(identity)
                if start_snapshot_projection(state, ProjectTargetIdentity)
                  is Some(issue) {
                  return snapshot_append_failed(state, issue, used)
                }
              }
              ProjectTargetIdentity => {
                state.target_identity = Some(identity)
                start_snapshot_encoding(
                  state,
                  ProjectedSourceToken,
                  [state.source_identity.unwrap()],
                  state.bytes,
                  state.construction_work + 1,
                )
              }
            }
          }
        }
      }
      EncodeSnapshotValue => {
        let encoding = state.encoding.unwrap()
        match advance_value_encoding(encoding, quantum - used) {
          ValueEncodingContinue(work~) => used += work
          ValueEncodingFailed(issue, work~) =>
            return snapshot_append_failed(state, issue, used + work)
          ValueEncodingComplete(text, bytes~, nodes~, work~) => {
            used += work
            cleanup_value_encoding(encoding)
            state.encoding = None
            match state.encoding_role {
              ReceivedIdentityToken => {
                snapshot_charge(builder, nodes) catch {
                  PropertySnapshotStop(issue) =>
                    return snapshot_append_failed(state, issue, used)
                }
                let previous = if state.edge {
                  builder.edges.last().map(edge => edge.identity_order_key)
                } else {
                  builder.nodes.last().map(node => node.identity_order_key)
                }
                if previous is Some(previous) &&
                  @canonical.compare_utf16(previous, text) >= 0 {
                  return snapshot_append_failed(state, InvalidIdentity, used)
                }
                state.token = text
                state.phase = if state.runtime_record {
                  NextRuntimeKey
                } else {
                  BeginSnapshotKeys
                }
              }
              ReceivedSourceToken | ReceivedTargetToken => {
                snapshot_charge(builder, nodes) catch {
                  PropertySnapshotStop(issue) =>
                    return snapshot_append_failed(state, issue, used)
                }
                guard builder.node_keys.get(text) is Some(index) else {
                  return snapshot_append_failed(state, MissingEndpoint, used)
                }
                if state.encoding_role == ReceivedSourceToken {
                  state.source_token = text
                  state.source_index = index
                  state.phase = ReadSnapshotTarget
                } else {
                  state.target_token = text
                  state.target_index = index
                  if start_snapshot_projection(state, ProjectRecordIdentity)
                    is Some(issue) {
                    return snapshot_append_failed(state, issue, used)
                  }
                }
              }
              ProjectedIdentityToken => {
                if text != state.token {
                  return snapshot_append_failed(state, InvalidIdentity, used)
                }
                state.key_bytes = bytes
                state.bytes = bytes
                state.construction_work += nodes
                if state.edge {
                  if builder.edge_keys.contains(text) {
                    return snapshot_append_failed(state, DuplicateEdgeKey, used)
                  }
                  if start_snapshot_projection(state, ProjectSourceIdentity)
                    is Some(issue) {
                    return snapshot_append_failed(state, issue, used)
                  }
                } else {
                  start_snapshot_encoding(
                    state,
                    SnapshotPayload,
                    state.properties,
                    state.bytes,
                    state.construction_work + 1,
                  )
                }
              }
              ProjectedSourceToken | ProjectedTargetToken => {
                let expected = if state.encoding_role == ProjectedSourceToken {
                  state.source_token
                } else {
                  state.target_token
                }
                if text != expected {
                  return snapshot_append_failed(state, InvalidIdentity, used)
                }
                state.bytes += bytes
                state.construction_work += nodes
                if state.encoding_role == ProjectedSourceToken {
                  start_snapshot_encoding(
                    state,
                    ProjectedTargetToken,
                    [state.target_identity.unwrap()],
                    state.bytes,
                    state.construction_work + 1,
                  )
                } else {
                  start_snapshot_encoding(
                    state,
                    SnapshotPayload,
                    state.properties,
                    state.bytes,
                    state.construction_work + 1,
                  )
                }
              }
              SnapshotPayload => {
                state.payload = text
                state.payload_bytes = bytes
                state.bytes += bytes
                state.construction_work += nodes + 1
                state.phase = CommitSnapshotRecord
              }
            }
          }
        }
      }
      CommitSnapshotRecord => {
        used += 1
        let retained = state.key_bytes + state.payload_bytes
        let slots = if state.edge {
          edge_slots(state.properties.length()) + state.keys.length() + 3
        } else {
          node_slots(state.properties.length()) + state.keys.length() + 1
        }
        if !state.edge && builder.node_keys.contains(state.token) {
          return snapshot_append_failed(state, DuplicateNodeKey, used)
        }
        if reserve(
            builder,
            1,
            if state.edge {
              0
            } else {
              1
            },
            if state.edge {
              1
            } else {
              0
            },
            state.bytes,
            retained,
            state.construction_work,
            slots,
          )
          is Some(issue) {
          return snapshot_append_failed(state, issue, used)
        }
        // Transfer the staged arrays instead of copying all columns at commit.
        // Cleanup clears only arrays still owned by this operation handle.
        let keys = state.keys
        let properties = state.properties
        state.keys = []
        state.properties = []
        if state.edge {
          builder.edge_keys[state.token] = builder.edges.length()
          builder.edge_payloads[state.token] = state.payload
          builder.edges.push({
            property_definition: state.definition_index,
            identity_order_key: state.token,
            identity: state.identity.unwrap(),
            typed_key: keys,
            source: state.source_index,
            target: state.target_index,
            properties,
          })
        } else {
          builder.node_keys[state.token] = builder.nodes.length()
          builder.node_payloads[state.token] = state.payload
          builder.nodes.push({
            property_definition: state.definition_index,
            identity_order_key: state.token,
            identity: state.identity.unwrap(),
            typed_key: keys,
            properties,
          })
        }
        builder.input_rows += 1
        builder.value_bytes += state.bytes
        builder.retained_value_bytes += retained
        builder.work += state.construction_work
        builder.workspace_slots += slots
        state.phase = SnapshotAppendFinished
        return PropertySnapshotAppendComplete(work=used)
      }
      SnapshotAppendFinished =>
        return PropertySnapshotAppendFailed(Closed, work=used)
    }
  }
  PropertySnapshotAppendContinue(work=used)
}

///|
/// Drop only temporary record preparation. The caller still owns Builder
/// cleanup, whether this operation failed, was cancelled or committed a record.
pub fn cleanup_property_snapshot_append(state : PropertySnapshotAppend) -> Unit {
  if state.runtime_recheck is Some(cursor) {
    @value.cancel_recheck_runtime_value(cursor)
    state.runtime_recheck = None
  }
  if state.admission is Some(admission) {
    @value.cancel_typed_admission(admission)
  }
  if state.encoding is Some(encoding) {
    cleanup_value_encoding(encoding)
  }
  if state.projection is Some(projection) {
    cleanup_property_identity(projection)
  }
  state.admission = None
  state.encoding = None
  state.projection = None
  state.input = None
  state.record = None
  state.issuer = None
  state.definition = None
  state.identity = None
  state.source_identity = None
  state.target_identity = None
  state.runtime_identity = None
  state.runtime_source = None
  state.runtime_target = None
  state.definition_name = ""
  state.token = ""
  state.source_token = ""
  state.target_token = ""
  state.payload = ""
  state.keys.clear()
  state.properties.clear()
  state.keys.shrink_to_fit()
  state.properties.shrink_to_fit()
  state.runtime_keys.clear()
  state.runtime_keys.shrink_to_fit()
  state.runtime_properties.clear()
  state.runtime_properties.shrink_to_fit()
  state.phase = SnapshotAppendFinished
}

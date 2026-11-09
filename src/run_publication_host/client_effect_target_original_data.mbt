///|
// Bounded DATA conversion for the existing selection Owner. These constants
// bound selection/installation metadata, not the complete nested Run material.
const CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES : Int = 65536

///|
// One complete existing material string can expand sixfold when JSON-quoted.
// Its independent selection metadata keeps the original 64 KiB policy. This
// physical conversion ceiling is not a resource grant or a larger inner codec.
const CLIENT_EFFECT_TARGET_ORIGINAL_ENVELOPE_MAX_BYTES : Int = 6 *
  @remote.REMOTE_RUN_MATERIALS_MAX_BYTES +
  CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES

///|
const CLIENT_EFFECT_TARGET_ORIGINAL_MAX_DEPTH : Int = 64

///|
/// Physical conversion ceilings of this existing DATA boundary, not funding.
pub fn client_effect_target_original_codec_limits() -> Array[Int] {
  [
    CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
    CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
    CLIENT_EFFECT_TARGET_ORIGINAL_MAX_DEPTH,
  ]
}

///|
priv suberror ClientEffectTargetOriginalStop {
  InvalidUpdateTargetOriginal
}

///|
fn client_effect_target_original_cursor(
  wire : String,
  envelope? : Bool = false,
) -> @decode.Cursor raise ClientEffectTargetOriginalStop {
  let maximum = if envelope {
    CLIENT_EFFECT_TARGET_ORIGINAL_ENVELOPE_MAX_BYTES
  } else {
    CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES
  }
  let source = @source.parse_json_bytes(
    @utf8.encode(wire),
    {
      max_input_bytes: maximum,
      max_nodes: CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
      max_depth: CLIENT_EFFECT_TARGET_ORIGINAL_MAX_DEPTH,
    },
    source_path="Original UPDATE custody",
  ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
  @decode.admit(source, {
    max_nodes: CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
    max_depth: CLIENT_EFFECT_TARGET_ORIGINAL_MAX_DEPTH,
    max_string_bytes: maximum,
    max_total_string_bytes: maximum,
  }).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
}

///|
fn client_effect_target_original_text(
  object : @decode.ObjectView,
  key : String,
  material? : Bool = false,
) -> String raise ClientEffectTargetOriginalStop {
  let value = @decode.required(object, key).unwrap_or_else(() => {
    raise InvalidUpdateTargetOriginal
  })
  let text = @decode.text(value).unwrap_or_else(() => {
    raise InvalidUpdateTargetOriginal
  })
  if text.is_empty() ||
    @utf8.encode(text).length() >
    (if material {
      @remote.REMOTE_RUN_MATERIALS_MAX_BYTES
    } else {
      CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES
    }) {
    raise InvalidUpdateTargetOriginal
  }
  text
}

///|
fn client_effect_target_original_canonical(
  wire : String,
) -> String raise ClientEffectTargetOriginalStop {
  let source = @source.parse_json_bytes(@utf8.encode(wire), {
    max_input_bytes: CLIENT_EFFECT_TARGET_ORIGINAL_ENVELOPE_MAX_BYTES,
    max_nodes: CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
    max_depth: CLIENT_EFFECT_TARGET_ORIGINAL_MAX_DEPTH,
  }).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
  let value = @canonical.from_source(
    source,
    CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
    CLIENT_EFFECT_TARGET_ORIGINAL_MAX_DEPTH,
    CLIENT_EFFECT_TARGET_ORIGINAL_ENVELOPE_MAX_BYTES,
    data_keys=true,
  ) catch {
    _ => raise InvalidUpdateTargetOriginal
  }
  @canonical.stringify_value(
    value,
    CLIENT_EFFECT_TARGET_ORIGINAL_ENVELOPE_MAX_BYTES,
    CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
    CLIENT_EFFECT_TARGET_ORIGINAL_MAX_DEPTH,
  ) catch {
    _ => raise InvalidUpdateTargetOriginal
  }
}

///|
fn client_effect_target_original_string_bytes(
  value : String,
) -> Int raise ClientEffectTargetOriginalStop {
  let wire = try {
    let writer = @encode.measuring_writer(
      CLIENT_EFFECT_TARGET_ORIGINAL_ENVELOPE_MAX_BYTES,
      1,
      1,
    )
    @encode.string_value(writer, value)
    @encode.finish_measurement(writer)
  } catch {
    _ => raise InvalidUpdateTargetOriginal
  }
  wire
}

///|
/// Demand for one actual original-material envelope, before the Host converts
/// it to nested JSON. The first borrowed string is the complete material; the
/// remaining strings are the already-owned installation wires. Metadata keeps
/// its independent limit. Measurement creates no second serialized material.
/// This DATA quote authenticates nothing and grants no resource or authority.
pub fn client_effect_target_original_envelope_capacity(
  count : Int,
  wire_at : (Int) -> String,
) -> @execution.ExecutionCapacity? {
  if count < 2 || count > 1025 {
    return None
  }
  try {
    let mut bytes = 256L
    let mut metadata = 0L
    let mut units = 0L
    for index in 0..<count {
      let wire = wire_at(index)
      let maximum = if index == 0 {
        @remote.REMOTE_RUN_MATERIALS_MAX_BYTES
      } else {
        CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES
      }
      if wire.is_empty() || @utf8.encode(wire).length() > maximum {
        return None
      }
      let quoted = client_effect_target_original_string_bytes(wire).to_int64()
      units += wire.length().to_int64()
      if index == 0 {
        bytes += quoted
      } else {
        // CID, two keys, record/array punctuation and original fixed slack.
        metadata += 128L + quoted
      }
    }
    bytes += metadata
    if metadata > CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES.to_int64() ||
      bytes > CLIENT_EFFECT_TARGET_ORIGINAL_ENVELOPE_MAX_BYTES.to_int64() {
      return None
    }
    let nodes = 8L + 6L * (count - 1).to_int64()
    @execution.execution_capacity_inventory(
      [
        // The captured original and its durable enclosing submission coexist.
        { unit: CanonicalWireBytes, count: bytes, copies: 2, },
        { unit: DecodedTextBytes, count: units, copies: 1, },
        { unit: ValueNodeSlots, count: nodes, copies: 2, },
      ],
      [
        // Active DATA admission/comparison is sequential constructor scratch.
        { unit: CanonicalWireBytes, count: bytes, copies: 2, },
        { unit: ValueNodeSlots, count: nodes, copies: 2, },
      ],
      RetainedAlongsideExecution,
    )
  } catch {
    _ => None
  }
}

///|
/// Preserve the installed row Owner's existing NFC structural identity.
/// Only already selected physical configuration is supplied by the Host.
pub fn issue_client_effect_target_installation(
  facts : String,
) -> Result[(String, String), ClientEffectUpdateTargetIssue] {
  admit_client_effect_target_installation_data(facts).map(data => {
    (data.cid, data.wire)
  })
}

///|
// Raw/untrusted and cold DATA keep complete closed-shape and byte admission.
fn admit_client_effect_target_installation_data(
  facts : String,
) -> Result[ClientEffectTargetInstallationData, ClientEffectUpdateTargetIssue] {
  try {
    let object = @decode.closed_object(
      client_effect_target_original_cursor(facts),
      [
        "binding_cid", "connection", "connector_registration", "connector_revision",
        "continuation_binding", "profile", "runtime_bundle_cid",
      ],
    ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
    let profile = @decode.closed_object(
      @decode.required(object, "profile").unwrap_or_else(() => {
        raise InvalidUpdateTargetOriginal
      }),
      [
        "continuation", "continuationBinding", "dispatch", "recovery", "source",
        "targetCheck", "unit",
      ],
    ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
    let values : Array[String] = []
    for
      key in [
        "binding_cid", "connection", "connector_registration", "connector_revision",
        "continuation_binding",
      ] {
      values.push(client_effect_target_original_text(object, key))
    }
    for
      key in [
        "continuation", "continuationBinding", "dispatch", "recovery", "source",
        "targetCheck", "unit",
      ] {
      values.push(client_effect_target_original_text(profile, key))
    }
    values.push(
      client_effect_target_original_text(object, "runtime_bundle_cid"),
    )
    prepare_client_effect_target_installation_data(values)
  } catch {
    _ => Err(InvalidMaterials)
  }
}

///|
fn client_effect_target_original_installations(
  root : @decode.Cursor,
) -> (Array[(String, String)], Int) raise ClientEffectTargetOriginalStop {
  let values = @decode.elements(root).unwrap_or_else(() => {
    raise InvalidUpdateTargetOriginal
  })
  if values.is_empty() || values.length() > 1024 {
    raise InvalidUpdateTargetOriginal
  }
  let seen : Map[String, Bool] = Map([])
  let installations : Array[(String, String)] = []
  let mut bytes = 0
  for value in values {
    let object = @decode.closed_object(value, ["cid", "wire"]).unwrap_or_else(() => {
      raise InvalidUpdateTargetOriginal
    })
    let cid = client_effect_target_original_text(object, "cid")
    let wire = client_effect_target_original_text(object, "wire")
    if !valid_client_request_cid(cid) || seen.contains(cid) {
      raise InvalidUpdateTargetOriginal
    }
    seen.set(cid, true)
    let (expected_cid, expected_wire) = issue_client_effect_target_installation(
      wire,
    ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
    if cid != expected_cid || wire != expected_wire {
      raise InvalidUpdateTargetOriginal
    }
    bytes += 128 +
      client_effect_target_original_string_bytes(cid) +
      client_effect_target_original_string_bytes(wire)
    if bytes > CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES {
      raise InvalidUpdateTargetOriginal
    }
    installations.push((cid, wire))
  }
  (installations, bytes)
}

///|
pub fn client_effect_target_installations_shape(wire : String) -> Bool {
  try {
    client_effect_target_original_installations(
      client_effect_target_original_cursor(wire),
    )
    |> ignore
    true
  } catch {
    _ => false
  }
}

///|
/// Compare borrowed canonical cid/wire pairs after full installation admission.
/// This is DATA equality only: it neither admits an installation nor replaces
/// the original selection's current purpose and Mapping observations.
pub fn client_effect_target_installations_data_equal(
  left : Array[String],
  right : Array[String],
) -> Bool {
  if left.length() < 2 ||
    left.length() > 2048 ||
    left.length() % 2 != 0 ||
    left.length() != right.length() {
    return false
  }
  let mut units = 0
  for index in 0..<left.length() {
    if left[index].length() > CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES ||
      left[index] != right[index] {
      return false
    }
    units += left[index].length()
    if units > CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES {
      return false
    }
  }
  true
}

///|
pub fn client_effect_target_prepared_original_shape(wire : String) -> Bool {
  try {
    let object = @decode.closed_object(
      client_effect_target_original_cursor(wire, envelope=true),
      ["preparedWire", "compiledPlanCid", "installations"],
    ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
    let prepared = client_effect_target_original_text(
      object,
      "preparedWire",
      material=true,
    )
    if !valid_client_request_cid(
        client_effect_target_original_text(object, "compiledPlanCid"),
      ) {
      raise InvalidUpdateTargetOriginal
    }
    let (_, bytes) = client_effect_target_original_installations(
      @decode.required(object, "installations").unwrap_or_else(() => {
        raise InvalidUpdateTargetOriginal
      }),
    )
    256 + client_effect_target_original_string_bytes(prepared) + bytes <=
    CLIENT_EFFECT_TARGET_ORIGINAL_ENVELOPE_MAX_BYTES
  } catch {
    _ => false
  }
}

///|
pub fn client_effect_target_run_original_shape(
  wire : String,
  prepared_evidence : String?,
  authorization_evidence : String?,
) -> Bool {
  try {
    let object = @decode.closed_object(
      client_effect_target_original_cursor(wire, envelope=true),
      ["materialsWire", "installations"],
    ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
    let materials = client_effect_target_original_text(
      object,
      "materialsWire",
      material=true,
    )
    let (_, bytes) = client_effect_target_original_installations(
      @decode.required(object, "installations").unwrap_or_else(() => {
        raise InvalidUpdateTargetOriginal
      }),
    )
    if 256 + client_effect_target_original_string_bytes(materials) + bytes >
      CLIENT_EFFECT_TARGET_ORIGINAL_ENVELOPE_MAX_BYTES {
      raise InvalidUpdateTargetOriginal
    }
    let body = @decode.open_object(
      client_effect_target_original_cursor(materials, envelope=true),
    ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
    if client_effect_target_original_text(body, "version") !=
      "actql-remote-run-materials/0.1" {
      raise InvalidUpdateTargetOriginal
    }
    client_effect_target_original_text(body, "effect_target_selections_json")
    |> ignore
    if prepared_evidence is Some(value) &&
      client_effect_target_original_text(body, "prepared_invocation") != value {
      raise InvalidUpdateTargetOriginal
    }
    if authorization_evidence is Some(value) &&
      client_effect_target_original_text(body, "run_authorization") != value {
      raise InvalidUpdateTargetOriginal
    }
    true
  } catch {
    _ => false
  }
}

///|
/// Equality of bounded saved DATA, not a same-process opaque equality claim.
pub fn client_effect_target_original_data_equal(
  left : String,
  right : String,
) -> Bool {
  try
    client_effect_target_original_canonical(left) ==
    client_effect_target_original_canonical(right)
  catch {
    _ => false
  }
}

///|
/// Compatibility projection for the existing saved DATA reader. It does not
/// issue an original selection: only the prepared Owner above can do that.
pub fn client_effect_target_selection_data_cid(
  wire : String,
) -> Result[String, ClientEffectUpdateTargetIssue] {
  try {
    let values = @decode.elements(client_effect_target_original_cursor(wire)).unwrap_or_else(() => {
        raise InvalidUpdateTargetOriginal
      },
    )
    if values.is_empty() || values.length() > 1024 {
      raise InvalidUpdateTargetOriginal
    }
    let mut bytes = 2
    for value in values {
      let object = @decode.closed_object(value, [
        "stage_index", "effect_id", "target_ref", "mapping_ref", "mapping_cid", "check_environment_cid",
        "installation_binding_cid", "installation_owner_cid",
      ]).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
      let stage = @decode.safe_integer(
        @decode.required(object, "stage_index").unwrap_or_else(() => {
          raise InvalidUpdateTargetOriginal
        }),
      ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
      if stage < 0L {
        raise InvalidUpdateTargetOriginal
      }
      bytes += 256
      for
        key in [
          "effect_id", "target_ref", "mapping_ref", "mapping_cid", "check_environment_cid",
          "installation_binding_cid", "installation_owner_cid",
        ] {
        bytes += client_effect_target_original_string_bytes(
          client_effect_target_original_text(object, key),
        )
      }
      if bytes > CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES {
        raise InvalidUpdateTargetOriginal
      }
    }
    let canonical = client_effect_target_original_canonical(wire)
    Ok("sha256:" + @sha.hex(@utf8.encode(canonical)))
  } catch {
    _ => Err(InvalidMaterials)
  }
}

///|
pub fn client_effect_target_run_selection_cid(
  wire : String,
) -> Result[Array[String], ClientEffectUpdateTargetIssue] {
  try {
    let object = @decode.open_object(client_effect_target_original_cursor(wire)).unwrap_or_else(() => {
        raise InvalidUpdateTargetOriginal
      },
    )
    match @decode.lookup(object, "effect_target_selections_cid") {
      None => Ok([])
      Some(value) => {
        let cid = @decode.text(value).unwrap_or_else(() => {
          raise InvalidUpdateTargetOriginal
        })
        if !valid_client_request_cid(cid) {
          raise InvalidUpdateTargetOriginal
        }
        Ok([cid])
      }
    }
  } catch {
    _ => Err(InvalidMaterials)
  }
}

///|
/// The Host reports only current physical installation/mapping facts. The
/// existing prepared selection decides whether those facts match its original
/// environment, occurrence, Mapping and installation generation. No authority,
/// Preview, physical stop or saved-custody observation is issued here.
fn client_effect_target_selection_purpose(
  prepared : PreparedClientEffectComputation,
  selection : ClientEffectUpdateTargetSelection,
) -> String raise ClientEffectTargetOriginalStop {
  let stage = selection.stage_index
  let effect_id = selection.effect_id
  let effects = @stage_results.effect_static_candidate_results(
    @checked.effect_program_static_effects(prepared.candidate),
  )
  let count = @stage_results.effect_result_binding_count(effects)
  if count > 1024 {
    raise InvalidUpdateTargetOriginal
  }
  let mut purpose : String? = None
  for index in 0..<count {
    let header = @stage_results.effect_result_binding_header(
      @stage_results.effect_result_binding_at(effects, index).unwrap(),
    )
    if @syntax.effect_header_stage(header) == stage &&
      @syntax.effect_header_id(header) == effect_id {
      if purpose is Some(_) {
        raise InvalidUpdateTargetOriginal
      }
      let kind = @syntax.effect_header_kind(header)
      purpose = if kind == "update" || kind == "delete" {
        Some(kind)
      } else if kind == "command" &&
        @syntax.effect_header_published_store_target(header) is Some(_) {
        Some("store")
      } else {
        raise InvalidUpdateTargetOriginal
      }
    }
  }
  purpose.unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
}

///|
pub fn client_effect_target_selection_current(
  original : ClientEffectUpdateTargetSelections,
  prepared : PreparedClientEffectComputation,
  observations : String,
) -> Bool {
  client_effect_target_selection_current_owned(
    original,
    prepared,
    observations,
    None,
  )
}

///|
pub fn client_effect_target_selection_current_data(
  original : ClientEffectUpdateTargetSelections,
  prepared : PreparedClientEffectComputation,
  installations : Array[ClientEffectTargetInstallationData],
  observations : String,
) -> Bool {
  client_effect_target_selection_current_owned(
    original,
    prepared,
    observations,
    Some(installations),
  )
}

///|
fn client_effect_target_selection_current_owned(
  original : ClientEffectUpdateTargetSelections,
  prepared : PreparedClientEffectComputation,
  observations : String,
  installations : Array[ClientEffectTargetInstallationData]?,
) -> Bool {
  if !client_effect_target_selection_matches_prepared(original, prepared) {
    return false
  }
  try {
    let current = @decode.elements(
      client_effect_target_original_cursor(observations),
    ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
    if current.is_empty() || current.length() > 1024 {
      raise InvalidUpdateTargetOriginal
    }
    if installations is Some(data) {
      if data.length() != current.length() {
        raise InvalidUpdateTargetOriginal
      }
      let mut virtual_bytes = @utf8.encode(observations).length().to_int64()
      for installation in data {
        if !physical_equal(
            installation.origin,
            client_effect_target_installation_data_origin,
          ) {
          raise InvalidUpdateTargetOriginal
        }
        virtual_bytes += installation.observation_extra_bytes.to_int64()
      }
      if virtual_bytes > CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES.to_int64() {
        raise InvalidUpdateTargetOriginal
      }
    }
    for selection in original.entries {
      let purpose = client_effect_target_selection_purpose(prepared, selection)
      let owner_cid = selection.installation_owner_cid
      let binding_cid = selection.installation_binding_cid
      let target = selection.target_ref
      let mapping_ref = selection.mapping_ref
      let mapping_cid = selection.mapping_cid
      let mut matches = 0
      for index, observation in current {
        let object = @decode.closed_object(
          observation,
          if installations is Some(_) {
            ["update", "delete", "store", "mappings"]
          } else {
            ["installation", "update", "delete", "store", "mappings"]
          },
        ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
        let installation = match installations {
          Some(data) => data[index]
          None => {
            let value = @decode.required(object, "installation").unwrap_or_else(() => {
                raise InvalidUpdateTargetOriginal
              },
            )
            let body = @decode.closed_object(value, ["cid", "wire"]).unwrap_or_else(() => {
                raise InvalidUpdateTargetOriginal
              },
            )
            if client_effect_target_original_text(body, "cid") != owner_cid {
              continue
            }
            let wire = client_effect_target_original_text(body, "wire")
            let data = admit_client_effect_target_installation_data(wire).unwrap_or_else(() => {
                raise InvalidUpdateTargetOriginal
              },
            )
            if data.cid != owner_cid || data.wire != wire {
              raise InvalidUpdateTargetOriginal
            }
            data
          }
        }
        if installation.cid != owner_cid {
          continue
        }
        if installation.binding_cid != binding_cid ||
          @decode.boolean(
            @decode.required(object, purpose).unwrap_or_else(() => {
              raise InvalidUpdateTargetOriginal
            }),
          ) !=
          Ok(true) {
          raise InvalidUpdateTargetOriginal
        }
        let mappings = @decode.elements(
          @decode.required(object, "mappings").unwrap_or_else(() => {
            raise InvalidUpdateTargetOriginal
          }),
        ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
        let mut found = false
        for mapping in mappings {
          let mapping = @decode.closed_object(mapping, [
            "target", "mappingRef", "mappingCid", "update", "delete", "store",
          ]).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
          if client_effect_target_original_text(mapping, "target") == target &&
            client_effect_target_original_text(mapping, "mappingRef") ==
            mapping_ref &&
            client_effect_target_original_text(mapping, "mappingCid") ==
            mapping_cid &&
            @decode.boolean(
              @decode.required(mapping, purpose).unwrap_or_else(() => {
                raise InvalidUpdateTargetOriginal
              }),
            ) ==
            Ok(true) {
            found = true
          }
        }
        if found {
          matches += 1
        }
      }
      if matches != 1 {
        raise InvalidUpdateTargetOriginal
      }
    }
    true
  } catch {
    _ => false
  }
}

///|
/// Check the selection facet only. Full original Program/compilation/Run
/// admission is still required: equal eight-field bytes cannot prove purpose.
pub fn client_effect_target_selection_matches_run(
  original : ClientEffectUpdateTargetSelections,
  prepared : PreparedClientEffectComputation,
  definition : @publication.PublicationContract,
) -> Bool {
  if !client_effect_target_selection_matches_prepared(original, prepared) {
    return false
  }
  @publication.publication_contract_name(definition) == "run_definition" &&
  @publication.publication_contract_effect_target_selections_cid(definition) ==
  Some(client_effect_target_selection_cid(original))
}

///|
/// Compare retained physical entry_facts facts with the original checked
/// occurrences. This projection does not issue a new selection.
pub fn client_effect_target_selection_members_current(
  original : ClientEffectUpdateTargetSelections,
  prepared : PreparedClientEffectComputation,
  members : String,
) -> Bool {
  if !client_effect_target_selection_matches_prepared(original, prepared) {
    return false
  }
  try {
    let selected = @decode.elements(
      client_effect_target_original_cursor(original.wire),
    ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
    let members = @decode.elements(
      client_effect_target_original_cursor(members),
    ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
    if selected.length() != members.length() {
      raise InvalidUpdateTargetOriginal
    }
    for entry in selected {
      let entry = @decode.open_object(entry).unwrap_or_else(() => {
        raise InvalidUpdateTargetOriginal
      })
      let stage = @decode.safe_integer(
        @decode.required(entry, "stage_index").unwrap_or_else(() => {
          raise InvalidUpdateTargetOriginal
        }),
      ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
      let mut matches = 0
      for entry_facts in members {
        let entry_facts = @decode.closed_object(entry_facts, [
          "stage_index", "effect_id", "target_ref", "mapping_ref", "mapping_cid",
        ]).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
        if @decode.safe_integer(
            @decode.required(entry_facts, "stage_index").unwrap_or_else(() => {
              raise InvalidUpdateTargetOriginal
            }),
          ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal) ==
          stage &&
          client_effect_target_original_text(entry_facts, "effect_id") ==
          client_effect_target_original_text(entry, "effect_id") &&
          client_effect_target_original_text(entry_facts, "target_ref") ==
          client_effect_target_original_text(entry, "target_ref") &&
          client_effect_target_original_text(entry_facts, "mapping_ref") ==
          client_effect_target_original_text(entry, "mapping_ref") &&
          client_effect_target_original_text(entry_facts, "mapping_cid") ==
          client_effect_target_original_text(entry, "mapping_cid") {
          matches += 1
        }
      }
      if matches != 1 {
        raise InvalidUpdateTargetOriginal
      }
    }
    true
  } catch {
    _ => false
  }
}

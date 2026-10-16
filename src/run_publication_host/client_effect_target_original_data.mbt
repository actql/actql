///|
// Bounded DATA conversion for the existing selection Owner. These constants
// describe its original journal envelope, not a new allowance or wire domain.
const CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES : Int = 65536

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
) -> @decode.Cursor raise ClientEffectTargetOriginalStop {
  let source = @source.parse_json_bytes(
    @utf8.encode(wire),
    {
      max_input_bytes: CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
      max_nodes: CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
      max_depth: CLIENT_EFFECT_TARGET_ORIGINAL_MAX_DEPTH,
    },
    source_path="Original UPDATE custody",
  ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
  @decode.admit(source, {
    max_nodes: CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
    max_depth: CLIENT_EFFECT_TARGET_ORIGINAL_MAX_DEPTH,
    max_string_bytes: CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
    max_total_string_bytes: CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
  }).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
}

///|
fn client_effect_target_original_text(
  object : @decode.ObjectView,
  key : String,
) -> String raise ClientEffectTargetOriginalStop {
  let value = @decode.required(object, key).unwrap_or_else(() => {
    raise InvalidUpdateTargetOriginal
  })
  let text = @decode.text(value).unwrap_or_else(() => {
    raise InvalidUpdateTargetOriginal
  })
  if text.is_empty() ||
    @utf8.encode(text).length() > CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES {
    raise InvalidUpdateTargetOriginal
  }
  text
}

///|
fn client_effect_target_original_canonical(
  wire : String,
) -> String raise ClientEffectTargetOriginalStop {
  let source = @source.parse_json_bytes(@utf8.encode(wire), {
    max_input_bytes: CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
    max_nodes: CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
    max_depth: CLIENT_EFFECT_TARGET_ORIGINAL_MAX_DEPTH,
  }).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
  let value = @canonical.from_source(
    source,
    CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
    CLIENT_EFFECT_TARGET_ORIGINAL_MAX_DEPTH,
    CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
    data_keys=true,
  ) catch {
    _ => raise InvalidUpdateTargetOriginal
  }
  @canonical.stringify_value(
    value,
    CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
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
    let writer = @encode.writer(CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES, 1, 1)
    @encode.string_value(writer, value)
    @encode.finish(writer)
  } catch {
    _ => raise InvalidUpdateTargetOriginal
  }
  @utf8.encode(wire).length()
}

///|
/// Preserve the installed row Owner's existing NFC structural identity.
/// Only already selected physical configuration is supplied by the Host.
pub fn issue_client_effect_target_installation(
  facts : String,
) -> Result[(String, String), ClientEffectUpdateTargetIssue] {
  try {
    let object = @decode.closed_object(
      client_effect_target_original_cursor(facts),
      [
        "binding_cid", "connection", "connector_registration", "connector_revision",
        "continuation_binding", "profile", "runtime_bundle_cid",
      ],
    ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
    let text = fn(key : String) -> String raise ClientEffectTargetOriginalStop {
      @canonical_value.normalize_nfc(
        client_effect_target_original_text(object, key),
      ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
    }
    let profile = @decode.closed_object(
      @decode.required(object, "profile").unwrap_or_else(() => {
        raise InvalidUpdateTargetOriginal
      }),
      [
        "continuation", "continuationBinding", "dispatch", "recovery", "source",
        "targetCheck", "unit",
      ],
    ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
    let wire = try {
      let writer = @encode.writer(
        CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
        32,
        3,
      )
      @encode.begin_object(writer)
      for
        key in [
          "binding_cid", "connection", "connector_registration", "connector_revision",
          "continuation_binding",
        ] {
        @encode.key(writer, key)
        @encode.string_value(writer, text(key))
      }
      @encode.key(writer, "profile")
      @encode.begin_object(writer)
      for
        key in [
          "continuation", "continuationBinding", "dispatch", "recovery", "source",
          "targetCheck", "unit",
        ] {
        @encode.key(writer, key)
        @encode.string_value(
          writer,
          @canonical_value.normalize_nfc(
            client_effect_target_original_text(profile, key),
          ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal),
        )
      }
      @encode.end_object(writer)
      @encode.key(writer, "runtime_bundle_cid")
      @encode.string_value(writer, text("runtime_bundle_cid"))
      @encode.end_object(writer)
      @encode.finish(writer)
    } catch {
      _ => raise InvalidUpdateTargetOriginal
    }
    Ok(("sha256:" + @sha.hex(@utf8.encode(wire)), wire))
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
pub fn client_effect_target_prepared_original_shape(wire : String) -> Bool {
  try {
    let object = @decode.closed_object(
      client_effect_target_original_cursor(wire),
      ["preparedWire", "compiledPlanCid", "installations"],
    ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
    let prepared = client_effect_target_original_text(object, "preparedWire")
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
    CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES
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
      client_effect_target_original_cursor(wire),
      ["materialsWire", "installations"],
    ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
    let materials = client_effect_target_original_text(object, "materialsWire")
    let (_, bytes) = client_effect_target_original_installations(
      @decode.required(object, "installations").unwrap_or_else(() => {
        raise InvalidUpdateTargetOriginal
      }),
    )
    if 256 + client_effect_target_original_string_bytes(materials) + bytes >
      CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES {
      raise InvalidUpdateTargetOriginal
    }
    let body = @decode.open_object(
      client_effect_target_original_cursor(materials),
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
pub fn client_effect_target_selection_current(
  original : ClientEffectUpdateTargetSelections,
  prepared : PreparedClientEffectComputation,
  observations : String,
) -> Bool {
  if !client_effect_target_selection_matches_prepared(original, prepared) {
    return false
  }
  try {
    let selected = @decode.elements(
      client_effect_target_original_cursor(original.wire),
    ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
    let current = @decode.elements(
      client_effect_target_original_cursor(observations),
    ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
    if current.is_empty() || current.length() > 1024 {
      raise InvalidUpdateTargetOriginal
    }
    for selection in selected {
      let selection = @decode.open_object(selection).unwrap_or_else(() => {
        raise InvalidUpdateTargetOriginal
      })
      let owner_cid = client_effect_target_original_text(
        selection, "installation_owner_cid",
      )
      let binding_cid = client_effect_target_original_text(
        selection, "installation_binding_cid",
      )
      let target = client_effect_target_original_text(selection, "target_ref")
      let mapping_ref = client_effect_target_original_text(
        selection, "mapping_ref",
      )
      let mapping_cid = client_effect_target_original_text(
        selection, "mapping_cid",
      )
      let mut matches = 0
      for observation in current {
        let object = @decode.closed_object(observation, [
          "installation", "update", "mappings",
        ]).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
        let installation = @decode.required(object, "installation").unwrap_or_else(() => {
            raise InvalidUpdateTargetOriginal
          },
        )
        let installation_object = @decode.closed_object(installation, [
          "cid", "wire",
        ]).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
        if client_effect_target_original_text(installation_object, "cid") !=
          owner_cid {
          continue
        }
        // Validate the claimed content against the SAME Owner's canonical body.
        let installation_wire = client_effect_target_original_text(
          installation_object, "wire",
        )
        let (cid, canonical) = issue_client_effect_target_installation(
          installation_wire,
        ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
        if cid != owner_cid || canonical != installation_wire {
          raise InvalidUpdateTargetOriginal
        }
        let body = @decode.open_object(
          client_effect_target_original_cursor(installation_wire),
        ).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
        if client_effect_target_original_text(body, "binding_cid") !=
          binding_cid ||
          @decode.boolean(
            @decode.required(object, "update").unwrap_or_else(() => {
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
            "target", "mappingRef", "mappingCid", "update",
          ]).unwrap_or_else(() => raise InvalidUpdateTargetOriginal)
          if client_effect_target_original_text(mapping, "target") == target &&
            client_effect_target_original_text(mapping, "mappingRef") ==
            mapping_ref &&
            client_effect_target_original_text(mapping, "mappingCid") ==
            mapping_cid &&
            @decode.boolean(
              @decode.required(mapping, "update").unwrap_or_else(() => {
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

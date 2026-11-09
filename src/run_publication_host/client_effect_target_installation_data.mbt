///|
/// One same-runtime, same-call validated installation DATA projection. It is
/// neither a currentness/permission verdict nor an installation registry.
pub struct ClientEffectTargetInstallationData {
  priv cid : String
  priv wire : String
  priv binding_cid : String
  priv observation_extra_bytes : Int
  priv origin : Ref[Int]
}

///|
let client_effect_target_installation_data_origin : Ref[Int] = Ref(0)

///|
// Canonical field order belongs only to this existing Core installation owner.
fn write_client_effect_target_installation_facts(
  writer : @encode.Writer,
  facts : Array[String],
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  for
    index, key in [
      "binding_cid", "connection", "connector_registration", "connector_revision",
      "continuation_binding",
    ] {
    @encode.key(writer, key)
    @encode.string_value(writer, facts[index])
  }
  @encode.key(writer, "profile")
  @encode.begin_object(writer)
  for
    index, key in [
      "continuation", "continuationBinding", "dispatch", "recovery", "source", "targetCheck",
      "unit",
    ] {
    @encode.key(writer, key)
    @encode.string_value(writer, facts[index + 5])
  }
  @encode.end_object(writer)
  @encode.key(writer, "runtime_bundle_cid")
  @encode.string_value(writer, facts[12])
  @encode.end_object(writer)
}

///|
fn prepare_client_effect_target_installation_data(
  facts : Array[String],
) -> Result[ClientEffectTargetInstallationData, ClientEffectUpdateTargetIssue] {
  if facts.length() != 13 {
    return Err(InvalidMaterials)
  }
  try {
    // Preserve the full raw DATA ceiling before normalization. Measurement
    // builds no JSON tree or serialized copy of the physical input.
    let raw = @encode.measuring_writer(
      CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES,
      32,
      3,
    )
    write_client_effect_target_installation_facts(raw, facts)
    @encode.finish_measurement(raw) |> ignore
    let normalized : Array[String] = []
    for value in facts {
      if value.is_empty() {
        raise InvalidUpdateTargetOriginal
      }
      normalized.push(
        @canonical_value.normalize_nfc(value).unwrap_or_else(() => {
          raise InvalidUpdateTargetOriginal
        }),
      )
    }
    let writer = @encode.writer(CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES, 32, 3)
    write_client_effect_target_installation_facts(writer, normalized)
    let wire = @encode.finish(writer)
    let cid = "sha256:" + @sha.hex(@utf8.encode(wire))
    // Compact current DATA omits this immutable body. Keep the EXACT previous
    // enclosing wire ceiling without serializing that body a second time.
    let original = @encode.measuring_writer(
      CLIENT_EFFECT_TARGET_ORIGINAL_ENVELOPE_MAX_BYTES,
      8,
      4,
    )
    @encode.begin_object(original)
    @encode.key(original, "installation")
    @encode.begin_object(original)
    @encode.key(original, "cid")
    @encode.string_value(original, cid)
    @encode.key(original, "wire")
    @encode.string_value(original, wire)
    @encode.end_object(original)
    @encode.end_object(original)
    let extra = @encode.finish_measurement(original) - 1
    Ok({
      cid,
      wire,
      binding_cid: normalized[0],
      observation_extra_bytes: extra,
      origin: client_effect_target_installation_data_origin,
    })
  } catch {
    _ => Err(InvalidMaterials)
  }
}

///|
/// Actual physical scalar inputs only. Identity normalization, field order,
/// all bounds and the canonical digest remain in the existing Core owner.
pub fn issue_client_effect_target_installation_data(
  facts : Array[String],
) -> Result[
  (String, String, ClientEffectTargetInstallationData),
  ClientEffectUpdateTargetIssue,
] {
  prepare_client_effect_target_installation_data(facts).map(data => {
    (data.cid, data.wire, data)
  })
}

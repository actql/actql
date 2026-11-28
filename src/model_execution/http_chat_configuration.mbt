///|
/// Bound a preserving JSON parse and indexed admission before either allocates.
/// The Host reserves its own representation against this inventory.
pub fn portable_model_http_configuration_construction_extent(
  bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  normalize_keys? : Bool = false,
) -> @relation.PreparationRepresentationUnits? {
  if bytes <= 0 || bytes > max_bytes || max_nodes < 1 || max_depth < 1 {
    return None
  }
  // Every JSON node consumes at least one byte from the same input.
  let nodes = Int::min(max_nodes, bytes)
  let depth = Int::min(max_depth, nodes)
  guard @decode.preserving_json_admission_construction_inventory(
      bytes, nodes, depth,
    )
    is Some(parse) &&
    @source.json_construction_extent(bytes, nodes, depth, normalize_keys~)
    is Some(source) &&
    @source.json_literal_construction_extent(bytes, nodes, depth)
    is Some(literal) else {
    return None
  }
  Some({
    record_headers: parse.record_headers +
    source.record_headers -
    literal.record_headers +
    24L,
    reference_slots: parse.reference_slots +
    source.reference_slots -
    literal.reference_slots +
    40L,
    scalar_words: parse.scalar_words +
    source.scalar_words -
    literal.scalar_words +
    24L,
    // Include the UTF-8 decode destination before it becomes a String.
    owned_utf16_units: parse.owned_utf16_units +
    source.owned_utf16_units -
    literal.owned_utf16_units +
    bytes.to_int64(),
    owned_wire_bytes: 0L,
  })
}

///|
fn read_portable_model_http_configuration_value(
  body : Bytes,
  limits : @environment.Limits,
) -> @decode.Cursor? {
  guard @source.parse_json_bytes_preserving(body, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    })
    is Ok(node) &&
    @decode.admit(node, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    })
    is Ok(value) else {
    return None
  }
  Some(value)
}

///|
/// Read nonsecret route data from a previously selected installation file.
/// The caller funds parsing and supplies the adopted file identities.
/// Provider binding, credential custody and dispatch remain separate.
pub fn read_portable_model_http_chat_file_route(
  body : Bytes,
  provider_id : String,
  revision_cid : String,
  contract_cid : String,
  profile_cid : String,
  credential_file : String,
  limits : @environment.Limits,
) -> ResolvedStructuredModel? {
  guard read_portable_model_http_configuration_value(body, limits)
    is Some(value) &&
    @decode.open_object(value) is Ok(object) else {
    return None
  }
  for
    (field, expected) in [
      ("installation_revision_cid", revision_cid),
      ("configuration_contract_cid", contract_cid),
      ("response_profile_cid", profile_cid),
      ("credential_ref", "file:" + credential_file),
      ("provider_id", provider_id),
      ("adapter_kind", "portable-http"),
      ("api_mode", "chat-completions"),
    ] {
    guard @decode.lookup(object, field) is Some(original) &&
      @decode.text(original) == Ok(expected) else {
      return None
    }
  }
  guard @decode.lookup(object, "selector").bind(value => {
      @decode.text(value).to_option()
    })
    is Some(selector) &&
    !selector.is_empty() &&
    @decode.lookup(object, "model_id").bind(value => {
      @decode.text(value).to_option()
    })
    is Some(model_id) &&
    !model_id.is_empty() &&
    @decode.lookup(object, "endpoint").bind(value => {
      @decode.text(value).to_option()
    })
    is Some(endpoint) &&
    endpoint.has_prefix("https://") else {
    return None
  }
  Some({
    selector,
    model_id,
    adapter_kind: "portable-http",
    api_mode: "chat-completions",
    endpoint,
  })
}

///|
/// Read the closed bundle used by the existing execution and dependency
/// readers. The embedded documents stay as original wire data.
pub fn read_portable_model_http_execution_wires(
  bytes : Bytes,
  limits : @environment.Limits,
) -> (String, String, String, String, String)? {
  guard read_portable_model_http_configuration_value(bytes, limits)
    is Some(value) &&
    @decode.closed_object(value, [
      "contract_cid", "contract", "prompt", "retry_policy", "backoff",
    ])
    is Ok(fields) &&
    @decode.lookup(fields, "contract_cid") is Some(cid) &&
    @decode.text(cid) is Ok(cid) &&
    @decode.lookup(fields, "contract") is Some(contract) &&
    @decode.text(contract) is Ok(contract) &&
    @decode.lookup(fields, "prompt") is Some(prompt) &&
    @decode.text(prompt) is Ok(prompt) &&
    @decode.lookup(fields, "retry_policy") is Some(retry) &&
    @decode.text(retry) is Ok(retry) &&
    @decode.lookup(fields, "backoff") is Some(backoff) &&
    @decode.text(backoff) is Ok(backoff) else {
    return None
  }
  Some((cid, contract, prompt, retry, backoff))
}

///|
// These readers keep source spans and an immutable index for each admitted
// body. The original Bytes stay borrowed. Add each returned index once and
// reuse the parser/hash peak across the four sequential reads.
fn portable_model_http_execution_construction(
  bodies : Array[String],
  bundle_bytes : Int,
  limits : @environment.Limits,
) -> (
  @relation.PreparationRepresentationUnits,
  @relation.PreparationRepresentationUnits,
)? {
  // The selected files, execution, three dependencies and their small policy
  // arrays/options stay live through the return of the composite contract.
  let mut retained : @relation.PreparationRepresentationUnits = {
    record_headers: 24L,
    reference_slots: 43L,
    scalar_words: 36L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let mut scratch = retained
  for body in bodies {
    guard @scalar.admit_utf8_length(body, limits.max_bytes) is Ok(bytes) else {
      return None
    }
    let nodes = Int::min(bytes, limits.max_nodes)
    let depth = Int::min(nodes, limits.max_depth)
    let fields = nodes - 1
    guard portable_model_http_configuration_construction_extent(
        bytes,
        limits.max_bytes,
        nodes,
        depth,
        normalize_keys=true,
      )
      is Some(parser) &&
      @environment.wire_hash_construction_extent(nodes) is Some(hashing) &&
      @source.json_index_borrowed_construction_extent(
        nodes,
        fields,
        bytes.to_int64(),
        keep_spans=true,
      )
      is Some(text) &&
      @decode.admission_construction_inventory(
        nodes, fields, nodes, nodes, depth,
      )
      is Some(decode) &&
      @relation.compose_preparation_representation([
        retained,
        {
          record_headers: decode.indexed.record_headers + text.record_headers,
          reference_slots: decode.indexed.reference_slots + text.reference_slots,
          scalar_words: decode.indexed.scalar_words + text.scalar_words,
          owned_utf16_units: text.owned_utf16_units,
          owned_wire_bytes: 0L,
        },
      ])
      is Some(next) else {
      return None
    }
    retained = next
    let fields = nodes.to_int64()
    guard @relation.compose_preparation_representation([
        parser,
        {
          record_headers: hashing.record_headers,
          reference_slots: hashing.reference_slots,
          scalar_words: hashing.scalar_words,
          owned_utf16_units: hashing.owned_utf16_units,
          owned_wire_bytes: hashing.owned_wire_bytes,
        },
        {
          record_headers: 32L + 12L * fields,
          reference_slots: 76L + 24L * fields,
          scalar_words: 56L + 18L * fields,
          owned_utf16_units: 3L * 71L,
          owned_wire_bytes: 512L,
        },
      ])
      is Some(working) else {
      return None
    }
    scratch = {
      record_headers: Int64::max(scratch.record_headers, working.record_headers),
      reference_slots: Int64::max(
        scratch.reference_slots,
        working.reference_slots,
      ),
      scalar_words: Int64::max(scratch.scalar_words, working.scalar_words),
      owned_utf16_units: Int64::max(
        scratch.owned_utf16_units,
        working.owned_utf16_units,
      ),
      owned_wire_bytes: Int64::max(
        scratch.owned_wire_bytes,
        working.owned_wire_bytes,
      ),
    }
  }
  // Bundle strings and the encoded byte inputs overlap each active parser.
  // Neither escapes the constructor. The original outer file remains borrowed.
  @relation.compose_preparation_representation([
    retained,
    scratch,
    {
      record_headers: 12L,
      reference_slots: 16L,
      scalar_words: 12L,
      owned_utf16_units: bundle_bytes.to_int64(),
      owned_wire_bytes: bundle_bytes.to_int64(),
    },
  ]).map(working => (retained, working))
}

///|
pub(all) enum PortableModelHttpExecutionIssue {
  Capacity
  InvalidBundle
  Execution(@publication_host.ClientInferPlanGraphIssue)
  Dependencies(@environment.ModelDependencyIssue)
}

///|
// Keep the copied wire strings only through conversion. The first reservation
// covers the outer parse, and the second covers the returned inner indexes.
fn prepare_portable_model_http_execution_wires(
  body : Bytes,
  limits : @environment.Limits,
  reserve : (
    @relation.PreparationRepresentationUnits,
    @relation.PreparationRepresentationUnits,
  ) -> Bool,
) -> Result[
  (String, String, String, String, String),
  PortableModelHttpExecutionIssue,
] {
  guard portable_model_http_configuration_construction_extent(
      body.length(),
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(outer) &&
    reserve(
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      outer,
    ) else {
    return Err(Capacity)
  }
  guard read_portable_model_http_execution_wires(body, limits) is Some(wires) else {
    return Err(InvalidBundle)
  }
  let (_, execution, prompt, retry, backoff) = wires
  guard portable_model_http_execution_construction(
      [execution, prompt, retry, backoff],
      body.length(),
      limits,
    )
    is Some((retained, working)) &&
    reserve(retained, working) else {
    return Err(Capacity)
  }
  Ok(wires)
}

///|
/// Read the installed execution materials against the original checked
/// occurrence. The current Host reserves each phase in its own Read or
/// Project owner. These materials carry no credential or dispatch permission.
pub fn read_portable_model_http_execution(
  occurrence : @publication_host.ClientInferOccurrence,
  body : Bytes,
  limits : @environment.ModelTaskLimits,
  reserve : (
    @relation.PreparationRepresentationUnits,
    @relation.PreparationRepresentationUnits,
  ) -> Bool,
) -> Result[
  (
    @environment.ModelExecutionContract,
    @environment.SingleAttemptModelDependencies,
  ),
  PortableModelHttpExecutionIssue,
] {
  prepare_portable_model_http_execution_wires(body, limits.bodies, reserve).bind(wires => {
      let (cid, execution, prompt, retry, backoff) = wires
      @publication_host.read_client_infer_occurrence_model_execution(
        occurrence,
        @utf8.encode(execution),
        cid,
        limits.bodies,
        limits.max_work,
      )
      .map_err(issue => PortableModelHttpExecutionIssue::Execution(issue))
      .bind(contract => {
        @environment.read_single_attempt_model_dependencies(
          contract,
          Some(@utf8.encode(prompt)),
          Some(@utf8.encode(retry)),
          Some(@utf8.encode(backoff)),
          limits.bodies,
          limits.max_work,
        )
        .map_err(issue => PortableModelHttpExecutionIssue::Dependencies(issue))
        .map(dependencies => (contract, dependencies))
      })
    },
  )
}

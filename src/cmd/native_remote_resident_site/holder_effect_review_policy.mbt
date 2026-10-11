///|
/// Independently installed Host inputs, not evidence disclosure or approval.
/// Loading this private projection opens no Provider, Store or credential use.
/// The production entry must still supply its separate current evidence gate.
priv struct HolderEffectReviewPolicyInstallation {
  configuration : @effect_review.NativeResidentEffectReviewConfiguration
  describe_limits : @effect_catalog.DescribeLimits
  declaration_limits : @effect_catalog.DeclarationLimits
  connector_id : String
  max_observation_bytes : Int
  publication : HolderEffectReviewPublication
  current : () -> Bool
}

///|
/// The configured key is local Store custody material, not a grant or Reviewer
/// identity. Refuse noncanonical or incomplete text instead of trimming values.
fn holder_effect_review_key(value : String) -> Bytes? {
  if value.length() != 64 {
    return None
  }
  let nibble = (value : UInt16) => {
    let number = value.to_int()
    if number >= 48 && number <= 57 {
      Some(number - 48)
    } else if number >= 97 && number <= 102 {
      Some(number - 97 + 10)
    } else {
      None
    }
  }
  let bytes : Array[Byte] = []
  for index in 0..<32 {
    guard nibble(value[index * 2]) is Some(high) &&
      nibble(value[index * 2 + 1]) is Some(low) else {
      return None
    }
    bytes.push((high * 16 + low).to_byte())
  }
  Some(Bytes::from_array(bytes))
}

///|
/// Fixed operator filenames, original contract admission and bounded settings.
/// The root must be chosen by the Host; no poll, Program or candidate report
/// supplies it. This function is not yet installed by the production CLI.
fn load_holder_effect_review_policy(
  root : String,
  matches : @argparse.Matches,
  resources : HolderOutputResources,
  export_limits : @host.PublicationOutputExportLimits,
) -> HolderEffectReviewPolicyInstallation raise CommandStop {
  let configured_file_limit = required_int64(matches, "max-file-bytes")
  guard configured_file_limit > 0L else {
    stop("Effect Review policy file limit refused")
  }
  let file_limit = if configured_file_limit < 65536L {
    configured_file_limit
  } else {
    65536L
  }
  let names = [
    "review-stage.txt", "review-effect-id.txt", "catalog-api-version.txt", "review-source-binding-cid.txt",
    "review-retention-cid.txt", "review-retention.json", "review-retention-contract-cid.txt",
    "review-retention-contract.json", "review-metadata-retention-cid.txt", "review-metadata-retention.json",
    "review-clock-cid.txt", "review-clock.json", "effect-connector-id.txt", "review-checkpoint-id.txt",
    "review-created-at.txt", "review-expires-at.txt", "review-store-key.hex", "review-max-bytes.txt",
    "review-max-nodes.txt", "review-max-depth.txt", "review-max-work.txt", "review-max-fields.txt",
    "review-max-rows.txt", "review-max-capture-workspace.txt", "review-max-utf16-units.txt",
    "review-dependency-max-entries.txt", "review-dependency-max-bytes.txt", "review-dependency-max-depth.txt",
    "review-dependency-max-references.txt",
  ]
  let snapshot = names.map(name => (name, load_text(root, name, file_limit)))
  if snapshot.any(entry => entry.1.is_empty()) {
    stop("Effect Review policy contains an empty field")
  }
  let read = (index : Int) => snapshot[index].1
  let integer = fn(
    index : Int,
    low : Int,
    high : Int,
  ) -> Int raise CommandStop {
    let value : Int = @string.from_str(read(index)) catch {
      _ => stop("Effect Review policy integer refused")
    }
    if value < low || value > high {
      stop("Effect Review policy budget refused")
    }
    value
  }
  let stage = integer(0, 0, 1000000)
  let max_bytes = integer(17, 1, file_limit.to_int())
  let max_nodes = integer(18, 1, 4096)
  let max_depth = integer(19, 1, 32)
  let max_work = integer(20, 1, 1000000)
  let max_fields = integer(21, 1, export_limits.max_result_fields)
  let max_rows = integer(22, 1, export_limits.max_rows)
  let max_capture_workspace_entries = integer(23, 1, 1000000)
  let max_utf16_units = integer(24, 1, 1000000)
  let retained_bytes = required_int64(matches, "budget-retained-bytes")
  // The loader cannot extend the Host's existing retained-capacity ceiling.
  if retained_bytes < 1L || retained_bytes > 536870912L {
    stop("Effect Review retained budget refused")
  }
  let dependency_limits : @publication.CapturedEffectDependencyLimits = {
    max_entries: integer(25, 1, 4096),
    max_total_bytes: integer(26, 1, retained_bytes.to_int()),
    max_depth: integer(27, 1, 64),
    max_references: integer(28, 1, 65536),
  }
  let retention = match
    @publication.admit_publication_contract(
      "result_retention_policy",
      read(5),
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(_) => stop("Effect Review retention admission refused")
  }
  if @publication.publication_contract_identity(retention) != read(4) ||
    !@publication.result_retention_intervals_valid(retention) {
    stop("Effect Review original retention refused")
  }
  let dependencies : Array[@publication.CapturedEffectDependencyBody] = []
  for
    (kind, cid_index, body_index) in [
      ("retention_contract", 6, 7),
      ("metadata_retention_policy", 8, 9),
      ("clock_contract", 10, 11),
    ] {
    let dependency = match
      @publication.admit_hashed_effect_dependency_body(
        kind,
        read(cid_index),
        read(body_index),
        max_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(_) => stop("Effect Review retention dependency refused")
    }
    dependencies.push(dependency)
  }
  // Exact original retention references and the full input evidence closure
  // are checked by the existing capture/Review Owners, not reparsed here.
  let key = match holder_effect_review_key(read(16)) {
    Some(value) => value
    None => stop("Effect Review local custody key refused")
  }
  let crypto = match
    @signature.load_library(required(matches, "crypto-library")) {
    Ok(value) => value
    Err(_) => stop("Effect Review signature library unavailable")
  }
  let current = () => {
    snapshot.all(entry => {
      match @bounded_files.read_bounded_text_file(root, entry.0, file_limit) {
        Ok(value) => value == entry.1
        Err(_) => false
      }
    })
  }
  if !current() {
    stop("Effect Review policy changed during admission")
  }
  let configuration : @effect_review.NativeResidentEffectReviewConfiguration = {
    stage,
    effect_id: read(1),
    api_version: read(2),
    // These independent Host values are compared with the original consumer
    // binding/current execution by the existing holder and Review Owners.
    runtime_bundle_cid: required(matches, "runtime-bundle-cid"),
    source_binding_cid: read(3),
    store_authority_cid: resources.store_authority,
    retention,
    retention_dependencies: dependencies,
    dependency_limits,
    preview_limits: {
      max_work,
      max_wire_bytes: max_bytes,
      max_nodes,
      max_depth,
      plan: { max_work, max_fields, max_bytes, max_nodes, max_depth, },
    },
    export_limits,
    dispatch_limits: { max_bytes, max_nodes, max_depth, },
    body_limits: { max_bytes, max_nodes, max_depth, },
    request_limits: {
      max_path_bytes: max_bytes,
      max_target_bytes: max_bytes,
      max_body_bytes: max_bytes,
    },
    observation_limits: {
      max_bytes,
      max_nodes,
      max_depth,
      max_identity_bytes: max_bytes,
    },
    max_rows,
    max_fields,
    max_capture_workspace_entries,
    max_work,
    max_utf16_units,
  }
  {
    configuration,
    describe_limits: {
      max_bytes,
      max_nodes,
      max_depth,
      max_fields,
      max_name_units: max_utf16_units,
    },
    declaration_limits: { max_bytes, max_nodes, max_depth, },
    connector_id: read(12),
    max_observation_bytes: max_bytes,
    publication: {
      crypto,
      key,
      checkpoint_id: read(13),
      created_at: read(14),
      expires_at: read(15),
      limits: { max_wire_bytes: max_bytes, max_nodes, max_depth, },
      current,
      // This finite adapter accepts create only. Any accidental update path
      // receives a refusal; no observe grant or fake target is manufactured.
      access: (_, _) => Err(@effect_review.ForeignScope),
    },
    current,
  }
}

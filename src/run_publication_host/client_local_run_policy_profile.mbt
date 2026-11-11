///|
/// An explicitly selected finite profile, not adoption, current permission,
/// a grant or an issued Run policy. Legacy absolute originals are unchanged.
struct ClientLocalRunPolicyProfile {
  wire : String
  result_policy_cid : String
  retention_contract_cid : String
  metadata_retention_policy_cid : String
  clock_contract_cid : String
} derive(Eq, Debug)

///|
pub(all) enum ClientLocalRunPolicyProfileIssue {
  InvalidOriginal
  ForeignProfile
  InvalidObservationTime
  Encoding
} derive(Eq, Debug)

///|
fn run_profile_value(wire : String) -> @canonical.CanonicalValue? {
  @source.parse_json_bytes_preserving(@utf8.encode(wire), {
    max_input_bytes: 8192,
    max_nodes: 512,
    max_depth: 8,
  })
  .to_option()
  .bind(value => {
    Some(@canonical.from_source(value, 512, 8, 8192)) catch {
      _ => None
    }
  })
}

///|
fn run_profile_text(
  value : @canonical.CanonicalValue,
  name : String,
) -> String? {
  match @canonical.object_field(value, name) {
    Some(@canonical.String(text)) => Some(text)
    _ => None
  }
}

///|
fn run_profile_wire(
  policy : String,
  retention : String,
  metadata : String,
  clock : String,
) -> Result[String, ClientLocalRunPolicyProfileIssue] {
  product_wire(
    product_object([
      ("version", Json::string("actql-local-run-policy-profile/0.1")),
      ("available_for_ms", Json::number(86400000.0)),
      ("delete_after_ms", Json::number(172800000.0)),
      ("metadata_after_ms", Json::number(604800000.0)),
      ("read_for_ms", Json::number(86400000.0)),
      ("effective_data_policy_cid", Json::string(policy)),
      ("retention_contract_cid", Json::string(retention)),
      ("metadata_retention_policy_cid", Json::string(metadata)),
      ("clock_contract_cid", Json::string(clock)),
    ]),
  ).map_err(_ => Encoding)
}

///|
/// Select the existing dependency originals without interpreting the old
/// absolute deadlines as rolling. The caller must persist this distinct
/// original at explicit adoption or an authorized immutable upgrade append.
pub fn client_local_run_policy_profile(
  originals : ClientLocalProductCommonOriginals,
) -> Result[ClientLocalRunPolicyProfile, ClientLocalRunPolicyProfileIssue] {
  let decode_bytes = bytes => @utf8.decode(bytes) catch { _ => "" }
  let policy_wire = decode_bytes(originals.result_policy)
  let policy = product_cid(policy_wire)
  if admit_source_free_result_policy_body(policy, policy_wire, 8192, 512, 8)
    is Err(_) {
    return Err(InvalidOriginal)
  }
  let retention_wire = decode_bytes(originals.retention_policy)
  guard @publication.admit_publication_contract(
      "result_retention_policy", retention_wire, 8192, 512, 8,
    )
    is Ok(original_retention) &&
    @publication.result_retention_intervals_valid(original_retention) &&
    run_profile_value(retention_wire) is Some(body) &&
    run_profile_text(body, "effective_data_policy_cid") == Some(policy) &&
    run_profile_text(body, "retention_contract_cid") is Some(retention) &&
    run_profile_text(body, "metadata_retention_policy_cid") is Some(metadata) &&
    run_profile_text(body, "clock_contract_cid") is Some(clock) else {
    return Err(InvalidOriginal)
  }
  let profile = run_profile_wire(policy, retention, metadata, clock).map(wire => {
    wire,
    result_policy_cid: policy,
    retention_contract_cid: retention,
    metadata_retention_policy_cid: metadata,
    clock_contract_cid: clock,
  })
  profile.bind(value => {
    client_local_run_policy_retention_bodies(
      value,
      originals.retention_dependencies,
    ).map(_ => value)
  })
}

///|
/// Project the three original dependency bodies selected by this admitted
/// profile. This is the same admission used at profile construction, not a
/// renewed Policy, replacement retention or physical holding.
pub fn client_local_run_policy_retention_bodies(
  profile : ClientLocalRunPolicyProfile,
  original : Bytes,
) -> Result[
  Array[@publication.CapturedEffectDependencyBody],
  ClientLocalRunPolicyProfileIssue,
] {
  let wire = @utf8.decode(original) catch { _ => return Err(InvalidOriginal) }
  guard run_profile_value(wire) is Some(@canonical.Array(dependencies)) &&
    @canonical.array_count(dependencies) == 3 else {
    return Err(InvalidOriginal)
  }
  let bodies : Array[@publication.CapturedEffectDependencyBody] = []
  for
    (kind, expected) in [
      ("retention_contract", profile.retention_contract_cid),
      ("metadata_retention_policy", profile.metadata_retention_policy_cid),
      ("clock_contract", profile.clock_contract_cid),
    ] {
    let mut found = 0
    for index in 0..<3 {
      let dependency = @canonical.array_at(dependencies, index).unwrap()
      if run_profile_text(dependency, "kind") == Some(kind) {
        guard run_profile_text(dependency, "cid") == Some(expected) &&
          run_profile_text(dependency, "wire") is Some(body_wire) &&
          @publication.admit_captured_effect_dependency_body(
            kind,
            Some(expected),
            body_wire,
            8192,
            512,
            8,
          )
          is Ok(body) else {
          return Err(InvalidOriginal)
        }
        bodies.push(body)
        found = found + 1
      }
    }
    if found != 1 {
      return Err(InvalidOriginal)
    }
  }
  Ok(bodies)
}

///|
/// Closed, exact-byte admission against the retained real dependency bodies.
/// Admitting copied metadata never creates original custody or permission.
pub fn admit_client_local_run_policy_profile(
  wire : String,
  originals : ClientLocalProductCommonOriginals,
) -> Result[ClientLocalRunPolicyProfile, ClientLocalRunPolicyProfileIssue] {
  client_local_run_policy_profile(originals).bind(profile => {
    if wire == profile.wire {
      Ok(profile)
    } else {
      Err(ForeignProfile)
    }
  })
}

///|
pub fn client_local_run_policy_profile_wire(
  profile : ClientLocalRunPolicyProfile,
) -> String {
  profile.wire
}

///|
pub fn client_local_run_policy_profile_cid(
  profile : ClientLocalRunPolicyProfile,
) -> String {
  product_cid(profile.wire)
}

///|
/// Pure construction of a regular finite retention Policy. The existing
/// authorized acceptance transaction must bind these exact bytes and this
/// first observation to the new Submission before they may be used. Restore,
/// lookup, read and response-loss recovery must reuse that saved original;
/// invoking this constructor again is not renewal or retry permission.
pub fn issue_client_local_run_retention_policy(
  profile : ClientLocalRunPolicyProfile,
  observed_at : String,
) -> Result[@publication.PublicationContract, ClientLocalRunPolicyProfileIssue] {
  guard @values.timestamp_epoch_milliseconds(observed_at) is Some(now) &&
    @values.epoch_milliseconds_timestamp(now + 86400000L) is Some(available) &&
    @values.epoch_milliseconds_timestamp(now + 172800000L) is Some(deletion) &&
    @values.epoch_milliseconds_timestamp(now + 604800000L) is Some(metadata) else {
    return Err(InvalidObservationTime)
  }
  let wire = match
    product_wire(
      product_object([
        ("version", Json::string("actql-result-retention-policy/0.1")),
        ("retention_contract_cid", Json::string(profile.retention_contract_cid)),
        ("effective_data_policy_cid", Json::string(profile.result_policy_cid)),
        ("available_until", Json::string(available)),
        ("delete_by", Json::string(deletion)),
        ("extension_ceiling_at", Json::string(deletion)),
        (
          "metadata_retention_policy_cid",
          Json::string(profile.metadata_retention_policy_cid),
        ),
        ("metadata_delete_by", Json::string(metadata)),
        ("clock_contract_cid", Json::string(profile.clock_contract_cid)),
      ]),
    ) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  @publication.seal_publication_contract(
    "result_retention_policy", wire, 8192, 512, 8,
  ).map_err(_ => Encoding)
}

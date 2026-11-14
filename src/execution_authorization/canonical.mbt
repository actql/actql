///|
/// Canonical spelling and identity of `actql-execution-account-config/0.1`
/// (Run protocol, Execution-account configuration): entries ascend by
/// `entry_id`, each `any_of` ascends, each `exclusions` array ascends by the
/// canonical JSON text of its tuples, all under UTF-16 code-unit order of
/// NFC-normalized strings. The identity is the CID of the complete canonical
/// document.

///|
/// Existing bounds for the two fixed bootstrap profile documents only.
/// Selected Account/exclusion documents use geometry observed while validating
/// their SAME originals; the structural depth bound remains unchanged.
const CANONICAL_MAX_BYTES : Int = 4194304

///|
const CANONICAL_MAX_NODES : Int = 1048576

///|
const CANONICAL_MAX_DEPTH : Int = 16

///|
/// Identity-bearing text must already be in the form canonical JSON emits, so
/// the admitted document is exactly the document whose CID is its identity.
fn normalized_text(value : String) -> Bool {
  match @canonical.normalize_nfc_lf(value) {
    Ok(normalized) => normalized == value
    Err(_) => false
  }
}

///|
fn outcome_token(outcome : ConfiguredOutcome) -> String {
  match outcome {
    Allow => "allow"
    Deny => "deny"
    Delegate => "delegate"
  }
}

///|
/// Canonical selector: `{"all":true}` or `{"any_of":[...]}` with values in
/// ascending UTF-16 code-unit order.
fn selector_json(selector : Selector) -> Json {
  match selector {
    All => Json::object({ "all": Json::boolean(true) })
    AnyOf(values) =>
      Json::object({
        "any_of": Json::array(
          sort_names(values).map(value => Json::string(value)),
        ),
      })
  }
}

///|
fn box_fields(box : SelectorBox) -> Map[String, Json] {
  {
    "principal": selector_json(box.principal),
    "connection": selector_json(box.connection),
    "resource": selector_json(box.resource),
    "operation": selector_json(box.operation),
  }
}

///|
fn canonical_value_of(
  json : Json,
  bounds? : AccountCanonicalBounds? = None,
) -> @canonical_json.CanonicalValue? {
  let limits = bounds.unwrap_or(account_profile_literal_bounds)
  Some(
    @canonical_json.from_json(
      json,
      limits.nodes,
      CANONICAL_MAX_DEPTH,
      limits.utf16_units,
    ),
  ) catch {
    _ => None
  }
}

///|
/// Canonical JSON text of one exclusion tuple, the key of the exclusion order.
fn box_canonical_text(
  box : SelectorBox,
  bounds? : AccountCanonicalBounds? = None,
) -> String? {
  let limits = bounds.unwrap_or(account_profile_literal_bounds)
  let value = match canonical_value_of(Json::object(box_fields(box)), bounds~) {
    Some(value) => value
    None => return None
  }
  Some(
    @canonical_json.stringify_value(
      value,
      limits.encoded_bytes,
      limits.nodes,
      CANONICAL_MAX_DEPTH,
    ),
  ) catch {
    _ => None
  }
}

///|
/// The complete canonical document of an admitted configuration.
fn canonical_document(
  account_id : String,
  bootstrap : BootstrapProfile?,
  entries : Array[CanonicalEntry],
) -> Json {
  let fields : Map[String, Json] = {
    "version": Json::string(ACCOUNT_CONFIG_VERSION),
    "account_id": Json::string(account_id),
    "entries": Json::array(
      entries.map(entry => {
        let body = box_fields(entry.scope)
        body["entry_id"] = Json::string(entry.entry_id)
        body["outcome"] = Json::string(outcome_token(entry.outcome))
        body["exclusions"] = Json::array(
          entry.exclusions.map(exclusion => Json::object(box_fields(exclusion))),
        )
        Json::object(body)
      }),
    ),
  }
  if bootstrap is Some(profile) {
    fields["bootstrap"] = Json::object({
      "profile_id": Json::string(profile.profile_id),
      "profile_version": Json::string(profile.profile_version),
      "profile_cid": Json::string(profile.profile_cid),
    })
  }
  Json::object(fields)
}

///|
/// One entry in canonical order: exclusions ascend by canonical text.
priv struct CanonicalEntry {
  entry_id : String
  outcome : ConfiguredOutcome
  scope : SelectorBox
  exclusions : Array[SelectorBox]
}

///|
fn document_cid(
  document : Json,
  bounds? : AccountCanonicalBounds? = None,
) -> String? {
  let limits = bounds.unwrap_or(account_profile_literal_bounds)
  let value = match canonical_value_of(document, bounds~) {
    Some(value) => value
    None => return None
  }
  Some(
    @canonical_json.cid_value(
      value,
      limits.encoded_bytes,
      limits.nodes,
      CANONICAL_MAX_DEPTH,
    ),
  ) catch {
    _ => None
  }
}

///|
fn selector_path(prefix : String, dimension : Dimension) -> String {
  prefix +
  "." +
  (match dimension {
    Principal => "principal"
    Connection => "connection"
    Resource => "resource"
    Operation => "operation"
  })
}

///|
fn box_selectors(box : SelectorBox) -> Array[(Dimension, Selector)] {
  [
    (Principal, box.principal),
    (Connection, box.connection),
    (Resource, box.resource),
    (Operation, box.operation),
  ]
}

///|
/// First identifier that is not already in canonical text form, with its
/// location in the given (not yet reordered) configuration.
fn first_unnormalized(
  raw : RawAccountConfiguration,
  geometry : AccountCanonicalGeometry,
) -> String? {
  geometry.observe_object(
    if raw.bootstrap is Some(_) {
      4
    } else {
      3
    },
    "versionaccount_identries".length() +
    (if raw.bootstrap is Some(_) { "bootstrap".length() } else { 0 }),
  )
  geometry.observe_text(ACCOUNT_CONFIG_VERSION)
  geometry.observe_array(raw.entries.length())
  if !normalized_text(raw.account_id) {
    return Some("$.account_id")
  }
  geometry.observe_text(raw.account_id)
  if raw.bootstrap is Some(profile) {
    if !normalized_text(profile.profile_id) {
      return Some("$.bootstrap.profile_id")
    }
    if !normalized_text(profile.profile_version) {
      return Some("$.bootstrap.profile_version")
    }
    geometry.observe_object(3, "profile_idprofile_versionprofile_cid".length())
    geometry.observe_text(profile.profile_id)
    geometry.observe_text(profile.profile_version)
    geometry.observe_text(profile.profile_cid)
  }
  for index, entry in raw.entries {
    geometry.observe_object(
      7,
      "principalconnectionresourceoperationentry_idoutcomeexclusions".length(),
    )
    geometry.observe_array(entry.exclusions.length())
    geometry.observe_text(outcome_token(entry.outcome))
    let prefix = "$.entries[\{index}]"
    if !normalized_text(entry.entry_id) {
      return Some(prefix + ".entry_id")
    }
    geometry.observe_text(entry.entry_id)
    let boxes = [(prefix, entry.scope)]
    for position, exclusion in entry.exclusions {
      geometry.observe_object(
        4,
        "principalconnectionresourceoperation".length(),
      )
      boxes.push((prefix + ".exclusions[\{position}]", exclusion))
    }
    for located in boxes {
      let (at, box) = located
      for item in box_selectors(box) {
        let (dimension, selector) = item
        if selector is All {
          geometry.observe_object(1, "all".length())
          geometry.observe_true()
        }
        if selector is AnyOf(values) {
          geometry.observe_object(1, "any_of".length())
          geometry.observe_array(values.length())
          for value_index, value in values {
            if !normalized_text(value) {
              return Some(
                selector_path(at, dimension) + ".any_of[\{value_index}]",
              )
            }
            geometry.observe_text(value)
          }
        }
      }
    }
  }
  None
}

///|
/// Strict canonical order check of a decoded wire document. Equal neighbours
/// are left to admission, which reports them as duplicates.
fn first_out_of_order(
  raw : RawAccountConfiguration,
  bounds : AccountCanonicalBounds,
) -> String? {
  for index in 1..<raw.entries.length() {
    if code_unit_compare(
        raw.entries[index - 1].entry_id,
        raw.entries[index].entry_id,
      ) >
      0 {
      return Some("$.entries[\{index}].entry_id")
    }
  }
  for index, entry in raw.entries {
    let prefix = "$.entries[\{index}]"
    let boxes = [(prefix, entry.scope)]
    for position, exclusion in entry.exclusions {
      boxes.push((prefix + ".exclusions[\{position}]", exclusion))
    }
    for located in boxes {
      let (at, box) = located
      for item in box_selectors(box) {
        let (dimension, selector) = item
        if selector is AnyOf(values) {
          for value_index in 1..<values.length() {
            if code_unit_compare(values[value_index - 1], values[value_index]) >
              0 {
              return Some(
                selector_path(at, dimension) + ".any_of[\{value_index}]",
              )
            }
          }
        }
      }
    }
    let mut previous : String? = None
    for position, exclusion in entry.exclusions {
      // Selector values were checked ascending above, so this is the
      // canonical text of the tuple as written.
      let text = match box_canonical_text(exclusion, bounds=Some(bounds)) {
        Some(text) => text
        None => return Some(prefix + ".exclusions[\{position}]")
      }
      if previous is Some(before) && code_unit_compare(before, text) > 0 {
        return Some(prefix + ".exclusions[\{position}]")
      }
      previous = Some(text)
    }
  }
  None
}

///|
/// Canonical CID of an admitted configuration. Evidence, decision requests
/// and Checkpoints bind this value.
pub fn account_configuration_cid(
  config : AdmittedAccountConfiguration,
) -> String {
  config.configuration_cid
}

///|
/// Decode, admit and identify a wire configuration in one step.
pub fn account_configuration_cid_json(
  body : String,
) -> Result[String, ConfigurationIssue] {
  admit_account_configuration_json(body).map(account_configuration_cid)
}

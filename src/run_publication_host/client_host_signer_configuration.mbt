///|
// Host-selected DATA, not project discovery, key custody or resolve authority.
// The original Host installer retains this wire and its physical generation.
struct ClientHostSignerConfiguration {
  wire : String
  explicit_signers : Bool
  signers : Array[ClientHostSignerSelection]
}

///|
// No constructor or mutable key/kind collection is exposed to callers.
struct ClientHostSignerSelection {
  name : String
  principal : String
  key_id : String
  private_key : String
  public_key : String
  kinds : Array[@checkpoint.CheckpointKind]
}

///|
/// Parsing ceilings only. They reserve no file, key, workspace or execution.
pub(all) struct ClientHostSignerReadLimits {
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_signers : Int
}

///|
pub(all) enum ClientHostSignerConfigurationIssue {
  InvalidHostSignerConfiguration
  HostSignerConfigurationLimit
} derive(Eq, Debug)

///|
priv suberror HostSignerConfigurationStop {
  HostSignerConfigurationStop(ClientHostSignerConfigurationIssue)
}

///|
fn[T] host_signer_decoded(
  value : Result[T, @decode.Issue],
) -> T raise HostSignerConfigurationStop {
  match value {
    Ok(value) => value
    Err(_) => raise HostSignerConfigurationStop(InvalidHostSignerConfiguration)
  }
}

///|
fn host_signer_text(
  value : @decode.Cursor,
) -> String raise HostSignerConfigurationStop {
  let text = host_signer_decoded(@decode.text(value))
  if text.is_empty() || text.contains("\u{0000}") {
    raise HostSignerConfigurationStop(InvalidHostSignerConfiguration)
  }
  text
}

///|
/// Project only the explicit public Host signers from the exact original wire.
/// This is not admission of account_config, run_policy or effect_policy. Those
/// fields remain subject to their own Owners before installation or dispatch.
/// Missing signers selects no default key; even a present selection supplies no
/// public/private correspondence, signing permission, grant or original use.
pub fn admit_client_host_signer_configuration(
  wire : String,
  limits : ClientHostSignerReadLimits,
) -> Result[ClientHostSignerConfiguration, ClientHostSignerConfigurationIssue] {
  if limits.max_wire_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_signers < 1 ||
    @utf8.encode(wire).length() > limits.max_wire_bytes {
    return Err(HostSignerConfigurationLimit)
  }
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: limits.max_wire_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidHostSignerConfiguration)
  }
  try {
    let cursor = host_signer_decoded(
      @decode.admit(source, {
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_string_bytes: limits.max_wire_bytes,
        max_total_string_bytes: limits.max_wire_bytes,
      }),
    )
    let root = host_signer_decoded(
      @decode.closed_object(cursor, [
        "version", "account_config", "run_policy", "effect_policy", "signers",
      ]),
    )
    if host_signer_text(host_signer_decoded(@decode.required(root, "version"))) !=
      "actql-host/0.1" {
      return Err(InvalidHostSignerConfiguration)
    }
    let signers : Array[ClientHostSignerSelection] = []
    let explicit_signers = match @decode.field(root, "signers") {
      Missing => false
      ExplicitNull => return Err(InvalidHostSignerConfiguration)
      Present(value) => {
        guard @decode.object_length(value) is Some(length) else {
          return Err(InvalidHostSignerConfiguration)
        }
        if length > limits.max_signers {
          return Err(HostSignerConfigurationLimit)
        }
        for index in 0..<length {
          guard @decode.field_at(value, index) is Some((name, item)) &&
            !name.is_empty() &&
            !name.contains("\u{0000}") else {
            return Err(InvalidHostSignerConfiguration)
          }
          let fields = host_signer_decoded(
            @decode.closed_object(item, [
              "principal", "key_id", "private_key", "public_key", "checkpoint_kinds",
            ]),
          )
          let kinds_value = host_signer_decoded(
            @decode.required(fields, "checkpoint_kinds"),
          )
          guard @decode.array_length(kinds_value) is Some(count) &&
            count > 0 &&
            count <= 6 else {
            return Err(InvalidHostSignerConfiguration)
          }
          let kinds : Array[@checkpoint.CheckpointKind] = []
          for ordinal in 0..<count {
            guard @decode.element_at(kinds_value, ordinal) is Some(item) else {
              return Err(InvalidHostSignerConfiguration)
            }
            guard @checkpoint.parse_checkpoint_kind(host_signer_text(item))
              is Some(kind) &&
              !kinds.contains(kind) else {
              return Err(InvalidHostSignerConfiguration)
            }
            kinds.push(kind)
          }
          signers.push({
            name,
            principal: host_signer_text(
              host_signer_decoded(@decode.required(fields, "principal")),
            ),
            key_id: host_signer_text(
              host_signer_decoded(@decode.required(fields, "key_id")),
            ),
            private_key: host_signer_text(
              host_signer_decoded(@decode.required(fields, "private_key")),
            ),
            public_key: host_signer_text(
              host_signer_decoded(@decode.required(fields, "public_key")),
            ),
            kinds,
          })
        }
        true
      }
    }
    Ok({ wire, explicit_signers, signers, })
  } catch {
    HostSignerConfigurationStop(issue) => Err(issue)
  }
}

///|
pub fn ClientHostSignerConfiguration::original_wire(self : Self) -> String {
  self.wire
}

///|
pub fn ClientHostSignerConfiguration::has_explicit_signers(self : Self) -> Bool {
  self.explicit_signers
}

///|
pub fn ClientHostSignerConfiguration::signer_count(self : Self) -> Int {
  self.signers.length()
}

///|
pub fn ClientHostSignerConfiguration::signer_at(
  self : Self,
  index : Int,
) -> ClientHostSignerSelection? {
  if index < 0 || index >= self.signers.length() {
    None
  } else {
    Some(self.signers[index])
  }
}

///|
/// Exact original name lookup, not implicit first/default signer selection.
pub fn ClientHostSignerConfiguration::select_signer(
  self : Self,
  name : String,
) -> ClientHostSignerSelection? {
  self.signers.iter().find_first(value => value.name == name)
}

///|
pub fn ClientHostSignerSelection::name(self : Self) -> String {
  self.name
}

///|
pub fn ClientHostSignerSelection::principal(self : Self) -> String {
  self.principal
}

///|
pub fn ClientHostSignerSelection::key_id(self : Self) -> String {
  self.key_id
}

///|
pub fn ClientHostSignerSelection::private_key_file(self : Self) -> String {
  self.private_key
}

///|
pub fn ClientHostSignerSelection::public_key_file(self : Self) -> String {
  self.public_key
}

///|
/// Declared kind membership only, never current resolve/key authorization.
pub fn ClientHostSignerSelection::allows_kind(
  self : Self,
  kind : @checkpoint.CheckpointKind,
) -> Bool {
  self.kinds.contains(kind)
}

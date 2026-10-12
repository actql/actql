///|
/// Actual physical observations supplied by the trusted installation port.
/// These fields and the resulting body do not prove adoption or permission.
pub(all) struct ClientLocalInitializationPhysical {
  nonce : String
  parent : (UInt64, UInt64)
  root : (UInt64, UInt64)
  source_root : (UInt64, UInt64)
  source_file : String
  source_path : String
  source_generation : (UInt64, UInt64, Int64)
  state_name : String
}

///|
pub fn client_local_initialization_record_body(
  fields : Array[String],
) -> Result[Bytes, ClientLocalOriginalCodecIssue] {
  let keys = [
    "account_id", "configuration_cid", "content_cid", "nonce", "parent_device", "parent_inode",
    "root_device", "root_inode", "settings_cid", "source_device", "source_file",
    "source_inode", "source_path", "source_root_device", "source_root_inode", "source_size",
    "state_name", "version",
  ]
  if fields.length() != keys.length() {
    return Err(InvalidOriginal)
  }
  client_local_original_record_body(
    keys.mapi((index, key) => (key, fields[index])),
  )
}

///|
pub fn client_local_configuration_custody_record(
  intent_cid : String,
  generation : (UInt64, UInt64, Int64),
) -> Result[Bytes, ClientLocalOriginalCodecIssue] {
  client_local_original_record_body([
    ("device", generation.0.to_string()),
    ("inode", generation.1.to_string()),
    ("intent_cid", intent_cid),
    ("size", generation.2.to_string()),
    ("version", "actql-native-local-configuration-custody/0.1"),
  ])
}

///|
pub fn client_local_journal_custody_record(
  intent_cid : String,
  configuration_custody_cid : String,
  generation : (UInt64, UInt64),
) -> Result[Bytes, ClientLocalOriginalCodecIssue] {
  client_local_original_record_body([
    ("configuration_custody_cid", configuration_custody_cid),
    ("device", generation.0.to_string()),
    ("inode", generation.1.to_string()),
    ("intent_cid", intent_cid),
    ("version", "actql-native-local-journal-custody/0.1"),
  ])
}

///|
/// The exact existing Native initialization preimage. Account identities and
/// original content hashes are emitted by their existing Core Owners/codecs.
/// The Host retains original file/selection/creation and nonce custody.
pub fn client_local_initialization_body(
  account : @authorization.AdmittedAccountConfiguration,
  account_original : Bytes,
  settings_original : Bytes,
  physical : ClientLocalInitializationPhysical,
) -> Result[Bytes, ClientLocalOriginalCodecIssue] {
  if physical.nonce.length() != 64 ||
    physical.source_generation.2 < 0L ||
    physical.source_generation.2 != account_original.length().to_int64() ||
    account_original.length() > 1048576 ||
    settings_original.length() > 8192 {
    return Err(InvalidOriginal)
  }
  for index in 0..<physical.nonce.length() {
    let char = physical.nonce[index]
    if !((char >= '0' && char <= '9') || (char >= 'a' && char <= 'f')) {
      return Err(InvalidOriginal)
    }
  }
  let wire = @utf8.decode(account_original) catch {
    _ => return Err(InvalidOriginal)
  }
  guard @authorization.admit_account_configuration_json(wire) is Ok(original) &&
    original.configuration_cid() == account.configuration_cid() else {
    return Err(InvalidOriginal)
  }
  client_local_initialization_record_body([
    account.account_id(),
    account.configuration_cid(),
    "sha256:" + @sha.hex(account_original),
    physical.nonce,
    physical.parent.0.to_string(),
    physical.parent.1.to_string(),
    physical.root.0.to_string(),
    physical.root.1.to_string(),
    "sha256:" + @sha.hex(settings_original),
    physical.source_generation.0.to_string(),
    physical.source_file,
    physical.source_generation.1.to_string(),
    physical.source_path,
    physical.source_root.0.to_string(),
    physical.source_root.1.to_string(),
    physical.source_generation.2.to_string(),
    physical.state_name,
    "actql-native-local-host-initialization/0.1",
  ])
}

///|
pub fn client_local_configuration_custody_body(
  intent_original : Bytes,
  generation : (UInt64, UInt64, Int64),
) -> Result[Bytes, ClientLocalOriginalCodecIssue] {
  if intent_original.length() > 8192 || generation.2 < 0L {
    return Err(InvalidOriginal)
  }
  client_local_configuration_custody_record(
    "sha256:" + @sha.hex(intent_original),
    generation,
  )
}

///|
pub fn client_local_journal_custody_body(
  intent_original : Bytes,
  configuration_custody_original : Bytes,
  generation : (UInt64, UInt64),
) -> Result[Bytes, ClientLocalOriginalCodecIssue] {
  if intent_original.length() > 8192 ||
    configuration_custody_original.length() > 8192 {
    return Err(InvalidOriginal)
  }
  client_local_journal_custody_record(
    "sha256:" + @sha.hex(intent_original),
    "sha256:" + @sha.hex(configuration_custody_original),
    generation,
  )
}

///|
/// Private Host configuration DATA only. The actual installer separately owns
/// trusted file selection, key/current custody and independent authorization.
#export_name("clientHostSignersAdmit")
pub fn client_host_signers_admit(
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_signers : Int,
) -> Result[
  @publication_host.ClientHostSignerConfiguration,
  @publication_host.ClientHostSignerConfigurationIssue,
] {
  @publication_host.admit_client_host_signer_configuration(wire, {
    max_wire_bytes,
    max_nodes,
    max_depth,
    max_signers,
  })
}

///|
#export_name("clientHostSignersOriginalWire")
pub fn client_host_signers_original_wire(
  value : @publication_host.ClientHostSignerConfiguration,
) -> String {
  value.original_wire()
}

///|
#export_name("clientHostSignersExplicit")
pub fn client_host_signers_explicit(
  value : @publication_host.ClientHostSignerConfiguration,
) -> Bool {
  value.has_explicit_signers()
}

///|
#export_name("clientHostSignersCount")
pub fn client_host_signers_count(
  value : @publication_host.ClientHostSignerConfiguration,
) -> Int {
  value.signer_count()
}

///|
#export_name("clientHostSignersSelect")
pub fn client_host_signers_select(
  value : @publication_host.ClientHostSignerConfiguration,
  name : String,
) -> @publication_host.ClientHostSignerSelection? {
  value.select_signer(name)
}

///|
#export_name("clientHostSignerName")
pub fn client_host_signer_name(
  value : @publication_host.ClientHostSignerSelection,
) -> String {
  value.name()
}

///|
#export_name("clientHostSignerPrincipal")
pub fn client_host_signer_principal(
  value : @publication_host.ClientHostSignerSelection,
) -> String {
  value.principal()
}

///|
#export_name("clientHostSignerKeyId")
pub fn client_host_signer_key_id(
  value : @publication_host.ClientHostSignerSelection,
) -> String {
  value.key_id()
}

///|
#export_name("clientHostSignerPrivateKeyFile")
pub fn client_host_signer_private_key_file(
  value : @publication_host.ClientHostSignerSelection,
) -> String {
  value.private_key_file()
}

///|
#export_name("clientHostSignerPublicKeyFile")
pub fn client_host_signer_public_key_file(
  value : @publication_host.ClientHostSignerSelection,
) -> String {
  value.public_key_file()
}

///|
/// Membership in original configuration only; true is not a signing permit.
#export_name("clientHostSignerAllowsKind")
pub fn client_host_signer_allows_kind(
  value : @publication_host.ClientHostSignerSelection,
  name : String,
) -> Bool {
  match @checkpoint.parse_checkpoint_kind(name) {
    Some(kind) => value.allows_kind(kind)
    None => false
  }
}

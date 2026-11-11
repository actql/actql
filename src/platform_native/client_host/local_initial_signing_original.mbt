///|
// Private first-initialization input. Its original nominal session/material is
// retained through the existing initialization transaction and its final fence.
priv struct NativeLocalInitialSigningCapture {
  session : NativeLocalAdoptionSession
  material : NativeLocalInitialSigningMaterial
  policy : @host.ClientLocalSigningBootstrapPolicy
  adoption : Bytes
  payload : Bytes
  host_payload : Bytes
  host_signing_subject_payload : Bytes?
}

///|
/// Authenticated original metadata in this Host's existing installation row.
/// This is not a grant, default-signer selection, issue sample or signing use.
struct NativeLocalInitialSigningOriginal {
  host : NativeLocalHostConnection
  original_read : (
    NativeLocalJournalCapture,
    @host.ClientLocalAdoptedHostMaterial[
      @sqlite.Database,
      NativeLocalAdoptionIssue,
    ],
  )?
  control_body : Bytes
  projection : @filesystem.PrivateFileProjection
  exported : Bytes
  policy : @host.ClientLocalSigningBootstrapPolicy
  public_key : @credential.LocalSigningPublicKey
  public_key_pem : String
  issuer : String
  // The independent Host key was decoded by this SAME control admission.
  // Only the original active Read may reuse its immutable public projection.
  host_public_key : (@credential.LocalSigningPublicKey, String)?
}

///|
priv struct NativeLocalInitialSigningFields {
  exported : Bytes
  policy : @host.ClientLocalSigningBootstrapPolicy
  public_key : @credential.LocalSigningPublicKey
  public_key_pem : String
  issuer : String
}

///|
fn[T] local_initial_signing_value(
  value : Result[T, NativeLocalAdoptionIssue],
) -> T raise LocalInstallationAdoptionStop {
  match value {
    Ok(value) => value
    Err(issue) => raise LocalInstallationAdoptionStop(issue)
  }
}

///|
fn NativeLocalAdoptionSession::prepare_initial_signing_capture(
  self : NativeLocalAdoptionSession,
  material : NativeLocalInitialSigningMaterial,
  policy : @host.ClientLocalSigningBootstrapPolicy,
  crypto : @crypto.Library,
  adoption : Bytes,
) -> Result[NativeLocalInitialSigningCapture, NativeLocalAdoptionIssue] {
  try {
    if !physical_equal(crypto, material.library) {
      return Err(CustodyLost)
    }
    let pem = local_initial_signing_value(
      self.initial_signing_public_key(material),
    )
    let raw = local_initial_signing_value(
      crypto.ed25519_public_key_raw32(pem).map_err(issue => Crypto(issue)),
    )
    let public_key = local_initial_signing_value(
      @credential.prepare_local_signing_public_key(raw).map_err(_ => Encoding),
    )
    let exported = local_initial_signing_value(
      material.projection.export_original().map_err(issue => Filesystem(issue)),
    )
    let issuer = local_initial_signing_value(
      policy.issuer_identity(self.intent_cid).map_err(_ => InvalidInput),
    )
    let adoption_cid = local_initial_signing_value(
      local_adoption_digest(crypto, adoption),
    )
    let fields : @host.ClientLocalInitialSigningPayloadFields = {
      adoption_cid,
      initialization_intent_cid: self.intent_cid,
      issuer_authority: issuer,
      key_file: "local-signing-key.pem",
      key_projection: @base64.encode(exported),
      policy_cid: policy.cid(),
      policy_original: policy.original_wire(),
      public_key_cid: public_key.cid(),
      public_key_original: public_key.json(),
      public_key_pem: pem,
      purpose: "reviewer_proof",
      root_role: "store",
      version: "actql-native-local-installation-original/0.1",
    }
    let payload = local_initial_signing_value(
      @host.client_local_initial_signing_payload_body(fields).map_err(_ => {
        Encoding
      }),
    )
    let host_pem = local_initial_signing_value(
      self.initial_host_signing_public_key(material),
    )
    let host_raw = local_initial_signing_value(
      crypto.ed25519_public_key_raw32(host_pem).map_err(issue => Crypto(issue)),
    )
    if host_raw == raw {
      return Err(CustodyLost)
    }
    let host_public = local_initial_signing_value(
      @credential.prepare_local_signing_public_key(host_raw).map_err(_ => {
        Encoding
      }),
    )
    let host_exported = local_initial_signing_value(
      material.host_attestation.projection
      .export_original()
      .map_err(issue => Filesystem(issue)),
    )
    let host_payload = local_initial_signing_value(
      @host.client_local_initial_signing_payload_body({
        ..fields,
        key_file: "local-host-attestation-key.pem",
        key_projection: @base64.encode(host_exported),
        public_key_cid: host_public.cid(),
        public_key_original: host_public.json(),
        public_key_pem: host_pem,
        purpose: "host_attestation",
      }).map_err(_ => Encoding),
    )
    let host_signing_subject_payload = match material.host_signing_subject {
      None => None
      Some(subject) => {
        let bytes = local_initial_signing_value(
          initial_host_signing_subject_payload(
            self.intent_cid,
            issuer,
            policy.cid(),
            host_public.cid(),
            subject,
          ),
        )
        if bytes.length() > 2048 {
          return Err(ConfigurationLimit)
        }
        Some(bytes)
      }
    }
    // Existing installation HMAC payload bound, not another capacity grant.
    if payload.length() > 2048 || host_payload.length() > 2048 {
      return Err(ConfigurationLimit)
    }
    let captured : NativeLocalInitialSigningCapture = {
      session: self,
      material,
      policy,
      adoption,
      payload,
      host_payload,
      host_signing_subject_payload,
    }
    local_initial_signing_value(captured.check_current(crypto, adoption))
    Ok(captured)
  } catch {
    LocalInstallationAdoptionStop(issue) => Err(issue)
  }
}

///|
fn NativeLocalInitialSigningCapture::check_current(
  self : NativeLocalInitialSigningCapture,
  crypto : @crypto.Library,
  adoption : Bytes,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if adoption != self.adoption ||
    !physical_equal(crypto, self.material.library) ||
    self.policy.issuer_identity(self.session.intent_cid) is Err(_) {
    return Err(CustodyLost)
  }
  match self.session.initial_signing_public_key(self.material) {
    Err(issue) => Err(issue)
    Ok(pem) if pem == self.material.public_key_pem => Ok(())
    Ok(_) => Err(CustodyLost)
  }
}

///|
fn NativeLocalInitialSigningCapture::control_body(
  self : NativeLocalInitialSigningCapture,
  database : @sqlite.Database,
  crypto : @crypto.Library,
  adoption : Bytes,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  try {
    local_initial_signing_value(self.check_current(crypto, adoption))
    if self.payload.length() > 2048 ||
      self.host_payload.length() > 2048 ||
      (
        self.host_signing_subject_payload is Some(bytes) &&
        bytes.length() > 2048
      ) {
      return Err(ConfigurationLimit)
    }
    let packet = local_initial_signing_value(
      local_installation_packet_in_transaction(
        database,
        crypto,
        self.payload,
        reads~,
      ),
    )
    let host_packet = local_initial_signing_value(
      local_installation_packet_in_transaction(
        database,
        crypto,
        self.host_payload,
        reads~,
      ),
    )
    // Closed alternative in the same host control row. The legacy raw adoption
    // body, issued count, setting reservations and all existing rows are intact.
    let fields = [
      ("adoption_body", @base64.encode(adoption)),
      ("initial_signing_original", @base64.encode(packet)),
      ("initial_host_attestation_original", @base64.encode(host_packet)),
    ]
    if self.host_signing_subject_payload is Some(payload) {
      let packet = local_initial_signing_value(
        local_installation_packet_in_transaction(
          database,
          crypto,
          payload,
          reads~,
        ),
      )
      fields.push(("initial_host_signing_subject", @base64.encode(packet)))
    }
    local_adoption_record(fields)
  } catch {
    LocalInstallationAdoptionStop(issue) => Err(issue)
  }
}

///|
fn local_initial_signing_control_header(
  body : Bytes,
) -> Result[Array[String], NativeLocalAdoptionIssue] {
  match
    local_adoption_fields(body, [
      "adoption_body", "initial_signing_original", "initial_host_attestation_original",
      "initial_host_signing_subject",
    ]) {
    Ok(value) => Ok(value)
    Err(_) =>
      match
        local_adoption_fields(body, [
          "adoption_body", "initial_signing_original", "initial_host_attestation_original",
        ]) {
        Ok(value) => Ok(value)
        Err(_) =>
          local_adoption_fields(body, [
            "adoption_body", "initial_signing_original",
          ])
      }
  }
}

///|
fn read_local_initial_signing_control(
  host : NativeLocalHostConnection,
  body : Bytes,
  signing_original? : NativeLocalInitialSigningOriginal? = None,
) -> Result[NativeLocalInitialSigningFields?, NativeLocalAdoptionIssue] {
  read_local_initial_signing_control_with_host_key(
    host,
    body,
    signing_original~,
  ).map(value => value.map(pair => pair.0))
}

///|
// Return the already checked Host projection with the existing Reviewer
// fields. This closed pair contains DATA, never an authorization decision.
fn read_local_initial_signing_control_with_host_key(
  host : NativeLocalHostConnection,
  body : Bytes,
  signing_original? : NativeLocalInitialSigningOriginal? = None,
) -> Result[
  (
    NativeLocalInitialSigningFields,
    (@credential.LocalSigningPublicKey, String)?,
  )?,
  NativeLocalAdoptionIssue,
] {
  if signing_original is Some(original) {
    if !physical_equal(original.host, host) || body != original.control_body {
      return Err(CustodyLost)
    }
  }
  if body == host.adoption_body {
    return Ok(None)
  }
  try {
    let header = local_initial_signing_value(
      local_initial_signing_control_header(body),
    )
    if header[0] != @base64.encode(host.adoption_body) {
      return Err(CustodyLost)
    }
    let packet = @base64.decode(header[1]) catch {
      _ => return Err(CustodyLost)
    }
    if @base64.encode(packet) != header[1] {
      return Err(CustodyLost)
    }
    let reviewer = local_initial_signing_value(
      read_local_initial_signing_packet(
        host,
        packet,
        "reviewer_proof",
        "local-signing-key.pem",
        signing_original~,
      ),
    )
    let mut retained_host_key = None
    if header.length() >= 3 {
      let host_packet = @base64.decode(header[2]) catch {
        _ => return Err(CustodyLost)
      }
      if @base64.encode(host_packet) != header[2] {
        return Err(CustodyLost)
      }
      let host_key = local_initial_signing_value(
        read_local_initial_signing_packet(
          host,
          host_packet,
          "host_attestation",
          "local-host-attestation-key.pem",
          signing_original~,
        ),
      )
      guard reviewer.public_key.raw32() is Ok(reviewer_raw) &&
        host_key.public_key.raw32() is Ok(host_raw) &&
        reviewer_raw != host_raw &&
        reviewer.exported[26:42].to_owned() !=
        host_key.exported[26:42].to_owned() &&
        reviewer.policy.cid() == host_key.policy.cid() &&
        reviewer.issuer == host_key.issuer else {
        return Err(CustodyLost)
      }
      if header.length() == 4 {
        guard local_initial_signing_value(
            read_initial_host_signing_subject(host, body, host_key),
          )
          is Some(_) else {
          return Err(CustodyLost)
        }
      }
      retained_host_key = Some((host_key.public_key, host_key.public_key_pem))
    }
    Ok(Some((reviewer, retained_host_key)))
  } catch {
    LocalInstallationAdoptionStop(issue) => Err(issue)
  }
}

///|
// The codec is unchanged DATA. This closed physical reader selects one exact
// role/file and authenticates the same initialization, policy and projection.
fn read_local_initial_signing_packet(
  host : NativeLocalHostConnection,
  packet : Bytes,
  purpose : String,
  key_file : String,
  signing_original? : NativeLocalInitialSigningOriginal? = None,
) -> Result[NativeLocalInitialSigningFields, NativeLocalAdoptionIssue] {
  try {
    let payload = local_initial_signing_value(
      read_local_installation_authenticated_payload(host, packet),
    )
    let fields = local_initial_signing_value(
      @host.read_client_local_initial_signing_payload(payload).map_err(issue => {
        match issue {
          @host.Encoding => Encoding
          @host.InvalidOriginal | @host.ConfigurationLimit => CustodyLost
        }
      }),
    )
    let policy = local_initial_signing_value(
      @host.admit_client_local_signing_bootstrap_policy(
        fields.policy_original,
        fields.policy_cid,
      ).map_err(_ => CustodyLost),
    )
    let issuer = local_initial_signing_value(
      policy.issuer_identity(host.session.intent_cid).map_err(_ => CustodyLost),
    )
    if fields.adoption_cid != host.adoption_cid ||
      fields.initialization_intent_cid != host.session.intent_cid ||
      fields.issuer_authority != issuer ||
      fields.key_file != key_file ||
      fields.purpose != purpose ||
      fields.root_role != "store" ||
      fields.version != "actql-native-local-installation-original/0.1" {
      return Err(CustodyLost)
    }
    let exported = @base64.decode(fields.key_projection) catch {
      _ => return Err(CustodyLost)
    }
    if exported.length() != 106 + @utf8.encode(fields.key_file).length() ||
      @base64.encode(exported) != fields.key_projection ||
      exported[106:].to_owned() != @utf8.encode(fields.key_file) {
      return Err(CustodyLost)
    }
    let public_key = local_initial_signing_value(
      @credential.admit_local_signing_public_key_json(
        fields.public_key_original,
        fields.public_key_cid,
      ).map_err(_ => CustodyLost),
    )
    if !valid_initial_signing_public_pem(fields.public_key_pem) {
      return Err(CustodyLost)
    }
    let raw = match signing_original {
      None =>
        local_initial_signing_value(
          host.epoch.crypto
          .ed25519_public_key_raw32(fields.public_key_pem)
          .map_err(issue => Crypto(issue)),
        )
      Some(original) => {
        if !physical_equal(original.host, host) {
          return Err(CustodyLost)
        }
        guard original.original_read is Some((capture, material)) &&
          capture.opening is JournalAcquired(actual_host) &&
          physical_equal(actual_host, host) &&
          capture.read_callback_active &&
          capture.read_facts_valid &&
          capture.read_material is Some(actual_material) &&
          physical_equal(actual_material, material) else {
          return Err(OriginalResourceScopePending)
        }
        // The enclosing closed current frame already checks the physical DB
        // and control row. Observe its SAME entered Read lifetime here, rather
        // than issuing another heavyweight global-current/SQL pass per key.
        local_initial_signing_value(capture.check_original_read_lifetime())
        local_initial_signing_value(
          host.epoch.crypto.require_current().map_err(issue => Crypto(issue)),
        )
        // HMAC, payload/policy admission and every closed-field check above
        // still execute. Reuse only the SAME previously decoded public key;
        // no EVP object, private key, permission or use result is retained.
        local_initial_signing_value(
          original.decoded_initial_signing_public_key(
            purpose,
            key_file,
            fields.public_key_pem,
            public_key,
          ),
        )
      }
    }
    guard public_key.raw32() is Ok(expected_raw) && expected_raw == raw else {
      return Err(CustodyLost)
    }
    Ok({
      exported,
      policy,
      public_key,
      public_key_pem: fields.public_key_pem,
      issuer,
    })
  } catch {
    LocalInstallationAdoptionStop(issue) => Err(issue)
  }
}

///|
// Pure correspondence of an already admitted public projection. The caller
// separately requires the actual original Read, Library and packet HMAC.
fn NativeLocalInitialSigningOriginal::decoded_initial_signing_public_key(
  self : NativeLocalInitialSigningOriginal,
  purpose : String,
  key_file : String,
  pem : String,
  public_key : @credential.LocalSigningPublicKey,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  let retained = match (purpose, key_file) {
    ("reviewer_proof", "local-signing-key.pem") =>
      Some((self.public_key, self.public_key_pem))
    ("host_attestation", "local-host-attestation-key.pem") =>
      self.host_public_key
    _ => None
  }
  guard retained is Some((original, original_pem)) &&
    pem == original_pem &&
    original.raw32() is Ok(raw) &&
    public_key.raw32() is Ok(actual) &&
    raw == actual else {
    return Err(CustodyLost)
  }
  Ok(raw)
}

///|
fn valid_local_installation_control(
  host : NativeLocalHostConnection,
  body : Bytes,
) -> Bool {
  read_local_initial_signing_control(host, body) is Ok(_)
}

///|
/// Trusted explicit first installer only. It accepts this session's opaque
/// material and the pinned Common policy; it does not sample an issue clock or
/// create a grant. Existing/Unknown journals cannot capture a missing original.
pub fn NativeLocalAdoptionSession::open_journal_with_initial_signing_material(
  self : NativeLocalAdoptionSession,
  material : NativeLocalInitialSigningMaterial,
  policy : @host.ClientLocalSigningBootstrapPolicy,
  library : @sqlite.Library,
  crypto : @crypto.Library,
  ttl_ms : Double,
  max_records : Int,
  max_snapshot_bytes : Int64,
  max_retained_intent_bytes? : Int64 = 67108864L,
) -> Result[NativeLocalHostConnection, NativeLocalAdoptionIssue] {
  // Reject a foreign original before filesystem/schema initialization.
  match self.initial_signing_public_key(material) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(crypto, material.library) {
    return Err(CustodyLost)
  }
  self.open_journal_selected(
    library,
    crypto,
    ttl_ms,
    max_records,
    max_snapshot_bytes,
    [],
    initial_signing=Some(material),
    initial_policy=Some(policy),
    max_retained_intent_bytes~,
  )
}

///|
/// Restore the authenticated metadata and exact original Store file generation.
/// A legacy raw host row returns unavailable; this never adopts today's key or
/// policy to repair it. The existing journal confirms its transaction first.
pub fn NativeLocalHostConnection::restore_initial_signing_original(
  self : NativeLocalHostConnection,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[NativeLocalInitialSigningOriginal, NativeLocalAdoptionIssue] {
  let original_read = match capture {
    None => None
    Some(capture) => {
      if !capture.read_callback_active || !capture.read_facts_valid {
        return Err(OriginalResourceScopePending)
      }
      let material = match
        capture.with_current_adoption_material_in_original_read((
          actual,
          material,
          _,
        ) => {
          if !physical_equal(actual, self) {
            return Err(CustodyLost)
          }
          Ok(material)
        }) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      Some((capture, material))
    }
  }
  match self.check_signing_original_read(original_read) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let primary : Ref[NativeLocalAdoptionIssue?] = Ref(None)
  let original = self.journal.transaction(() => {
    try {
      local_initial_signing_value(
        self.check_signing_original_read(original_read),
      )
      local_initial_signing_value(self.installation_custody()) |> ignore
      let row = local_initial_signing_value(
        self.database
        .read("client_local_installation_custody", "host")
        .map_err(issue => Physical(issue)),
      )
      guard local_initial_signing_value(
          read_local_initial_signing_control_with_host_key(self, row.body),
        )
        is Some((fields, host_public_key)) else {
        return Err(CustodyLost)
      }
      local_initial_signing_value(
        self.require_initial_signing_separation(fields),
      )
      let projection = local_initial_signing_value(
        self.session.root
        .restore_private_file_projection(fields.exported)
        .map_err(issue => Filesystem(issue)),
      )
      local_initial_signing_value(
        self.check_signing_original_read(original_read),
      )
      Ok({
        host: self,
        original_read,
        control_body: row.body,
        projection,
        exported: fields.exported,
        policy: fields.policy,
        public_key: fields.public_key,
        public_key_pem: fields.public_key_pem,
        issuer: fields.issuer,
        host_public_key,
      })
    } catch {
      LocalInstallationAdoptionStop(issue) => {
        primary.val = Some(issue)
        Err(CustodyLost)
      }
    }
  })
  match original {
    Err(issue) =>
      match primary.val {
        None => Err(Journal(issue))
        Some(original) =>
          match issue {
            CustodyLost => Err(original)
            _ => Err(InstallationReadTransactionFailure(original, issue))
          }
      }
    Ok(value) => value.require_current().map(_ => value)
  }
}

///|
/// Current physical/original custody only. Actor, Reviewer, Run, exact purpose,
/// preimage and durable operation/use authorization remain independent gates.
pub fn NativeLocalInitialSigningOriginal::require_current(
  self : NativeLocalInitialSigningOriginal,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match self.check_host_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.require_current_after_host_binding()
}

///|
// Private continuation of this SAME Host's immediately preceding binding
// check. No callback or IO may intervene. All original control/key projection
// reads and the final post-IO binding fence remain below.
fn NativeLocalInitialSigningOriginal::require_current_after_host_binding(
  self : NativeLocalInitialSigningOriginal,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  guard self.host.database.read("client_local_installation_custody", "host")
    is Ok(row) &&
    row.revision == 0L &&
    row.body == self.control_body else {
    return Err(CustodyLost)
  }
  let signing_original = if self.original_read is Some(_) {
    Some(self)
  } else {
    None
  }
  guard read_local_initial_signing_control(
      self.host,
      row.body,
      signing_original~,
    )
    is Ok(Some(fields)) else {
    return Err(CustodyLost)
  }
  if fields.public_key_pem != self.public_key_pem {
    return Err(CustodyLost)
  }
  guard self.projection.export_original() is Ok(exported) &&
    exported == self.exported else {
    return Err(CustodyLost)
  }
  match self.host.require_initial_signing_separation(fields) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match self.host.session.root.restore_private_file_projection(self.exported) {
    Err(issue) => return Err(Filesystem(issue))
    Ok(_) => ()
  }
  self.check_host_current()
}

///|
/// Metadata identity, not an issuer issue capability or current permission.
pub fn NativeLocalInitialSigningOriginal::issuer_identity(
  self : NativeLocalInitialSigningOriginal,
) -> Result[String, NativeLocalAdoptionIssue] {
  self.require_current().map(_ => self.issuer)
}

///|
pub fn NativeLocalInitialSigningOriginal::policy(
  self : NativeLocalInitialSigningOriginal,
) -> Result[@host.ClientLocalSigningBootstrapPolicy, NativeLocalAdoptionIssue] {
  self.require_current().map(_ => self.policy)
}

///|
pub fn NativeLocalInitialSigningOriginal::public_key(
  self : NativeLocalInitialSigningOriginal,
) -> Result[@credential.LocalSigningPublicKey, NativeLocalAdoptionIssue] {
  self.require_current().map(_ => self.public_key)
}

///|
// Join the new Store-root ReviewerProof original to the existing separation
// rule. Original source-root custody remains source-root, never relabelled.
fn NativeLocalHostConnection::require_initial_signing_separation(
  self : NativeLocalHostConnection,
  original : NativeLocalInitialSigningFields,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  let mut cursor = ""
  for _ in 0..<8 {
    let row = match
      self.database.scan_after("client_local_installation_originals", cursor) {
      Err(@sqlite.NotFound) => return Ok(())
      Err(issue) => return Err(Physical(issue))
      Ok(value) => value
    }
    cursor = row.key
    if row.key == local_policy_upgrade_key {
      continue
    }
    guard self.session.settings.files
      .iter()
      .find_first(file => file.name == row.key)
      is Some(file) else {
      return Err(CustodyLost)
    }
    let other = match read_local_installation_projection(self, file, row.body) {
      Err(issue) => return Err(issue)
      Ok(value) => value
    }
    if self.session.source_root.restore_private_file_projection(other) is Err(_) {
      return Err(CustodyLost)
    }
    // AQLPFP01's file device/inode pair is independent of which original Root
    // selected it. This is an existing private export, not a native C layout.
    let same_file = other.length() > 106 &&
      original.exported.length() > 106 &&
      other[26:42].to_owned() == original.exported[26:42].to_owned()
    let wire = @utf8.decode(file.body) catch { _ => return Err(CustodyLost) }
    match @credential_resource.admit_native_local_signing_key_selection(wire) {
      Err(_) => if same_file { return Err(CustodyLost) }
      Ok(selection) => {
        let (_, purpose, _, _, _, _, _, pem) = @credential_resource.native_local_signing_key_selection_projection(
          selection,
        )
        if purpose == @credential.HostAttestation {
          let raw = match self.epoch.crypto.ed25519_public_key_raw32(pem) {
            Err(issue) => return Err(Crypto(issue))
            Ok(value) => value
          }
          guard original.public_key.raw32() is Ok(own_raw) else {
            return Err(CustodyLost)
          }
          if same_file || raw == own_raw {
            return Err(CustodyLost)
          }
        }
      }
    }
  }
  match
    self.database.scan_after("client_local_installation_originals", cursor) {
    Err(@sqlite.NotFound) => Ok(())
    Err(issue) => Err(Physical(issue))
    Ok(_) => Err(CustodyLost)
  }
}

///|
// The generated initial SPKI PEM is one fixed representation. The generic
// Crypto parser deliberately accepts other PEM documents/trailing material;
// it cannot alone validate this closed original record. Reuse existing base64
// and Crypto admission, without introducing another public-key identity codec.
fn valid_initial_signing_public_pem(pem : String) -> Bool {
  let prefix = "-----BEGIN PUBLIC KEY-----\n"
  let suffix = "\n-----END PUBLIC KEY-----\n"
  if pem.length() != 113 || !pem.has_prefix(prefix) || !pem.has_suffix(suffix) {
    return false
  }
  let encoded = pem[prefix.length():pem.length() - suffix.length()].to_owned()
  let der = @base64.decode(encoded) catch { _ => return false }
  der.length() == 44 && @base64.encode(der) == encoded
}

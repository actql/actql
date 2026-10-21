///|
/// Physical custody for the existing SubmissionEpoch identity law. The caller
/// must admit the journal format before opening SQLite and retain its cleanup
/// owner; this adapter neither creates a directory nor opens a missing DB.
struct NativeClientEpochAuthority {
  database : @sqlite.Database
  crypto : @crypto.Library
  ttl_ms : Double
  mut fenced : Bool
}

///|
pub(all) enum NativeClientEpochIssue {
  InvalidInput
  Encoding
  AlreadyInitialized
  CustodyLost
  AuthorizationDenied
  Unverifiable
  ScopeMismatch
  Fenced
  TransactionUnknown
  Physical(@sqlite.NativeSqliteIssue)
  Crypto(@crypto.NativeSignatureIssue)
  Identity(@scope.SubmissionIdentityIssue)
}

///|
struct NativeClientSubmissionEpoch {
  body : @scope.SubmissionEpoch
  authority_scope_cid : String
  tag : Bytes
  wire : String
}

///|
fn valid_epoch_clock(now : Double) -> Bool {
  !now.is_nan() &&
  !now.is_inf() &&
  now >= 0.0 &&
  now <= 9007199254740991.0 - 86400000.0 &&
  now.trunc() == now &&
  !(now == 0.0 && 1.0 / now < 0.0)
}

///|
fn epoch_hex(bytes : Bytes) -> String {
  let out = StringBuilder(size_hint=bytes.length() * 2)
  for byte in bytes {
    let text = byte.to_hex()
    if text.length() == 1 {
      out.write_char('0')
    }
    out.write_string(text)
  }
  out.to_string()
}

///|
fn epoch_hex_bytes(text : String) -> Bytes? {
  if text.length() != 64 {
    return None
  }
  let out : Array[Byte] = []
  for i in 0..<32 {
    let digit = fn(unit : UInt16) {
      let ch = unit.to_int()
      if ch >= 48 && ch <= 57 {
        Some(ch - 48)
      } else if ch >= 97 && ch <= 102 {
        Some(ch - 87)
      } else {
        None
      }
    }
    guard digit(text[i * 2]) is Some(a) && digit(text[i * 2 + 1]) is Some(b) else {
      return None
    }
    out.push((a * 16 + b).to_byte())
  }
  Some(Bytes::makei(32, i => out[i]))
}

///|
fn epoch_cursor(wire : String) -> @decode.Cursor? {
  let value = @source.parse_json_bytes_preserving(@utf8.encode(wire), {
    max_input_bytes: 4096,
    max_nodes: 32,
    max_depth: 4,
  }).to_option()
  value.bind(value => {
    @decode.admit(value, {
      max_nodes: 32,
      max_depth: 4,
      max_string_bytes: 1024,
      max_total_string_bytes: 4096,
    }).to_option()
  })
}

///|
fn epoch_text(object : @decode.ObjectView, key : String) -> String? {
  @decode.lookup(object, key).bind(value => @decode.text(value).to_option())
}

///|
fn epoch_number(object : @decode.ObjectView, key : String) -> Double? {
  @decode.lookup(object, key).bind(value => {
    @decode.finite_number(value).to_option()
  })
}

///|
fn epoch_custody_body(
  key : Bytes,
  now : Double,
) -> Result[Bytes, NativeClientEpochIssue] {
  let writer = @encode.writer(4096, 16, 4) catch { _ => return Err(Encoding) }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "authentication_key")
    @encode.string_value(writer, @base64.encode(key))
    @encode.key(writer, "observed_at")
    @encode.number_value(writer, now)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-submission-epoch-custody/0.1")
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(Encoding)
  }
}

///|
fn read_epoch_custody(
  database : @sqlite.Database,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[(Bytes, Double, Int64), NativeClientEpochIssue] {
  match
    scan_client_journal_value(database, "client_submission_epoch", "", reads) {
    Ok(entry) if entry.key == "authority" => ()
    Ok(_) | Err(@sqlite.NotFound) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
  }
  match
    scan_client_journal_value(
      database, "client_submission_epoch", "authority", reads,
    ) {
    Err(@sqlite.NotFound) => ()
    Ok(_) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
  }
  let row = match
    read_client_journal_value(
      database, "client_submission_epoch", "authority", reads,
    ) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
  }
  let wire = @utf8.decode(row.body) catch { _ => return Err(CustodyLost) }
  guard epoch_cursor(wire) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "authentication_key", "observed_at", "version",
    ])
    is Ok(object) &&
    epoch_text(object, "version") ==
    Some("actql-native-submission-epoch-custody/0.1") &&
    epoch_text(object, "authentication_key") is Some(encoded) &&
    epoch_number(object, "observed_at") is Some(now) &&
    valid_epoch_clock(now) else {
    return Err(CustodyLost)
  }
  let key = @base64.decode(encoded) catch { _ => return Err(CustodyLost) }
  let expected = match epoch_custody_body(key, now) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if key.length() != 32 ||
    @base64.encode(key) != encoded ||
    expected != row.body {
    return Err(CustodyLost)
  }
  Ok((key, now, row.revision))
}

///|
/// Establish custody only in an explicitly admitted fresh journal. A caller
/// must not call this to repair a missing record in an existing journal.
// The standalone fresh-journal initializer is exercised by epoch/journal WBs.
// Installed initialization uses the atomic *_in_transaction entry instead.
#warnings("-unused_value")
fn initialize_native_client_epoch_authority(
  database : @sqlite.Database,
  crypto : @crypto.Library,
) -> Result[Unit, NativeClientEpochIssue] {
  if database.transaction_fenced() {
    return Err(Fenced)
  }
  match database.begin_immediate() {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  let result = initialize_native_client_epoch_in_transaction(database, crypto)
  match result {
    Ok(_) =>
      match database.commit() {
        Ok(_) => Ok(())
        Err(_) => {
          database.fence_transactions()
          Err(TransactionUnknown)
        }
      }
    Err(issue) =>
      match database.rollback() {
        Ok(_) => Err(issue)
        Err(_) => {
          database.fence_transactions()
          Err(TransactionUnknown)
        }
      }
  }
}

///|
// Caller holds the existing SQLite transaction. This lets trusted Local
// assembly finalize the epoch key and other Client custody atomically.
fn initialize_native_client_epoch_in_transaction(
  database : @sqlite.Database,
  crypto : @crypto.Library,
  bootstrap? : NativeClientJournalBootstrapAccess? = None,
) -> Result[Unit, NativeClientEpochIssue] {
  if client_journal_transaction_fenced(
      database,
      bootstrap_journal_reads(bootstrap),
    ) {
    return Err(Fenced)
  }
  match
    scan_client_journal_value(
      database,
      "client_submission_epoch",
      "",
      bootstrap_journal_reads(bootstrap),
    ) {
    Ok(_) => Err(AlreadyInitialized)
    Err(@sqlite.NotFound) =>
      match crypto.random_bytes(32) {
        Err(issue) => Err(Crypto(issue))
        Ok(key) =>
          match epoch_custody_body(key, 0.0) {
            Err(issue) => Err(issue)
            Ok(body) =>
              insert_bootstrap_journal_value(
                database, "client_submission_epoch", "authority", body, bootstrap,
              )
              .map(_ => ())
              .map_err(issue => Physical(issue))
          }
      }
    Err(issue) => Err(Physical(issue))
  }
}

///|
pub fn open_native_client_epoch_authority(
  database : @sqlite.Database,
  crypto : @crypto.Library,
  ttl_ms : Double,
) -> Result[NativeClientEpochAuthority, NativeClientEpochIssue] {
  open_native_client_epoch_authority_with_reads(database, crypto, ttl_ms)
}

///|
fn open_native_client_epoch_authority_with_reads(
  database : @sqlite.Database,
  crypto : @crypto.Library,
  ttl_ms : Double,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[NativeClientEpochAuthority, NativeClientEpochIssue] {
  if client_journal_transaction_fenced(database, reads) {
    return Err(Fenced)
  }
  if !valid_epoch_clock(ttl_ms) || ttl_ms < 1.0 || ttl_ms > 86400000.0 {
    return Err(InvalidInput)
  }
  match read_epoch_custody(database, reads~) {
    Ok(_) => Ok({ database, crypto, ttl_ms, fenced: false, })
    Err(issue) => Err(issue)
  }
}

///|
/// The watermark commits even when the subsequent admission is refused.
/// Clock rollback must not make an expired, authenticated epoch reusable.
fn NativeClientEpochAuthority::clock(
  self : NativeClientEpochAuthority,
  now : Double,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[(Bytes, Double), NativeClientEpochIssue] {
  let reads = operations.map(original => original.reads)
  if self.fenced || client_journal_transaction_fenced(self.database, reads) {
    return Err(Fenced)
  }
  if !valid_epoch_clock(now) {
    return Err(InvalidInput)
  }
  match
    client_journal_transaction_operation(self.database, JournalBegin, reads) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  let result = match read_epoch_custody(self.database, reads~) {
    Err(issue) => Err(issue)
    Ok((key, retained, revision)) => {
      let clock = if now > retained { now } else { retained }
      // An already durable watermark needs no identical row rewrite. The
      // original read transaction still requires its real COMMIT ACK below.
      if clock == retained {
        Ok((key, clock))
      } else {
        match epoch_custody_body(key, clock) {
          Err(issue) => Err(issue)
          Ok(body) =>
            compare_exchange_client_journal_value(
              self.database,
              "client_submission_epoch",
              "authority",
              revision,
              body,
              operations,
            )
            .map(_ => (key, clock))
            .map_err(issue => Physical(issue))
        }
      }
    }
  }
  match result {
    Ok(value) =>
      match
        client_journal_transaction_operation(
          self.database,
          JournalCommit,
          reads,
        ) {
        Ok(_) => Ok(value)
        Err(_) => {
          self.fenced = true
          fence_client_journal_transactions(self.database, reads)
          Err(TransactionUnknown)
        }
      }
    Err(issue) =>
      match
        client_journal_transaction_operation(
          self.database,
          JournalRollback,
          reads,
        ) {
        Ok(_) => Err(issue)
        Err(_) => {
          self.fenced = true
          fence_client_journal_transactions(self.database, reads)
          Err(TransactionUnknown)
        }
      }
  }
}

///|
pub fn NativeClientEpochAuthority::issue_epoch(
  self : NativeClientEpochAuthority,
  authority_scope_cid : String,
  current_authorization : Bool,
  now : Double,
) -> Result[NativeClientSubmissionEpoch, NativeClientEpochIssue] {
  self.issue_epoch_with_operations(
    authority_scope_cid, current_authorization, now,
  )
}

///|
fn NativeClientEpochAuthority::issue_epoch_with_operations(
  self : NativeClientEpochAuthority,
  authority_scope_cid : String,
  current_authorization : Bool,
  now : Double,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[NativeClientSubmissionEpoch, NativeClientEpochIssue] {
  if !current_authorization {
    return Err(AuthorizationDenied)
  }
  let (key, clock) = match self.clock(now, operations~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let nonce = match self.crypto.random_bytes(32) {
    Ok(value) => epoch_hex(value)
    Err(issue) => return Err(Crypto(issue))
  }
  let body = match
    @scope.prepare_submission_epoch(
      authority_scope_cid,
      nonce,
      clock,
      clock + self.ttl_ms,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Identity(issue))
  }
  let tag = match
    self.crypto.hmac_sha256(
      key,
      @utf8.encode(@scope.submission_epoch_wire(body)),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Crypto(issue))
  }
  let writer = @encode.writer(4096, 16, 4) catch { _ => return Err(Encoding) }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "authenticator")
    @encode.string_value(writer, epoch_hex(tag))
    @encode.key(writer, "authorityScopeCid")
    @encode.string_value(writer, authority_scope_cid)
    @encode.key(writer, "epochNonce")
    @encode.string_value(writer, nonce)
    @encode.key(writer, "expiresAt")
    @encode.number_value(writer, clock + self.ttl_ms)
    @encode.key(writer, "notBefore")
    @encode.number_value(writer, clock)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-submission-epoch/0.1")
    @encode.end_object(writer)
    Ok({ body, authority_scope_cid, tag, wire: @encode.finish(writer), })
  } catch {
    _ => Err(Encoding)
  }
}

///|
pub fn native_client_submission_epoch_wire(
  epoch : NativeClientSubmissionEpoch,
) -> String {
  epoch.wire
}

///|
/// Shape and common identity admission are not authentication or read rights.
pub fn admit_native_client_submission_epoch(
  wire : String,
) -> Result[NativeClientSubmissionEpoch, NativeClientEpochIssue] {
  @host.admit_client_submission_epoch_token(wire)
  .map(value => {
    body: @host.client_submission_epoch_token_body(value),
    authority_scope_cid: @host.client_submission_epoch_token_authority_scope_cid(
      value,
    ),
    tag: @host.client_submission_epoch_token_tag(value),
    wire: @host.client_submission_epoch_token_wire(value),
  })
  .map_err(issue => {
    match issue {
      @host.Unverifiable => Unverifiable
      @host.Identity(issue) => Identity(issue)
    }
  })
}

///|
/// Expired authentication can still identify an original lookup. This returns
/// identity validity only, never a new acceptance or physical-start permit.
pub fn NativeClientEpochAuthority::verify_epoch(
  self : NativeClientEpochAuthority,
  epoch : NativeClientSubmissionEpoch,
  authority_scope_cid : String,
  current_authorization : Bool,
  now : Double,
) -> Result[@scope.SubmissionEpochValidity, NativeClientEpochIssue] {
  self.verify_epoch_with_operations(
    epoch, authority_scope_cid, current_authorization, now,
  )
}

///|
fn NativeClientEpochAuthority::verify_epoch_with_operations(
  self : NativeClientEpochAuthority,
  epoch : NativeClientSubmissionEpoch,
  authority_scope_cid : String,
  current_authorization : Bool,
  now : Double,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[@scope.SubmissionEpochValidity, NativeClientEpochIssue] {
  if !current_authorization {
    return Err(AuthorizationDenied)
  }
  let (key, clock) = match self.clock(now, operations~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // clock() just observed this original and acknowledged its watermark. No
  // application callback or reentry separates these two synchronous steps.
  self.verify_epoch_with_custody(epoch, authority_scope_cid, key, clock)
}

///|
/// Recheck the original key and monotonic watermark inside the caller's
/// existing SQLite transaction. The caller must advance clock() first and
/// share this exact physical handle; this does not begin or commit a nested
/// transaction and does not confer an admission purpose.
fn NativeClientEpochAuthority::verify_epoch_locked(
  self : NativeClientEpochAuthority,
  epoch : NativeClientSubmissionEpoch,
  authority_scope_cid : String,
  current_authorization : Bool,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[@scope.SubmissionEpochValidity, NativeClientEpochIssue] {
  if !current_authorization {
    return Err(AuthorizationDenied)
  }
  if self.fenced || client_journal_transaction_fenced(self.database, reads) {
    return Err(Fenced)
  }
  let (key, clock, _) = match read_epoch_custody(self.database, reads~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.verify_epoch_with_custody(epoch, authority_scope_cid, key, clock)
}

///|
// Only the immediately preceding actual custody read reaches this private
// helper. It is not an external key/capacity/admission constructor.
fn NativeClientEpochAuthority::verify_epoch_with_custody(
  self : NativeClientEpochAuthority,
  epoch : NativeClientSubmissionEpoch,
  authority_scope_cid : String,
  key : Bytes,
  clock : Double,
) -> Result[@scope.SubmissionEpochValidity, NativeClientEpochIssue] {
  if self.fenced || self.database.transaction_fenced() {
    return Err(Fenced)
  }
  // Counts actual authentication calls, not cheap entry checks or cache hits.
  native_timing_count(38)
  match
    self.crypto.verify_hmac_sha256(
      key,
      @utf8.encode(@scope.submission_epoch_wire(epoch.body)),
      epoch.tag,
    ) {
    Ok(true) => ()
    Ok(false) => return Err(Unverifiable)
    Err(issue) => return Err(Crypto(issue))
  }
  if epoch.authority_scope_cid != authority_scope_cid {
    return Err(ScopeMismatch)
  }
  @scope.submission_epoch_validity(epoch.body, clock).map_err(issue => {
    Identity(issue)
  })
}

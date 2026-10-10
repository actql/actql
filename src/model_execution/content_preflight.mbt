///|
/// Exact typed input selected from an admitted provider and its original
/// request. Host byte ports receive this opaque capability, not authored JSON.
pub struct ModelContentInput {
  request : ModelRequest
  role : String
  item : Int
  reference : @admitted.ReferenceValue
  dependency : @environment.ModelDependency
  media_type : String
  content_cid : String
  size_bytes : Int64
  classification : String
  policy_cid : String
}

///|
pub(all) enum ModelContentIssue {
  Request
  Role
  ReferenceUnavailable
  Metadata
  MediaType
  ByteLimit
  Classification
  Region
  EgressScope
  PageLimit
  FrameLimit
  ChunkLimit
  ContentIdentity
  Closed
} derive(Eq, Debug)

///|
/// Incremental exact-byte validation; the existing physical cursor retains
/// buffers and owns cleanup. This object does not retain another byte copy.
pub struct ModelContentByteCheck {
  input : ModelContentInput
  hasher : @sha.Hasher
  current : () -> Bool
  region : String
  egress_scope_cid : String
  pages : Int64?
  frames : Int64?
  mut bytes : Int64
  mut closed : Bool
}

///|
/// A checked live physical attachment, not a durable Run observation.
/// Its byte and current-custody facts remain tied to this request occurrence.
pub struct ModelContentAdmission {
  input : ModelContentInput
  current : () -> Bool
  region : String
  egress_scope_cid : String
  pages : Int64?
  frames : Int64?
}

///|
fn model_content_text(value : @identity.CanonicalValue?) -> String? {
  match value {
    Some(@identity.String(text)) => Some(text)
    _ => None
  }
}

///|
fn model_content_integer(value : @identity.CanonicalValue?) -> Int64? {
  guard value is Some(@identity.Number(number)) &&
    number >= 0.0 &&
    number <= 9007199254740991.0 &&
    number.to_int64().to_double() == number else {
    return None
  }
  Some(number.to_int64())
}

///|
fn model_media_payload(input : ModelContentInput) -> @decode.ObjectView {
  @decode.open_object(
    @environment.model_dependency_payload(input.dependency).unwrap(),
  ).unwrap()
}

///|
/// item=-1 selects a direct Content role; an array uses its original ordinal.
/// NULL has no attachment, but its static media binding is still mandatory.
pub fn model_content_input(
  provider : AdmittedModelProvider,
  request : ModelRequest,
  role : String,
  item : Int,
) -> Result[ModelContentInput?, ModelContentIssue] {
  if !physical_equal(
      @environment.model_execution_task(provider.execution),
      request.task,
    ) {
    return Err(Request)
  }
  guard @environment.single_attempt_model_media(provider.dependencies, role)
    is Some(dependency) else {
    return Err(Role)
  }
  let mut selected : @admitted.Value? = None
  for (name, value) in request.inputs {
    if name != role {
      continue
    }
    if selected is Some(_) {
      return Err(Role)
    }
    selected = Some(value.value)
  }
  guard selected is Some(value) else { return Err(Role) }
  let leaf = if item == -1 {
    value
  } else {
    guard item >= 0 &&
      value is @admitted.Array(values) &&
      @admitted.element_at(values, item) is Some(leaf) else {
      return Err(Role)
    }
    leaf
  }
  if leaf is @admitted.Null {
    return Ok(None)
  }
  guard leaf is @admitted.Reference(reference) &&
    @admitted.reference_content_metadata(reference) is Some((media, metadata)) else {
    return Err(Role)
  }
  if !@admitted.reference_available(reference) {
    return Err(ReferenceUnavailable)
  }
  let get = name => @identity.object_field(metadata, name)
  guard model_content_text(get("content_cid")) is Some(content_cid) &&
    valid_cid(content_cid) &&
    model_content_integer(get("size_bytes")) is Some(size_bytes) &&
    model_content_text(get("data_classification")) is Some(classification) &&
    model_content_text(get("effective_data_policy_cid")) is Some(policy_cid) &&
    valid_cid(policy_cid) &&
    model_content_text(get("media_type")) == Some(media) &&
    model_content_text(get("capture_authority")) == Some("read_content") &&
    get("truncated") is Some(@identity.Bool(false)) else {
    return Err(Metadata)
  }
  let input = {
    request,
    role,
    item,
    reference,
    dependency,
    media_type: media,
    content_cid,
    size_bytes,
    classification,
    policy_cid,
  }
  let payload = model_media_payload(input)
  if @decode.text(@decode.lookup(payload, "media_type").unwrap()) != Ok(media) {
    return Err(MediaType)
  }
  if size_bytes >
    @decode.safe_integer(@decode.lookup(payload, "max_bytes").unwrap()).unwrap() {
    return Err(ByteLimit)
  }
  Ok(Some(input))
}

///|
fn model_media_contains(
  object : @decode.ObjectView,
  name : String,
  expected : String,
) -> Bool {
  let list = @decode.lookup(object, name).unwrap()
  for index in 0..<@decode.array_length(list).unwrap() {
    if @decode.text(@decode.element_at(list, index).unwrap()) == Ok(expected) {
      return true
    }
  }
  false
}

///|
fn model_media_count_allowed(
  object : @decode.ObjectView,
  name : String,
  actual : Int64?,
) -> Bool {
  let limit = @decode.lookup(object, name).unwrap()
  if @decode.is_null(limit) {
    return actual is None
  }
  actual is Some(count) &&
  count > 0L &&
  count <= @decode.safe_integer(limit).unwrap()
}

///|
/// Physical observations come from the installed adapter, not metadata MIME
/// guesses. current checks that same retained payload, scope and Store custody.
/// The common dispatch egress Owner still supplies authorization separately.
pub fn start_model_content_byte_check(
  input : ModelContentInput,
  region : String,
  egress_scope_cid : String,
  pages : Int64?,
  frames : Int64?,
  current : () -> Bool,
) -> Result[ModelContentByteCheck, ModelContentIssue] {
  if !@admitted.reference_available(input.reference) || !current() {
    return Err(ReferenceUnavailable)
  }
  let payload = model_media_payload(input)
  if !model_media_contains(payload, "classifications", input.classification) {
    return Err(Classification)
  }
  if !model_media_contains(payload, "regions", region) {
    return Err(Region)
  }
  if @decode.text(@decode.lookup(payload, "egress_scope_cid").unwrap()) !=
    Ok(egress_scope_cid) {
    return Err(EgressScope)
  }
  if !model_media_count_allowed(payload, "max_pages", pages) {
    return Err(PageLimit)
  }
  if !model_media_count_allowed(payload, "max_frames", frames) {
    return Err(FrameLimit)
  }
  Ok({
    input,
    hasher: @sha.hasher(),
    current,
    region,
    egress_scope_cid,
    pages,
    frames,
    bytes: 0L,
    closed: false,
  })
}

///|
/// One bounded physical preparation unit, with an independent 256-byte cap.
/// Return the actual byte work; callers must not hide repeated updates inside
/// one unbounded cursor callback or rebuild bytes after admission.
pub fn update_model_content_bytes(
  check : ModelContentByteCheck,
  bytes : Bytes,
) -> Result[Int, ModelContentIssue] {
  if check.closed {
    return Err(Closed)
  }
  if bytes.length() > 256 {
    return Err(ChunkLimit)
  }
  if !@admitted.reference_available(check.input.reference) || !(check.current)() {
    check.closed = true
    return Err(ReferenceUnavailable)
  }
  if bytes.length().to_int64() > check.input.size_bytes - check.bytes {
    check.closed = true
    return Err(ByteLimit)
  }
  @sha.update(check.hasher, bytes) catch {
    _ => {
      check.closed = true
      return Err(ContentIdentity)
    }
  }
  check.bytes += bytes.length().to_int64()
  Ok(bytes.length())
}

///|
pub fn finish_model_content_bytes(
  check : ModelContentByteCheck,
) -> Result[ModelContentAdmission, ModelContentIssue] {
  if check.closed {
    return Err(Closed)
  }
  check.closed = true
  if !@admitted.reference_available(check.input.reference) || !(check.current)() {
    return Err(ReferenceUnavailable)
  }
  if check.bytes != check.input.size_bytes {
    return Err(ContentIdentity)
  }
  let digest = @sha.finish_hex(check.hasher) catch {
    _ => return Err(ContentIdentity)
  }
  if "sha256:" + digest != check.input.content_cid {
    return Err(ContentIdentity)
  }
  Ok({
    input: check.input,
    current: check.current,
    region: check.region,
    egress_scope_cid: check.egress_scope_cid,
    pages: check.pages,
    frames: check.frames,
  })
}

///|
pub fn model_content_admission_current(value : ModelContentAdmission) -> Bool {
  @admitted.reference_available(value.input.reference) && (value.current)()
}

///|
pub fn model_content_input_description(
  input : ModelContentInput,
) -> (String, String, String, Int64, String) {
  (
    @admitted.reference_wire(input.reference),
    input.media_type,
    input.content_cid,
    input.size_bytes,
    input.policy_cid,
  )
}

///|
// Each non-null original occurrence needs its own role/index binding. Equal
// envelopes and byte CIDs cannot substitute another request or issuer token.
fn model_content_admissions_match(
  request : ModelRequest,
  attachments : Array[ModelContentAdmission],
  wire_bytes : Int64,
) -> Result[Unit, ModelContentIssue] {
  let ordinal = Ref(0)
  let charged_bytes = Ref(0L)
  let check = (value : @admitted.Value, role : String, item : Int) => {
    if value is @admitted.Null {
      return Ok(())
    }
    guard value is @admitted.Reference(reference) &&
      @admitted.reference_content_metadata(reference) is Some(_) &&
      attachments.get(ordinal.val) is Some(admission) &&
      physical_equal(admission.input.request, request) &&
      admission.input.role == role &&
      admission.input.item == item &&
      physical_equal(admission.input.reference, reference) else {
      return Err(Request)
    }
    if !model_content_admission_current(admission) {
      return Err(ReferenceUnavailable)
    }
    // The retained hash/check/admission metadata shares the already
    // reserved request envelope, not another free physical workspace.
    let bytes = admission.input.size_bytes + 128L
    if bytes > wire_bytes - charged_bytes.val {
      return Err(ByteLimit)
    }
    charged_bytes.val += bytes
    ordinal.val += 1
    Ok(())
  }
  for (role, checked) in request.inputs {
    match checked.value {
      @admitted.Reference(_) =>
        match check(checked.value, role, -1) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
      @admitted.Array(items) => {
        // The installed profile only permits direct or finite homogeneous
        // Content arrays. Ordinary scalar arrays create no attachment work.
        guard checked.contract.shape is @contract.Array(item, ..) &&
          item.shape is @contract.ContentRef(_) else {
          continue
        }
        for index in 0..<@admitted.element_count(items) {
          match
            check(@admitted.element_at(items, index).unwrap(), role, index) {
            Err(issue) => return Err(issue)
            Ok(_) => ()
          }
        }
      }
      _ => continue
    }
  }
  if ordinal.val != attachments.length() {
    return Err(Request)
  }
  Ok(())
}

///|
fn model_content_admissions_current(
  attachments : Array[ModelContentAdmission],
) -> Bool {
  for admission in attachments {
    if !model_content_admission_current(admission) {
      return false
    }
  }
  true
}

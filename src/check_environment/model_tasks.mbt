///|
pub(all) struct ModelTaskLimits {
  bodies : Limits
  contracts : @value_contract.Limits
  max_work : Int
}

///|
pub(all) enum ModelTaskIssueKind {
  InvalidLimits
  TaskLimit
  BodyLimit
  WorkLimit
  InvalidBody
  IdentityMismatch
  InputSchemaMismatch
  OutputSchemaMismatch
  InvalidValueContract(@value_contract.AdmissionError)
  InvalidObjectContract
  DuplicateSelector(String)
  UnknownSelector(String)
  ReferenceMismatch
} derive(Eq, Debug)

///|
pub(all) struct ModelTaskIssue {
  kind : ModelTaskIssueKind
  source : @decode.Cursor?
}

///|
pub struct ModelGeneration {
  temperature : Double
  top_p : Double
  max_output_tokens : Int64
  seed_requested : Int64?
}

///|
priv struct ModelDataHandling {
  cid : String
  classifications : Array[DataClassification]
  regions : Array[String]
  provider_retention : Bool
}

///|
struct ModelTaskContract {
  item : Member
  cid : String
  task_id : String
  version : String
  connector : String
  model : String
  prompt : String
  input_schema_cid : String
  output_schema_cid : String
  input : @value_contract.Contract
  output : @value_contract.Contract
  generation : ModelGeneration
  data_handling : ModelDataHandling
  max_items : Int64?
}

///|
struct ModelTasks {
  environment : WireEnvironment
  entries : Array[ModelTaskContract]
  selectors : Map[String, Int]
  bytes : Int
  nodes : Int
  work : Int
  contract_nodes : Int
  contract_text : Int
}

///|
priv struct ModelTaskBudget {
  limits : ModelTaskLimits
  mut work : Int
  mut contract_nodes : Int
  mut contract_text : Int
}

///|
priv suberror ModelTaskStop {
  ModelTaskStop(ModelTaskIssue)
}

///|
fn[T] model_task_fail(
  kind : ModelTaskIssueKind,
  source : @decode.Cursor,
) -> T raise ModelTaskStop {
  raise ModelTaskStop({ kind, source: Some(source), })
}

///|
fn model_task_charge(
  b : ModelTaskBudget,
  amount : Int,
  source : @decode.Cursor,
) -> Unit raise ModelTaskStop {
  if amount < 0 || amount > b.limits.max_work - b.work {
    model_task_fail(WorkLimit, source)
  }
  b.work += amount
}

///|
fn model_task_object(
  root : @decode.Cursor,
  names : Array[String],
  b : ModelTaskBudget,
) -> @decode.ObjectView raise ModelTaskStop {
  let count = match @decode.object_length(root) {
    Some(n) => n
    None => model_task_fail(InvalidBody, root)
  }
  model_task_charge(b, count, root)
  for i in 0..<count {
    let (name, child) = @decode.field_at(root, i).unwrap()
    model_task_charge(b, name.length(), child)
  }
  match @decode.closed_object(root, names) {
    Ok(v) => v
    Err(_) => model_task_fail(InvalidBody, root)
  }
}

///|
fn model_task_required(
  o : @decode.ObjectView,
  name : String,
  root : @decode.Cursor,
) -> @decode.Cursor raise ModelTaskStop {
  match @decode.required(o, name) {
    Ok(v) => v
    Err(_) => model_task_fail(InvalidBody, root)
  }
}

///|
fn model_task_text(
  source : @decode.Cursor,
  b : ModelTaskBudget,
) -> String raise ModelTaskStop {
  let text = match @decode.text(source) {
    Ok(v) => v
    Err(_) => model_task_fail(InvalidBody, source)
  }
  model_task_charge(b, text.length(), source)
  if text.is_empty() {
    model_task_fail(InvalidBody, source)
  }
  text
}

///|
fn model_task_string(
  o : @decode.ObjectView,
  name : String,
  root : @decode.Cursor,
  b : ModelTaskBudget,
) -> String raise ModelTaskStop {
  model_task_text(model_task_required(o, name, root), b)
}

///|
fn model_task_cid(
  o : @decode.ObjectView,
  name : String,
  root : @decode.Cursor,
  b : ModelTaskBudget,
) -> String raise ModelTaskStop {
  let cid = model_task_string(o, name, root, b)
  if cid.length() != 71 || !cid.has_prefix("sha256:") {
    model_task_fail(InvalidBody, root)
  }
  for i in 7..<71 {
    let c = cid[i].to_int()
    if !((c >= 48 && c <= 57) || (c >= 97 && c <= 102)) {
      model_task_fail(InvalidBody, root)
    }
  }
  cid
}

///|
fn model_task_integer(
  source : @decode.Cursor,
  positive : Bool,
  b : ModelTaskBudget,
) -> Int64 raise ModelTaskStop {
  model_task_charge(b, 1, source)
  let n = match @decode.safe_integer(source) {
    Ok(v) => v
    Err(_) => model_task_fail(InvalidBody, source)
  }
  if positive && n <= 0L {
    model_task_fail(InvalidBody, source)
  }
  n
}

///|
fn model_task_generation(
  root : @decode.Cursor,
  b : ModelTaskBudget,
) -> ModelGeneration raise ModelTaskStop {
  let o = model_task_object(
    root,
    ["temperature", "top_p", "max_output_tokens", "seed_requested"],
    b,
  )
  let t = model_task_required(o, "temperature", root)
  let p = model_task_required(o, "top_p", root)
  model_task_charge(b, 2, root)
  let temperature = match @decode.finite_number(t) {
    Ok(v) => v
    Err(_) => model_task_fail(InvalidBody, t)
  }
  let top_p = match @decode.finite_number(p) {
    Ok(v) => v
    Err(_) => model_task_fail(InvalidBody, p)
  }
  if top_p <= 0.0 || top_p > 1.0 {
    model_task_fail(InvalidBody, p)
  }
  let max_output_tokens = model_task_integer(
    model_task_required(o, "max_output_tokens", root),
    true,
    b,
  )
  let seed_requested = match @decode.lookup(o, "seed_requested") {
    Some(c) => Some(model_task_integer(c, false, b))
    None => None
  }
  { temperature, top_p, max_output_tokens, seed_requested, }
}

///|
fn model_task_handling(
  root : @decode.Cursor,
  b : ModelTaskBudget,
) -> ModelDataHandling raise ModelTaskStop {
  let o = model_task_object(
    root,
    [
      "contract_cid", "accepted_classifications", "training_use", "retention", "allowed_regions",
    ],
    b,
  )
  let cid = model_task_cid(o, "contract_cid", root, b)
  if model_task_string(o, "training_use", root, b) != "forbidden" {
    model_task_fail(InvalidBody, root)
  }
  let retention = model_task_string(o, "retention", root, b)
  if retention != "none" && retention != "provider_contract" {
    model_task_fail(InvalidBody, root)
  }
  let c = model_task_required(o, "accepted_classifications", root)
  let count = match @decode.array_length(c) {
    Some(n) if n > 0 => n
    _ => model_task_fail(InvalidBody, c)
  }
  // Reserve finite list work before growing either private collection.
  model_task_charge(b, count, c)
  let classifications = []
  for i in 0..<count {
    let value = @decode.element_at(c, i).unwrap()
    let name = model_task_text(value, b)
    let classification = match name {
      "public" => Public
      "internal" => Internal
      "confidential" => Confidential
      "restricted" => Restricted
      _ => model_task_fail(InvalidBody, value)
    }
    // At most four classifications; there is no unbounded quadratic search.
    if classifications.contains(classification) {
      model_task_fail(InvalidBody, value)
    }
    classifications.push(classification)
  }
  let r = model_task_required(o, "allowed_regions", root)
  let count = match @decode.array_length(r) {
    Some(n) if n > 0 => n
    _ => model_task_fail(InvalidBody, r)
  }
  model_task_charge(b, count, r)
  let regions = []
  let seen : Map[String, Bool] = Map([])
  for i in 0..<count {
    let value = @decode.element_at(r, i).unwrap()
    let name = model_task_text(value, b)
    if seen.contains(name) {
      model_task_fail(InvalidBody, value)
    }
    seen[name] = true
    regions.push(name)
  }
  {
    cid,
    classifications,
    regions,
    provider_retention: retention == "provider_contract",
  }
}

///|
fn model_task_value_contract(
  root : @decode.Cursor,
  item : Member,
  b : ModelTaskBudget,
) -> @value_contract.Contract raise ModelTaskStop {
  // Reserve the same conservative subtree bound before typed reconstruction;
  // a hash reservation does not exempt this separate traversal from work.
  model_task_charge(b, item.entry.bytes, root)
  model_task_charge(b, item.entry.nodes, root)
  let limits = {
    ..b.limits.contracts,
    max_nodes: b.limits.contracts.max_nodes - b.contract_nodes,
    max_text_bytes: b.limits.contracts.max_text_bytes - b.contract_text,
  }
  let (contract, nodes, text) = match
    @value_contract.read_checked_usage(root, limits) {
    Ok(v) => v
    Err(e) => model_task_fail(InvalidValueContract(e), root)
  }
  b.contract_nodes += nodes
  b.contract_text += text
  if contract.nullable || !(contract.shape is @value_contract.Object(_)) {
    model_task_fail(InvalidObjectContract, root)
  }
  contract
}

///|
fn model_task_hash(
  root : @decode.Cursor,
  omitted : String?,
  item : Member,
  b : ModelTaskBudget,
) -> String raise ModelTaskStop {
  // The full member is a conservative bound for every subset hash. Admission
  // work includes emission, not only the fields inspected by semantic checks.
  model_task_charge(b, item.entry.bytes, root)
  model_task_charge(b, item.entry.nodes, root)
  try {
    let writer = @encode.hashing_writer(
      item.entry.bytes,
      item.entry.nodes,
      b.limits.bodies.max_depth,
    )
    emit_except(root, writer, omitted)
    let (hex, _, _) = @encode.finish_hash_usage(writer)
    "sha256:" + hex
  } catch {
    _ => model_task_fail(BodyLimit, root)
  }
}

///|
fn model_task_read(
  item : Member,
  b : ModelTaskBudget,
) -> ModelTaskContract raise ModelTaskStop {
  let root = member_body(item)
  let o = model_task_object(
    root,
    [
      "schema", "task_id", "version", "connector_id", "task_kind", "authored_model_selector",
      "prompt_template_cid", "input_schema_cid", "input_contract", "output_schema_cid",
      "output_contract", "generation_config", "tool_policy", "retrieval_policy",
      "streaming", "data_handling", "max_items", "contract_cid",
    ],
    b,
  )
  if model_task_string(o, "schema", root, b) != "actql.model_task/0.1" ||
    model_task_string(o, "task_kind", root, b) != "structured_generate" ||
    model_task_string(o, "tool_policy", root, b) != "none" ||
    model_task_string(o, "retrieval_policy", root, b) != "none" {
    model_task_fail(InvalidBody, root)
  }
  let streaming = model_task_required(o, "streaming", root)
  model_task_charge(b, 1, streaming)
  if @decode.boolean(streaming) != Ok(false) {
    model_task_fail(InvalidBody, streaming)
  }
  let task_id = model_task_string(o, "task_id", root, b)
  if !task_id.has_prefix("model-task:") {
    model_task_fail(InvalidBody, root)
  }
  let version = model_task_string(o, "version", root, b)
  let connector = model_task_string(o, "connector_id", root, b)
  let model = model_task_string(o, "authored_model_selector", root, b)
  let prompt = model_task_cid(o, "prompt_template_cid", root, b)
  let cid = model_task_cid(o, "contract_cid", root, b)
  if model_task_hash(root, Some("contract_cid"), item, b) != cid {
    model_task_fail(IdentityMismatch, root)
  }
  let input_source = model_task_required(o, "input_contract", root)
  let input_schema_cid = model_task_cid(o, "input_schema_cid", root, b)
  if model_task_hash(input_source, None, item, b) != input_schema_cid {
    model_task_fail(InputSchemaMismatch, input_source)
  }
  let input = model_task_value_contract(input_source, item, b)
  let output_source = model_task_required(o, "output_contract", root)
  let output_schema_cid = model_task_cid(o, "output_schema_cid", root, b)
  if model_task_hash(output_source, None, item, b) != output_schema_cid {
    model_task_fail(OutputSchemaMismatch, output_source)
  }
  let output = model_task_value_contract(output_source, item, b)
  let generation = model_task_generation(
    model_task_required(o, "generation_config", root),
    b,
  )
  let data_handling = model_task_handling(
    model_task_required(o, "data_handling", root),
    b,
  )
  let max_items = match @decode.lookup(o, "max_items") {
    None => None
    Some(c) => Some(model_task_integer(c, true, b))
  }
  {
    item,
    cid,
    task_id,
    version,
    connector,
    model,
    prompt,
    input_schema_cid,
    output_schema_cid,
    input,
    output,
    generation,
    data_handling,
    max_items,
  }
}

///|
/// Admits every supplied ModelTask, including unused declarations. This proves
/// typed contract and environment identity, not prompt availability, Connector
/// authority, execution-policy admission or permission to dispatch a model.
pub fn check_model_tasks(
  environment : WireEnvironment,
  limits : ModelTaskLimits,
) -> Result[ModelTasks, ModelTaskIssue] {
  if limits.max_work < 0 ||
    limits.bodies.max_members < 0 ||
    limits.bodies.max_bytes < 0 ||
    limits.bodies.max_nodes < 0 ||
    limits.bodies.max_depth < 0 ||
    limits.contracts.max_nodes < 0 ||
    limits.contracts.max_depth < 0 ||
    limits.contracts.max_text_bytes < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  let count = member_count(environment, ModelTaskContracts)
  if count > limits.bodies.max_members {
    return Err({ kind: TaskLimit, source: None, })
  }
  let b = { limits, work: 0, contract_nodes: 0, contract_text: 0, }
  let entries = []
  let selectors : Map[String, Int] = Map([])
  let mut bytes = 0
  let mut nodes = 0
  try {
    for i in 0..<count {
      let item = member_at(environment, ModelTaskContracts, i).unwrap()
      if item.entry.bytes > limits.bodies.max_bytes - bytes ||
        item.entry.nodes > limits.bodies.max_nodes - nodes {
        model_task_fail(BodyLimit, member_body(item))
      }
      bytes += item.entry.bytes
      nodes += item.entry.nodes
      model_task_charge(b, 1, member_body(item))
      let task = model_task_read(item, b)
      if selectors.contains(task.task_id) {
        model_task_fail(DuplicateSelector(task.task_id), member_body(item))
      }
      selectors[task.task_id] = entries.length()
      entries.push(task)
    }
    Ok({
      environment,
      entries,
      selectors,
      bytes,
      nodes,
      work: b.work,
      contract_nodes: b.contract_nodes,
      contract_text: b.contract_text,
    })
  } catch {
    ModelTaskStop(e) => Err(e)
  }
}

///|
pub fn model_tasks_environment(v : ModelTasks) -> WireEnvironment {
  v.environment
}

///|
pub fn model_tasks_usage(v : ModelTasks) -> (Int, Int, Int, Int, Int, Int) {
  (
    v.bytes,
    v.nodes,
    v.work,
    v.contract_nodes,
    v.contract_text,
    v.entries.length(),
  )
}

///|
pub fn model_task_at(v : ModelTasks, i : Int) -> ModelTaskContract? {
  v.entries.get(i)
}

///|
pub fn resolve_model_task(
  v : ModelTasks,
  selector : String,
) -> Result[ModelTaskContract, ModelTaskIssue] {
  match v.selectors.get(selector) {
    Some(i) => Ok(v.entries[i])
    None => Err({ kind: UnknownSelector(selector), source: None, })
  }
}

///|
/// Equal-looking members from a separately admitted environment are not owners.
pub fn model_task_for(v : ModelTasks, item : Member) -> ModelTaskContract? {
  if member_section(item) != ModelTaskContracts ||
    !physical_equal(member_environment(item), v.environment) {
    return None
  }
  v.entries.get(member_index(item))
}

///|
pub fn model_task_member(v : ModelTaskContract) -> Member {
  v.item
}

///|
pub fn model_task_identity(v : ModelTaskContract) -> (String, String, String) {
  (v.task_id, v.version, v.cid)
}

///|
pub fn model_task_connector(v : ModelTaskContract) -> String {
  v.connector
}

///|
pub fn model_task_model_selector(v : ModelTaskContract) -> String {
  v.model
}

///|
pub fn model_task_prompt_cid(v : ModelTaskContract) -> String {
  v.prompt
}

///|
pub fn model_task_schema_cids(v : ModelTaskContract) -> (String, String) {
  (v.input_schema_cid, v.output_schema_cid)
}

///|
pub fn model_task_input(v : ModelTaskContract) -> @value_contract.Contract {
  v.input
}

///|
pub fn model_task_output(v : ModelTaskContract) -> @value_contract.Contract {
  v.output
}

///|
pub fn model_task_generation_config(v : ModelTaskContract) -> ModelGeneration {
  v.generation
}

///|
pub fn model_task_max_items(v : ModelTaskContract) -> Int64? {
  v.max_items
}

///|
pub fn model_task_data_handling_cid(v : ModelTaskContract) -> String {
  v.data_handling.cid
}

///|
/// Contract compatibility only. Host-owned current egress and account admission
/// remain mandatory; an author-supplied classification is not authority.
pub fn model_task_accepts_classification(
  v : ModelTaskContract,
  classification : DataClassification,
) -> Bool {
  classification != Unknown &&
  v.data_handling.classifications.contains(classification)
}

///|
pub fn model_task_region_count(v : ModelTaskContract) -> Int {
  v.data_handling.regions.length()
}

///|
pub fn model_task_region_at(v : ModelTaskContract, index : Int) -> String? {
  v.data_handling.regions.get(index)
}

///|
pub fn model_task_provider_retention(v : ModelTaskContract) -> Bool {
  v.data_handling.provider_retention
}

///|
pub(all) enum PoolMethod {
  Mean
  Sum
  Max
} derive(Eq, Debug)

///|
struct PoolOptions {
  source : @decode.Cursor
  vector : @row.FieldName?
  by : Array[@row.FieldName]
  reduction : PoolMethod
  output_id : String?
  usage : Usage
}

///|
pub fn read_pool_options(
  source : @decode.Cursor,
  limits : Limits,
) -> Result[PoolOptions, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      @checking.fail(source, InvalidLimits)
    }
    let b : @checking.Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    @checking.scan(b, source)
    let root = @checking.decoded(
      @decode.closed_object(source, ["vector", "by", "method", "output_id"]),
    )
    let vector = match @decode.lookup(root, "vector") {
      Some(at) => Some(@checking.role_name(at))
      None => None
    }
    let by_at = @checking.decoded(@decode.required(root, "by"))
    let items = @checking.decoded(@decode.elements(by_at))
    if items.is_empty() {
      @checking.fail(by_at, InvalidBody)
    }
    @checking.spend(b, by_at, items.length())
    let by : Array[@row.FieldName] = []
    let seen : Map[String, Bool] = Map([])
    for at in items {
      let name = @checking.role_name(at)
      let spelling = @row.reference_name(name)
      if seen.contains(spelling) {
        @checking.fail(at, DuplicatePoolField(name))
      }
      seen[spelling] = true
      by.push(name)
    }
    let at = @checking.decoded(@decode.required(root, "method"))
    let reduction = match @checking.decoded(@decode.text(at)) {
      "mean" => Mean
      "sum" => Sum
      "max" => Max
      _ => @checking.fail(at, InvalidBody)
    }
    let output_id = match @decode.lookup(root, "output_id") {
      None => None
      Some(at) => {
        if by.length() != 1 {
          @checking.fail(at, InvalidBody)
        }
        let name = @checking.decoded(@decode.text(at))
        // Generated names use the same authored-name contract as object fields.
        match
          @contract.object_contract(
            [(name, @contract.primitive(NumberType, nullable=false))],
            nullable=false,
            max_fields=1,
            max_name_bytes=limits.max_text_bytes,
          ) {
          Ok(_) => ()
          Err(_) => @checking.fail(at, InvalidBody)
        }
        Some(name)
      }
    }
    Ok({
      source,
      vector,
      by,
      reduction,
      output_id,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    @checking.Stop(e) => Err(e)
  }
}

///|
pub fn pool_source(c : PoolOptions) -> @decode.Cursor {
  c.source
}

///|
pub fn pool_vector(c : PoolOptions) -> @row.FieldName? {
  c.vector
}

///|
pub fn pool_group_fields(c : PoolOptions) -> Array[@row.FieldName] {
  c.by.copy()
}

///|
pub fn pool_method(c : PoolOptions) -> PoolMethod {
  c.reduction
}

///|
pub fn pool_output_id(c : PoolOptions) -> String? {
  c.output_id
}

///|
pub fn pool_options_usage(c : PoolOptions) -> Usage {
  c.usage
}

///|
pub(all) enum PoolObligation {
  ValidateDeclaredPoolKey(@evidence.KeyObligation)
  JournalPoolMemberIdentity
  EncodePoolMemberKeyByScalarLengths
  OrderPoolMembersByEncodedIdentity
  AdmitPoolVectorComponents
  ValidatePoolMemberIdentityGlobally
  MatchPoolDimensions
  OrderPoolMembersByIdentity
  QuantizeBeforeAndAfterPoolFold
  EvaluateDeterministicPoolFold
  OrderPoolGroupsByIdentity
  ValidatePositiveSafeMemberCounts
  ResolvePoolResources
  ResolvePoolProfile
} derive(Eq, Debug)

///|
struct CheckedPool {
  options : PoolOptions
  members : @carrier.Vectors
  output : @carrier.Carrier
  usage : Usage
  declaration : @evidence.KeyedRelation?
  encoded_member : Bool
}

///|
/// Checks the Vectors alternative; Relation pooling also needs retained key evidence.
pub fn check_pool_vectors(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedPool, Issue] {
  try {
    let options = match read_pool_options(source, limits) {
      Ok(c) => c
      Err(e) => raise @checking.Stop(e)
    }
    let u = options.usage
    let b : @checking.Budget = {
      limits,
      work: limits.max_work - u.work,
      nodes: limits.max_nodes - u.nodes,
      text: limits.max_text_bytes - u.text_bytes,
    }
    let members = match input {
      @carrier.VectorValue(v) => v
      _ => @checking.fail(source, WrongCarrier(@carrier.kind(input)))
    }
    let root = @checking.decoded(@decode.open_object(source))
    let vector = @carrier.vector_components(members)
    if options.vector is Some(name) && name != vector.name {
      @checking.fail(
        @decode.lookup(root, "vector").unwrap(),
        InvalidRole(@carrier.InvalidRole(name)),
      )
    }
    let records = @carrier.vector_records(members)
    let groups = @checking.decoded(
      @decode.elements(@checking.decoded(@decode.required(root, "by"))),
    )
    @checking.spend(b, source, options.by.length() + 2)
    let fields : Array[(@row.FieldName, @contract.Contract?)] = []
    let names : Map[String, Bool] = Map([])
    for i in 0..<options.by.length() {
      let name = options.by[i]
      let at = groups[i]
      let c = match @carrier.lookup(records, name) {
        Present({ contract: Some(c), .. }) => c
        _ => @checking.fail(at, InvalidRole(@carrier.UnknownRole(name)))
      }
      if c.nullable || !@contract.key_comparable(c, c) {
        @checking.fail(at, InvalidRole(@carrier.InvalidRole(name)))
      }
      let spelling = @row.reference_name(name)
      @checking.charge(b, at, spelling)
      names[spelling] = true
      fields.push((name, Some(c)))
    }
    let count = @row.Unqualified("member_count")
    let number = @contract.primitive(NumberType, nullable=false)
    if b.nodes <= 0 {
      @checking.fail(source, BudgetExceeded)
    }
    b.nodes -= 1
    for (name, c) in [(vector.name, vector.contract.unwrap()), (count, number)] {
      let spelling = @row.reference_name(name)
      if names.contains(spelling) {
        @checking.fail(source, OutputCollision(spelling))
      }
      names[spelling] = true
      @checking.charge(b, source, spelling)
      fields.push((name, Some(c)))
    }
    let ids = match options.output_id {
      None => options.by.copy()
      Some(output_name) => {
        let name = @row.Unqualified(output_name)
        if name != options.by[0] {
          let at = @decode.lookup(root, "output_id").unwrap()
          if names.contains(output_name) {
            @checking.fail(at, OutputCollision(output_name))
          }
          @checking.spend(b, at, 1)
          @checking.charge(b, at, output_name)
          fields.push((name, fields[0].1))
        }
        [name]
      }
    }
    let rows = match
      @carrier.rows(
        fields,
        field_set=Closed,
        max_fields=fields.length(),
        max_name_bytes=limits.max_text_bytes,
      ) {
      Ok(rows) => rows
      Err(_) => @checking.fail(source, BudgetExceeded)
    }
    let output = match
      @carrier.vectors(
        rows,
        ids~,
        components=vector.name,
        max_identity_fields=ids.length(),
      ) {
      Ok(v) => v
      Err(e) => @checking.fail(source, InvalidRole(e))
    }
    Ok({
      options,
      members,
      output,
      declaration: None,
      encoded_member: false,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    @checking.Stop(e) => Err(e)
  }
}

///|
pub fn pooled_output(c : CheckedPool) -> @carrier.Carrier {
  c.output
}

///|
pub fn pooled_options(c : CheckedPool) -> PoolOptions {
  c.options
}

///|
pub fn pool_member_vectors(c : CheckedPool) -> @carrier.Vectors {
  c.members
}

///|
pub fn pooled_usage(c : CheckedPool) -> Usage {
  c.usage
}

///|
pub fn pool_pending(c : CheckedPool) -> Array[PoolObligation] {
  let out = []
  pool_pending_each(c, item => out.push(item))
  out
}

///|
// One bounded enumeration rule shared by copied and indexed reads.
fn pool_pending_each(c : CheckedPool, emit : (PoolObligation) -> Unit) -> Unit {
  emit(AdmitPoolVectorComponents)
  emit(ValidatePoolMemberIdentityGlobally)
  emit(MatchPoolDimensions)
  emit(QuantizeBeforeAndAfterPoolFold)
  emit(EvaluateDeterministicPoolFold)
  emit(OrderPoolGroupsByIdentity)
  emit(ValidatePositiveSafeMemberCounts)
  emit(ResolvePoolResources)
  emit(ResolvePoolProfile)
  if c.declaration is Some(key) {
    for i in 0..<@evidence.key_pending_count(key) {
      let obligation = @evidence.key_pending_at(key, i).unwrap()
      emit(ValidateDeclaredPoolKey(obligation))
    }
    emit(JournalPoolMemberIdentity)
  }
  if c.encoded_member {
    emit(EncodePoolMemberKeyByScalarLengths)
    emit(OrderPoolMembersByEncodedIdentity)
  } else {
    emit(OrderPoolMembersByIdentity)
  }
}

///|
/// O(1), independent of input data size; no obligation array is materialized.
pub fn pool_pending_count(c : CheckedPool) -> Int {
  let mut count = 0
  pool_pending_each(c, _ => count += 1)
  count
}

///|
/// O(1), without copying the obligation array; invalid indices return None.
pub fn pool_pending_at(c : CheckedPool, index : Int) -> PoolObligation? {
  if index < 0 {
    return None
  }
  let mut count = 0
  let mut found = None
  pool_pending_each(c, item => {
    if count == index {
      found = Some(item)
    }
    count += 1
  })
  found
}

///|
/// Uses the immutable Relation bound to a retained key witness.
pub fn check_pool_relation(
  source : @decode.Cursor,
  input : @evidence.KeyedRelation,
  limits : Limits,
) -> Result[CheckedPool, Issue] {
  check_pool_keys(source, @evidence.singleton_key(input), limits)
}

///|
/// Selects the canonical eligible scalar key while retaining its admission origin.
pub fn check_pool_keys(
  source : @decode.Cursor,
  input : @evidence.KeySet,
  limits : Limits,
) -> Result[CheckedPool, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      @checking.fail(source, InvalidLimits)
    }
    let selection = match
      @evidence.select_key(source, input, ScalarIdentity, {
        max_work: limits.max_work,
        max_name_bytes: limits.max_text_bytes,
      }) {
      Ok(v) => v
      Err(_) => @checking.fail(source, BudgetExceeded)
    }
    guard selection.key is Some(key) else {
      @checking.fail(source, MissingEligiblePoolKey)
    }
    let checked = match
      check_pool_selected(source, key, {
        ..limits,
        max_work: limits.max_work - selection.work,
        max_text_bytes: limits.max_text_bytes - selection.name_bytes,
      }) {
      Ok(v) => v
      Err(e) => raise @checking.Stop(e)
    }
    Ok({
      ..checked,
      usage: {
        ..checked.usage,
        work: checked.usage.work + selection.work,
        text_bytes: checked.usage.text_bytes + selection.name_bytes,
      },
    })
  } catch {
    @checking.Stop(e) => Err(e)
  }
}

///|
fn check_pool_selected(
  source : @decode.Cursor,
  input : @evidence.KeyedRelation,
  limits : Limits,
) -> Result[CheckedPool, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      @checking.fail(source, InvalidLimits)
    }
    let b : @checking.Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    let root = @checking.decoded(@decode.open_object(source))
    let vector_at = @checking.decoded(@decode.required(root, "vector"))
    let components = @checking.role_name(vector_at)
    let rows = @evidence.keyed_records(input)
    let n = @evidence.key_field_count(input)
    @checking.spend(b, source, n + 1)
    let ids : Array[@row.FieldName] = []
    let mut direct_string = false
    for i in 0..<n {
      let field = @evidence.key_field_at(input, i).unwrap()
      @checking.charge(b, source, @row.reference_name(field.name))
      let c = match field.contract {
        Some(c) => c
        None =>
          @checking.fail(source, UnsupportedPoolMemberIdentity(field.name))
      }
      match c.shape {
        @contract.Text(_) => if n == 1 { direct_string = true }
        @contract.Number
        | @contract.Boolean
        | @contract.Date
        | @contract.Timestamp
        | @contract.Decimal(..) => ()
        _ => @checking.fail(source, UnsupportedPoolMemberIdentity(field.name))
      }
      ids.push(field.name)
    }
    if !direct_string {
      match @carrier.lookup(rows, Unqualified("__actql_vector_record_id")) {
        Absent => ()
        Unknown => @checking.fail(source, UnknownOutputFields)
        Present(_) =>
          @checking.fail(source, OutputCollision("__actql_vector_record_id"))
      }
    }
    let members = match
      @carrier.vectors(rows, ids~, components~, max_identity_fields=n) {
      Ok(v) => v
      Err(e) => @checking.fail(vector_at, InvalidRole(e))
    }
    let checked = match
      check_pool_vectors(source, members, {
        ..limits,
        max_work: b.work,
        max_nodes: b.nodes,
        max_text_bytes: b.text,
      }) {
      Ok(c) => c
      Err(e) => raise @checking.Stop(e)
    }
    Ok({
      ..checked,
      declaration: Some(input),
      encoded_member: !direct_string,
      usage: {
        work: limits.max_work - b.work + checked.usage.work,
        nodes: limits.max_nodes - b.nodes + checked.usage.nodes,
        text_bytes: limits.max_text_bytes - b.text + checked.usage.text_bytes,
      },
    })
  } catch {
    @checking.Stop(e) => Err(e)
  }
}

///|
pub fn pool_key_declaration(c : CheckedPool) -> @evidence.KeyedRelation? {
  c.declaration
}

///|
pub fn pool_encodes_member_key(c : CheckedPool) -> Bool {
  c.encoded_member
}

///|
pub(all) enum Issue {
  InvalidLimits
  BudgetExceeded
  InvalidInputType
  InputCeiling
  OutputCeiling
  ReplacementCeiling
  InvalidPatternMode
} derive(Eq, Debug)

///|
pub(all) enum Origin {
  ValueContract
  KnownValue
  RuntimePreflight
  DerivedOutput
} derive(Eq, Debug)

///|
struct Input {
  contract : @contract.Contract
  value : @value.CheckedValue?
  producer : Output?
  policy : @policy.Policy
  origin : Origin
  codepoints : Int64
  bytes : Int64
}

///|
/// These identify bound formulas, not independently validated expression nodes.
/// Some(length) is a resolved numeric literal; None is an unevaluated operand.
pub(all) enum Operation {
  SplitPart
  Substring(Double?)
  Utf8Truncate(Double?)
  TryNumber
  Nfkc
  CaseFold
  ParseTimestamp
  TryTimestamp
  FormatTimestamp(@timestamp.Pattern)
  RegexMatch
  RegexExtract
  RegexReplace(@replacement.Replacement)
}

///|
struct Output {
  input : Input
  operation : Operation
  contract : @contract.Contract
  bytes : Int64
  replacements : Int64?
}

///|
fn ceiling(p : @policy.Policy, field : String) -> Int64 {
  @policy.ceiling_value(@policy.ceiling(p, field).unwrap())
}

///|
fn admitted(
  contract : @contract.Contract,
  value : @value.CheckedValue?,
  policy : @policy.Policy,
  origin : Origin,
  points : Int64,
  bytes : Int64,
) -> Result[Input, Issue] {
  if points > ceiling(policy, "max_input_codepoints") ||
    bytes > ceiling(policy, "max_input_utf8_bytes") {
    return Err(InputCeiling)
  }
  Ok({
    contract,
    value,
    producer: None,
    policy,
    origin,
    codepoints: points,
    bytes,
  })
}

///|
/// Tighten known scalar/byte bounds against each other before Host comparison.
/// Unbounded text retains the selected runtime preflight ceilings, not evidence
/// that actual input already fits them. No field contract is silently clamped.
pub fn from_contract(
  contract : @contract.Contract,
  policy : @policy.Policy,
) -> Result[Input, Issue] {
  match contract.shape {
    @contract.Timestamp =>
      admitted(contract, None, policy, ValueContract, 24L, 24L)
    @contract.Text(bounds) => {
      let (points, bytes) = match
        (bounds.max_codepoints, bounds.max_utf8_bytes) {
        (Some(p), Some(b)) => (Int64::min(p, b), Int64::min(b, p * 4L))
        (Some(p), None) => (p, p * 4L)
        (None, Some(b)) => (b, b)
        (None, None) =>
          return admitted(
            contract,
            None,
            policy,
            RuntimePreflight,
            ceiling(policy, "max_input_codepoints"),
            ceiling(policy, "max_input_utf8_bytes"),
          )
      }
      admitted(contract, None, policy, ValueContract, points, bytes)
    }
    _ => Err(InvalidInputType)
  }
}

///|
/// A checked string/timestamp (including known null) supplies exact input extent.
/// Scalar counting is bounded by the caller before scanning the owned value.
pub fn from_value(
  value : @value.CheckedValue,
  policy : @policy.Policy,
  max_text_bytes~ : Int,
) -> Result[Input, Issue] {
  if max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  match value.contract.shape {
    @contract.Text(_) | @contract.Timestamp => ()
    _ => return Err(InvalidInputType)
  }
  let text = match value.value {
    @value.Null =>
      return admitted(value.contract, Some(value), policy, KnownValue, 0L, 0L)
    @value.Text(v) | @value.Timestamp(v) => v
    _ => return Err(InvalidInputType)
  }
  let bytes = match @scalar.admit_utf8_length(text, max_text_bytes) {
    Ok(n) => n.to_int64()
    Err(_) => return Err(BudgetExceeded)
  }
  let points = @scalar.unicode_scalar_count(text).unwrap().to_int64()
  admitted(value.contract, Some(value), policy, KnownValue, points, bytes)
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn multiply(a : Int64, b : Int64, cap : Int64) -> Int64 raise Stop {
  if a != 0L && b > cap / a {
    raise Stop(OutputCeiling)
  }
  a * b
}

///|
fn add(a : Int64, b : Int64, cap : Int64) -> Int64 raise Stop {
  if a > cap || b > cap - a {
    raise Stop(OutputCeiling)
  }
  a + b
}

///|
fn literal_limit(v : Double?) -> Int64? {
  match v {
    Some(n) if n >= 0.0 && !(n == 0.0 && 1.0 / n < 0.0) =>
      @scalar.read_safe_integer(n)
    _ => None
  }
}

///|
/// Derive the fixed portable bound law. Invalid/dynamic length operands do not
/// cause speculative evaluation or rejection: their demanded checks stay pending.
pub fn derive_output(
  input : Input,
  operation : Operation,
) -> Result[Output, Issue] {
  let timestamp = input.contract.shape is @contract.Timestamp
  if (operation is FormatTimestamp(_)) != timestamp {
    return Err(InvalidInputType)
  }
  let cap = ceiling(input.policy, "max_output_bytes")
  let mut bytes = input.bytes
  let mut points = input.codepoints
  let mut replacements = None
  let mut kind = @contract.StringType
  let mut nullable = input.contract.nullable
  try {
    match operation {
      Substring(limit) => {
        if literal_limit(limit) is Some(n) {
          bytes = Int64::min(bytes, 4L * n)
        }
        points = Int64::min(points, bytes)
      }
      Utf8Truncate(limit) => {
        if literal_limit(limit) is Some(n) {
          bytes = Int64::min(bytes, n)
        }
        points = Int64::min(points, bytes)
      }
      SplitPart | RegexExtract => {
        points = Int64::min(points, bytes)
        if operation is RegexExtract {
          nullable = true
        }
      }
      TryNumber => {
        bytes = 32L
        kind = @contract.NumberType
        nullable = true
      }
      RegexMatch => {
        bytes = 5L
        kind = @contract.BooleanType
      }
      ParseTimestamp | TryTimestamp => {
        bytes = 24L
        kind = @contract.TimestampType
        if operation is TryTimestamp {
          nullable = true
        }
      }
      FormatTimestamp(pattern) => {
        if @timestamp.mode(pattern) != @timestamp.Format {
          return Err(InvalidPatternMode)
        }
        bytes = @timestamp.value_width(pattern).to_int64()
        points = bytes
      }
      Nfkc | CaseFold => {
        let factor = if operation is Nfkc { 72L } else { 16L }
        bytes = multiply(points, factor, cap)
        points = bytes / 4L
      }
      RegexReplace(replacement) => {
        // A scalar sequence has at most codepoints+1 left-to-right match starts.
        let count = points + 1L
        if count > ceiling(input.policy, "max_replacements") {
          return Err(ReplacementCeiling)
        }
        replacements = Some(count)
        let stats = @replacement.stats(replacement)
        let captures = multiply(
          stats.capture_reference_count.to_int64(),
          bytes,
          cap,
        )
        let per_match = add(stats.literal_utf8_bytes.to_int64(), captures, cap)
        bytes = add(bytes, multiply(count, per_match, cap), cap)
        points = bytes
      }
    }
    if bytes > cap {
      return Err(OutputCeiling)
    }
    let contract = if kind == @contract.StringType {
      @contract.string_contract(
        nullable~,
        max_codepoints=Some(points),
        max_utf8_bytes=Some(bytes),
      ).unwrap()
    } else {
      @contract.primitive(kind, nullable~)
    }
    Ok({ input, operation, contract, bytes, replacements, })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn input_contract(v : Input) -> @contract.Contract {
  v.contract
}

///|
/// Consume a checked child's extents while retaining its exact derivation and
/// policy. Do not turn a runtime-dependent child into an independent fact.
pub fn from_output(v : Output) -> Result[Input, Issue] {
  match from_contract(v.contract, v.input.policy) {
    Err(e) => Err(e)
    Ok(input) => Ok({ ..input, producer: Some(v), origin: DerivedOutput, })
  }
}

///|
pub fn input_producer(v : Input) -> Output? {
  v.producer
}

///|
pub fn input_value(v : Input) -> @value.CheckedValue? {
  v.value
}

///|
pub fn input_policy(v : Input) -> @policy.Policy {
  v.policy
}

///|
pub fn input_origin(v : Input) -> Origin {
  v.origin
}

///|
pub fn input_extent(v : Input) -> (Int64, Int64) {
  (v.codepoints, v.bytes)
}

///|
pub fn output_input(v : Output) -> Input {
  v.input
}

///|
pub fn output_operation(v : Output) -> Operation {
  v.operation
}

///|
pub fn output_contract(v : Output) -> @contract.Contract {
  v.contract
}

///|
pub fn output_bytes(v : Output) -> Int64 {
  v.bytes
}

///|
pub fn output_replacements(v : Output) -> Int64? {
  v.replacements
}

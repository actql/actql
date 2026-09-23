///|
pub(all) enum Dependency {
  UnicodeData
  CompositionExclusions
  CaseFolding
  DerivedNormalizationProps
  NormalizationTest
  License
  TokenizerVectors
  NumericVectors
} derive(Eq, Debug)

///|
fn index(d : Dependency) -> Int {
  match d {
    UnicodeData => 0
    CompositionExclusions => 1
    CaseFolding => 2
    DerivedNormalizationProps => 3
    NormalizationTest => 4
    License => 5
    TokenizerVectors => 6
    NumericVectors => 7
  }
}

///|
fn dependencies() -> Array[Dependency] {
  [
    UnicodeData,
    CompositionExclusions,
    CaseFolding,
    DerivedNormalizationProps,
    NormalizationTest,
    License,
    TokenizerVectors,
    NumericVectors,
  ]
}

///|
pub(all) struct Limits {
  max_profile_bytes : Int
  max_dependency_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum Issue {
  InvalidLimits
  BudgetExceeded
  InvalidDependencySet
  MissingDependency(Dependency)
  DuplicateDependency(Dependency)
  DependencyMismatch(Dependency)
  IdentityMismatch
  InvalidJson
  InvalidBody
  InvalidDigest
  UnsupportedVersion
  UnsupportedLaw
  NoncanonicalArtifact
} derive(Eq, Debug)

///|
struct Profile {
  cid : String
  blobs : Array[Bytes]
  identities : Array[String]
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn[T] decoded(v : Result[T, @decode.Issue]) -> T raise Stop {
  match v {
    Ok(v) => v
    Err(_) => raise Stop(InvalidBody)
  }
}

///|
fn required(o : @decode.ObjectView, name : String) -> @decode.Cursor raise Stop {
  decoded(@decode.required(o, name))
}

///|
fn digest(at : @decode.Cursor, prefix~ : Bool) -> String raise Stop {
  let value = decoded(@decode.text(at))
  let raw = if prefix {
    if !value.has_prefix("sha256:") {
      raise Stop(InvalidDigest)
    }
    value[7:].to_owned()
  } else {
    value
  }
  if raw.length() != 64 {
    raise Stop(InvalidDigest)
  }
  for char in raw.to_array() {
    if !((char >= '0' && char <= '9') || (char >= 'a' && char <= 'f')) {
      raise Stop(InvalidDigest)
    }
  }
  "sha256:" + raw
}

///|
/// Pins come from an independently selected Check Environment. This establishes
/// bounded byte integrity and supported laws, not provenance or evaluator proof.
pub fn admit(
  bytes : Bytes,
  expected_cid : String,
  supplied : Array[(Dependency, Bytes)],
  limits : Limits,
) -> Result[Profile, Issue] {
  try {
    if limits.max_profile_bytes < 0 ||
      limits.max_dependency_bytes < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 {
      raise Stop(InvalidLimits)
    }
    if bytes.length() > limits.max_profile_bytes {
      raise Stop(BudgetExceeded)
    }
    if supplied.length() > 8 {
      raise Stop(InvalidDependencySet)
    }
    let slots : Array[Bytes?] = Array::make(8, None)
    let mut remaining = limits.max_dependency_bytes
    for (kind, data) in supplied {
      let i = index(kind)
      if slots[i] is Some(_) {
        raise Stop(DuplicateDependency(kind))
      }
      if data.length() > remaining {
        raise Stop(BudgetExceeded)
      }
      remaining -= data.length()
      slots[i] = Some(data)
    }
    for kind in dependencies() {
      if slots[index(kind)] is None {
        raise Stop(MissingDependency(kind))
      }
    }
    let cid = "sha256:" + @sha.hex(bytes)
    if cid != expected_cid {
      raise Stop(IdentityMismatch)
    }
    let node = match
      @source.parse_json_bytes(bytes, {
        max_input_bytes: limits.max_profile_bytes,
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
      }) {
      Ok(v) => v
      Err(e) =>
        match e.issue {
          InputLimit | NodeLimit | DepthLimit => raise Stop(BudgetExceeded)
          _ => raise Stop(InvalidJson)
        }
    }
    let c = match
      @decode.admit(node, {
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_string_bytes: limits.max_profile_bytes,
        max_total_string_bytes: limits.max_profile_bytes,
      }) {
      Ok(v) => v
      Err(_) => raise Stop(BudgetExceeded)
    }
    let o = decoded(
      @decode.closed_object(c, [
        "version", "unicode_version", "unicode_source_sha256", "tokenizer_law", "numeric_law",
        "tokenizer_vectors_bytes_cid", "numeric_vectors_bytes_cid",
      ]),
    )
    if decoded(@decode.text(required(o, "version"))) !=
      "actql-text-rank-profile/0.1" ||
      decoded(@decode.text(required(o, "unicode_version"))) != "16.0.0" {
      raise Stop(UnsupportedVersion)
    }
    if canonical_hash(required(o, "tokenizer_law"), limits) !=
      tokenizer_law_cid() ||
      canonical_hash(required(o, "numeric_law"), limits) != numeric_law_cid() {
      raise Stop(UnsupportedLaw)
    }
    let names = [
      "UnicodeData.txt", "CompositionExclusions.txt", "CaseFolding.txt", "DerivedNormalizationProps.txt",
      "NormalizationTest.txt", "LICENSE.txt",
    ]
    let source_pins = decoded(
      @decode.closed_object(required(o, "unicode_source_sha256"), names),
    )
    let pins : Array[String] = []
    for name in names {
      pins.push(digest(required(source_pins, name), prefix=false))
    }
    pins.push(digest(required(o, "tokenizer_vectors_bytes_cid"), prefix=true))
    pins.push(digest(required(o, "numeric_vectors_bytes_cid"), prefix=true))
    if canonical_hash(c, limits) != cid {
      raise Stop(NoncanonicalArtifact)
    }
    let blobs : Array[Bytes] = []
    for kind in dependencies() {
      let i = index(kind)
      let data = slots[i].unwrap()
      if "sha256:" + @sha.hex(data) != pins[i] {
        raise Stop(DependencyMismatch(kind))
      }
      blobs.push(data)
    }
    Ok({ cid, blobs, identities: pins, })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn cid(p : Profile) -> String {
  p.cid
}

///|
/// Bytes are immutable; the caller's dependency array is not retained.
pub fn dependency_bytes(p : Profile, kind : Dependency) -> Bytes {
  p.blobs[index(kind)]
}

///|
pub fn dependency_cid(p : Profile, kind : Dependency) -> String {
  p.identities[index(kind)]
}

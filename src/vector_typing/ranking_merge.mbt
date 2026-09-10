///|
pub(all) enum RankingObligation {
  ValidateCompleteRankingInputs
  ValidateUniqueQueryCandidatePerInput
  ValidatePositiveSafeContiguousRanks
  AuthenticateCapturedScoreDeclarations
  ValidateDeclaredScoreRanges
  ValidateBusinessTieAgreement
  ApplyRankWindowAfterAdmission
  EvaluateRankingPolicyWithFiniteIntermediates
  OrderRankingByScoreAndSemanticIdentity
  AssignFusedContiguousRanks
  ResolveRankingResources
  ResolveRankingProfile
  DeriveOutputScoreEnvelope
} derive(Eq, Debug)

///|
struct CheckedRanking {
  options : RankingOptions
  inputs : Array[RankingShape]
  output : @carrier.Carrier
  tuples : Map[String, Int]
  usage : Usage
}

///|
fn ranking_join(
  b : Budget,
  at : @decode.Cursor,
  name : @row.FieldName,
  a : @contract.Contract,
  z : @contract.Contract,
) -> @contract.Contract raise Stop {
  let work = [(a, z, 0)]
  let mut pairs = 0
  while work.pop() is Some((x, y, depth)) {
    spend(b, at, 1)
    if b.nodes <= 0 || depth > b.limits.max_depth {
      fail(at, BudgetExceeded)
    }
    b.nodes -= 1
    pairs += 1
    match (x.shape, y.shape) {
      (Object(left), Object(right)) => {
        let n = @contract.field_count(left)
        if n != @contract.field_count(right) {
          fail(at, RankingDomainMismatch(name))
        }
        spend(b, at, n)
        if n > b.nodes {
          fail(at, BudgetExceeded)
        }
        for i in 0..<n {
          let l = @contract.field_at(left, i).unwrap()
          let r = @contract.field_at(right, i).unwrap()
          charge(b, at, l.name)
          charge(b, at, r.name)
          if l.name != r.name {
            fail(at, RankingDomainMismatch(name))
          }
          work.push((l.contract, r.contract, depth + 1))
        }
      }
      (Object(_), _) | (_, Object(_)) => fail(at, RankingDomainMismatch(name))
      _ =>
        for c in [x, y] {
          match c.shape {
            ResourceRef(resource_kind~) => charge(b, at, resource_kind)
            ArtifactRef(media_type=Some(media)) => charge(b, at, media)
            _ => ()
          }
        }
    }
  }
  let joined = @contract.join_nullability(a, z, pairs) catch {
    _ => fail(at, BudgetExceeded)
  }
  match joined {
    Some(c) => c
    None => fail(at, RankingDomainMismatch(name))
  }
}

///|
/// Inputs are ordered current-first and include repeated authored occurrences.
pub fn check_merge_rankings(
  source : @decode.Cursor,
  inputs : Array[RankingInput],
  limits : Limits,
) -> Result[CheckedRanking, Issue] {
  let options = match read_ranking_options(source, limits) {
    Ok(o) => o
    Err(e) => return Err(e)
  }
  let u = options.usage
  match
    check_ranking_fusion(options, inputs, {
      max_work: limits.max_work - u.work,
      max_nodes: limits.max_nodes - u.nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_text_bytes - u.text_bytes,
    }) {
    Err(e) => Err(e)
    Ok(c) =>
      Ok({
        ..c,
        usage: {
          work: u.work + c.usage.work,
          nodes: u.nodes + c.usage.nodes,
          text_bytes: u.text_bytes + c.usage.text_bytes,
        },
      })
  }
}

///|
/// Consumes already admitted options; usage excludes their earlier admission.
pub fn check_ranking_fusion(
  options : RankingOptions,
  inputs : Array[RankingInput],
  limits : Limits,
) -> Result[CheckedRanking, Issue] {
  try {
    let source = options.source
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    if inputs.length() - 1 != options.others.length() {
      fail(source, InvalidBody)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    spend(b, source, inputs.length())
    let shapes : Array[RankingShape] = []
    for input in inputs {
      let c = match
        check_ranking_shape(options, input, {
          max_work: b.work,
          max_nodes: b.nodes,
          max_depth: limits.max_depth,
          max_text_bytes: b.text,
        }) {
        Ok(c) => c
        Err(e) => raise Stop(e)
      }
      b.work -= c.usage.work
      b.nodes -= c.usage.nodes
      b.text -= c.usage.text_bytes
      if options.contract is Some(expected) {
        guard ranking_score_at(input, options.score.unwrap()) is Some(declared) else {
          fail(source, MissingScoreContract)
        }
        let actual = declared.contract
        for
          s in [
            expected.domain,
            actual.domain,
            expected.normalization,
            actual.normalization,
          ] {
          charge(b, source, s)
        }
        if actual.domain != expected.domain ||
          actual.normalization != expected.normalization ||
          actual.minimum != expected.minimum ||
          actual.maximum != expected.maximum {
          fail(source, ScoreContractMismatch)
        }
      }
      shapes.push(c)
    }
    let root = decoded(@decode.open_object(source))
    let by_at = decoded(@decode.elements(decoded(@decode.required(root, "by"))))
    let selected : Array[(@row.FieldName, @decode.Cursor)] = []
    let seen : Map[String, Bool] = Map([])
    spend(b, source, options.by.length() + 1)
    for i in 0..<options.by.length() {
      let name = options.by[i]
      let spelling = @row.reference_name(name)
      if !seen.contains(spelling) {
        seen[spelling] = true
        selected.push((name, by_at[i]))
      }
    }
    let candidate_at = decoded(@decode.required(root, "candidate"))
    let spelling = @row.reference_name(options.candidate)
    if seen.contains(spelling) {
      fail(candidate_at, OutputCollision(spelling))
    }
    selected.push((options.candidate, candidate_at))
    seen[spelling] = true
    for name in ["score", "rank"] {
      if seen.contains(name) {
        fail(source, OutputCollision(name))
      }
    }
    let fields : Array[(@row.FieldName, @contract.Contract?)] = []
    let tuples : Map[String, Int] = Map([])
    for (name, at) in selected {
      let mut c = @row.lookup(shapes[0].schema, name).unwrap()
      let tuple = shapes[0].input.tuples.get(ranking_field_key(name))
      for i in 1..<shapes.length() {
        if shapes[i].input.tuples.get(ranking_field_key(name)) != tuple {
          fail(at, RankingDomainMismatch(name))
        }
        c = ranking_join(
          b,
          at,
          name,
          c,
          @row.lookup(shapes[i].schema, name).unwrap(),
        )
      }
      charge(b, at, @row.reference_name(name))
      fields.push((name, Some(c)))
      if tuple is Some(n) {
        tuples[ranking_field_key(name)] = n
      }
    }
    if options.tie_break is Some(names) {
      let locations = decoded(
        @decode.elements(decoded(@decode.required(root, "tie_break"))),
      )
      for i in 0..<names.length() {
        let name = names[i]
        let first = @row.lookup(shapes[0].schema, name).unwrap()
        for j in 1..<shapes.length() {
          ignore(
            ranking_join(
              b,
              locations[i],
              name,
              first,
              @row.lookup(shapes[j].schema, name).unwrap(),
            ),
          )
        }
      }
    }
    spend(b, source, fields.length() + 2)
    if b.nodes == 0 {
      fail(source, BudgetExceeded)
    }
    b.nodes -= 1
    let number = @contract.primitive(NumberType, nullable=false)
    for name in ["score", "rank"] {
      charge(b, source, name)
      fields.push((@row.Unqualified(name), Some(number)))
    }
    let output = match
      @carrier.rows(
        fields,
        field_set=Closed,
        max_fields=fields.length(),
        max_name_bytes=limits.max_text_bytes,
      ) {
      Ok(r) => @carrier.relation(r)
      Err(_) => fail(source, BudgetExceeded)
    }
    Ok({
      options,
      inputs: shapes,
      output,
      tuples,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn merged_ranking_output(value : CheckedRanking) -> @carrier.Carrier {
  value.output
}

///|
pub fn merged_ranking_options(value : CheckedRanking) -> RankingOptions {
  value.options
}

///|
pub fn merged_ranking_input_count(value : CheckedRanking) -> Int {
  value.inputs.length()
}

///|
pub fn merged_ranking_input_at(
  value : CheckedRanking,
  index : Int,
) -> RankingShape? {
  value.inputs.get(index)
}

///|
pub fn merged_ranking_usage(value : CheckedRanking) -> Usage {
  value.usage
}

///|
pub fn merged_ranking_pending(
  value : CheckedRanking,
) -> Array[RankingObligation] {
  let result = [
    ValidateCompleteRankingInputs,
    ValidateUniqueQueryCandidatePerInput,
    EvaluateRankingPolicyWithFiniteIntermediates,
    OrderRankingByScoreAndSemanticIdentity,
    AssignFusedContiguousRanks,
    ResolveRankingResources,
    ResolveRankingProfile,
    DeriveOutputScoreEnvelope,
  ]
  if value.options.policy == ReciprocalRank {
    result.push(ValidatePositiveSafeContiguousRanks)
    result.push(ApplyRankWindowAfterAdmission)
  } else {
    result.push(AuthenticateCapturedScoreDeclarations)
    result.push(ValidateDeclaredScoreRanges)
    result.push(ValidateBusinessTieAgreement)
  }
  result
}

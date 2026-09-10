///|
fn combined_rows() -> @carrier.Carrier {
  let number = @contract.primitive(NumberType, nullable=false)
  @carrier.relation(
    @carrier.rows(
      [
        (Unqualified("id"), Some(number)),
        (Unqualified("score"), Some(number)),
        (
          Unqualified("embedding"),
          Some(@contract.vector_contract(2, nullable=false).unwrap()),
        ),
      ],
      field_set=Closed,
      max_fields=3,
      max_name_bytes=100,
    ).unwrap(),
  )
}

///|
fn combined_keys(input : @carrier.Carrier) -> @evidence.KeySet {
  @evidence.singleton_key(
    @evidence.declare_primary_key(cursor("[\"id\"]"), input, {
      max_fields: 1,
      max_name_bytes: 2,
    }).unwrap(),
  )
}

///|
fn combined_ranking(input : @carrier.Carrier) -> @vector.RankingInput {
  @vector.declare_ranking_score(
    cursor(
      "{\"domain\":\"relevance\",\"range\":[0,1],\"normalization\":\"identity\"}",
    ),
    input,
    Unqualified("score"),
    { max_work: 1000, max_nodes: 1000, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
}

///|
test "combined input retains independent keys and scores through branches" {
  let rows = combined_rows()
  let keys = combined_keys(rows)
  let ranking = combined_ranking(rows)
  let bound = @pipeline_typing.combine_relation_evidence(
    cursor("null"),
    keys,
    ranking,
  ).unwrap()
  let source = cursor(
    "[{\"derive\":{\"saved_id\":\"id\",\"saved_score\":\"score\"}},{\"select\":[\"saved_id\",\"saved_score\",\"embedding\"],\"as\":\"prepared\"},{\"pool_vectors\":{\"vector\":\"embedding\",\"by\":[\"saved_id\"],\"method\":\"sum\"}},{\"from\":\"prepared\",\"merge_rankings\":{\"with\":\"prepared\",\"by\":[],\"candidate\":\"saved_id\",\"score\":\"saved_score\",\"k\":1,\"score_policy\":\"max\",\"score_contract\":{\"domain\":\"relevance\",\"range\":[0,1],\"normalization\":\"identity\"}}}]",
  )
  let inputs = [("rows", @pipeline_typing.RelationEvidenceInput(bound))]
  let p = @pipeline_typing.check_with_evidence(
    source,
    inputs,
    None,
    None,
    limits(),
  ).unwrap()
  let key = @pipeline_typing.candidate_key(p, Step(1)).unwrap()
  assert_eq(
    @evidence.key_field_at(key, 0).unwrap().name,
    Unqualified("saved_id"),
  )
  assert_eq(
    @evidence.declared_key_field_at(key, 0).unwrap().name,
    Unqualified("id"),
  )
  assert_eq(@evidence.key_origin(key), InputDeclaration)
  let score = @vector.ranking_score_at(
    @pipeline_typing.ranking_evidence(p, Step(1)).unwrap(),
    Unqualified("saved_score"),
  ).unwrap()
  assert_eq(@vector.declared_score_field(score), Unqualified("score"))
  // Independently transferred axes share the checked output schema handle.
  let rebound = @pipeline_typing.combine_relation_evidence(
    cursor("null"),
    @pipeline_typing.candidate_keys(p, Step(1)).unwrap(),
    @pipeline_typing.ranking_evidence(p, Step(1)).unwrap(),
  ).unwrap()
  let resumed = @pipeline_typing.check_with_evidence(
    cursor("[]"),
    [("prepared", RelationEvidenceInput(rebound))],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(
    @evidence.declared_key_field_at(
      @pipeline_typing.input_key(resumed, 0).unwrap(),
      0,
    ).unwrap().name,
    Unqualified("id"),
  )
  assert_true(
    @vector.ranking_score_at(
      @pipeline_typing.ranking_evidence(resumed, Input(0)).unwrap(),
      Unqualified("saved_score"),
    )
    is Some(_),
  )
  guard @pipeline_typing.step_at(p, 2).unwrap().operation is Pool(pool) else {
    abort("pool")
  }
  assert_true(
    @vector.pool_pending(pool).contains(
      ValidateDeclaredPoolKey(
        ValidateWholeTupleUniquenessAfterInputNormalization,
      ),
    ),
  )
  guard @pipeline_typing.step_at(p, 3).unwrap().operation is Ranking(fusion) else {
    abort("fusion")
  }
  assert_true(
    @vector.merged_ranking_pending(fusion).contains(
      AuthenticateCapturedScoreDeclarations,
    ),
  )
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @pipeline_typing.check_with_evidence(source, inputs, None, None, exact)
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_with_evidence(source, inputs, None, None, cap)
      is Err(_),
    )
  }
  assert_true(
    @pipeline_typing.check_with_evidence(
      source,
      [("rows", RankingInput(ranking))],
      None,
      None,
      limits(),
    )
    is Err({ kind: Vector(MissingEligiblePoolKey), .. }),
  )
  assert_true(
    @pipeline_typing.check_with_evidence(
      source,
      [("rows", CandidateKeysInput(keys))],
      None,
      None,
      limits(),
    )
    is Err({ kind: Vector(MissingScoreContract), .. }),
  )
}

///|
test "combining evidence requires bound row handles rather than equal shapes" {
  let rows = combined_rows()
  let keys = combined_keys(rows)
  let ranking = combined_ranking(rows)
  assert_true(
    @pipeline_typing.combine_relation_evidence(cursor("null"), keys, ranking)
    is Ok(_),
  )
  let same_schema = @carrier.relation(
    @carrier.typed_rows(
      @carrier.complete_schema(@carrier.relation_rows(rows).unwrap()).unwrap(),
    ),
  )
  assert_true(
    @pipeline_typing.combine_relation_evidence(
      cursor("null"),
      keys,
      combined_ranking(same_schema),
    )
    is Ok(_),
  )
  let at = @decode.elements(cursor("[null]")).unwrap()[0]
  let mismatch = @pipeline_typing.combine_relation_evidence(
    at,
    keys,
    combined_ranking(combined_rows()),
  ).unwrap_err()
  assert_eq(mismatch.kind, KeyEvidence(InputContractMismatch))
  assert_eq(mismatch.path, @decode.cursor_path(at))
  assert_eq(mismatch.span, @decode.cursor_span(at))
  let wrong = @pipeline_typing.combine_relation_evidence(
    at,
    keys,
    @vector.ranking_relation(vector_input()),
  ).unwrap_err()
  assert_eq(wrong.kind, WrongCarrier(VectorsKind))
}

///|
test "empty partial evidence binds only to the same knowledge and invents no key" {
  let unknown = @carrier.relation(@carrier.unknown_rows())
  let keys = @evidence.collect_keys(cursor("null"), unknown, [], {
    max_keys: 0,
    max_work: 0,
    max_name_bytes: 0,
  }).unwrap()
  let bound = @pipeline_typing.combine_relation_evidence(
    cursor("null"),
    keys,
    @vector.ranking_relation(unknown),
  ).unwrap()
  let p = @pipeline_typing.check_with_evidence(
    cursor("[]"),
    [("rows", RelationEvidenceInput(bound))],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(
    @evidence.key_witness_count(
      @pipeline_typing.candidate_keys(p, Input(0)).unwrap(),
    ),
    0,
  )
  assert_true(
    @vector.ranking_score_declaration(
      @pipeline_typing.ranking_evidence(p, Input(0)).unwrap(),
    )
    is None,
  )
  assert_true(
    @pipeline_typing.combine_relation_evidence(
      cursor("null"),
      keys,
      @vector.ranking_relation(@carrier.relation(@carrier.unknown_rows())),
    )
    is Err({ kind: KeyEvidence(InputContractMismatch), .. }),
  )
}

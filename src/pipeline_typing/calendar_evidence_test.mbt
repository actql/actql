///|
fn calendar_scored_rows() -> @carrier.Carrier {
  let number = @contract.primitive(NumberType, nullable=false)
  @carrier.relation(
    @carrier.rows(
      [
        (Unqualified("id"), Some(number)),
        (Unqualified("score"), Some(number)),
        (
          Unqualified("at"),
          Some(@contract.primitive(TimestampType, nullable=false)),
        ),
        (
          Unqualified("embedding"),
          Some(@contract.vector_contract(2, nullable=false).unwrap()),
        ),
      ],
      field_set=Closed,
      max_fields=4,
      max_name_bytes=100,
    ).unwrap(),
  )
}

///|
test "calendar bucket preserves independent keys and scores into later consumers" {
  let rows = calendar_scored_rows()
  let keys = combined_keys(rows)
  let ranking = combined_ranking(rows)
  let bound = @pipeline_typing.combine_relation_evidence(
    cursor("null"),
    keys,
    ranking,
  ).unwrap()
  let source = cursor(
    "[{\"calendar_bucket\":{\"time\":\"at\",\"into\":\"bucket\",\"unit\":\"day\",\"timezone\":\"UTC\"}},{\"rename\":{\"id\":\"saved_id\",\"score\":\"saved_score\"},\"as\":\"prepared\"},{\"pool_vectors\":{\"vector\":\"embedding\",\"by\":[\"saved_id\"],\"method\":\"sum\"}},{\"from\":\"prepared\",\"merge_rankings\":{\"with\":\"prepared\",\"by\":[],\"candidate\":\"saved_id\",\"score\":\"saved_score\",\"k\":1,\"score_policy\":\"max\",\"score_contract\":{\"domain\":\"relevance\",\"range\":[0,1],\"normalization\":\"identity\"}}}]",
  )
  let inputs = [("rows", @pipeline_typing.RelationEvidenceInput(bound))]
  let profile = Some(calendar_profile())
  let p = @pipeline_typing.check_with_evidence(
    source,
    inputs,
    None,
    None,
    limits(),
    calendar_profile=profile,
  ).unwrap()
  let key = @pipeline_typing.candidate_key(p, Step(1)).unwrap()
  assert_eq(@evidence.key_origin(key), InputDeclaration)
  assert_eq(
    @evidence.key_field_at(key, 0).unwrap().name,
    Unqualified("saved_id"),
  )
  assert_eq(
    @evidence.declared_key_field_at(key, 0).unwrap().name,
    Unqualified("id"),
  )
  let ranked = @pipeline_typing.ranking_evidence(p, Step(1)).unwrap()
  let score = @vector.ranking_score_at(ranked, Unqualified("saved_score")).unwrap()
  assert_eq(@vector.declared_score_field(score), Unqualified("score"))
  assert_true(@vector.ranking_score_at(ranked, Unqualified("bucket")) is None)
  assert_true(
    @pipeline_typing.combine_relation_evidence(
      cursor("null"),
      @pipeline_typing.candidate_keys(p, Step(1)).unwrap(),
      ranked,
    )
    is Ok(_),
  )
  guard @pipeline_typing.step_at(p, 0).unwrap().operation is Calendar(c) else {
    abort("calendar")
  }
  assert_true(@calendar.input(c) is Some(_))
  assert_true(@calendar.pending_validations(c).contains(ValidateBoundaryDomain))
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
    abort("ranking")
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
    @pipeline_typing.check_with_evidence(
      source,
      inputs,
      None,
      None,
      exact,
      calendar_profile=profile,
    )
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_with_evidence(
        source,
        inputs,
        None,
        None,
        cap,
        calendar_profile=profile,
      )
      is Err(_),
    )
  }
}

///|
test "calendar evidence transfer rejects unrelated inputs and generators" {
  let rows = calendar_scored_rows()
  let keys = combined_keys(rows)
  let ranking = combined_ranking(rows)
  let profile = Some(calendar_profile())
  let c = @calendar.check(
    Bucket,
    cursor(
      "{\"time\":\"at\",\"into\":\"bucket\",\"unit\":\"day\",\"timezone\":\"UTC\"}",
    ),
    Some(rows),
    None,
    profile,
    { max_work: 1000, max_nodes: 1000, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let caps : @evidence.TransferLimits = { max_work: 2, max_name_bytes: 0, }
  let transfer = @evidence.transfer_calendar_keys(keys, c, caps).unwrap()
  assert_eq(transfer.work, 2)
  assert_eq(transfer.name_bytes, 0)
  assert_true(
    @evidence.transfer_calendar_keys(keys, c, { ..caps, max_work: 1, })
    is Err({ kind: LimitExceeded, .. }),
  )
  assert_true(
    @evidence.transfer_calendar_keys(keys, c, { ..caps, max_name_bytes: -1, })
    is Err({ kind: InvalidLimits, .. }),
  )
  let vcaps : @vector.Limits = {
    max_work: 1,
    max_nodes: 0,
    max_depth: 0,
    max_text_bytes: 0,
  }
  assert_true(@vector.transfer_ranking_calendar(ranking, c, vcaps) is Ok(_))
  assert_true(
    @vector.transfer_ranking_calendar(ranking, c, { ..vcaps, max_work: 0, })
    is Err({ kind: BudgetExceeded, .. }),
  )
  assert_true(
    @vector.transfer_ranking_calendar(ranking, c, { ..vcaps, max_depth: -1, })
    is Err({ kind: InvalidLimits, .. }),
  )
  let other = calendar_scored_rows()
  assert_true(
    @evidence.transfer_calendar_keys(combined_keys(other), c, caps)
    is Err({ kind: InputContractMismatch, .. }),
  )
  assert_true(
    @vector.transfer_ranking_calendar(combined_ranking(other), c, vcaps)
    is Err({ kind: RankingInputMismatch, .. }),
  )
  let series = @calendar.check(
    Series,
    cursor(
      "{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-02T00:00:00.000Z\",\"unit\":\"day\",\"timezone\":\"UTC\"}",
    ),
    None,
    None,
    profile,
    { max_work: 1000, max_nodes: 1000, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  assert_true(@calendar.input(series) is None)
  let generated = @evidence.advance_calendar_keys(None, series, {
    max_work: 2,
    max_name_bytes: 5,
  }).unwrap()
  let key = @evidence.key_witness_at(generated.keys, 0).unwrap()
  assert_eq(@evidence.key_origin(key), CalendarSeriesResult)
  assert_eq(@evidence.key_field_at(key, 0).unwrap().name, Unqualified("start"))
  assert_true(@evidence.key_producer(key) is None)
  assert_true(@evidence.key_calendar_producer(key) is Some(_))
  assert_eq(@evidence.key_pending(key), [ValidateKeyProducer])
  assert_true(
    @evidence.advance_calendar_keys(None, series, {
      max_work: 1,
      max_name_bytes: 5,
    })
    is Err({ kind: LimitExceeded, .. }),
  )
  assert_true(
    @evidence.advance_calendar_keys(None, series, {
      max_work: 2,
      max_name_bytes: 4,
    })
    is Err({ kind: LimitExceeded, .. }),
  )
  assert_true(
    @evidence.advance_calendar_keys(Some(keys), series, caps)
    is Err({ kind: InputContractMismatch, .. }),
  )
  assert_true(
    @evidence.transfer_calendar_keys(keys, series, caps)
    is Err({ kind: InputContractMismatch, .. }),
  )
  assert_true(
    @vector.transfer_ranking_calendar(ranking, series, vcaps)
    is Err({ kind: RankingInputMismatch, .. }),
  )
}

///|
test "calendar series start key completes as-of identity after bucket and rename" {
  for end in ["2000-01-01T00:00:00.000Z", "2000-01-03T00:00:00.000Z"] {
    let source = cursor(
      "[{\"calendar_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"" +
      end +
      "\",\"unit\":\"day\",\"timezone\":\"UTC\"},\"as\":\"days\"},{\"calendar_bucket\":{\"time\":\"start\",\"into\":\"month\",\"unit\":\"month\",\"timezone\":\"UTC\"}},{\"rename\":{\"start\":\"begin\"}},{\"asof_join\":{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_time\":\"begin\",\"right_time\":\"at\",\"direction\":\"nearest\",\"tolerance\":100,\"select\":{\"begin\":\"left.begin\"}}}]",
    )
    let p = @pipeline_typing.check_carriers(
      source,
      [("r", calendar_scored_rows())],
      None,
      None,
      limits(),
      calendar_profile=Some(calendar_profile()),
    ).unwrap()
    guard @pipeline_typing.step_at(p, 3).unwrap().operation
      is AsOfJoin(checked~, ..) else {
      abort("as-of")
    }
    assert_eq(@join.asof_identity(checked), [Unqualified("begin")])
    let key = @join.asof_key_completion(checked, Left).unwrap()
    assert_eq(@evidence.key_origin(key), CalendarSeriesResult)
    let producer = @evidence.key_calendar_producer(key).unwrap()
    assert_true(@calendar.input(producer) is None)
    assert_true(
      @calendar.pending_validations(producer).contains(ValidateCalendarValues),
    )
    assert_eq(
      @evidence.declared_key_field_at(key, 0).unwrap().name,
      Unqualified("start"),
    )
    assert_eq(@evidence.key_pending(key), [ValidateKeyProducer])
  }
}

// Generated from registered ActQL publication schemas.
export type WireDeliveryAttempt = Readonly<{
  version: "actql-delivery-attempt/0.1";
  attempt_id: string;
  result_read_grant_cid: string;
  run_definition_cid: string;
  result_manifest_cid: string;
  result_name: string;
  result_artifact_cid: string;
  serialization_contract_cid: string;
  requested_at: string;
  delivery_attempt_cid: string;
}>;

export type WireDeliveryRecord = Readonly<{
  version: "actql-delivery-record/0.1";
  delivery_attempt_cid: string;
  prior_record_cid?: string;
  sequence: number;
  state: "streaming" | "succeeded" | "failed" | "cancelled";
  confirmed_byte_count: number;
  exposure: "exact" | "unknown_additional";
  possible_unconfirmed_max_bytes?: number;
  delivered_sha256?: string;
  result_delivery_receipt_cid?: string;
  failure_cid?: string;
  observed_at: string;
  cleanup_owner_cids: readonly string[];
  delivery_record_cid: string;
}>;

export type WireHostReleaseReceipt = Readonly<{
  version: "actql-result-delivery-receipt/0.1";
  run_definition_cid: string;
  invocation_cid: string;
  result_manifest_cid: string;
  result_name: string;
  result_artifact_cid: string;
  serialization_contract_cid: string;
  delivered_byte_count: number;
  delivered_sha256: string;
  authorization_context_cid: string;
  egress_admission_cid: string;
  result_delivery_receipt_cid: string;
}>;

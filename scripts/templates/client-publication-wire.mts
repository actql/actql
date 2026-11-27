/* @wire-bindings */

const valid = structuralWireValidator({schemas});

export function validDeliveryAttempt(value: unknown): value is WireDeliveryAttempt {
  return valid(value, schemas.delivery_attempt);
}

export function validDeliveryRecord(value: unknown): value is WireDeliveryRecord {
  return valid(value, schemas.delivery_record);
}

export function validHostReleaseReceipt(value: unknown): value is WireHostReleaseReceipt {
  return valid(value, schemas.result_delivery_receipt);
}

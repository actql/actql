// Independent fixture projection, not a product issuer. List every logical
// fact explicitly so leaking physical fields or dropping operation binding
// changes the expected result. Original physical bytes remain the evidence.
import {createHash} from 'node:crypto';
import {canonicalText} from '../../../scripts/check-canonical-json.mjs';

type PhysicalReceipt = Readonly<{
  request_cid: string; effect_identity_cid: string; catalog_identity_cid: string;
  table_uuid: string; generation_cid: string; schema_cid: string;
  storage_mapping_cid: string; receipt_cid: string; row_count: number;
}>;

export function expectedLogicalTableReceipt(physical: PhysicalReceipt) {
  const body = {
    version: 'actql-table-logical-receipt/0.1',
    request_cid: physical.request_cid,
    effect_identity_cid: physical.effect_identity_cid,
    catalog_identity_cid: physical.catalog_identity_cid,
    table_uuid: physical.table_uuid,
    generation_cid: physical.generation_cid,
    schema_cid: physical.schema_cid,
    storage_mapping_cid: physical.storage_mapping_cid,
    physical_receipt_cid: physical.receipt_cid,
    row_count: physical.row_count,
  };
  return {...body, receipt_cid: `sha256:${createHash('sha256')
    .update(canonicalText(body)).digest('hex')}`};
}

// Generated from registered ActQL publication schemas.
// Run: node scripts/generate-client-publication-wire.mjs --write
const schemas = {
  "delivery_attempt": {
    "type": "object",
    "additionalProperties": false,
    "required": [
      "version",
      "attempt_id",
      "result_read_grant_cid",
      "run_definition_cid",
      "result_manifest_cid",
      "result_name",
      "result_artifact_cid",
      "serialization_contract_cid",
      "requested_at",
      "delivery_attempt_cid"
    ],
    "properties": {
      "version": {
        "const": "actql-delivery-attempt/0.1"
      },
      "attempt_id": {
        "type": "string",
        "minLength": 1
      },
      "result_read_grant_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "run_definition_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "result_manifest_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "result_name": {
        "type": "string",
        "minLength": 1
      },
      "result_artifact_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "serialization_contract_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "requested_at": {
        "type": "string",
        "pattern": "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$"
      },
      "delivery_attempt_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      }
    }
  },
  "delivery_record": {
    "type": "object",
    "additionalProperties": false,
    "required": [
      "version",
      "delivery_attempt_cid",
      "sequence",
      "state",
      "confirmed_byte_count",
      "exposure",
      "observed_at",
      "cleanup_owner_cids",
      "delivery_record_cid"
    ],
    "properties": {
      "version": {
        "const": "actql-delivery-record/0.1"
      },
      "delivery_attempt_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "prior_record_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "sequence": {
        "type": "integer",
        "minimum": 0,
        "maximum": 9007199254740991
      },
      "state": {
        "enum": [
          "streaming",
          "succeeded",
          "failed",
          "cancelled"
        ]
      },
      "confirmed_byte_count": {
        "type": "integer",
        "minimum": 0,
        "maximum": 9007199254740991
      },
      "exposure": {
        "enum": [
          "exact",
          "unknown_additional"
        ]
      },
      "possible_unconfirmed_max_bytes": {
        "type": "integer",
        "minimum": 0,
        "maximum": 9007199254740991
      },
      "delivered_sha256": {
        "type": "string",
        "pattern": "^[0-9a-f]{64}$"
      },
      "result_delivery_receipt_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "failure_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "observed_at": {
        "type": "string",
        "pattern": "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$"
      },
      "cleanup_owner_cids": {
        "type": "array",
        "uniqueItems": true,
        "items": {
          "type": "string",
          "pattern": "^sha256:[0-9a-f]{64}$"
        }
      },
      "delivery_record_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      }
    },
    "allOf": [
      {
        "if": {
          "required": [
            "state"
          ],
          "properties": {
            "state": {
              "const": "succeeded"
            }
          }
        },
        "then": {
          "required": [
            "delivered_sha256",
            "result_delivery_receipt_cid"
          ],
          "properties": {
            "exposure": {
              "const": "exact"
            }
          }
        }
      },
      {
        "if": {
          "required": [
            "exposure"
          ],
          "properties": {
            "exposure": {
              "const": "unknown_additional"
            }
          }
        },
        "then": {
          "required": [
            "possible_unconfirmed_max_bytes"
          ]
        }
      }
    ]
  },
  "result_delivery_receipt": {
    "type": "object",
    "additionalProperties": false,
    "required": [
      "version",
      "run_definition_cid",
      "invocation_cid",
      "result_manifest_cid",
      "result_name",
      "result_artifact_cid",
      "serialization_contract_cid",
      "delivered_byte_count",
      "delivered_sha256",
      "authorization_context_cid",
      "egress_admission_cid",
      "result_delivery_receipt_cid"
    ],
    "properties": {
      "version": {
        "const": "actql-result-delivery-receipt/0.1"
      },
      "run_definition_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "invocation_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "result_manifest_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "result_name": {
        "type": "string",
        "minLength": 1
      },
      "result_artifact_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "serialization_contract_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "delivered_byte_count": {
        "type": "integer",
        "minimum": 0,
        "maximum": 9007199254740991
      },
      "delivered_sha256": {
        "type": "string",
        "pattern": "^[0-9a-f]{64}$"
      },
      "authorization_context_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "egress_admission_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "result_delivery_receipt_cid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      }
    }
  }
};

function valid(value, schema) {
  if (schema.if && valid(value, schema.if) && !valid(value, schema.then)) return false;
  if (schema.allOf && !schema.allOf.every(rule => valid(value, rule))) return false;
  if (Object.hasOwn(schema, 'const') && value !== schema.const) return false;
  if (schema.enum && !schema.enum.includes(value)) return false;
  if (schema.type === 'string') return typeof value === 'string' &&
    (schema.minLength === undefined || [...value].length >= schema.minLength) &&
    (schema.pattern === undefined || new RegExp(schema.pattern, 'u').test(value));
  if (schema.type === 'integer') return Number.isSafeInteger(value) &&
    (schema.minimum === undefined || value >= schema.minimum) &&
    (schema.maximum === undefined || value <= schema.maximum);
  if (schema.type === 'array') return Array.isArray(value) &&
    value.every(item => valid(item, schema.items)) &&
    (!schema.uniqueItems || new Set(value).size === value.length);
  if (schema.type === 'object' || schema.properties || schema.required) {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
    if (schema.required?.some(key => !Object.hasOwn(value, key))) return false;
    if (schema.additionalProperties === false &&
        Object.keys(value).some(key => !Object.hasOwn(schema.properties, key))) return false;
    return Object.entries(schema.properties ?? {}).every(([key, field]) =>
      !Object.hasOwn(value, key) || valid(value[key], field));
  }
  return true;
}

export const validDeliveryAttempt = value => valid(value, schemas.delivery_attempt);
export const validDeliveryRecord = value => valid(value, schemas.delivery_record);
export const validHostReleaseReceipt = value =>
  valid(value, schemas.result_delivery_receipt);

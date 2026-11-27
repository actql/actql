// Generated from registered ActQL publication schemas.
// Run: node scripts/generate-client-publication-wire.mjs --write
function wireObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}
function sameConstant(value, expected) {
    if (value === expected)
        return true;
    if (Array.isArray(expected)) {
        return Array.isArray(value) && value.length === expected.length &&
            expected.every((item, index) => sameConstant(value[index], item));
    }
    return wireObject(expected) && wireObject(value) &&
        Object.keys(value).length === Object.keys(expected).length &&
        Object.keys(expected).every(key => Object.hasOwn(value, key) && sameConstant(value[key], expected[key]));
}
function structuralWireValidator({ schemas, extended, compositeConstants } = {}) {
    return function valid(value, schema) {
        if (typeof value === 'number' && (!Number.isFinite(value) || Object.is(value, -0)))
            return false;
        if (typeof value === 'string' && !value.isWellFormed())
            return false;
        if (extended) {
            if (schema.anyOf && !schema.anyOf.some(rule => valid(value, rule)))
                return false;
            if (schema.if && !valid(value, schema.if) && schema.else && !valid(value, schema.else))
                return false;
            if (schema.type === 'null')
                return value === null;
            if (schema.format === 'date-time' && (typeof value !== 'string' ||
                !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u.test(value) || Number.isNaN(Date.parse(value))))
                return false;
        }
        if (schemas && schema.$ref)
            return valid(value, schemas[schema.$ref]);
        if (schema.oneOf && schema.oneOf.filter(rule => valid(value, rule)).length !== 1)
            return false;
        if (schema.not && valid(value, schema.not))
            return false;
        if (schema.if && valid(value, schema.if) && !valid(value, schema.then))
            return false;
        if (schema.allOf && !schema.allOf.every(rule => valid(value, rule)))
            return false;
        if (Object.hasOwn(schema, 'const') &&
            (compositeConstants ? !sameConstant(value, schema.const) : value !== schema.const))
            return false;
        if (schema.enum && !schema.enum.includes(value))
            return false;
        if (typeof value === 'number' &&
            (schema.minimum !== undefined && value < schema.minimum ||
                schema.maximum !== undefined && value > schema.maximum))
            return false;
        if (typeof value === 'string' &&
            ((schema.minLength !== undefined && [...value].length < schema.minLength) ||
                (schema.maxLength !== undefined && (extended ? [...value].length : value.length) > schema.maxLength) ||
                (schema.pattern !== undefined && !new RegExp(schema.pattern, 'u').test(value))))
            return false;
        if (schema.type === 'string')
            return typeof value === 'string';
        if (schema.type === 'number')
            return typeof value === 'number';
        if (schema.type === 'integer')
            return typeof value === 'number' && Number.isSafeInteger(value) &&
                (schema.minimum === undefined || value >= schema.minimum) &&
                (schema.maximum === undefined || value <= schema.maximum);
        if (schema.type === 'boolean')
            return typeof value === 'boolean';
        if (schema.type === 'array')
            return Array.isArray(value) &&
                (schema.minItems === undefined || value.length >= schema.minItems) &&
                (schema.maxItems === undefined || value.length <= schema.maxItems) &&
                value.every(item => valid(item, schema.items)) &&
                (!schema.uniqueItems || new Set(value).size === value.length);
        if (wireObject(value) &&
            ((schema.minProperties !== undefined && Object.keys(value).length < schema.minProperties) ||
                (schema.maxProperties !== undefined && Object.keys(value).length > schema.maxProperties)))
            return false;
        if (schema.type === 'object' || schema.properties || schema.required) {
            if (!wireObject(value))
                return false;
            if (schema.required?.some(key => !Object.hasOwn(value, key)))
                return false;
            const { propertyNames, properties, additionalProperties } = schema;
            if (propertyNames && Object.keys(value).some(key => !valid(key, propertyNames)))
                return false;
            if (additionalProperties === false && Object.keys(value).some(key => !Object.hasOwn(properties, key)))
                return false;
            if (additionalProperties && typeof additionalProperties === 'object' &&
                Object.entries(value).some(([key, item]) => !Object.hasOwn(properties ?? {}, key) &&
                    !valid(item, additionalProperties)))
                return false;
            return Object.entries(properties ?? {}).every(([key, field]) => !Object.hasOwn(value, key) || valid(value[key], field));
        }
        return true;
    };
}
const schemas = {
    "delivery_attempt": {
        "type": "object",
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
        "additionalProperties": false,
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
        "additionalProperties": false,
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
        "additionalProperties": false,
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
const valid = structuralWireValidator({ schemas });
export function validDeliveryAttempt(value) {
    return valid(value, schemas.delivery_attempt);
}
export function validDeliveryRecord(value) {
    return valid(value, schemas.delivery_record);
}
export function validHostReleaseReceipt(value) {
    return valid(value, schemas.result_delivery_receipt);
}

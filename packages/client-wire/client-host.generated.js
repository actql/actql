// Generated from the registered Client–Host machine contract.
// Run: node scripts/generate-client-host-wire.mjs --write
const schemas = {
  "run_ref": {
    "type": "object",
    "additionalProperties": false,
    "required": [
      "tenantId",
      "authorityScopeCid",
      "runDefinitionCid"
    ],
    "properties": {
      "tenantId": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "authorityScopeCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "runDefinitionCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      }
    }
  },
  "connection": {
    "type": "object",
    "additionalProperties": false,
    "required": [
      "mode",
      "owner",
      "consentRefs",
      "runners"
    ],
    "properties": {
      "mode": {
        "enum": [
          "local",
          "remote",
          "hybrid"
        ]
      },
      "owner": {
        "enum": [
          "local",
          "remote",
          "cloud"
        ]
      },
      "consentRefs": {
        "type": "array",
        "uniqueItems": true,
        "items": {
          "type": "string",
          "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
          "minLength": 1,
          "maxLength": 256
        }
      },
      "runners": {
        "type": "array",
        "uniqueItems": true,
        "items": {
          "type": "string",
          "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
          "minLength": 1,
          "maxLength": 256
        }
      },
      "durability": {
        "enum": [
          "volatile",
          "durable"
        ]
      },
      "movementPolicyRef": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "cloudConnectionRef": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      }
    }
  },
  "profile": {
    "type": "object",
    "additionalProperties": false,
    "required": [
      "version",
      "mode",
      "owner",
      "durability",
      "scopeRef",
      "capabilities",
      "limits"
    ],
    "properties": {
      "version": {
        "const": "actql-client-host/0.1"
      },
      "mode": {
        "enum": [
          "local",
          "remote",
          "hybrid"
        ]
      },
      "owner": {
        "enum": [
          "local",
          "remote",
          "cloud"
        ]
      },
      "durability": {
        "enum": [
          "volatile",
          "durable"
        ]
      },
      "scopeRef": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "capabilities": {
        "type": "array",
        "items": {
          "type": "string",
          "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
          "minLength": 1,
          "maxLength": 256
        }
      },
      "limits": {
        "type": "object",
        "additionalProperties": false,
        "required": [
          "maxReadWireBytes",
          "maxRowWireBytes",
          "maxRowRetainedValueBytes",
          "maxRetainedValueBytes",
          "maxRows",
          "maxBatchRows",
          "maxBatchRetainedValueBytes"
        ],
        "properties": {
          "maxReadWireBytes": {
            "type": "integer",
            "minimum": 1
          },
          "maxRowWireBytes": {
            "type": "integer",
            "minimum": 1
          },
          "maxRowRetainedValueBytes": {
            "type": "integer",
            "minimum": 1
          },
          "maxRetainedValueBytes": {
            "type": "integer",
            "minimum": 1
          },
          "maxRows": {
            "type": "integer",
            "minimum": 1
          },
          "maxBatchRows": {
            "type": "integer",
            "minimum": 1
          },
          "maxBatchRetainedValueBytes": {
            "type": "integer",
            "minimum": 1
          }
        }
      }
    }
  },
  "admission": {
    "type": "object",
    "additionalProperties": false,
    "required": [
      "ref",
      "durability",
      "revision"
    ],
    "properties": {
      "ref": {
        "type": "object",
        "additionalProperties": false,
        "required": [
          "tenantId",
          "authorityScopeCid",
          "runDefinitionCid"
        ],
        "properties": {
          "tenantId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
            "minLength": 1,
            "maxLength": 256
          },
          "authorityScopeCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "runDefinitionCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          }
        }
      },
      "durability": {
        "enum": [
          "volatile",
          "durable"
        ]
      },
      "revision": {
        "type": "integer",
        "minimum": 0
      }
    }
  },
  "lookup_found": {
    "type": "object",
    "additionalProperties": false,
    "required": [
      "kind",
      "requestId",
      "ref",
      "durability",
      "lookupExpiresAt"
    ],
    "properties": {
      "kind": {
        "const": "found"
      },
      "requestId": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      },
      "ref": {
        "type": "object",
        "additionalProperties": false,
        "required": [
          "tenantId",
          "authorityScopeCid",
          "runDefinitionCid"
        ],
        "properties": {
          "tenantId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
            "minLength": 1,
            "maxLength": 256
          },
          "authorityScopeCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "runDefinitionCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          }
        }
      },
      "durability": {
        "enum": [
          "volatile",
          "durable"
        ]
      },
      "lookupExpiresAt": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      }
    }
  },
  "lookup_not_found": {
    "type": "object",
    "additionalProperties": false,
    "required": [
      "kind"
    ],
    "properties": {
      "kind": {
        "const": "not_found"
      }
    }
  },
  "lookup_unknown": {
    "type": "object",
    "additionalProperties": false,
    "required": [
      "kind",
      "reason"
    ],
    "properties": {
      "kind": {
        "const": "unknown"
      },
      "reason": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+$",
        "minLength": 1,
        "maxLength": 256
      }
    }
  }
};
const operationKeys = {
  "connect": [
    "connection"
  ],
  "submit": [
    "connection",
    "requestId",
    "kind",
    "input",
    "parameters"
  ],
  "attach": [
    "connection",
    "ref"
  ],
  "lookup-request": [
    "connection",
    "requestId"
  ],
  "status": [
    "connection",
    "ref"
  ],
  "wait": [
    "connection",
    "ref",
    "until"
  ],
  "cancel": [
    "connection",
    "ref"
  ],
  "reconcile": [
    "connection",
    "ref"
  ],
  "read": [
    "connection",
    "ref",
    "resultName",
    "format",
    "attemptId"
  ],
  "delivery-attempt": [
    "connection",
    "ref",
    "resultName",
    "attemptId"
  ]
};

function valid(value, schema) {
  if (schema.if && valid(value, schema.if) && !valid(value, schema.then)) return false;
  if (schema.allOf && !schema.allOf.every(rule => valid(value, rule))) return false;
  if (Object.hasOwn(schema, 'const') && value !== schema.const) return false;
  if (schema.enum && !schema.enum.includes(value)) return false;
  if (schema.type === 'string') return typeof value === 'string' &&
    (schema.minLength === undefined || [...value].length >= schema.minLength) &&
    (schema.maxLength === undefined || value.length <= schema.maxLength) &&
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

export const clientHostOperations = Object.freeze(Object.keys(operationKeys));
export const clientHostRequestKeys = operation => (Object.hasOwn(operationKeys, operation) ? operationKeys[operation] : undefined);
export const validRunRefShape = value => valid(value, schemas.run_ref);
export const validConnectionShape = value => valid(value, schemas.connection);
export const validProfileShape = value => valid(value, schemas.profile);
export const validAdmissionShape = value => valid(value, schemas.admission);
export const validLookupFoundShape = value => valid(value, schemas.lookup_found);
export const validLookupNotFoundShape = value => valid(value, schemas.lookup_not_found);
export const validLookupUnknownShape = value => valid(value, schemas.lookup_unknown);

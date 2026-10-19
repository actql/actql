// Generated from the registered Client–Host machine contract.
// Run: node scripts/generate-client-host-wire.mjs --write
const schemas = {
  "submission_epoch": {
    "type": "object",
    "required": [
      "version",
      "authorityScopeCid",
      "epochNonce",
      "notBefore",
      "expiresAt",
      "authenticator"
    ],
    "additionalProperties": false,
    "properties": {
      "version": {
        "const": "actql-submission-epoch/0.1"
      },
      "authorityScopeCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "epochNonce": {
        "type": "string",
        "pattern": "^[0-9a-f]{64}$"
      },
      "notBefore": {
        "type": "integer",
        "minimum": 0,
        "maximum": 9007199254740991
      },
      "expiresAt": {
        "type": "integer",
        "minimum": 1,
        "maximum": 9007199254740991
      },
      "authenticator": {
        "type": "string",
        "pattern": "^[0-9a-f]{64}$"
      }
    }
  },
  "submission_ref": {
    "type": "object",
    "required": [
      "epoch",
      "nonce"
    ],
    "additionalProperties": false,
    "properties": {
      "epoch": {
        "type": "object",
        "required": [
          "version",
          "authorityScopeCid",
          "epochNonce",
          "notBefore",
          "expiresAt",
          "authenticator"
        ],
        "additionalProperties": false,
        "properties": {
          "version": {
            "const": "actql-submission-epoch/0.1"
          },
          "authorityScopeCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "epochNonce": {
            "type": "string",
            "pattern": "^[0-9a-f]{64}$"
          },
          "notBefore": {
            "type": "integer",
            "minimum": 0,
            "maximum": 9007199254740991
          },
          "expiresAt": {
            "type": "integer",
            "minimum": 1,
            "maximum": 9007199254740991
          },
          "authenticator": {
            "type": "string",
            "pattern": "^[0-9a-f]{64}$"
          }
        }
      },
      "nonce": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      }
    }
  },
  "submission_outcome": {
    "oneOf": [
      {
        "type": "object",
        "required": [
          "kind",
          "submissionRef",
          "intentCid",
          "admission"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "ready"
          },
          "submissionRef": {
            "type": "object",
            "required": [
              "epoch",
              "nonce"
            ],
            "additionalProperties": false,
            "properties": {
              "epoch": {
                "type": "object",
                "required": [
                  "version",
                  "authorityScopeCid",
                  "epochNonce",
                  "notBefore",
                  "expiresAt",
                  "authenticator"
                ],
                "additionalProperties": false,
                "properties": {
                  "version": {
                    "const": "actql-submission-epoch/0.1"
                  },
                  "authorityScopeCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "epochNonce": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  },
                  "notBefore": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 9007199254740991
                  },
                  "expiresAt": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 9007199254740991
                  },
                  "authenticator": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  }
                }
              },
              "nonce": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "intentCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "admission": {
            "type": "object",
            "required": [
              "ref",
              "durability",
              "revision"
            ],
            "additionalProperties": false,
            "properties": {
              "ref": {
                "type": "object",
                "required": [
                  "namespaceId",
                  "authorityScopeCid",
                  "runDefinitionCid"
                ],
                "additionalProperties": false,
                "properties": {
                  "namespaceId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
          "unresolvedHistory": {
            "type": "object",
            "required": [
              "submissionRef",
              "acknowledgement"
            ],
            "additionalProperties": false,
            "properties": {
              "submissionRef": {
                "type": "object",
                "required": [
                  "epoch",
                  "nonce"
                ],
                "additionalProperties": false,
                "properties": {
                  "epoch": {
                    "type": "object",
                    "required": [
                      "version",
                      "authorityScopeCid",
                      "epochNonce",
                      "notBefore",
                      "expiresAt",
                      "authenticator"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "version": {
                        "const": "actql-submission-epoch/0.1"
                      },
                      "authorityScopeCid": {
                        "type": "string",
                        "pattern": "^sha256:[0-9a-f]{64}$"
                      },
                      "epochNonce": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      },
                      "notBefore": {
                        "type": "integer",
                        "minimum": 0,
                        "maximum": 9007199254740991
                      },
                      "expiresAt": {
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 9007199254740991
                      },
                      "authenticator": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      }
                    }
                  },
                  "nonce": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  }
                }
              },
              "acknowledgement": {
                "const": "possible_prior_execution_and_effects"
              }
            }
          }
        }
      },
      {
        "type": "object",
        "required": [
          "kind",
          "submissionRef",
          "intentCid",
          "held"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "held"
          },
          "submissionRef": {
            "type": "object",
            "required": [
              "epoch",
              "nonce"
            ],
            "additionalProperties": false,
            "properties": {
              "epoch": {
                "type": "object",
                "required": [
                  "version",
                  "authorityScopeCid",
                  "epochNonce",
                  "notBefore",
                  "expiresAt",
                  "authenticator"
                ],
                "additionalProperties": false,
                "properties": {
                  "version": {
                    "const": "actql-submission-epoch/0.1"
                  },
                  "authorityScopeCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "epochNonce": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  },
                  "notBefore": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 9007199254740991
                  },
                  "expiresAt": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 9007199254740991
                  },
                  "authenticator": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  }
                }
              },
              "nonce": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "intentCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "held": {
            "type": "object",
            "required": [
              "kind",
              "requestId",
              "prepareAttemptId",
              "state",
              "durability",
              "lookupExpiresAt"
            ],
            "additionalProperties": false,
            "properties": {
              "kind": {
                "const": "held"
              },
              "requestId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              },
              "prepareAttemptId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              },
              "state": {
                "enum": [
                  "waiting_checkpoint",
                  "resuming",
                  "ended"
                ]
              },
              "durability": {
                "const": "durable"
              },
              "lookupExpiresAt": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              },
              "checkpoint": {
                "type": "object",
                "required": [
                  "checkpointId",
                  "checkpointCid",
                  "kind",
                  "expiresAt"
                ],
                "additionalProperties": false,
                "properties": {
                  "checkpointId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  },
                  "checkpointCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "kind": {
                    "enum": [
                      "run_scope",
                      "read_access",
                      "data_egress",
                      "cost_scope",
                      "effect_set"
                    ]
                  },
                  "expiresAt": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  }
                }
              },
              "endReason": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              },
              "terminalErrorCode": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            },
            "allOf": [
              {
                "oneOf": [
                  {
                    "required": [
                      "checkpoint"
                    ],
                    "properties": {
                      "state": {
                        "const": "waiting_checkpoint"
                      }
                    },
                    "allOf": [
                      {
                        "not": {
                          "required": [
                            "endReason"
                          ]
                        }
                      },
                      {
                        "not": {
                          "required": [
                            "terminalErrorCode"
                          ]
                        }
                      }
                    ]
                  },
                  {
                    "properties": {
                      "state": {
                        "const": "resuming"
                      }
                    },
                    "allOf": [
                      {
                        "not": {
                          "required": [
                            "endReason"
                          ]
                        }
                      },
                      {
                        "not": {
                          "required": [
                            "terminalErrorCode"
                          ]
                        }
                      }
                    ]
                  },
                  {
                    "required": [
                      "endReason"
                    ],
                    "properties": {
                      "state": {
                        "const": "ended"
                      }
                    }
                  }
                ]
              }
            ]
          },
          "unresolvedHistory": {
            "type": "object",
            "required": [
              "submissionRef",
              "acknowledgement"
            ],
            "additionalProperties": false,
            "properties": {
              "submissionRef": {
                "type": "object",
                "required": [
                  "epoch",
                  "nonce"
                ],
                "additionalProperties": false,
                "properties": {
                  "epoch": {
                    "type": "object",
                    "required": [
                      "version",
                      "authorityScopeCid",
                      "epochNonce",
                      "notBefore",
                      "expiresAt",
                      "authenticator"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "version": {
                        "const": "actql-submission-epoch/0.1"
                      },
                      "authorityScopeCid": {
                        "type": "string",
                        "pattern": "^sha256:[0-9a-f]{64}$"
                      },
                      "epochNonce": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      },
                      "notBefore": {
                        "type": "integer",
                        "minimum": 0,
                        "maximum": 9007199254740991
                      },
                      "expiresAt": {
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 9007199254740991
                      },
                      "authenticator": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      }
                    }
                  },
                  "nonce": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  }
                }
              },
              "acknowledgement": {
                "const": "possible_prior_execution_and_effects"
              }
            }
          }
        }
      },
      {
        "type": "object",
        "required": [
          "kind",
          "submissionRef",
          "intentCid"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "preparing"
          },
          "submissionRef": {
            "type": "object",
            "required": [
              "epoch",
              "nonce"
            ],
            "additionalProperties": false,
            "properties": {
              "epoch": {
                "type": "object",
                "required": [
                  "version",
                  "authorityScopeCid",
                  "epochNonce",
                  "notBefore",
                  "expiresAt",
                  "authenticator"
                ],
                "additionalProperties": false,
                "properties": {
                  "version": {
                    "const": "actql-submission-epoch/0.1"
                  },
                  "authorityScopeCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "epochNonce": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  },
                  "notBefore": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 9007199254740991
                  },
                  "expiresAt": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 9007199254740991
                  },
                  "authenticator": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  }
                }
              },
              "nonce": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "intentCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "unresolvedHistory": {
            "type": "object",
            "required": [
              "submissionRef",
              "acknowledgement"
            ],
            "additionalProperties": false,
            "properties": {
              "submissionRef": {
                "type": "object",
                "required": [
                  "epoch",
                  "nonce"
                ],
                "additionalProperties": false,
                "properties": {
                  "epoch": {
                    "type": "object",
                    "required": [
                      "version",
                      "authorityScopeCid",
                      "epochNonce",
                      "notBefore",
                      "expiresAt",
                      "authenticator"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "version": {
                        "const": "actql-submission-epoch/0.1"
                      },
                      "authorityScopeCid": {
                        "type": "string",
                        "pattern": "^sha256:[0-9a-f]{64}$"
                      },
                      "epochNonce": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      },
                      "notBefore": {
                        "type": "integer",
                        "minimum": 0,
                        "maximum": 9007199254740991
                      },
                      "expiresAt": {
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 9007199254740991
                      },
                      "authenticator": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      }
                    }
                  },
                  "nonce": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  }
                }
              },
              "acknowledgement": {
                "const": "possible_prior_execution_and_effects"
              }
            }
          }
        }
      },
      {
        "type": "object",
        "required": [
          "kind",
          "submissionRef",
          "intentCid",
          "problem"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "not_accepted"
          },
          "submissionRef": {
            "type": "object",
            "required": [
              "epoch",
              "nonce"
            ],
            "additionalProperties": false,
            "properties": {
              "epoch": {
                "type": "object",
                "required": [
                  "version",
                  "authorityScopeCid",
                  "epochNonce",
                  "notBefore",
                  "expiresAt",
                  "authenticator"
                ],
                "additionalProperties": false,
                "properties": {
                  "version": {
                    "const": "actql-submission-epoch/0.1"
                  },
                  "authorityScopeCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "epochNonce": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  },
                  "notBefore": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 9007199254740991
                  },
                  "expiresAt": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 9007199254740991
                  },
                  "authenticator": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  }
                }
              },
              "nonce": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "intentCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "checkObservation": {
            "allOf": [
              {
                "$ref": "check_outcome"
              },
              {
                "type": "object",
                "properties": {
                  "report": {
                    "type": "object",
                    "properties": {
                      "scope": {
                        "type": "object",
                        "properties": {
                          "kind": {
                            "const": "bound_input"
                          }
                        }
                      }
                    }
                  },
                  "partial_report": {
                    "type": "object",
                    "properties": {
                      "scope": {
                        "type": "object",
                        "properties": {
                          "kind": {
                            "const": "bound_input"
                          }
                        }
                      }
                    }
                  }
                }
              }
            ]
          },
          "problem": {
            "type": "object",
            "required": [
              "code",
              "classification"
            ],
            "additionalProperties": false,
            "properties": {
              "code": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              },
              "classification": {
                "enum": [
                  "invalid_input",
                  "requirements",
                  "implementation_limit",
                  "authorization",
                  "operation_failed"
                ]
              }
            }
          },
          "unresolvedHistory": {
            "type": "object",
            "required": [
              "submissionRef",
              "acknowledgement"
            ],
            "additionalProperties": false,
            "properties": {
              "submissionRef": {
                "type": "object",
                "required": [
                  "epoch",
                  "nonce"
                ],
                "additionalProperties": false,
                "properties": {
                  "epoch": {
                    "type": "object",
                    "required": [
                      "version",
                      "authorityScopeCid",
                      "epochNonce",
                      "notBefore",
                      "expiresAt",
                      "authenticator"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "version": {
                        "const": "actql-submission-epoch/0.1"
                      },
                      "authorityScopeCid": {
                        "type": "string",
                        "pattern": "^sha256:[0-9a-f]{64}$"
                      },
                      "epochNonce": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      },
                      "notBefore": {
                        "type": "integer",
                        "minimum": 0,
                        "maximum": 9007199254740991
                      },
                      "expiresAt": {
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 9007199254740991
                      },
                      "authenticator": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      }
                    }
                  },
                  "nonce": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  }
                }
              },
              "acknowledgement": {
                "const": "possible_prior_execution_and_effects"
              }
            }
          }
        }
      },
      {
        "type": "object",
        "required": [
          "kind",
          "submissionRef",
          "intentCid",
          "problem"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "preparation_failed"
          },
          "submissionRef": {
            "type": "object",
            "required": [
              "epoch",
              "nonce"
            ],
            "additionalProperties": false,
            "properties": {
              "epoch": {
                "type": "object",
                "required": [
                  "version",
                  "authorityScopeCid",
                  "epochNonce",
                  "notBefore",
                  "expiresAt",
                  "authenticator"
                ],
                "additionalProperties": false,
                "properties": {
                  "version": {
                    "const": "actql-submission-epoch/0.1"
                  },
                  "authorityScopeCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "epochNonce": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  },
                  "notBefore": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 9007199254740991
                  },
                  "expiresAt": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 9007199254740991
                  },
                  "authenticator": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  }
                }
              },
              "nonce": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "intentCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "checkObservation": {
            "allOf": [
              {
                "$ref": "check_outcome"
              },
              {
                "type": "object",
                "properties": {
                  "report": {
                    "type": "object",
                    "properties": {
                      "scope": {
                        "type": "object",
                        "properties": {
                          "kind": {
                            "const": "bound_input"
                          }
                        }
                      }
                    }
                  },
                  "partial_report": {
                    "type": "object",
                    "properties": {
                      "scope": {
                        "type": "object",
                        "properties": {
                          "kind": {
                            "const": "bound_input"
                          }
                        }
                      }
                    }
                  }
                }
              }
            ]
          },
          "problem": {
            "type": "object",
            "required": [
              "code",
              "classification"
            ],
            "additionalProperties": false,
            "properties": {
              "code": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              },
              "classification": {
                "enum": [
                  "invalid_input",
                  "requirements",
                  "implementation_limit",
                  "authorization",
                  "operation_failed"
                ]
              }
            }
          },
          "unresolvedHistory": {
            "type": "object",
            "required": [
              "submissionRef",
              "acknowledgement"
            ],
            "additionalProperties": false,
            "properties": {
              "submissionRef": {
                "type": "object",
                "required": [
                  "epoch",
                  "nonce"
                ],
                "additionalProperties": false,
                "properties": {
                  "epoch": {
                    "type": "object",
                    "required": [
                      "version",
                      "authorityScopeCid",
                      "epochNonce",
                      "notBefore",
                      "expiresAt",
                      "authenticator"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "version": {
                        "const": "actql-submission-epoch/0.1"
                      },
                      "authorityScopeCid": {
                        "type": "string",
                        "pattern": "^sha256:[0-9a-f]{64}$"
                      },
                      "epochNonce": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      },
                      "notBefore": {
                        "type": "integer",
                        "minimum": 0,
                        "maximum": 9007199254740991
                      },
                      "expiresAt": {
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 9007199254740991
                      },
                      "authenticator": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      }
                    }
                  },
                  "nonce": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  }
                }
              },
              "acknowledgement": {
                "const": "possible_prior_execution_and_effects"
              }
            }
          }
        }
      }
    ]
  },
  "submission_lookup": {
    "oneOf": [
      {
        "type": "object",
        "required": [
          "kind",
          "submissionRef",
          "intentCid",
          "admission"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "ready"
          },
          "submissionRef": {
            "type": "object",
            "required": [
              "epoch",
              "nonce"
            ],
            "additionalProperties": false,
            "properties": {
              "epoch": {
                "type": "object",
                "required": [
                  "version",
                  "authorityScopeCid",
                  "epochNonce",
                  "notBefore",
                  "expiresAt",
                  "authenticator"
                ],
                "additionalProperties": false,
                "properties": {
                  "version": {
                    "const": "actql-submission-epoch/0.1"
                  },
                  "authorityScopeCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "epochNonce": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  },
                  "notBefore": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 9007199254740991
                  },
                  "expiresAt": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 9007199254740991
                  },
                  "authenticator": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  }
                }
              },
              "nonce": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "intentCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "admission": {
            "type": "object",
            "required": [
              "ref",
              "durability",
              "revision"
            ],
            "additionalProperties": false,
            "properties": {
              "ref": {
                "type": "object",
                "required": [
                  "namespaceId",
                  "authorityScopeCid",
                  "runDefinitionCid"
                ],
                "additionalProperties": false,
                "properties": {
                  "namespaceId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
          "unresolvedHistory": {
            "type": "object",
            "required": [
              "submissionRef",
              "acknowledgement"
            ],
            "additionalProperties": false,
            "properties": {
              "submissionRef": {
                "type": "object",
                "required": [
                  "epoch",
                  "nonce"
                ],
                "additionalProperties": false,
                "properties": {
                  "epoch": {
                    "type": "object",
                    "required": [
                      "version",
                      "authorityScopeCid",
                      "epochNonce",
                      "notBefore",
                      "expiresAt",
                      "authenticator"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "version": {
                        "const": "actql-submission-epoch/0.1"
                      },
                      "authorityScopeCid": {
                        "type": "string",
                        "pattern": "^sha256:[0-9a-f]{64}$"
                      },
                      "epochNonce": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      },
                      "notBefore": {
                        "type": "integer",
                        "minimum": 0,
                        "maximum": 9007199254740991
                      },
                      "expiresAt": {
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 9007199254740991
                      },
                      "authenticator": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      }
                    }
                  },
                  "nonce": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  }
                }
              },
              "acknowledgement": {
                "const": "possible_prior_execution_and_effects"
              }
            }
          }
        }
      },
      {
        "type": "object",
        "required": [
          "kind",
          "submissionRef",
          "intentCid",
          "held"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "held"
          },
          "submissionRef": {
            "type": "object",
            "required": [
              "epoch",
              "nonce"
            ],
            "additionalProperties": false,
            "properties": {
              "epoch": {
                "type": "object",
                "required": [
                  "version",
                  "authorityScopeCid",
                  "epochNonce",
                  "notBefore",
                  "expiresAt",
                  "authenticator"
                ],
                "additionalProperties": false,
                "properties": {
                  "version": {
                    "const": "actql-submission-epoch/0.1"
                  },
                  "authorityScopeCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "epochNonce": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  },
                  "notBefore": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 9007199254740991
                  },
                  "expiresAt": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 9007199254740991
                  },
                  "authenticator": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  }
                }
              },
              "nonce": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "intentCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "held": {
            "type": "object",
            "required": [
              "kind",
              "requestId",
              "prepareAttemptId",
              "state",
              "durability",
              "lookupExpiresAt"
            ],
            "additionalProperties": false,
            "properties": {
              "kind": {
                "const": "held"
              },
              "requestId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              },
              "prepareAttemptId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              },
              "state": {
                "enum": [
                  "waiting_checkpoint",
                  "resuming",
                  "ended"
                ]
              },
              "durability": {
                "const": "durable"
              },
              "lookupExpiresAt": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              },
              "checkpoint": {
                "type": "object",
                "required": [
                  "checkpointId",
                  "checkpointCid",
                  "kind",
                  "expiresAt"
                ],
                "additionalProperties": false,
                "properties": {
                  "checkpointId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  },
                  "checkpointCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "kind": {
                    "enum": [
                      "run_scope",
                      "read_access",
                      "data_egress",
                      "cost_scope",
                      "effect_set"
                    ]
                  },
                  "expiresAt": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  }
                }
              },
              "endReason": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              },
              "terminalErrorCode": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            },
            "allOf": [
              {
                "oneOf": [
                  {
                    "required": [
                      "checkpoint"
                    ],
                    "properties": {
                      "state": {
                        "const": "waiting_checkpoint"
                      }
                    },
                    "allOf": [
                      {
                        "not": {
                          "required": [
                            "endReason"
                          ]
                        }
                      },
                      {
                        "not": {
                          "required": [
                            "terminalErrorCode"
                          ]
                        }
                      }
                    ]
                  },
                  {
                    "properties": {
                      "state": {
                        "const": "resuming"
                      }
                    },
                    "allOf": [
                      {
                        "not": {
                          "required": [
                            "endReason"
                          ]
                        }
                      },
                      {
                        "not": {
                          "required": [
                            "terminalErrorCode"
                          ]
                        }
                      }
                    ]
                  },
                  {
                    "required": [
                      "endReason"
                    ],
                    "properties": {
                      "state": {
                        "const": "ended"
                      }
                    }
                  }
                ]
              }
            ]
          },
          "unresolvedHistory": {
            "type": "object",
            "required": [
              "submissionRef",
              "acknowledgement"
            ],
            "additionalProperties": false,
            "properties": {
              "submissionRef": {
                "type": "object",
                "required": [
                  "epoch",
                  "nonce"
                ],
                "additionalProperties": false,
                "properties": {
                  "epoch": {
                    "type": "object",
                    "required": [
                      "version",
                      "authorityScopeCid",
                      "epochNonce",
                      "notBefore",
                      "expiresAt",
                      "authenticator"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "version": {
                        "const": "actql-submission-epoch/0.1"
                      },
                      "authorityScopeCid": {
                        "type": "string",
                        "pattern": "^sha256:[0-9a-f]{64}$"
                      },
                      "epochNonce": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      },
                      "notBefore": {
                        "type": "integer",
                        "minimum": 0,
                        "maximum": 9007199254740991
                      },
                      "expiresAt": {
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 9007199254740991
                      },
                      "authenticator": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      }
                    }
                  },
                  "nonce": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  }
                }
              },
              "acknowledgement": {
                "const": "possible_prior_execution_and_effects"
              }
            }
          }
        }
      },
      {
        "type": "object",
        "required": [
          "kind",
          "submissionRef",
          "intentCid"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "preparing"
          },
          "submissionRef": {
            "type": "object",
            "required": [
              "epoch",
              "nonce"
            ],
            "additionalProperties": false,
            "properties": {
              "epoch": {
                "type": "object",
                "required": [
                  "version",
                  "authorityScopeCid",
                  "epochNonce",
                  "notBefore",
                  "expiresAt",
                  "authenticator"
                ],
                "additionalProperties": false,
                "properties": {
                  "version": {
                    "const": "actql-submission-epoch/0.1"
                  },
                  "authorityScopeCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "epochNonce": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  },
                  "notBefore": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 9007199254740991
                  },
                  "expiresAt": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 9007199254740991
                  },
                  "authenticator": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  }
                }
              },
              "nonce": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "intentCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "unresolvedHistory": {
            "type": "object",
            "required": [
              "submissionRef",
              "acknowledgement"
            ],
            "additionalProperties": false,
            "properties": {
              "submissionRef": {
                "type": "object",
                "required": [
                  "epoch",
                  "nonce"
                ],
                "additionalProperties": false,
                "properties": {
                  "epoch": {
                    "type": "object",
                    "required": [
                      "version",
                      "authorityScopeCid",
                      "epochNonce",
                      "notBefore",
                      "expiresAt",
                      "authenticator"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "version": {
                        "const": "actql-submission-epoch/0.1"
                      },
                      "authorityScopeCid": {
                        "type": "string",
                        "pattern": "^sha256:[0-9a-f]{64}$"
                      },
                      "epochNonce": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      },
                      "notBefore": {
                        "type": "integer",
                        "minimum": 0,
                        "maximum": 9007199254740991
                      },
                      "expiresAt": {
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 9007199254740991
                      },
                      "authenticator": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      }
                    }
                  },
                  "nonce": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  }
                }
              },
              "acknowledgement": {
                "const": "possible_prior_execution_and_effects"
              }
            }
          }
        }
      },
      {
        "type": "object",
        "required": [
          "kind",
          "submissionRef",
          "intentCid",
          "problem"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "not_accepted"
          },
          "submissionRef": {
            "type": "object",
            "required": [
              "epoch",
              "nonce"
            ],
            "additionalProperties": false,
            "properties": {
              "epoch": {
                "type": "object",
                "required": [
                  "version",
                  "authorityScopeCid",
                  "epochNonce",
                  "notBefore",
                  "expiresAt",
                  "authenticator"
                ],
                "additionalProperties": false,
                "properties": {
                  "version": {
                    "const": "actql-submission-epoch/0.1"
                  },
                  "authorityScopeCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "epochNonce": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  },
                  "notBefore": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 9007199254740991
                  },
                  "expiresAt": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 9007199254740991
                  },
                  "authenticator": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  }
                }
              },
              "nonce": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "intentCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "problem": {
            "type": "object",
            "required": [
              "code",
              "classification"
            ],
            "additionalProperties": false,
            "properties": {
              "code": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              },
              "classification": {
                "enum": [
                  "invalid_input",
                  "requirements",
                  "implementation_limit",
                  "authorization",
                  "operation_failed"
                ]
              }
            }
          },
          "unresolvedHistory": {
            "type": "object",
            "required": [
              "submissionRef",
              "acknowledgement"
            ],
            "additionalProperties": false,
            "properties": {
              "submissionRef": {
                "type": "object",
                "required": [
                  "epoch",
                  "nonce"
                ],
                "additionalProperties": false,
                "properties": {
                  "epoch": {
                    "type": "object",
                    "required": [
                      "version",
                      "authorityScopeCid",
                      "epochNonce",
                      "notBefore",
                      "expiresAt",
                      "authenticator"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "version": {
                        "const": "actql-submission-epoch/0.1"
                      },
                      "authorityScopeCid": {
                        "type": "string",
                        "pattern": "^sha256:[0-9a-f]{64}$"
                      },
                      "epochNonce": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      },
                      "notBefore": {
                        "type": "integer",
                        "minimum": 0,
                        "maximum": 9007199254740991
                      },
                      "expiresAt": {
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 9007199254740991
                      },
                      "authenticator": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      }
                    }
                  },
                  "nonce": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  }
                }
              },
              "acknowledgement": {
                "const": "possible_prior_execution_and_effects"
              }
            }
          }
        }
      },
      {
        "type": "object",
        "required": [
          "kind",
          "submissionRef",
          "intentCid",
          "problem"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "preparation_failed"
          },
          "submissionRef": {
            "type": "object",
            "required": [
              "epoch",
              "nonce"
            ],
            "additionalProperties": false,
            "properties": {
              "epoch": {
                "type": "object",
                "required": [
                  "version",
                  "authorityScopeCid",
                  "epochNonce",
                  "notBefore",
                  "expiresAt",
                  "authenticator"
                ],
                "additionalProperties": false,
                "properties": {
                  "version": {
                    "const": "actql-submission-epoch/0.1"
                  },
                  "authorityScopeCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "epochNonce": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  },
                  "notBefore": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 9007199254740991
                  },
                  "expiresAt": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 9007199254740991
                  },
                  "authenticator": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  }
                }
              },
              "nonce": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "intentCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "problem": {
            "type": "object",
            "required": [
              "code",
              "classification"
            ],
            "additionalProperties": false,
            "properties": {
              "code": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              },
              "classification": {
                "enum": [
                  "invalid_input",
                  "requirements",
                  "implementation_limit",
                  "authorization",
                  "operation_failed"
                ]
              }
            }
          },
          "unresolvedHistory": {
            "type": "object",
            "required": [
              "submissionRef",
              "acknowledgement"
            ],
            "additionalProperties": false,
            "properties": {
              "submissionRef": {
                "type": "object",
                "required": [
                  "epoch",
                  "nonce"
                ],
                "additionalProperties": false,
                "properties": {
                  "epoch": {
                    "type": "object",
                    "required": [
                      "version",
                      "authorityScopeCid",
                      "epochNonce",
                      "notBefore",
                      "expiresAt",
                      "authenticator"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "version": {
                        "const": "actql-submission-epoch/0.1"
                      },
                      "authorityScopeCid": {
                        "type": "string",
                        "pattern": "^sha256:[0-9a-f]{64}$"
                      },
                      "epochNonce": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      },
                      "notBefore": {
                        "type": "integer",
                        "minimum": 0,
                        "maximum": 9007199254740991
                      },
                      "expiresAt": {
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 9007199254740991
                      },
                      "authenticator": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      }
                    }
                  },
                  "nonce": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  }
                }
              },
              "acknowledgement": {
                "const": "possible_prior_execution_and_effects"
              }
            }
          }
        }
      },
      {
        "type": "object",
        "required": [
          "kind",
          "submissionRef",
          "problem"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "unresolvable"
          },
          "submissionRef": {
            "type": "object",
            "required": [
              "epoch",
              "nonce"
            ],
            "additionalProperties": false,
            "properties": {
              "epoch": {
                "type": "object",
                "required": [
                  "version",
                  "authorityScopeCid",
                  "epochNonce",
                  "notBefore",
                  "expiresAt",
                  "authenticator"
                ],
                "additionalProperties": false,
                "properties": {
                  "version": {
                    "const": "actql-submission-epoch/0.1"
                  },
                  "authorityScopeCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "epochNonce": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  },
                  "notBefore": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 9007199254740991
                  },
                  "expiresAt": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 9007199254740991
                  },
                  "authenticator": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  }
                }
              },
              "nonce": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "problem": {
            "type": "object",
            "required": [
              "code"
            ],
            "additionalProperties": false,
            "properties": {
              "code": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "unresolvedHistory": {
            "type": "object",
            "required": [
              "submissionRef",
              "acknowledgement"
            ],
            "additionalProperties": false,
            "properties": {
              "submissionRef": {
                "type": "object",
                "required": [
                  "epoch",
                  "nonce"
                ],
                "additionalProperties": false,
                "properties": {
                  "epoch": {
                    "type": "object",
                    "required": [
                      "version",
                      "authorityScopeCid",
                      "epochNonce",
                      "notBefore",
                      "expiresAt",
                      "authenticator"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "version": {
                        "const": "actql-submission-epoch/0.1"
                      },
                      "authorityScopeCid": {
                        "type": "string",
                        "pattern": "^sha256:[0-9a-f]{64}$"
                      },
                      "epochNonce": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      },
                      "notBefore": {
                        "type": "integer",
                        "minimum": 0,
                        "maximum": 9007199254740991
                      },
                      "expiresAt": {
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 9007199254740991
                      },
                      "authenticator": {
                        "type": "string",
                        "pattern": "^[0-9a-f]{64}$"
                      }
                    }
                  },
                  "nonce": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  }
                }
              },
              "acknowledgement": {
                "const": "possible_prior_execution_and_effects"
              }
            }
          }
        }
      }
    ]
  },
  "submission_restart": {
    "type": "object",
    "required": [
      "submissionRef",
      "acknowledgement"
    ],
    "additionalProperties": false,
    "properties": {
      "submissionRef": {
        "type": "object",
        "required": [
          "epoch",
          "nonce"
        ],
        "additionalProperties": false,
        "properties": {
          "epoch": {
            "type": "object",
            "required": [
              "version",
              "authorityScopeCid",
              "epochNonce",
              "notBefore",
              "expiresAt",
              "authenticator"
            ],
            "additionalProperties": false,
            "properties": {
              "version": {
                "const": "actql-submission-epoch/0.1"
              },
              "authorityScopeCid": {
                "type": "string",
                "pattern": "^sha256:[0-9a-f]{64}$"
              },
              "epochNonce": {
                "type": "string",
                "pattern": "^[0-9a-f]{64}$"
              },
              "notBefore": {
                "type": "integer",
                "minimum": 0,
                "maximum": 9007199254740991
              },
              "expiresAt": {
                "type": "integer",
                "minimum": 1,
                "maximum": 9007199254740991
              },
              "authenticator": {
                "type": "string",
                "pattern": "^[0-9a-f]{64}$"
              }
            }
          },
          "nonce": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
            "minLength": 1,
            "maxLength": 256
          }
        }
      },
      "acknowledgement": {
        "const": "possible_prior_execution_and_effects"
      }
    }
  },
  "submission_attempt": {
    "oneOf": [
      {
        "type": "object",
        "required": [
          "kind",
          "attemptRef",
          "outcome"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "enum": [
              "recorded",
              "already_satisfied"
            ]
          },
          "attemptRef": {
            "type": "object",
            "required": [
              "operation",
              "attemptId"
            ],
            "additionalProperties": false,
            "properties": {
              "operation": {
                "const": "submit"
              },
              "attemptId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "outcome": {
            "oneOf": [
              {
                "type": "object",
                "required": [
                  "kind",
                  "submissionRef",
                  "intentCid",
                  "admission"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "const": "ready"
                  },
                  "submissionRef": {
                    "type": "object",
                    "required": [
                      "epoch",
                      "nonce"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "epoch": {
                        "type": "object",
                        "required": [
                          "version",
                          "authorityScopeCid",
                          "epochNonce",
                          "notBefore",
                          "expiresAt",
                          "authenticator"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "version": {
                            "const": "actql-submission-epoch/0.1"
                          },
                          "authorityScopeCid": {
                            "type": "string",
                            "pattern": "^sha256:[0-9a-f]{64}$"
                          },
                          "epochNonce": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          },
                          "notBefore": {
                            "type": "integer",
                            "minimum": 0,
                            "maximum": 9007199254740991
                          },
                          "expiresAt": {
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 9007199254740991
                          },
                          "authenticator": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          }
                        }
                      },
                      "nonce": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      }
                    }
                  },
                  "intentCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "admission": {
                    "type": "object",
                    "required": [
                      "ref",
                      "durability",
                      "revision"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "ref": {
                        "type": "object",
                        "required": [
                          "namespaceId",
                          "authorityScopeCid",
                          "runDefinitionCid"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "namespaceId": {
                            "type": "string",
                            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
                  "unresolvedHistory": {
                    "type": "object",
                    "required": [
                      "submissionRef",
                      "acknowledgement"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "submissionRef": {
                        "type": "object",
                        "required": [
                          "epoch",
                          "nonce"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "epoch": {
                            "type": "object",
                            "required": [
                              "version",
                              "authorityScopeCid",
                              "epochNonce",
                              "notBefore",
                              "expiresAt",
                              "authenticator"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "version": {
                                "const": "actql-submission-epoch/0.1"
                              },
                              "authorityScopeCid": {
                                "type": "string",
                                "pattern": "^sha256:[0-9a-f]{64}$"
                              },
                              "epochNonce": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              },
                              "notBefore": {
                                "type": "integer",
                                "minimum": 0,
                                "maximum": 9007199254740991
                              },
                              "expiresAt": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 9007199254740991
                              },
                              "authenticator": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              }
                            }
                          },
                          "nonce": {
                            "type": "string",
                            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                            "minLength": 1,
                            "maxLength": 256
                          }
                        }
                      },
                      "acknowledgement": {
                        "const": "possible_prior_execution_and_effects"
                      }
                    }
                  }
                }
              },
              {
                "type": "object",
                "required": [
                  "kind",
                  "submissionRef",
                  "intentCid",
                  "held"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "const": "held"
                  },
                  "submissionRef": {
                    "type": "object",
                    "required": [
                      "epoch",
                      "nonce"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "epoch": {
                        "type": "object",
                        "required": [
                          "version",
                          "authorityScopeCid",
                          "epochNonce",
                          "notBefore",
                          "expiresAt",
                          "authenticator"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "version": {
                            "const": "actql-submission-epoch/0.1"
                          },
                          "authorityScopeCid": {
                            "type": "string",
                            "pattern": "^sha256:[0-9a-f]{64}$"
                          },
                          "epochNonce": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          },
                          "notBefore": {
                            "type": "integer",
                            "minimum": 0,
                            "maximum": 9007199254740991
                          },
                          "expiresAt": {
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 9007199254740991
                          },
                          "authenticator": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          }
                        }
                      },
                      "nonce": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      }
                    }
                  },
                  "intentCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "held": {
                    "type": "object",
                    "required": [
                      "kind",
                      "requestId",
                      "prepareAttemptId",
                      "state",
                      "durability",
                      "lookupExpiresAt"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "kind": {
                        "const": "held"
                      },
                      "requestId": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      },
                      "prepareAttemptId": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      },
                      "state": {
                        "enum": [
                          "waiting_checkpoint",
                          "resuming",
                          "ended"
                        ]
                      },
                      "durability": {
                        "const": "durable"
                      },
                      "lookupExpiresAt": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      },
                      "checkpoint": {
                        "type": "object",
                        "required": [
                          "checkpointId",
                          "checkpointCid",
                          "kind",
                          "expiresAt"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "checkpointId": {
                            "type": "string",
                            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                            "minLength": 1,
                            "maxLength": 256
                          },
                          "checkpointCid": {
                            "type": "string",
                            "pattern": "^sha256:[0-9a-f]{64}$"
                          },
                          "kind": {
                            "enum": [
                              "run_scope",
                              "read_access",
                              "data_egress",
                              "cost_scope",
                              "effect_set"
                            ]
                          },
                          "expiresAt": {
                            "type": "string",
                            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                            "minLength": 1,
                            "maxLength": 256
                          }
                        }
                      },
                      "endReason": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      },
                      "terminalErrorCode": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      }
                    },
                    "allOf": [
                      {
                        "oneOf": [
                          {
                            "required": [
                              "checkpoint"
                            ],
                            "properties": {
                              "state": {
                                "const": "waiting_checkpoint"
                              }
                            },
                            "allOf": [
                              {
                                "not": {
                                  "required": [
                                    "endReason"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "terminalErrorCode"
                                  ]
                                }
                              }
                            ]
                          },
                          {
                            "properties": {
                              "state": {
                                "const": "resuming"
                              }
                            },
                            "allOf": [
                              {
                                "not": {
                                  "required": [
                                    "endReason"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "terminalErrorCode"
                                  ]
                                }
                              }
                            ]
                          },
                          {
                            "required": [
                              "endReason"
                            ],
                            "properties": {
                              "state": {
                                "const": "ended"
                              }
                            }
                          }
                        ]
                      }
                    ]
                  },
                  "unresolvedHistory": {
                    "type": "object",
                    "required": [
                      "submissionRef",
                      "acknowledgement"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "submissionRef": {
                        "type": "object",
                        "required": [
                          "epoch",
                          "nonce"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "epoch": {
                            "type": "object",
                            "required": [
                              "version",
                              "authorityScopeCid",
                              "epochNonce",
                              "notBefore",
                              "expiresAt",
                              "authenticator"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "version": {
                                "const": "actql-submission-epoch/0.1"
                              },
                              "authorityScopeCid": {
                                "type": "string",
                                "pattern": "^sha256:[0-9a-f]{64}$"
                              },
                              "epochNonce": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              },
                              "notBefore": {
                                "type": "integer",
                                "minimum": 0,
                                "maximum": 9007199254740991
                              },
                              "expiresAt": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 9007199254740991
                              },
                              "authenticator": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              }
                            }
                          },
                          "nonce": {
                            "type": "string",
                            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                            "minLength": 1,
                            "maxLength": 256
                          }
                        }
                      },
                      "acknowledgement": {
                        "const": "possible_prior_execution_and_effects"
                      }
                    }
                  }
                }
              },
              {
                "type": "object",
                "required": [
                  "kind",
                  "submissionRef",
                  "intentCid"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "const": "preparing"
                  },
                  "submissionRef": {
                    "type": "object",
                    "required": [
                      "epoch",
                      "nonce"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "epoch": {
                        "type": "object",
                        "required": [
                          "version",
                          "authorityScopeCid",
                          "epochNonce",
                          "notBefore",
                          "expiresAt",
                          "authenticator"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "version": {
                            "const": "actql-submission-epoch/0.1"
                          },
                          "authorityScopeCid": {
                            "type": "string",
                            "pattern": "^sha256:[0-9a-f]{64}$"
                          },
                          "epochNonce": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          },
                          "notBefore": {
                            "type": "integer",
                            "minimum": 0,
                            "maximum": 9007199254740991
                          },
                          "expiresAt": {
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 9007199254740991
                          },
                          "authenticator": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          }
                        }
                      },
                      "nonce": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      }
                    }
                  },
                  "intentCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "unresolvedHistory": {
                    "type": "object",
                    "required": [
                      "submissionRef",
                      "acknowledgement"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "submissionRef": {
                        "type": "object",
                        "required": [
                          "epoch",
                          "nonce"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "epoch": {
                            "type": "object",
                            "required": [
                              "version",
                              "authorityScopeCid",
                              "epochNonce",
                              "notBefore",
                              "expiresAt",
                              "authenticator"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "version": {
                                "const": "actql-submission-epoch/0.1"
                              },
                              "authorityScopeCid": {
                                "type": "string",
                                "pattern": "^sha256:[0-9a-f]{64}$"
                              },
                              "epochNonce": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              },
                              "notBefore": {
                                "type": "integer",
                                "minimum": 0,
                                "maximum": 9007199254740991
                              },
                              "expiresAt": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 9007199254740991
                              },
                              "authenticator": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              }
                            }
                          },
                          "nonce": {
                            "type": "string",
                            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                            "minLength": 1,
                            "maxLength": 256
                          }
                        }
                      },
                      "acknowledgement": {
                        "const": "possible_prior_execution_and_effects"
                      }
                    }
                  }
                }
              },
              {
                "type": "object",
                "required": [
                  "kind",
                  "submissionRef",
                  "intentCid",
                  "problem"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "const": "not_accepted"
                  },
                  "submissionRef": {
                    "type": "object",
                    "required": [
                      "epoch",
                      "nonce"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "epoch": {
                        "type": "object",
                        "required": [
                          "version",
                          "authorityScopeCid",
                          "epochNonce",
                          "notBefore",
                          "expiresAt",
                          "authenticator"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "version": {
                            "const": "actql-submission-epoch/0.1"
                          },
                          "authorityScopeCid": {
                            "type": "string",
                            "pattern": "^sha256:[0-9a-f]{64}$"
                          },
                          "epochNonce": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          },
                          "notBefore": {
                            "type": "integer",
                            "minimum": 0,
                            "maximum": 9007199254740991
                          },
                          "expiresAt": {
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 9007199254740991
                          },
                          "authenticator": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          }
                        }
                      },
                      "nonce": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      }
                    }
                  },
                  "intentCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "checkObservation": {
                    "allOf": [
                      {
                        "$ref": "check_outcome"
                      },
                      {
                        "type": "object",
                        "properties": {
                          "report": {
                            "type": "object",
                            "properties": {
                              "scope": {
                                "type": "object",
                                "properties": {
                                  "kind": {
                                    "const": "bound_input"
                                  }
                                }
                              }
                            }
                          },
                          "partial_report": {
                            "type": "object",
                            "properties": {
                              "scope": {
                                "type": "object",
                                "properties": {
                                  "kind": {
                                    "const": "bound_input"
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    ]
                  },
                  "problem": {
                    "type": "object",
                    "required": [
                      "code",
                      "classification"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "code": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      },
                      "classification": {
                        "enum": [
                          "invalid_input",
                          "requirements",
                          "implementation_limit",
                          "authorization",
                          "operation_failed"
                        ]
                      }
                    }
                  },
                  "unresolvedHistory": {
                    "type": "object",
                    "required": [
                      "submissionRef",
                      "acknowledgement"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "submissionRef": {
                        "type": "object",
                        "required": [
                          "epoch",
                          "nonce"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "epoch": {
                            "type": "object",
                            "required": [
                              "version",
                              "authorityScopeCid",
                              "epochNonce",
                              "notBefore",
                              "expiresAt",
                              "authenticator"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "version": {
                                "const": "actql-submission-epoch/0.1"
                              },
                              "authorityScopeCid": {
                                "type": "string",
                                "pattern": "^sha256:[0-9a-f]{64}$"
                              },
                              "epochNonce": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              },
                              "notBefore": {
                                "type": "integer",
                                "minimum": 0,
                                "maximum": 9007199254740991
                              },
                              "expiresAt": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 9007199254740991
                              },
                              "authenticator": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              }
                            }
                          },
                          "nonce": {
                            "type": "string",
                            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                            "minLength": 1,
                            "maxLength": 256
                          }
                        }
                      },
                      "acknowledgement": {
                        "const": "possible_prior_execution_and_effects"
                      }
                    }
                  }
                }
              },
              {
                "type": "object",
                "required": [
                  "kind",
                  "submissionRef",
                  "intentCid",
                  "problem"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "const": "preparation_failed"
                  },
                  "submissionRef": {
                    "type": "object",
                    "required": [
                      "epoch",
                      "nonce"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "epoch": {
                        "type": "object",
                        "required": [
                          "version",
                          "authorityScopeCid",
                          "epochNonce",
                          "notBefore",
                          "expiresAt",
                          "authenticator"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "version": {
                            "const": "actql-submission-epoch/0.1"
                          },
                          "authorityScopeCid": {
                            "type": "string",
                            "pattern": "^sha256:[0-9a-f]{64}$"
                          },
                          "epochNonce": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          },
                          "notBefore": {
                            "type": "integer",
                            "minimum": 0,
                            "maximum": 9007199254740991
                          },
                          "expiresAt": {
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 9007199254740991
                          },
                          "authenticator": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          }
                        }
                      },
                      "nonce": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      }
                    }
                  },
                  "intentCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "checkObservation": {
                    "allOf": [
                      {
                        "$ref": "check_outcome"
                      },
                      {
                        "type": "object",
                        "properties": {
                          "report": {
                            "type": "object",
                            "properties": {
                              "scope": {
                                "type": "object",
                                "properties": {
                                  "kind": {
                                    "const": "bound_input"
                                  }
                                }
                              }
                            }
                          },
                          "partial_report": {
                            "type": "object",
                            "properties": {
                              "scope": {
                                "type": "object",
                                "properties": {
                                  "kind": {
                                    "const": "bound_input"
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    ]
                  },
                  "problem": {
                    "type": "object",
                    "required": [
                      "code",
                      "classification"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "code": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      },
                      "classification": {
                        "enum": [
                          "invalid_input",
                          "requirements",
                          "implementation_limit",
                          "authorization",
                          "operation_failed"
                        ]
                      }
                    }
                  },
                  "unresolvedHistory": {
                    "type": "object",
                    "required": [
                      "submissionRef",
                      "acknowledgement"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "submissionRef": {
                        "type": "object",
                        "required": [
                          "epoch",
                          "nonce"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "epoch": {
                            "type": "object",
                            "required": [
                              "version",
                              "authorityScopeCid",
                              "epochNonce",
                              "notBefore",
                              "expiresAt",
                              "authenticator"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "version": {
                                "const": "actql-submission-epoch/0.1"
                              },
                              "authorityScopeCid": {
                                "type": "string",
                                "pattern": "^sha256:[0-9a-f]{64}$"
                              },
                              "epochNonce": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              },
                              "notBefore": {
                                "type": "integer",
                                "minimum": 0,
                                "maximum": 9007199254740991
                              },
                              "expiresAt": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 9007199254740991
                              },
                              "authenticator": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              }
                            }
                          },
                          "nonce": {
                            "type": "string",
                            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                            "minLength": 1,
                            "maxLength": 256
                          }
                        }
                      },
                      "acknowledgement": {
                        "const": "possible_prior_execution_and_effects"
                      }
                    }
                  }
                }
              }
            ]
          }
        },
        "allOf": [
          {
            "if": {
              "type": "object",
              "required": [
                "kind"
              ],
              "properties": {
                "kind": {
                  "const": "already_satisfied"
                }
              }
            },
            "then": {
              "type": "object",
              "required": [
                "outcome"
              ],
              "properties": {
                "outcome": {
                  "not": {
                    "type": "object",
                    "required": [
                      "kind"
                    ],
                    "properties": {
                      "kind": {
                        "const": "preparing"
                      }
                    }
                  }
                }
              }
            }
          }
        ]
      },
      {
        "type": "object",
        "required": [
          "kind",
          "attemptRef",
          "guarantee",
          "reason"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "refused"
          },
          "attemptRef": {
            "type": "object",
            "required": [
              "operation",
              "attemptId"
            ],
            "additionalProperties": false,
            "properties": {
              "operation": {
                "const": "submit"
              },
              "attemptId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "guarantee": {
            "const": "attempt_uncommitted_unconsumed"
          },
          "reason": {
            "const": "authorization"
          }
        }
      },
      {
        "type": "object",
        "required": [
          "kind",
          "attemptRef",
          "submissionRef",
          "intentCid",
          "guarantee",
          "reason"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "refused"
          },
          "attemptRef": {
            "type": "object",
            "required": [
              "operation",
              "attemptId"
            ],
            "additionalProperties": false,
            "properties": {
              "operation": {
                "const": "submit"
              },
              "attemptId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "submissionRef": {
            "type": "object",
            "required": [
              "epoch",
              "nonce"
            ],
            "additionalProperties": false,
            "properties": {
              "epoch": {
                "type": "object",
                "required": [
                  "version",
                  "authorityScopeCid",
                  "epochNonce",
                  "notBefore",
                  "expiresAt",
                  "authenticator"
                ],
                "additionalProperties": false,
                "properties": {
                  "version": {
                    "const": "actql-submission-epoch/0.1"
                  },
                  "authorityScopeCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "epochNonce": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  },
                  "notBefore": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 9007199254740991
                  },
                  "expiresAt": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 9007199254740991
                  },
                  "authenticator": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  }
                }
              },
              "nonce": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "intentCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "guarantee": {
            "const": "attempt_uncommitted_unconsumed"
          },
          "reason": {
            "enum": [
              "admission_capacity",
              "epoch_expired",
              "epoch_not_yet_valid"
            ]
          }
        }
      },
      {
        "type": "object",
        "required": [
          "kind",
          "attemptRef",
          "submissionRef",
          "intentCid",
          "reason"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "conflict"
          },
          "attemptRef": {
            "type": "object",
            "required": [
              "operation",
              "attemptId"
            ],
            "additionalProperties": false,
            "properties": {
              "operation": {
                "const": "submit"
              },
              "attemptId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "submissionRef": {
            "type": "object",
            "required": [
              "epoch",
              "nonce"
            ],
            "additionalProperties": false,
            "properties": {
              "epoch": {
                "type": "object",
                "required": [
                  "version",
                  "authorityScopeCid",
                  "epochNonce",
                  "notBefore",
                  "expiresAt",
                  "authenticator"
                ],
                "additionalProperties": false,
                "properties": {
                  "version": {
                    "const": "actql-submission-epoch/0.1"
                  },
                  "authorityScopeCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "epochNonce": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  },
                  "notBefore": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 9007199254740991
                  },
                  "expiresAt": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 9007199254740991
                  },
                  "authenticator": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                  }
                }
              },
              "nonce": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "intentCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "reason": {
            "enum": [
              "intent",
              "restart_decision"
            ]
          }
        }
      }
    ]
  },
  "submission_name": {
    "type": "string",
    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
    "minLength": 1,
    "maxLength": 256
  },
  "named_submission_attempt": {
    "oneOf": [
      {
        "type": "object",
        "required": [
          "kind",
          "requestName",
          "intentCid",
          "attemptRef",
          "outcome"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "observed"
          },
          "requestName": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
            "minLength": 1,
            "maxLength": 256
          },
          "intentCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "attemptRef": {
            "type": "object",
            "required": [
              "operation",
              "attemptId"
            ],
            "additionalProperties": false,
            "properties": {
              "operation": {
                "const": "submit"
              },
              "attemptId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "outcome": {
            "oneOf": [
              {
                "type": "object",
                "required": [
                  "kind",
                  "submissionRef",
                  "intentCid",
                  "admission"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "const": "ready"
                  },
                  "submissionRef": {
                    "type": "object",
                    "required": [
                      "epoch",
                      "nonce"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "epoch": {
                        "type": "object",
                        "required": [
                          "version",
                          "authorityScopeCid",
                          "epochNonce",
                          "notBefore",
                          "expiresAt",
                          "authenticator"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "version": {
                            "const": "actql-submission-epoch/0.1"
                          },
                          "authorityScopeCid": {
                            "type": "string",
                            "pattern": "^sha256:[0-9a-f]{64}$"
                          },
                          "epochNonce": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          },
                          "notBefore": {
                            "type": "integer",
                            "minimum": 0,
                            "maximum": 9007199254740991
                          },
                          "expiresAt": {
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 9007199254740991
                          },
                          "authenticator": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          }
                        }
                      },
                      "nonce": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      }
                    }
                  },
                  "intentCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "admission": {
                    "type": "object",
                    "required": [
                      "ref",
                      "durability",
                      "revision"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "ref": {
                        "type": "object",
                        "required": [
                          "namespaceId",
                          "authorityScopeCid",
                          "runDefinitionCid"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "namespaceId": {
                            "type": "string",
                            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
                  "unresolvedHistory": {
                    "type": "object",
                    "required": [
                      "submissionRef",
                      "acknowledgement"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "submissionRef": {
                        "type": "object",
                        "required": [
                          "epoch",
                          "nonce"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "epoch": {
                            "type": "object",
                            "required": [
                              "version",
                              "authorityScopeCid",
                              "epochNonce",
                              "notBefore",
                              "expiresAt",
                              "authenticator"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "version": {
                                "const": "actql-submission-epoch/0.1"
                              },
                              "authorityScopeCid": {
                                "type": "string",
                                "pattern": "^sha256:[0-9a-f]{64}$"
                              },
                              "epochNonce": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              },
                              "notBefore": {
                                "type": "integer",
                                "minimum": 0,
                                "maximum": 9007199254740991
                              },
                              "expiresAt": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 9007199254740991
                              },
                              "authenticator": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              }
                            }
                          },
                          "nonce": {
                            "type": "string",
                            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                            "minLength": 1,
                            "maxLength": 256
                          }
                        }
                      },
                      "acknowledgement": {
                        "const": "possible_prior_execution_and_effects"
                      }
                    }
                  }
                }
              },
              {
                "type": "object",
                "required": [
                  "kind",
                  "submissionRef",
                  "intentCid",
                  "held"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "const": "held"
                  },
                  "submissionRef": {
                    "type": "object",
                    "required": [
                      "epoch",
                      "nonce"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "epoch": {
                        "type": "object",
                        "required": [
                          "version",
                          "authorityScopeCid",
                          "epochNonce",
                          "notBefore",
                          "expiresAt",
                          "authenticator"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "version": {
                            "const": "actql-submission-epoch/0.1"
                          },
                          "authorityScopeCid": {
                            "type": "string",
                            "pattern": "^sha256:[0-9a-f]{64}$"
                          },
                          "epochNonce": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          },
                          "notBefore": {
                            "type": "integer",
                            "minimum": 0,
                            "maximum": 9007199254740991
                          },
                          "expiresAt": {
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 9007199254740991
                          },
                          "authenticator": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          }
                        }
                      },
                      "nonce": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      }
                    }
                  },
                  "intentCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "held": {
                    "type": "object",
                    "required": [
                      "kind",
                      "requestId",
                      "prepareAttemptId",
                      "state",
                      "durability",
                      "lookupExpiresAt"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "kind": {
                        "const": "held"
                      },
                      "requestId": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      },
                      "prepareAttemptId": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      },
                      "state": {
                        "enum": [
                          "waiting_checkpoint",
                          "resuming",
                          "ended"
                        ]
                      },
                      "durability": {
                        "const": "durable"
                      },
                      "lookupExpiresAt": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      },
                      "checkpoint": {
                        "type": "object",
                        "required": [
                          "checkpointId",
                          "checkpointCid",
                          "kind",
                          "expiresAt"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "checkpointId": {
                            "type": "string",
                            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                            "minLength": 1,
                            "maxLength": 256
                          },
                          "checkpointCid": {
                            "type": "string",
                            "pattern": "^sha256:[0-9a-f]{64}$"
                          },
                          "kind": {
                            "enum": [
                              "run_scope",
                              "read_access",
                              "data_egress",
                              "cost_scope",
                              "effect_set"
                            ]
                          },
                          "expiresAt": {
                            "type": "string",
                            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                            "minLength": 1,
                            "maxLength": 256
                          }
                        }
                      },
                      "endReason": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      },
                      "terminalErrorCode": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      }
                    },
                    "allOf": [
                      {
                        "oneOf": [
                          {
                            "required": [
                              "checkpoint"
                            ],
                            "properties": {
                              "state": {
                                "const": "waiting_checkpoint"
                              }
                            },
                            "allOf": [
                              {
                                "not": {
                                  "required": [
                                    "endReason"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "terminalErrorCode"
                                  ]
                                }
                              }
                            ]
                          },
                          {
                            "properties": {
                              "state": {
                                "const": "resuming"
                              }
                            },
                            "allOf": [
                              {
                                "not": {
                                  "required": [
                                    "endReason"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "terminalErrorCode"
                                  ]
                                }
                              }
                            ]
                          },
                          {
                            "required": [
                              "endReason"
                            ],
                            "properties": {
                              "state": {
                                "const": "ended"
                              }
                            }
                          }
                        ]
                      }
                    ]
                  },
                  "unresolvedHistory": {
                    "type": "object",
                    "required": [
                      "submissionRef",
                      "acknowledgement"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "submissionRef": {
                        "type": "object",
                        "required": [
                          "epoch",
                          "nonce"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "epoch": {
                            "type": "object",
                            "required": [
                              "version",
                              "authorityScopeCid",
                              "epochNonce",
                              "notBefore",
                              "expiresAt",
                              "authenticator"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "version": {
                                "const": "actql-submission-epoch/0.1"
                              },
                              "authorityScopeCid": {
                                "type": "string",
                                "pattern": "^sha256:[0-9a-f]{64}$"
                              },
                              "epochNonce": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              },
                              "notBefore": {
                                "type": "integer",
                                "minimum": 0,
                                "maximum": 9007199254740991
                              },
                              "expiresAt": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 9007199254740991
                              },
                              "authenticator": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              }
                            }
                          },
                          "nonce": {
                            "type": "string",
                            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                            "minLength": 1,
                            "maxLength": 256
                          }
                        }
                      },
                      "acknowledgement": {
                        "const": "possible_prior_execution_and_effects"
                      }
                    }
                  }
                }
              },
              {
                "type": "object",
                "required": [
                  "kind",
                  "submissionRef",
                  "intentCid"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "const": "preparing"
                  },
                  "submissionRef": {
                    "type": "object",
                    "required": [
                      "epoch",
                      "nonce"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "epoch": {
                        "type": "object",
                        "required": [
                          "version",
                          "authorityScopeCid",
                          "epochNonce",
                          "notBefore",
                          "expiresAt",
                          "authenticator"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "version": {
                            "const": "actql-submission-epoch/0.1"
                          },
                          "authorityScopeCid": {
                            "type": "string",
                            "pattern": "^sha256:[0-9a-f]{64}$"
                          },
                          "epochNonce": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          },
                          "notBefore": {
                            "type": "integer",
                            "minimum": 0,
                            "maximum": 9007199254740991
                          },
                          "expiresAt": {
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 9007199254740991
                          },
                          "authenticator": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          }
                        }
                      },
                      "nonce": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      }
                    }
                  },
                  "intentCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "unresolvedHistory": {
                    "type": "object",
                    "required": [
                      "submissionRef",
                      "acknowledgement"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "submissionRef": {
                        "type": "object",
                        "required": [
                          "epoch",
                          "nonce"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "epoch": {
                            "type": "object",
                            "required": [
                              "version",
                              "authorityScopeCid",
                              "epochNonce",
                              "notBefore",
                              "expiresAt",
                              "authenticator"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "version": {
                                "const": "actql-submission-epoch/0.1"
                              },
                              "authorityScopeCid": {
                                "type": "string",
                                "pattern": "^sha256:[0-9a-f]{64}$"
                              },
                              "epochNonce": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              },
                              "notBefore": {
                                "type": "integer",
                                "minimum": 0,
                                "maximum": 9007199254740991
                              },
                              "expiresAt": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 9007199254740991
                              },
                              "authenticator": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              }
                            }
                          },
                          "nonce": {
                            "type": "string",
                            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                            "minLength": 1,
                            "maxLength": 256
                          }
                        }
                      },
                      "acknowledgement": {
                        "const": "possible_prior_execution_and_effects"
                      }
                    }
                  }
                }
              },
              {
                "type": "object",
                "required": [
                  "kind",
                  "submissionRef",
                  "intentCid",
                  "problem"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "const": "not_accepted"
                  },
                  "submissionRef": {
                    "type": "object",
                    "required": [
                      "epoch",
                      "nonce"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "epoch": {
                        "type": "object",
                        "required": [
                          "version",
                          "authorityScopeCid",
                          "epochNonce",
                          "notBefore",
                          "expiresAt",
                          "authenticator"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "version": {
                            "const": "actql-submission-epoch/0.1"
                          },
                          "authorityScopeCid": {
                            "type": "string",
                            "pattern": "^sha256:[0-9a-f]{64}$"
                          },
                          "epochNonce": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          },
                          "notBefore": {
                            "type": "integer",
                            "minimum": 0,
                            "maximum": 9007199254740991
                          },
                          "expiresAt": {
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 9007199254740991
                          },
                          "authenticator": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          }
                        }
                      },
                      "nonce": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      }
                    }
                  },
                  "intentCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "checkObservation": {
                    "allOf": [
                      {
                        "$ref": "check_outcome"
                      },
                      {
                        "type": "object",
                        "properties": {
                          "report": {
                            "type": "object",
                            "properties": {
                              "scope": {
                                "type": "object",
                                "properties": {
                                  "kind": {
                                    "const": "bound_input"
                                  }
                                }
                              }
                            }
                          },
                          "partial_report": {
                            "type": "object",
                            "properties": {
                              "scope": {
                                "type": "object",
                                "properties": {
                                  "kind": {
                                    "const": "bound_input"
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    ]
                  },
                  "problem": {
                    "type": "object",
                    "required": [
                      "code",
                      "classification"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "code": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      },
                      "classification": {
                        "enum": [
                          "invalid_input",
                          "requirements",
                          "implementation_limit",
                          "authorization",
                          "operation_failed"
                        ]
                      }
                    }
                  },
                  "unresolvedHistory": {
                    "type": "object",
                    "required": [
                      "submissionRef",
                      "acknowledgement"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "submissionRef": {
                        "type": "object",
                        "required": [
                          "epoch",
                          "nonce"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "epoch": {
                            "type": "object",
                            "required": [
                              "version",
                              "authorityScopeCid",
                              "epochNonce",
                              "notBefore",
                              "expiresAt",
                              "authenticator"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "version": {
                                "const": "actql-submission-epoch/0.1"
                              },
                              "authorityScopeCid": {
                                "type": "string",
                                "pattern": "^sha256:[0-9a-f]{64}$"
                              },
                              "epochNonce": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              },
                              "notBefore": {
                                "type": "integer",
                                "minimum": 0,
                                "maximum": 9007199254740991
                              },
                              "expiresAt": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 9007199254740991
                              },
                              "authenticator": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              }
                            }
                          },
                          "nonce": {
                            "type": "string",
                            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                            "minLength": 1,
                            "maxLength": 256
                          }
                        }
                      },
                      "acknowledgement": {
                        "const": "possible_prior_execution_and_effects"
                      }
                    }
                  }
                }
              },
              {
                "type": "object",
                "required": [
                  "kind",
                  "submissionRef",
                  "intentCid",
                  "problem"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "const": "preparation_failed"
                  },
                  "submissionRef": {
                    "type": "object",
                    "required": [
                      "epoch",
                      "nonce"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "epoch": {
                        "type": "object",
                        "required": [
                          "version",
                          "authorityScopeCid",
                          "epochNonce",
                          "notBefore",
                          "expiresAt",
                          "authenticator"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "version": {
                            "const": "actql-submission-epoch/0.1"
                          },
                          "authorityScopeCid": {
                            "type": "string",
                            "pattern": "^sha256:[0-9a-f]{64}$"
                          },
                          "epochNonce": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          },
                          "notBefore": {
                            "type": "integer",
                            "minimum": 0,
                            "maximum": 9007199254740991
                          },
                          "expiresAt": {
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 9007199254740991
                          },
                          "authenticator": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          }
                        }
                      },
                      "nonce": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      }
                    }
                  },
                  "intentCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  },
                  "checkObservation": {
                    "allOf": [
                      {
                        "$ref": "check_outcome"
                      },
                      {
                        "type": "object",
                        "properties": {
                          "report": {
                            "type": "object",
                            "properties": {
                              "scope": {
                                "type": "object",
                                "properties": {
                                  "kind": {
                                    "const": "bound_input"
                                  }
                                }
                              }
                            }
                          },
                          "partial_report": {
                            "type": "object",
                            "properties": {
                              "scope": {
                                "type": "object",
                                "properties": {
                                  "kind": {
                                    "const": "bound_input"
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    ]
                  },
                  "problem": {
                    "type": "object",
                    "required": [
                      "code",
                      "classification"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "code": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      },
                      "classification": {
                        "enum": [
                          "invalid_input",
                          "requirements",
                          "implementation_limit",
                          "authorization",
                          "operation_failed"
                        ]
                      }
                    }
                  },
                  "unresolvedHistory": {
                    "type": "object",
                    "required": [
                      "submissionRef",
                      "acknowledgement"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "submissionRef": {
                        "type": "object",
                        "required": [
                          "epoch",
                          "nonce"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "epoch": {
                            "type": "object",
                            "required": [
                              "version",
                              "authorityScopeCid",
                              "epochNonce",
                              "notBefore",
                              "expiresAt",
                              "authenticator"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "version": {
                                "const": "actql-submission-epoch/0.1"
                              },
                              "authorityScopeCid": {
                                "type": "string",
                                "pattern": "^sha256:[0-9a-f]{64}$"
                              },
                              "epochNonce": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              },
                              "notBefore": {
                                "type": "integer",
                                "minimum": 0,
                                "maximum": 9007199254740991
                              },
                              "expiresAt": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 9007199254740991
                              },
                              "authenticator": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              }
                            }
                          },
                          "nonce": {
                            "type": "string",
                            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                            "minLength": 1,
                            "maxLength": 256
                          }
                        }
                      },
                      "acknowledgement": {
                        "const": "possible_prior_execution_and_effects"
                      }
                    }
                  }
                }
              },
              {
                "type": "object",
                "required": [
                  "kind",
                  "submissionRef",
                  "problem"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "const": "unresolvable"
                  },
                  "submissionRef": {
                    "type": "object",
                    "required": [
                      "epoch",
                      "nonce"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "epoch": {
                        "type": "object",
                        "required": [
                          "version",
                          "authorityScopeCid",
                          "epochNonce",
                          "notBefore",
                          "expiresAt",
                          "authenticator"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "version": {
                            "const": "actql-submission-epoch/0.1"
                          },
                          "authorityScopeCid": {
                            "type": "string",
                            "pattern": "^sha256:[0-9a-f]{64}$"
                          },
                          "epochNonce": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          },
                          "notBefore": {
                            "type": "integer",
                            "minimum": 0,
                            "maximum": 9007199254740991
                          },
                          "expiresAt": {
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 9007199254740991
                          },
                          "authenticator": {
                            "type": "string",
                            "pattern": "^[0-9a-f]{64}$"
                          }
                        }
                      },
                      "nonce": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      }
                    }
                  },
                  "problem": {
                    "type": "object",
                    "required": [
                      "code"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "code": {
                        "type": "string",
                        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                        "minLength": 1,
                        "maxLength": 256
                      }
                    }
                  },
                  "unresolvedHistory": {
                    "type": "object",
                    "required": [
                      "submissionRef",
                      "acknowledgement"
                    ],
                    "additionalProperties": false,
                    "properties": {
                      "submissionRef": {
                        "type": "object",
                        "required": [
                          "epoch",
                          "nonce"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "epoch": {
                            "type": "object",
                            "required": [
                              "version",
                              "authorityScopeCid",
                              "epochNonce",
                              "notBefore",
                              "expiresAt",
                              "authenticator"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "version": {
                                "const": "actql-submission-epoch/0.1"
                              },
                              "authorityScopeCid": {
                                "type": "string",
                                "pattern": "^sha256:[0-9a-f]{64}$"
                              },
                              "epochNonce": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              },
                              "notBefore": {
                                "type": "integer",
                                "minimum": 0,
                                "maximum": 9007199254740991
                              },
                              "expiresAt": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 9007199254740991
                              },
                              "authenticator": {
                                "type": "string",
                                "pattern": "^[0-9a-f]{64}$"
                              }
                            }
                          },
                          "nonce": {
                            "type": "string",
                            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                            "minLength": 1,
                            "maxLength": 256
                          }
                        }
                      },
                      "acknowledgement": {
                        "const": "possible_prior_execution_and_effects"
                      }
                    }
                  }
                }
              }
            ]
          }
        }
      },
      {
        "type": "object",
        "required": [
          "kind",
          "requestName",
          "intentCid",
          "attemptRef",
          "guarantee",
          "reason"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "refused"
          },
          "requestName": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
            "minLength": 1,
            "maxLength": 256
          },
          "intentCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "attemptRef": {
            "type": "object",
            "required": [
              "operation",
              "attemptId"
            ],
            "additionalProperties": false,
            "properties": {
              "operation": {
                "const": "submit"
              },
              "attemptId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "guarantee": {
            "const": "attempt_uncommitted_unconsumed"
          },
          "reason": {
            "enum": [
              "authorization",
              "admission_capacity",
              "epoch_expired",
              "epoch_not_yet_valid"
            ]
          }
        }
      },
      {
        "type": "object",
        "required": [
          "kind",
          "requestName",
          "intentCid",
          "attemptRef",
          "reason"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "conflict"
          },
          "requestName": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
            "minLength": 1,
            "maxLength": 256
          },
          "intentCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "attemptRef": {
            "type": "object",
            "required": [
              "operation",
              "attemptId"
            ],
            "additionalProperties": false,
            "properties": {
              "operation": {
                "const": "submit"
              },
              "attemptId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "reason": {
            "const": "intent"
          }
        }
      }
    ]
  },
  "run_ref": {
    "type": "object",
    "required": [
      "namespaceId",
      "authorityScopeCid",
      "runDefinitionCid"
    ],
    "additionalProperties": false,
    "properties": {
      "namespaceId": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
    "required": [
      "mode",
      "owner",
      "consentRefs",
      "runners"
    ],
    "additionalProperties": false,
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
      "workspaceId": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      },
      "consentRefs": {
        "type": "array",
        "uniqueItems": true,
        "items": {
          "type": "string",
          "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
          "minLength": 1,
          "maxLength": 256
        }
      },
      "runners": {
        "type": "array",
        "uniqueItems": true,
        "items": {
          "type": "string",
          "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      },
      "cloudConnectionRef": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      }
    },
    "allOf": [
      {
        "oneOf": [
          {
            "properties": {
              "mode": {
                "const": "remote"
              },
              "owner": {
                "const": "remote"
              },
              "runners": {
                "type": "array",
                "maxItems": 0,
                "items": {
                  "type": "string",
                  "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                  "minLength": 1,
                  "maxLength": 256
                }
              }
            },
            "allOf": [
              {
                "not": {
                  "required": [
                    "movementPolicyRef"
                  ]
                }
              },
              {
                "not": {
                  "required": [
                    "cloudConnectionRef"
                  ]
                }
              }
            ]
          },
          {
            "properties": {
              "mode": {
                "const": "local"
              },
              "owner": {
                "const": "local"
              },
              "runners": {
                "type": "array",
                "maxItems": 0,
                "items": {
                  "type": "string",
                  "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                  "minLength": 1,
                  "maxLength": 256
                }
              }
            },
            "allOf": [
              {
                "not": {
                  "required": [
                    "movementPolicyRef"
                  ]
                }
              },
              {
                "not": {
                  "required": [
                    "cloudConnectionRef"
                  ]
                }
              }
            ]
          },
          {
            "required": [
              "movementPolicyRef",
              "cloudConnectionRef"
            ],
            "properties": {
              "mode": {
                "const": "hybrid"
              },
              "owner": {
                "const": "local"
              }
            }
          },
          {
            "required": [
              "movementPolicyRef"
            ],
            "properties": {
              "mode": {
                "const": "hybrid"
              },
              "owner": {
                "const": "cloud"
              },
              "runners": {
                "type": "array",
                "minItems": 1,
                "items": {
                  "type": "string",
                  "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                  "minLength": 1,
                  "maxLength": 256
                }
              }
            },
            "not": {
              "required": [
                "cloudConnectionRef"
              ]
            }
          }
        ]
      }
    ]
  },
  "profile": {
    "type": "object",
    "required": [
      "version",
      "mode",
      "owner",
      "durability",
      "scopeRef",
      "capabilities",
      "limits"
    ],
    "additionalProperties": false,
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
      "submissionEpoch": {
        "type": "object",
        "required": [
          "version",
          "authorityScopeCid",
          "epochNonce",
          "notBefore",
          "expiresAt",
          "authenticator"
        ],
        "additionalProperties": false,
        "properties": {
          "version": {
            "const": "actql-submission-epoch/0.1"
          },
          "authorityScopeCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "epochNonce": {
            "type": "string",
            "pattern": "^[0-9a-f]{64}$"
          },
          "notBefore": {
            "type": "integer",
            "minimum": 0,
            "maximum": 9007199254740991
          },
          "expiresAt": {
            "type": "integer",
            "minimum": 1,
            "maximum": 9007199254740991
          },
          "authenticator": {
            "type": "string",
            "pattern": "^[0-9a-f]{64}$"
          }
        }
      },
      "scopeRef": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      },
      "workspaceId": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      },
      "capabilities": {
        "type": "array",
        "items": {
          "type": "string",
          "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
          "minLength": 1,
          "maxLength": 256
        }
      },
      "limits": {
        "type": "object",
        "required": [
          "maxReadWireBytes",
          "maxRowWireBytes",
          "maxRowRetainedValueBytes",
          "maxRetainedValueBytes",
          "maxRows",
          "maxBatchRows",
          "maxBatchRetainedValueBytes"
        ],
        "additionalProperties": false,
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
    "required": [
      "ref",
      "durability",
      "revision"
    ],
    "additionalProperties": false,
    "properties": {
      "ref": {
        "type": "object",
        "required": [
          "namespaceId",
          "authorityScopeCid",
          "runDefinitionCid"
        ],
        "additionalProperties": false,
        "properties": {
          "namespaceId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
    "required": [
      "kind",
      "requestId",
      "ref",
      "durability",
      "lookupExpiresAt"
    ],
    "additionalProperties": false,
    "properties": {
      "kind": {
        "const": "found"
      },
      "requestId": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      },
      "ref": {
        "type": "object",
        "required": [
          "namespaceId",
          "authorityScopeCid",
          "runDefinitionCid"
        ],
        "additionalProperties": false,
        "properties": {
          "namespaceId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      }
    }
  },
  "lookup_not_found": {
    "type": "object",
    "required": [
      "kind"
    ],
    "additionalProperties": false,
    "properties": {
      "kind": {
        "const": "not_found"
      }
    }
  },
  "lookup_unknown": {
    "type": "object",
    "required": [
      "kind",
      "reason"
    ],
    "additionalProperties": false,
    "properties": {
      "kind": {
        "const": "unknown"
      },
      "reason": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      }
    }
  },
  "held": {
    "type": "object",
    "required": [
      "kind",
      "requestId",
      "prepareAttemptId",
      "state",
      "durability",
      "lookupExpiresAt"
    ],
    "additionalProperties": false,
    "properties": {
      "kind": {
        "const": "held"
      },
      "requestId": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      },
      "prepareAttemptId": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      },
      "state": {
        "enum": [
          "waiting_checkpoint",
          "resuming",
          "ended"
        ]
      },
      "durability": {
        "const": "durable"
      },
      "lookupExpiresAt": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      },
      "checkpoint": {
        "type": "object",
        "required": [
          "checkpointId",
          "checkpointCid",
          "kind",
          "expiresAt"
        ],
        "additionalProperties": false,
        "properties": {
          "checkpointId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
            "minLength": 1,
            "maxLength": 256
          },
          "checkpointCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "kind": {
            "enum": [
              "run_scope",
              "read_access",
              "data_egress",
              "cost_scope",
              "effect_set"
            ]
          },
          "expiresAt": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
            "minLength": 1,
            "maxLength": 256
          }
        }
      },
      "endReason": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      },
      "terminalErrorCode": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      }
    },
    "allOf": [
      {
        "oneOf": [
          {
            "required": [
              "checkpoint"
            ],
            "properties": {
              "state": {
                "const": "waiting_checkpoint"
              }
            },
            "allOf": [
              {
                "not": {
                  "required": [
                    "endReason"
                  ]
                }
              },
              {
                "not": {
                  "required": [
                    "terminalErrorCode"
                  ]
                }
              }
            ]
          },
          {
            "properties": {
              "state": {
                "const": "resuming"
              }
            },
            "allOf": [
              {
                "not": {
                  "required": [
                    "endReason"
                  ]
                }
              },
              {
                "not": {
                  "required": [
                    "terminalErrorCode"
                  ]
                }
              }
            ]
          },
          {
            "required": [
              "endReason"
            ],
            "properties": {
              "state": {
                "const": "ended"
              }
            }
          }
        ]
      }
    ]
  },
  "checkpoint_summary": {
    "oneOf": [
      {
        "type": "object",
        "required": [
          "checkpointId",
          "checkpointCid",
          "kind",
          "phase",
          "subject",
          "requiredArtifact",
          "reviewProjectionCid",
          "requirements",
          "createdAt",
          "expiresAt",
          "humanSummary"
        ],
        "additionalProperties": false,
        "properties": {
          "checkpointId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
            "minLength": 1,
            "maxLength": 256
          },
          "checkpointCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "kind": {
            "enum": [
              "run_scope",
              "read_access",
              "data_egress",
              "cost_scope",
              "effect_set"
            ]
          },
          "phase": {
            "enum": [
              "preflight",
              "commit"
            ]
          },
          "subject": {
            "oneOf": [
              {
                "type": "object",
                "required": [
                  "kind",
                  "prepareAttemptId",
                  "requestId"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "const": "prepare_attempt"
                  },
                  "prepareAttemptId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  },
                  "requestId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  }
                }
              },
              {
                "type": "object",
                "required": [
                  "kind",
                  "runId",
                  "runDefinitionCid"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "const": "run_unit"
                  },
                  "runId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  },
                  "runDefinitionCid": {
                    "type": "string",
                    "pattern": "^sha256:[0-9a-f]{64}$"
                  }
                }
              }
            ]
          },
          "requiredArtifact": {
            "type": "object",
            "required": [
              "type",
              "cid"
            ],
            "additionalProperties": false,
            "properties": {
              "type": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              },
              "cid": {
                "type": "string",
                "pattern": "^sha256:[0-9a-f]{64}$"
              }
            }
          },
          "reviewProjectionCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "requirements": {
            "type": "array",
            "uniqueItems": true,
            "items": {
              "type": "string",
              "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
              "minLength": 1,
              "maxLength": 256
            }
          },
          "createdAt": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
            "minLength": 1,
            "maxLength": 256
          },
          "expiresAt": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
            "minLength": 1,
            "maxLength": 256
          },
          "humanSummary": {
            "type": "string",
            "maxLength": 1024
          }
        }
      },
      {
        "type": "object",
        "required": [
          "checkpointId",
          "checkpointCid",
          "kind",
          "phase",
          "subject",
          "requiredArtifact",
          "reviewProjectionCid",
          "requirements",
          "createdAt",
          "expiresAt",
          "humanSummary",
          "preparedInvocationCid"
        ],
        "additionalProperties": false,
        "properties": {
          "checkpointId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
            "minLength": 1,
            "maxLength": 256
          },
          "checkpointCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "kind": {
            "const": "model_invocation"
          },
          "phase": {
            "const": "preflight"
          },
          "subject": {
            "type": "object",
            "required": [
              "kind",
              "runId",
              "runDefinitionCid"
            ],
            "additionalProperties": false,
            "properties": {
              "kind": {
                "const": "run_unit"
              },
              "runId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              },
              "runDefinitionCid": {
                "type": "string",
                "pattern": "^sha256:[0-9a-f]{64}$"
              }
            }
          },
          "requiredArtifact": {
            "type": "object",
            "required": [
              "type",
              "cid"
            ],
            "additionalProperties": false,
            "properties": {
              "type": {
                "const": "model_invocation_scope"
              },
              "cid": {
                "type": "string",
                "pattern": "^sha256:[0-9a-f]{64}$"
              }
            }
          },
          "reviewProjectionCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "requirements": {
            "type": "array",
            "uniqueItems": true,
            "minItems": 1,
            "maxItems": 1,
            "items": {
              "type": "string",
              "const": "invocation_scope_approved"
            }
          },
          "createdAt": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
            "minLength": 1,
            "maxLength": 256
          },
          "expiresAt": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
            "minLength": 1,
            "maxLength": 256
          },
          "humanSummary": {
            "type": "string",
            "maxLength": 1024
          },
          "preparedInvocationCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          }
        }
      }
    ]
  },
  "checkpoint_review": {
    "type": "object",
    "required": [
      "kind",
      "checkpointCid",
      "artifactCid",
      "byteLength",
      "contentBase64"
    ],
    "additionalProperties": false,
    "properties": {
      "kind": {
        "const": "review"
      },
      "checkpointCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "artifactCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "byteLength": {
        "type": "integer",
        "minimum": 1
      },
      "contentBase64": {
        "type": "string",
        "pattern": "^[A-Za-z0-9+/]+={0,2}$",
        "minLength": 1
      }
    }
  },
  "resolve_item": {
    "type": "object",
    "required": [
      "checkpointCid",
      "resolutionWire",
      "approvalEvidenceWire"
    ],
    "additionalProperties": false,
    "properties": {
      "checkpointCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "resolutionWire": {
        "type": "string",
        "minLength": 1,
        "maxLength": 16384
      },
      "approvalEvidenceWire": {
        "type": "string",
        "maxLength": 16384
      }
    }
  },
  "resolve_result": {
    "type": "object",
    "required": [
      "checkpointCid",
      "status"
    ],
    "additionalProperties": false,
    "properties": {
      "checkpointCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "status": {
        "enum": [
          "committed",
          "duplicate",
          "conflicting",
          "expired",
          "cancelled",
          "invalid"
        ]
      },
      "decision": {
        "enum": [
          "approved",
          "rejected"
        ]
      },
      "resolutionCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "reason": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      }
    }
  },
  "submit_preparation_error": {
    "type": "object",
    "required": [
      "code"
    ],
    "additionalProperties": false,
    "properties": {
      "code": {
        "enum": [
          "ClientProgramInvalidInput",
          "ClientParametersInvalid",
          "ClientParametersTooLarge",
          "ClientProgramUnsupported",
          "ClientProgramAnalysisLimit",
          "ClientProgramImplementationLimit",
          "ClientProgramNeedsInputs",
          "ClientProgramRejected"
        ]
      }
    }
  },
  "cancellation": {
    "type": "object",
    "required": [
      "ref",
      "kind",
      "revision",
      "cancelRef"
    ],
    "additionalProperties": false,
    "properties": {
      "ref": {
        "type": "object",
        "required": [
          "namespaceId",
          "authorityScopeCid",
          "runDefinitionCid"
        ],
        "additionalProperties": false,
        "properties": {
          "namespaceId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
      "kind": {
        "enum": [
          "accepted",
          "already_requested",
          "already_terminal"
        ]
      },
      "revision": {
        "type": "integer",
        "minimum": 0,
        "maximum": 2147483647
      },
      "cancelRef": {
        "type": "object",
        "required": [
          "namespaceId",
          "authorityScopeCid",
          "runDefinitionCid",
          "cancelId",
          "expectedRevision"
        ],
        "additionalProperties": false,
        "properties": {
          "namespaceId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
          },
          "cancelId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
            "minLength": 1,
            "maxLength": 256
          },
          "expectedRevision": {
            "type": "integer",
            "minimum": 0,
            "maximum": 2147483647
          }
        }
      }
    }
  },
  "cancellation_ref": {
    "type": "object",
    "required": [
      "namespaceId",
      "authorityScopeCid",
      "runDefinitionCid",
      "cancelId",
      "expectedRevision"
    ],
    "additionalProperties": false,
    "properties": {
      "namespaceId": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
      },
      "cancelId": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      },
      "expectedRevision": {
        "type": "integer",
        "minimum": 0,
        "maximum": 2147483647
      }
    }
  },
  "cancellation_lookup": {
    "oneOf": [
      {
        "type": "object",
        "required": [
          "kind",
          "cancellation"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "found"
          },
          "cancellation": {
            "type": "object",
            "required": [
              "ref",
              "kind",
              "revision",
              "cancelRef"
            ],
            "additionalProperties": false,
            "properties": {
              "ref": {
                "type": "object",
                "required": [
                  "namespaceId",
                  "authorityScopeCid",
                  "runDefinitionCid"
                ],
                "additionalProperties": false,
                "properties": {
                  "namespaceId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
              "kind": {
                "enum": [
                  "accepted",
                  "already_requested",
                  "already_terminal"
                ]
              },
              "revision": {
                "type": "integer",
                "minimum": 0,
                "maximum": 2147483647
              },
              "cancelRef": {
                "type": "object",
                "required": [
                  "namespaceId",
                  "authorityScopeCid",
                  "runDefinitionCid",
                  "cancelId",
                  "expectedRevision"
                ],
                "additionalProperties": false,
                "properties": {
                  "namespaceId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
                  },
                  "cancelId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  },
                  "expectedRevision": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 2147483647
                  }
                }
              }
            }
          }
        }
      },
      {
        "type": "object",
        "required": [
          "kind",
          "cancelRef"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "unknown"
          },
          "cancelRef": {
            "type": "object",
            "required": [
              "namespaceId",
              "authorityScopeCid",
              "runDefinitionCid",
              "cancelId",
              "expectedRevision"
            ],
            "additionalProperties": false,
            "properties": {
              "namespaceId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
              },
              "cancelId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              },
              "expectedRevision": {
                "type": "integer",
                "minimum": 0,
                "maximum": 2147483647
              }
            }
          }
        }
      }
    ]
  },
  "operation_attempt_ref": {
    "type": "object",
    "required": [
      "operation",
      "attemptId"
    ],
    "additionalProperties": false,
    "properties": {
      "operation": {
        "enum": [
          "submit",
          "cancel"
        ]
      },
      "attemptId": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      }
    }
  },
  "cancellation_attempt": {
    "oneOf": [
      {
        "type": "object",
        "required": [
          "kind",
          "attemptRef",
          "cancellation"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "accepted"
          },
          "attemptRef": {
            "type": "object",
            "required": [
              "operation",
              "attemptId"
            ],
            "additionalProperties": false,
            "properties": {
              "operation": {
                "const": "cancel"
              },
              "attemptId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "cancellation": {
            "type": "object",
            "required": [
              "ref",
              "kind",
              "revision",
              "cancelRef"
            ],
            "additionalProperties": false,
            "properties": {
              "ref": {
                "type": "object",
                "required": [
                  "namespaceId",
                  "authorityScopeCid",
                  "runDefinitionCid"
                ],
                "additionalProperties": false,
                "properties": {
                  "namespaceId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
              "kind": {
                "const": "accepted"
              },
              "revision": {
                "type": "integer",
                "minimum": 0,
                "maximum": 2147483647
              },
              "cancelRef": {
                "type": "object",
                "required": [
                  "namespaceId",
                  "authorityScopeCid",
                  "runDefinitionCid",
                  "cancelId",
                  "expectedRevision"
                ],
                "additionalProperties": false,
                "properties": {
                  "namespaceId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
                  },
                  "cancelId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  },
                  "expectedRevision": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 2147483647
                  }
                }
              }
            }
          }
        }
      },
      {
        "type": "object",
        "required": [
          "kind",
          "attemptRef",
          "cancellation"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "already_satisfied"
          },
          "attemptRef": {
            "type": "object",
            "required": [
              "operation",
              "attemptId"
            ],
            "additionalProperties": false,
            "properties": {
              "operation": {
                "const": "cancel"
              },
              "attemptId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "cancellation": {
            "type": "object",
            "required": [
              "ref",
              "kind",
              "revision",
              "cancelRef"
            ],
            "additionalProperties": false,
            "properties": {
              "ref": {
                "type": "object",
                "required": [
                  "namespaceId",
                  "authorityScopeCid",
                  "runDefinitionCid"
                ],
                "additionalProperties": false,
                "properties": {
                  "namespaceId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
              "kind": {
                "enum": [
                  "already_requested",
                  "already_terminal"
                ]
              },
              "revision": {
                "type": "integer",
                "minimum": 0,
                "maximum": 2147483647
              },
              "cancelRef": {
                "type": "object",
                "required": [
                  "namespaceId",
                  "authorityScopeCid",
                  "runDefinitionCid",
                  "cancelId",
                  "expectedRevision"
                ],
                "additionalProperties": false,
                "properties": {
                  "namespaceId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
                  },
                  "cancelId": {
                    "type": "string",
                    "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                    "minLength": 1,
                    "maxLength": 256
                  },
                  "expectedRevision": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 2147483647
                  }
                }
              }
            }
          }
        }
      },
      {
        "type": "object",
        "required": [
          "kind",
          "attemptRef",
          "guarantee",
          "reason"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "refused"
          },
          "attemptRef": {
            "type": "object",
            "required": [
              "operation",
              "attemptId"
            ],
            "additionalProperties": false,
            "properties": {
              "operation": {
                "const": "cancel"
              },
              "attemptId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "guarantee": {
            "const": "attempt_uncommitted_unconsumed"
          },
          "reason": {
            "enum": [
              "authorization",
              "admission_capacity"
            ]
          },
          "cancelRef": {
            "type": "object",
            "required": [
              "namespaceId",
              "authorityScopeCid",
              "runDefinitionCid",
              "cancelId",
              "expectedRevision"
            ],
            "additionalProperties": false,
            "properties": {
              "namespaceId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
              },
              "cancelId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              },
              "expectedRevision": {
                "type": "integer",
                "minimum": 0,
                "maximum": 2147483647
              }
            }
          }
        }
      },
      {
        "type": "object",
        "required": [
          "kind",
          "attemptRef",
          "reason",
          "cancelRef"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "const": "conflict"
          },
          "attemptRef": {
            "type": "object",
            "required": [
              "operation",
              "attemptId"
            ],
            "additionalProperties": false,
            "properties": {
              "operation": {
                "const": "cancel"
              },
              "attemptId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              }
            }
          },
          "reason": {
            "enum": [
              "intent",
              "control_revision"
            ]
          },
          "cancelRef": {
            "type": "object",
            "required": [
              "namespaceId",
              "authorityScopeCid",
              "runDefinitionCid",
              "cancelId",
              "expectedRevision"
            ],
            "additionalProperties": false,
            "properties": {
              "namespaceId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
              },
              "cancelId": {
                "type": "string",
                "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
                "minLength": 1,
                "maxLength": 256
              },
              "expectedRevision": {
                "type": "integer",
                "minimum": 0,
                "maximum": 2147483647
              }
            }
          }
        }
      }
    ]
  },
  "request_cancellation": {
    "type": "object",
    "required": [
      "requestId",
      "kind"
    ],
    "additionalProperties": false,
    "properties": {
      "requestId": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      },
      "kind": {
        "enum": [
          "accepted",
          "already_requested",
          "already_terminal"
        ]
      },
      "ref": {
        "type": "object",
        "required": [
          "namespaceId",
          "authorityScopeCid",
          "runDefinitionCid"
        ],
        "additionalProperties": false,
        "properties": {
          "namespaceId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
      "revision": {
        "type": "integer",
        "minimum": 0,
        "maximum": 2147483647
      }
    }
  },
  "resource_listing": {
    "type": "object",
    "required": [
      "resourceConnection",
      "observationCid",
      "resources",
      "snapshotComplete",
      "snapshotTruncated",
      "resultTruncated"
    ],
    "additionalProperties": false,
    "properties": {
      "resourceConnection": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      },
      "observationCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "resources": {
        "type": "array",
        "items": {
          "type": "object",
          "required": [
            "name",
            "outcome"
          ],
          "additionalProperties": false,
          "properties": {
            "name": {
              "type": "string",
              "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
              "minLength": 1,
              "maxLength": 256
            },
            "outcome": {
              "type": "string",
              "pattern": "^[a-z_]+$",
              "minLength": 1,
              "maxLength": 64
            }
          }
        }
      },
      "snapshotComplete": {
        "type": "boolean"
      },
      "snapshotTruncated": {
        "type": "boolean"
      },
      "resultTruncated": {
        "type": "boolean"
      }
    }
  },
  "resource_inspection": {
    "type": "object",
    "required": [
      "resourceConnection",
      "resource",
      "observationCid",
      "status"
    ],
    "additionalProperties": false,
    "properties": {
      "resourceConnection": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      },
      "resource": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      },
      "observationCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "status": {
        "enum": [
          "ready",
          "catalog_required"
        ]
      },
      "reason": {
        "enum": [
          "listing_truncated",
          "not_visible",
          "not_observed",
          "not_found",
          "describe_unavailable"
        ]
      },
      "summaryJson": {
        "type": "string",
        "minLength": 2,
        "maxLength": 1048576
      }
    }
  },
  "resource_peek": {
    "type": "object",
    "required": [
      "resourceConnection",
      "resource",
      "observationCid",
      "fields",
      "rowsJson",
      "limited"
    ],
    "additionalProperties": false,
    "properties": {
      "resourceConnection": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      },
      "resource": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      },
      "observationCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "fields": {
        "type": "array",
        "uniqueItems": true,
        "minItems": 1,
        "items": {
          "type": "string",
          "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
          "minLength": 1,
          "maxLength": 256
        }
      },
      "rowsJson": {
        "type": "string",
        "minLength": 2,
        "maxLength": 4194304
      },
      "limited": {
        "type": "boolean"
      }
    }
  },
  "result_description": {
    "type": "object",
    "required": [
      "ref",
      "resultName",
      "programDefinitionCid",
      "resultDefinitionCid",
      "resultArtifactCid",
      "resultSchemaCid",
      "columns",
      "serialization"
    ],
    "additionalProperties": false,
    "properties": {
      "ref": {
        "type": "object",
        "required": [
          "namespaceId",
          "authorityScopeCid",
          "runDefinitionCid"
        ],
        "additionalProperties": false,
        "properties": {
          "namespaceId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
      "resultName": {
        "type": "string",
        "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
        "minLength": 1,
        "maxLength": 256
      },
      "programDefinitionCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "resultDefinitionCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "resultArtifactCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "resultSchemaCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "columns": {
        "type": "array",
        "minItems": 1,
        "items": {
          "type": "object",
          "required": [
            "name",
            "contract"
          ],
          "additionalProperties": false,
          "properties": {
            "name": {
              "type": "string",
              "minLength": 1
            },
            "contract": {
              "$ref": "value_contract"
            }
          }
        }
      },
      "serialization": {
        "type": "object",
        "required": [
          "format",
          "version",
          "contractCid"
        ],
        "additionalProperties": false,
        "properties": {
          "format": {
            "enum": [
              "json",
              "jsonl",
              "csv"
            ]
          },
          "version": {
            "enum": [
              "actql-json/0.1",
              "actql-jsonl/0.1",
              "actql-csv/0.1"
            ]
          },
          "contractCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          }
        }
      }
    }
  },
  "owner_ref": {
    "type": "object",
    "required": [
      "kind",
      "scopeCid",
      "streamCid"
    ],
    "additionalProperties": false,
    "properties": {
      "kind": {
        "enum": [
          "run",
          "effect",
          "publication",
          "delivery",
          "site"
        ]
      },
      "scopeCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      },
      "streamCid": {
        "type": "string",
        "pattern": "^sha256:[0-9a-f]{64}$"
      }
    }
  },
  "owner_cursor": {
    "type": "object",
    "required": [
      "owner",
      "value"
    ],
    "additionalProperties": false,
    "properties": {
      "owner": {
        "type": "object",
        "required": [
          "kind",
          "scopeCid",
          "streamCid"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "enum": [
              "run",
              "effect",
              "publication",
              "delivery",
              "site"
            ]
          },
          "scopeCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "streamCid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          }
        }
      },
      "value": {
        "type": "string",
        "minLength": 1,
        "maxLength": 8192
      }
    }
  },
  "owner_observations": {
    "type": "object",
    "required": [
      "ref",
      "consistency",
      "ordering",
      "owners",
      "revisionVector"
    ],
    "additionalProperties": false,
    "properties": {
      "ref": {
        "type": "object",
        "required": [
          "namespaceId",
          "authorityScopeCid",
          "runDefinitionCid"
        ],
        "additionalProperties": false,
        "properties": {
          "namespaceId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
      "consistency": {
        "const": "non_atomic"
      },
      "ordering": {
        "const": "owner_local"
      },
      "owners": {
        "type": "array",
        "maxItems": 5,
        "items": {
          "oneOf": [
            {
              "type": "object",
              "required": [
                "owner",
                "kind"
              ],
              "additionalProperties": false,
              "properties": {
                "owner": {
                  "enum": [
                    "run",
                    "effect",
                    "publication",
                    "delivery",
                    "site"
                  ]
                },
                "kind": {
                  "const": "unavailable"
                },
                "problem": {
                  "type": "object",
                  "required": [
                    "kind"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "kind": {
                      "enum": [
                        "acquisition_failed",
                        "limit_exceeded",
                        "history_unrecoverable",
                        "cursor_mismatch"
                      ]
                    }
                  }
                }
              }
            },
            {
              "type": "object",
              "required": [
                "owner",
                "ownerRef",
                "kind",
                "history",
                "snapshot"
              ],
              "additionalProperties": false,
              "properties": {
                "owner": {
                  "const": "run"
                },
                "ownerRef": {
                  "type": "object",
                  "required": [
                    "kind",
                    "scopeCid",
                    "streamCid"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "kind": {
                      "enum": [
                        "run",
                        "effect",
                        "publication",
                        "delivery",
                        "site"
                      ]
                    },
                    "scopeCid": {
                      "type": "string",
                      "pattern": "^sha256:[0-9a-f]{64}$"
                    },
                    "streamCid": {
                      "type": "string",
                      "pattern": "^sha256:[0-9a-f]{64}$"
                    }
                  }
                },
                "kind": {
                  "const": "observed"
                },
                "history": {
                  "oneOf": [
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "not_provided"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "retention_expired"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "history_unrecoverable"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "cursor_mismatch"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "cursor_expired"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "limit_exceeded"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "acquisition_failed"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind",
                        "entries"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "page"
                        },
                        "entries": {
                          "type": "array",
                          "maxItems": 1000,
                          "items": {
                            "type": "object",
                            "required": [
                              "revision",
                              "entryCid",
                              "state"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "revision": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 9007199254740991
                              },
                              "entryCid": {
                                "type": "string",
                                "pattern": "^sha256:[0-9a-f]{64}$"
                              },
                              "state": {
                                "enum": [
                                  "prepared",
                                  "dispatching",
                                  "applied",
                                  "accepted",
                                  "failed",
                                  "unknown"
                                ]
                              }
                            }
                          }
                        },
                        "cursor": {
                          "type": "object",
                          "required": [
                            "owner",
                            "value"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "owner": {
                              "type": "object",
                              "required": [
                                "kind",
                                "scopeCid",
                                "streamCid"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "kind": {
                                  "enum": [
                                    "run",
                                    "effect",
                                    "publication",
                                    "delivery",
                                    "site"
                                  ]
                                },
                                "scopeCid": {
                                  "type": "string",
                                  "pattern": "^sha256:[0-9a-f]{64}$"
                                },
                                "streamCid": {
                                  "type": "string",
                                  "pattern": "^sha256:[0-9a-f]{64}$"
                                }
                              }
                            },
                            "value": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 8192
                            }
                          }
                        }
                      }
                    }
                  ]
                },
                "snapshot": {
                  "type": "object",
                  "required": [
                    "value"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "revision": {
                      "type": "integer",
                      "minimum": 0,
                      "maximum": 9007199254740991
                    },
                    "value": {
                      "$ref": "run_state"
                    }
                  }
                }
              }
            },
            {
              "type": "object",
              "required": [
                "owner",
                "ownerRef",
                "kind",
                "history",
                "snapshotProblem"
              ],
              "additionalProperties": false,
              "properties": {
                "owner": {
                  "const": "run"
                },
                "ownerRef": {
                  "type": "object",
                  "required": [
                    "kind",
                    "scopeCid",
                    "streamCid"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "kind": {
                      "enum": [
                        "run",
                        "effect",
                        "publication",
                        "delivery",
                        "site"
                      ]
                    },
                    "scopeCid": {
                      "type": "string",
                      "pattern": "^sha256:[0-9a-f]{64}$"
                    },
                    "streamCid": {
                      "type": "string",
                      "pattern": "^sha256:[0-9a-f]{64}$"
                    }
                  }
                },
                "kind": {
                  "const": "observed"
                },
                "history": {
                  "oneOf": [
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "not_provided"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "retention_expired"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "history_unrecoverable"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "cursor_mismatch"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "cursor_expired"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "limit_exceeded"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "acquisition_failed"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind",
                        "entries"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "page"
                        },
                        "entries": {
                          "type": "array",
                          "maxItems": 1000,
                          "items": {
                            "type": "object",
                            "required": [
                              "revision",
                              "entryCid",
                              "state"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "revision": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 9007199254740991
                              },
                              "entryCid": {
                                "type": "string",
                                "pattern": "^sha256:[0-9a-f]{64}$"
                              },
                              "state": {
                                "enum": [
                                  "prepared",
                                  "dispatching",
                                  "applied",
                                  "accepted",
                                  "failed",
                                  "unknown"
                                ]
                              }
                            }
                          }
                        },
                        "cursor": {
                          "type": "object",
                          "required": [
                            "owner",
                            "value"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "owner": {
                              "type": "object",
                              "required": [
                                "kind",
                                "scopeCid",
                                "streamCid"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "kind": {
                                  "enum": [
                                    "run",
                                    "effect",
                                    "publication",
                                    "delivery",
                                    "site"
                                  ]
                                },
                                "scopeCid": {
                                  "type": "string",
                                  "pattern": "^sha256:[0-9a-f]{64}$"
                                },
                                "streamCid": {
                                  "type": "string",
                                  "pattern": "^sha256:[0-9a-f]{64}$"
                                }
                              }
                            },
                            "value": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 8192
                            }
                          }
                        }
                      }
                    }
                  ]
                },
                "snapshotProblem": {
                  "type": "object",
                  "required": [
                    "kind"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "kind": {
                      "enum": [
                        "limit_exceeded",
                        "acquisition_failed"
                      ]
                    }
                  }
                }
              }
            },
            {
              "type": "object",
              "required": [
                "owner",
                "ownerRef",
                "kind",
                "history",
                "snapshot"
              ],
              "additionalProperties": false,
              "properties": {
                "owner": {
                  "const": "effect"
                },
                "ownerRef": {
                  "type": "object",
                  "required": [
                    "kind",
                    "scopeCid",
                    "streamCid"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "kind": {
                      "enum": [
                        "run",
                        "effect",
                        "publication",
                        "delivery",
                        "site"
                      ]
                    },
                    "scopeCid": {
                      "type": "string",
                      "pattern": "^sha256:[0-9a-f]{64}$"
                    },
                    "streamCid": {
                      "type": "string",
                      "pattern": "^sha256:[0-9a-f]{64}$"
                    }
                  }
                },
                "kind": {
                  "const": "observed"
                },
                "history": {
                  "oneOf": [
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "not_provided"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "retention_expired"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "history_unrecoverable"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "cursor_mismatch"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "cursor_expired"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "limit_exceeded"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "acquisition_failed"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind",
                        "entries"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "page"
                        },
                        "entries": {
                          "type": "array",
                          "maxItems": 1000,
                          "items": {
                            "type": "object",
                            "required": [
                              "revision",
                              "entryCid",
                              "state"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "revision": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 9007199254740991
                              },
                              "entryCid": {
                                "type": "string",
                                "pattern": "^sha256:[0-9a-f]{64}$"
                              },
                              "state": {
                                "enum": [
                                  "prepared",
                                  "dispatching",
                                  "applied",
                                  "accepted",
                                  "failed",
                                  "unknown"
                                ]
                              }
                            }
                          }
                        },
                        "cursor": {
                          "type": "object",
                          "required": [
                            "owner",
                            "value"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "owner": {
                              "type": "object",
                              "required": [
                                "kind",
                                "scopeCid",
                                "streamCid"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "kind": {
                                  "enum": [
                                    "run",
                                    "effect",
                                    "publication",
                                    "delivery",
                                    "site"
                                  ]
                                },
                                "scopeCid": {
                                  "type": "string",
                                  "pattern": "^sha256:[0-9a-f]{64}$"
                                },
                                "streamCid": {
                                  "type": "string",
                                  "pattern": "^sha256:[0-9a-f]{64}$"
                                }
                              }
                            },
                            "value": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 8192
                            }
                          }
                        }
                      }
                    }
                  ]
                },
                "snapshot": {
                  "type": "object",
                  "required": [
                    "value"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "revision": {
                      "type": "integer",
                      "minimum": 0,
                      "maximum": 9007199254740991
                    },
                    "value": {
                      "type": "object",
                      "required": [
                        "state"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "state": {
                          "enum": [
                            "prepared",
                            "dispatching",
                            "applied",
                            "accepted",
                            "failed",
                            "unknown"
                          ]
                        }
                      }
                    }
                  }
                }
              }
            },
            {
              "type": "object",
              "required": [
                "owner",
                "ownerRef",
                "kind",
                "history",
                "snapshotProblem"
              ],
              "additionalProperties": false,
              "properties": {
                "owner": {
                  "const": "effect"
                },
                "ownerRef": {
                  "type": "object",
                  "required": [
                    "kind",
                    "scopeCid",
                    "streamCid"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "kind": {
                      "enum": [
                        "run",
                        "effect",
                        "publication",
                        "delivery",
                        "site"
                      ]
                    },
                    "scopeCid": {
                      "type": "string",
                      "pattern": "^sha256:[0-9a-f]{64}$"
                    },
                    "streamCid": {
                      "type": "string",
                      "pattern": "^sha256:[0-9a-f]{64}$"
                    }
                  }
                },
                "kind": {
                  "const": "observed"
                },
                "history": {
                  "oneOf": [
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "not_provided"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "retention_expired"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "history_unrecoverable"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "cursor_mismatch"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "cursor_expired"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "limit_exceeded"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "acquisition_failed"
                        }
                      }
                    },
                    {
                      "type": "object",
                      "required": [
                        "kind",
                        "entries"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "kind": {
                          "const": "page"
                        },
                        "entries": {
                          "type": "array",
                          "maxItems": 1000,
                          "items": {
                            "type": "object",
                            "required": [
                              "revision",
                              "entryCid",
                              "state"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "revision": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 9007199254740991
                              },
                              "entryCid": {
                                "type": "string",
                                "pattern": "^sha256:[0-9a-f]{64}$"
                              },
                              "state": {
                                "enum": [
                                  "prepared",
                                  "dispatching",
                                  "applied",
                                  "accepted",
                                  "failed",
                                  "unknown"
                                ]
                              }
                            }
                          }
                        },
                        "cursor": {
                          "type": "object",
                          "required": [
                            "owner",
                            "value"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "owner": {
                              "type": "object",
                              "required": [
                                "kind",
                                "scopeCid",
                                "streamCid"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "kind": {
                                  "enum": [
                                    "run",
                                    "effect",
                                    "publication",
                                    "delivery",
                                    "site"
                                  ]
                                },
                                "scopeCid": {
                                  "type": "string",
                                  "pattern": "^sha256:[0-9a-f]{64}$"
                                },
                                "streamCid": {
                                  "type": "string",
                                  "pattern": "^sha256:[0-9a-f]{64}$"
                                }
                              }
                            },
                            "value": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 8192
                            }
                          }
                        }
                      }
                    }
                  ]
                },
                "snapshotProblem": {
                  "type": "object",
                  "required": [
                    "kind"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "kind": {
                      "enum": [
                        "limit_exceeded",
                        "acquisition_failed"
                      ]
                    }
                  }
                }
              }
            }
          ]
        }
      },
      "revisionVector": {
        "type": "array",
        "maxItems": 5,
        "items": {
          "type": "object",
          "required": [
            "owner"
          ],
          "additionalProperties": false,
          "properties": {
            "owner": {
              "type": "object",
              "required": [
                "kind",
                "scopeCid",
                "streamCid"
              ],
              "additionalProperties": false,
              "properties": {
                "kind": {
                  "enum": [
                    "run",
                    "effect",
                    "publication",
                    "delivery",
                    "site"
                  ]
                },
                "scopeCid": {
                  "type": "string",
                  "pattern": "^sha256:[0-9a-f]{64}$"
                },
                "streamCid": {
                  "type": "string",
                  "pattern": "^sha256:[0-9a-f]{64}$"
                }
              }
            },
            "snapshotCid": {
              "type": "string",
              "pattern": "^sha256:[0-9a-f]{64}$"
            },
            "historyHead": {
              "oneOf": [
                {
                  "const": null
                },
                {
                  "type": "object",
                  "required": [
                    "generation",
                    "revision",
                    "entryCid"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "generation": {
                      "type": "string",
                      "pattern": "^sha256:[0-9a-f]{64}$"
                    },
                    "revision": {
                      "type": "integer",
                      "minimum": 1,
                      "maximum": 9007199254740991
                    },
                    "entryCid": {
                      "type": "string",
                      "pattern": "^sha256:[0-9a-f]{64}$"
                    }
                  }
                }
              ]
            }
          }
        }
      },
      "unmatchedCursors": {
        "type": "array",
        "maxItems": 5,
        "items": {
          "type": "object",
          "required": [
            "index",
            "kind"
          ],
          "additionalProperties": false,
          "properties": {
            "index": {
              "type": "integer",
              "minimum": 0,
              "maximum": 4
            },
            "kind": {
              "const": "unavailable"
            }
          }
        }
      }
    }
  },
  "run_state": {
    "type": "object",
    "required": [
      "version",
      "run_id",
      "status",
      "updated_at",
      "next_action",
      "result_available",
      "result_availability",
      "revision"
    ],
    "additionalProperties": false,
    "properties": {
      "version": {
        "const": "actql-run-state/0.1"
      },
      "run_id": {
        "type": "string",
        "minLength": 1
      },
      "status": {
        "enum": [
          "preparing",
          "running",
          "waiting_checkpoint",
          "resuming",
          "needs_reconciliation",
          "succeeded",
          "failed",
          "cancelled"
        ]
      },
      "updated_at": {
        "type": "string",
        "pattern": "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$"
      },
      "checkpoint": {
        "type": "object",
        "required": [
          "checkpoint_id",
          "checkpoint_cid",
          "kind"
        ],
        "additionalProperties": false,
        "properties": {
          "checkpoint_id": {
            "type": "string",
            "minLength": 1
          },
          "checkpoint_cid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "kind": {
            "enum": [
              "run_scope",
              "read_access",
              "data_egress",
              "cost_scope",
              "effect_set",
              "model_invocation"
            ]
          }
        }
      },
      "next_action": {
        "oneOf": [
          {
            "type": "object",
            "required": [
              "kind",
              "checkpoint_id"
            ],
            "additionalProperties": false,
            "properties": {
              "kind": {
                "const": "resolve_checkpoint"
              },
              "checkpoint_id": {
                "type": "string",
                "minLength": 1
              }
            }
          },
          {
            "type": "object",
            "required": [
              "kind",
              "effects"
            ],
            "additionalProperties": false,
            "properties": {
              "kind": {
                "const": "reconcile"
              },
              "effects": {
                "type": "array",
                "uniqueItems": true,
                "minItems": 1,
                "items": {
                  "type": "string",
                  "minLength": 1
                }
              }
            }
          },
          {
            "type": "object",
            "required": [
              "kind",
              "results"
            ],
            "additionalProperties": false,
            "properties": {
              "kind": {
                "const": "read_result"
              },
              "results": {
                "type": "array",
                "uniqueItems": true,
                "minItems": 1,
                "items": {
                  "type": "string",
                  "minLength": 1
                }
              }
            }
          },
          {
            "type": "object",
            "required": [
              "kind",
              "results"
            ],
            "additionalProperties": false,
            "properties": {
              "kind": {
                "const": "refresh_availability"
              },
              "results": {
                "type": "array",
                "uniqueItems": true,
                "minItems": 1,
                "items": {
                  "type": "string",
                  "minLength": 1
                }
              }
            }
          },
          {
            "type": "object",
            "required": [
              "kind"
            ],
            "additionalProperties": false,
            "properties": {
              "kind": {
                "const": "none"
              }
            }
          },
          {
            "type": "object",
            "required": [
              "kind",
              "reason"
            ],
            "additionalProperties": false,
            "properties": {
              "kind": {
                "const": "reconcile_run"
              },
              "reason": {
                "const": "execution_unknown"
              }
            }
          }
        ]
      },
      "result_available": {
        "type": "boolean"
      },
      "terminal_error": {
        "type": "object",
        "required": [
          "code",
          "message"
        ],
        "additionalProperties": false,
        "properties": {
          "code": {
            "type": "string",
            "pattern": "^ACTQL_E_[A-Z0-9_]+$"
          },
          "message": {
            "type": "string",
            "minLength": 1
          }
        }
      },
      "result_availability": {
        "type": "object",
        "additionalProperties": {
          "type": "object",
          "required": [
            "state",
            "observed_at",
            "reason"
          ],
          "additionalProperties": false,
          "properties": {
            "state": {
              "enum": [
                "available",
                "unavailable",
                "unknown"
              ]
            },
            "observed_at": {
              "type": "string",
              "pattern": "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$"
            },
            "reason": {
              "enum": [
                "confirmed_present",
                "retention_expired",
                "deleted",
                "policy_unavailable",
                "integrity_failed",
                "not_published",
                "store_query_failed",
                "clock_uncertain",
                "verification_pending"
              ]
            },
            "cause_cid": {
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
                    "const": "available"
                  }
                }
              },
              "then": {
                "properties": {
                  "reason": {
                    "const": "confirmed_present"
                  }
                }
              }
            },
            {
              "if": {
                "required": [
                  "state"
                ],
                "properties": {
                  "state": {
                    "const": "unavailable"
                  }
                }
              },
              "then": {
                "properties": {
                  "reason": {
                    "enum": [
                      "retention_expired",
                      "deleted",
                      "policy_unavailable",
                      "integrity_failed",
                      "not_published"
                    ]
                  }
                }
              }
            },
            {
              "if": {
                "required": [
                  "state"
                ],
                "properties": {
                  "state": {
                    "const": "unknown"
                  }
                }
              },
              "then": {
                "properties": {
                  "reason": {
                    "enum": [
                      "store_query_failed",
                      "clock_uncertain",
                      "verification_pending"
                    ]
                  }
                }
              }
            }
          ]
        },
        "propertyNames": {
          "minLength": 1
        }
      },
      "control": {
        "type": "object",
        "required": [
          "revision",
          "cancellation_requested",
          "physical_stop"
        ],
        "additionalProperties": false,
        "properties": {
          "revision": {
            "type": "integer",
            "minimum": 0,
            "maximum": 2147483647
          },
          "cancellation_requested": {
            "type": "boolean"
          },
          "physical_stop": {
            "enum": [
              "unknown",
              "confirmed"
            ]
          }
        }
      },
      "revision": {
        "type": "integer",
        "minimum": 0,
        "maximum": 9007199254740991
      }
    },
    "allOf": [
      {
        "if": {
          "required": [
            "status"
          ],
          "properties": {
            "status": {
              "const": "waiting_checkpoint"
            }
          }
        },
        "then": {
          "required": [
            "checkpoint"
          ],
          "properties": {
            "next_action": {
              "type": "object",
              "required": [
                "kind",
                "checkpoint_id"
              ],
              "properties": {
                "kind": {
                  "const": "resolve_checkpoint"
                }
              }
            }
          }
        }
      },
      {
        "if": {
          "required": [
            "status"
          ],
          "properties": {
            "status": {
              "const": "needs_reconciliation"
            }
          }
        },
        "then": {
          "properties": {
            "next_action": {
              "oneOf": [
                {
                  "type": "object",
                  "required": [
                    "kind",
                    "effects"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "kind": {
                      "const": "reconcile"
                    },
                    "effects": {
                      "type": "array",
                      "uniqueItems": true,
                      "minItems": 1,
                      "items": {
                        "type": "string",
                        "minLength": 1
                      }
                    }
                  }
                },
                {
                  "type": "object",
                  "required": [
                    "kind",
                    "reason"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "kind": {
                      "const": "reconcile_run"
                    },
                    "reason": {
                      "const": "execution_unknown"
                    }
                  }
                }
              ]
            }
          },
          "not": {
            "required": [
              "checkpoint"
            ]
          }
        }
      },
      {
        "if": {
          "required": [
            "status"
          ],
          "properties": {
            "status": {
              "const": "succeeded"
            }
          }
        },
        "then": {
          "properties": {
            "next_action": {
              "type": "object",
              "required": [
                "kind"
              ],
              "properties": {
                "kind": {
                  "enum": [
                    "read_result",
                    "refresh_availability",
                    "none"
                  ]
                }
              }
            }
          },
          "not": {
            "required": [
              "checkpoint"
            ]
          }
        }
      },
      {
        "if": {
          "required": [
            "status"
          ],
          "properties": {
            "status": {
              "enum": [
                "preparing",
                "running",
                "resuming",
                "failed",
                "cancelled"
              ]
            }
          }
        },
        "then": {
          "properties": {
            "next_action": {
              "type": "object",
              "required": [
                "kind"
              ],
              "properties": {
                "kind": {
                  "const": "none"
                }
              }
            }
          },
          "not": {
            "required": [
              "checkpoint"
            ]
          }
        }
      },
      {
        "if": {
          "required": [
            "result_availability"
          ],
          "properties": {
            "result_availability": {
              "maxProperties": 0
            }
          }
        },
        "then": {
          "properties": {
            "result_available": {
              "const": false
            },
            "next_action": {
              "properties": {
                "kind": {
                  "enum": [
                    "none",
                    "resolve_checkpoint",
                    "reconcile",
                    "reconcile_run"
                  ]
                }
              }
            }
          }
        }
      }
    ]
  },
  "check_outcome": {
    "oneOf": [
      {
        "type": "object",
        "required": [
          "outcome",
          "report",
          "version",
          "reason_schema_cid",
          "outcome_schema_cid"
        ],
        "additionalProperties": false,
        "properties": {
          "outcome": {
            "const": "completed"
          },
          "report": {
            "type": "object",
            "required": [
              "context_ref",
              "coverage",
              "inputs",
              "reasons",
              "requirements",
              "runnable",
              "scope",
              "verdict"
            ],
            "additionalProperties": false,
            "properties": {
              "runnable": {
                "type": "object",
                "required": [
                  "verdict",
                  "reasons"
                ],
                "additionalProperties": false,
                "properties": {
                  "verdict": {
                    "enum": [
                      "yes",
                      "no"
                    ]
                  },
                  "reasons": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "required": [
                        "code"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "code": {
                          "type": "string",
                          "pattern": "^[a-z][a-z0-9_]{0,63}$"
                        }
                      }
                    }
                  }
                },
                "allOf": [
                  {
                    "if": {
                      "properties": {
                        "verdict": {
                          "const": "yes"
                        }
                      }
                    },
                    "then": {
                      "properties": {
                        "reasons": {
                          "maxItems": 0
                        }
                      }
                    }
                  },
                  {
                    "if": {
                      "properties": {
                        "verdict": {
                          "const": "no"
                        }
                      }
                    },
                    "then": {
                      "properties": {
                        "reasons": {
                          "minItems": 1
                        }
                      }
                    }
                  }
                ]
              },
              "context_ref": {
                "type": "string",
                "pattern": "^[A-Za-z0-9:_-]+$",
                "minLength": 1,
                "maxLength": 128
              },
              "omissions": {
                "type": "object",
                "required": [
                  "requirements"
                ],
                "additionalProperties": false,
                "properties": {
                  "requirements": {
                    "const": true
                  }
                }
              },
              "inputs": {
                "type": "array",
                "minItems": 1,
                "maxItems": 3,
                "items": {
                  "type": "object",
                  "required": [
                    "document_id",
                    "revision",
                    "kind",
                    "byte_length"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "document_id": {
                      "enum": [
                        "source",
                        "program",
                        "parameter_declarations",
                        "parameters"
                      ]
                    },
                    "revision": {
                      "type": "string",
                      "pattern": "^rev:[0-9a-f]{64}$"
                    },
                    "kind": {
                      "enum": [
                        "text",
                        "structured"
                      ]
                    },
                    "byte_length": {
                      "type": "integer",
                      "minimum": 0,
                      "maximum": 9007199254740991
                    }
                  }
                }
              },
              "coverage": {
                "type": "object",
                "required": [
                  "limits",
                  "unresolved"
                ],
                "additionalProperties": false,
                "properties": {
                  "limits": {
                    "type": "array",
                    "items": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "code"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "code": {
                              "type": "string",
                              "pattern": "^[a-z][a-z0-9_]{0,63}$"
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "code",
                            "location"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "code": {
                              "enum": [
                                "implementation_limit",
                                "analysis_budget_exhausted"
                              ]
                            },
                            "location": {
                              "type": "object",
                              "required": [
                                "kind",
                                "document_id",
                                "revision",
                                "pointer"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "kind": {
                                  "const": "structured"
                                },
                                "document_id": {
                                  "const": "program"
                                },
                                "revision": {
                                  "type": "string",
                                  "pattern": "^rev:[0-9a-f]{64}$"
                                },
                                "pointer": {
                                  "type": "string",
                                  "pattern": "^(?:/(?:[^~]|~[01])*)*$",
                                  "maxLength": 4096
                                }
                              }
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "code",
                            "facts"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "code": {
                              "const": "implementation_limit"
                            },
                            "facts": {
                              "type": "object",
                              "required": [
                                "issue"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "issue": {
                                  "const": "function_lowering_unresolved"
                                }
                              }
                            },
                            "location": {
                              "type": "object",
                              "required": [
                                "kind",
                                "document_id",
                                "revision",
                                "start_byte",
                                "end_byte",
                                "precision"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "kind": {
                                  "const": "text"
                                },
                                "document_id": {
                                  "const": "source"
                                },
                                "revision": {
                                  "type": "string",
                                  "pattern": "^rev:[0-9a-f]{64}$"
                                },
                                "start_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "end_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "precision": {
                                  "enum": [
                                    "exact",
                                    "approximate"
                                  ]
                                }
                              }
                            }
                          }
                        }
                      ]
                    }
                  },
                  "unresolved": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "required": [
                        "boundary",
                        "reason"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "boundary": {
                          "type": "string",
                          "pattern": "^[a-z][a-z0-9_]{0,63}$"
                        },
                        "reason": {
                          "const": "unresolved_protected"
                        }
                      }
                    }
                  }
                }
              },
              "reasons": {
                "type": "array",
                "maxItems": 1024,
                "items": {
                  "type": "object",
                  "required": [
                    "code"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "code": {
                      "type": "string",
                      "pattern": "^[a-z][a-z0-9_]{0,63}$"
                    },
                    "location": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "kind",
                            "document_id",
                            "revision",
                            "start_byte",
                            "end_byte",
                            "precision"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "kind": {
                              "const": "text"
                            },
                            "document_id": {
                              "const": "source"
                            },
                            "revision": {
                              "type": "string",
                              "pattern": "^rev:[0-9a-f]{64}$"
                            },
                            "start_byte": {
                              "type": "integer",
                              "minimum": 0,
                              "maximum": 1048576
                            },
                            "end_byte": {
                              "type": "integer",
                              "minimum": 0,
                              "maximum": 1048576
                            },
                            "precision": {
                              "enum": [
                                "exact",
                                "approximate"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "kind",
                            "document_id",
                            "revision",
                            "pointer"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "kind": {
                              "const": "structured"
                            },
                            "document_id": {
                              "enum": [
                                "program",
                                "parameter_declarations",
                                "parameters"
                              ]
                            },
                            "revision": {
                              "type": "string",
                              "pattern": "^rev:[0-9a-f]{64}$"
                            },
                            "pointer": {
                              "type": "string",
                              "pattern": "^(?:/(?:[^~]|~[01])*)*$",
                              "maxLength": 4096
                            }
                          }
                        }
                      ]
                    },
                    "fixes": {
                      "type": "array",
                      "minItems": 1,
                      "maxItems": 1,
                      "items": {
                        "type": "object",
                        "required": [
                          "code",
                          "applicability",
                          "risk",
                          "target",
                          "edits"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "code": {
                            "const": "close_block_comment"
                          },
                          "applicability": {
                            "const": "requires_review"
                          },
                          "risk": {
                            "const": "syntax_structure"
                          },
                          "target": {
                            "type": "object",
                            "required": [
                              "document_id",
                              "revision"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "document_id": {
                                "const": "source"
                              },
                              "revision": {
                                "type": "string",
                                "pattern": "^rev:[0-9a-f]{64}$"
                              }
                            }
                          },
                          "edits": {
                            "type": "array",
                            "minItems": 1,
                            "maxItems": 1,
                            "items": {
                              "type": "object",
                              "required": [
                                "start_byte",
                                "end_byte",
                                "replacement"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "start_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "end_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "replacement": {
                                  "const": "*/"
                                }
                              }
                            }
                          }
                        }
                      }
                    },
                    "facts": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "parameter"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "expected_type",
                            "actual_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "expected_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "content_ref",
                                "int64"
                              ]
                            },
                            "actual_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "content_ref",
                                "int64"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "expected_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "expected_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "content_ref",
                                "int64"
                              ]
                            },
                            "admission": {
                              "type": "object",
                              "required": [
                                "kind",
                                "contract_schema_cid",
                                "contract",
                                "constraints",
                                "supplier"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "contract_schema_cid": {
                                  "const": "sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1"
                                },
                                "kind": {
                                  "const": "parameter_declaration"
                                },
                                "contract": {
                                  "$ref": "value_contract"
                                },
                                "supplier": {
                                  "const": "caller"
                                },
                                "constraints": {
                                  "type": "array",
                                  "maxItems": 8192,
                                  "items": {
                                    "oneOf": [
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path",
                                          "integer"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "numeric"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
                                                    }
                                                  }
                                                },
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          },
                                          "integer": {
                                            "type": "boolean"
                                          },
                                          "minimum": {
                                            "type": "number"
                                          },
                                          "maximum": {
                                            "type": "number"
                                          }
                                        }
                                      },
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "duration"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
                                                    }
                                                  }
                                                },
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          }
                                        }
                                      },
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path",
                                          "length"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "array_length"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
                                                    }
                                                  }
                                                },
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          },
                                          "length": {
                                            "type": "integer",
                                            "minimum": 1,
                                            "maximum": 9007199254740991
                                          }
                                        }
                                      }
                                    ]
                                  }
                                }
                              }
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "constraint"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "constraint": {
                              "enum": [
                                "numeric",
                                "duration",
                                "array_length",
                                "array_size"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "expected_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "expected_type": {
                              "enum": [
                                "number",
                                "boolean",
                                "string"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "domain"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "domain": {
                              "enum": [
                                "positive_safe_integer",
                                "nonnegative_safe_integer",
                                "unit_fraction",
                                "finite_number",
                                "duration",
                                "positive_milliseconds",
                                "signed_milliseconds",
                                "timestamp"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "operation",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "operation": {
                              "const": "components"
                            },
                            "issue": {
                              "enum": [
                                "invalid_kind",
                                "invalid_output_rows"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "operation",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "operation": {
                              "const": "subgraph"
                            },
                            "issue": {
                              "enum": [
                                "invalid_node_selector"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "document",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "document": {
                              "enum": [
                                "parameters",
                                "parameter_declarations"
                              ]
                            },
                            "issue": {
                              "enum": [
                                "invalid_unicode",
                                "unexpected_end",
                                "unexpected_token",
                                "invalid_string",
                                "invalid_escape",
                                "invalid_number",
                                "number_out_of_range",
                                "negative_zero",
                                "expected_colon",
                                "expected_array_separator",
                                "expected_object_separator",
                                "duplicate_key",
                                "trailing_content"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "issue": {
                              "enum": [
                                "unexpected_end",
                                "unexpected_token",
                                "invalid_escape",
                                "invalid_scalar",
                                "empty_identifier",
                                "unterminated_comment",
                                "invalid_number",
                                "invalid_parameter",
                                "unknown_reference",
                                "invalid_arguments",
                                "expected_boolean",
                                "invalid_bounds",
                                "function_lowering_unresolved",
                                "missing_field",
                                "wrong_type",
                                "unexpected_null",
                                "invalid_structure"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "contract_cid",
                            "schema_cid",
                            "schema_pointer",
                            "supplier",
                            "stage"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "contract_cid": {
                              "const": "sha256:6a419d77cad73380825177f80901a12e24eb742055e89bbb27ffa5a3cc9e7da9"
                            },
                            "schema_cid": {
                              "const": "sha256:3cc98bb9d2850a8070a6c9e66f6e3baf52e5f32e997488a3d91dd809fe95b265"
                            },
                            "schema_pointer": {
                              "const": "/schema"
                            },
                            "supplier": {
                              "const": "checking_context_owner"
                            },
                            "stage": {
                              "const": "checking"
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "profile_cid",
                            "supplier",
                            "stage"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "profile_cid": {
                              "const": "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df"
                            },
                            "supplier": {
                              "const": "checking_context_owner"
                            },
                            "stage": {
                              "const": "checking"
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "namespace",
                            "connector",
                            "resource"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "namespace": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "connector": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 65536
                            },
                            "resource": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 65536
                            },
                            "view": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 65536
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "namespace",
                            "reference"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "namespace": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "reference": {
                              "type": "array",
                              "minItems": 1,
                              "maxItems": 8192,
                              "items": {
                                "type": "object",
                                "required": [
                                  "value",
                                  "quoted"
                                ],
                                "additionalProperties": false,
                                "properties": {
                                  "value": {
                                    "type": "string",
                                    "minLength": 1,
                                    "maxLength": 65536
                                  },
                                  "quoted": {
                                    "type": "boolean"
                                  }
                                }
                              }
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "argument",
                            "constraint",
                            "expected_type",
                            "maximum",
                            "minimum",
                            "operation",
                            "parameter",
                            "stage"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "argument": {
                              "enum": [
                                "count",
                                "offset"
                              ]
                            },
                            "constraint": {
                              "const": "safe_integer"
                            },
                            "expected_type": {
                              "enum": [
                                "number",
                                "int64"
                              ]
                            },
                            "maximum": {
                              "const": 9007199254740991
                            },
                            "minimum": {
                              "enum": [
                                0,
                                1
                              ]
                            },
                            "operation": {
                              "const": "take"
                            },
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "stage": {
                              "const": "binding"
                            }
                          },
                          "allOf": [
                            {
                              "if": {
                                "properties": {
                                  "argument": {
                                    "const": "count"
                                  }
                                }
                              },
                              "then": {
                                "properties": {
                                  "minimum": {
                                    "const": 1
                                  }
                                }
                              }
                            },
                            {
                              "if": {
                                "properties": {
                                  "argument": {
                                    "const": "offset"
                                  }
                                }
                              },
                              "then": {
                                "properties": {
                                  "minimum": {
                                    "const": 0
                                  }
                                }
                              }
                            }
                          ]
                        }
                      ]
                    }
                  },
                  "allOf": [
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "program_structure_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "issue"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "issue": {
                                "enum": [
                                  "missing_field",
                                  "wrong_type",
                                  "unexpected_null",
                                  "invalid_structure"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "program"
                              }
                            }
                          }
                        },
                        "not": {
                          "required": [
                            "fixes"
                          ]
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "numeric_reduction_profile_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "profile_cid",
                              "supplier",
                              "stage"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "profile_cid": {
                                "const": "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df"
                              },
                              "supplier": {
                                "const": "checking_context_owner"
                              },
                              "stage": {
                                "const": "checking"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "not": {
                              "required": [
                                "location"
                              ]
                            }
                          },
                          {
                            "not": {
                              "required": [
                                "fixes"
                              ]
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "numeric_reduction_profile_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "profile_cid"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "host_capacity_policy_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "contract_cid",
                              "schema_cid",
                              "schema_pointer",
                              "supplier",
                              "stage"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "contract_cid": {
                                "const": "sha256:6a419d77cad73380825177f80901a12e24eb742055e89bbb27ffa5a3cc9e7da9"
                              },
                              "schema_cid": {
                                "const": "sha256:3cc98bb9d2850a8070a6c9e66f6e3baf52e5f32e997488a3d91dd809fe95b265"
                              },
                              "schema_pointer": {
                                "const": "/schema"
                              },
                              "supplier": {
                                "const": "checking_context_owner"
                              },
                              "stage": {
                                "const": "checking"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "not": {
                              "required": [
                                "location"
                              ]
                            }
                          },
                          {
                            "not": {
                              "required": [
                                "fixes"
                              ]
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "host_capacity_policy_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "schema_pointer"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "implementation_limit"
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "const": "function_lowering_unresolved"
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "parameter_value_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "admission"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "required": [
                          "fixes"
                        ]
                      },
                      "then": {
                        "required": [
                          "facts",
                          "location"
                        ],
                        "properties": {
                          "code": {
                            "const": "query_lexical_invalid"
                          },
                          "facts": {
                            "properties": {
                              "issue": {
                                "const": "unterminated_comment"
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "precision": {
                                "const": "exact"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "query_syntax_invalid",
                              "parameter_undeclared"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "supplied_value_type_mismatch",
                              "supplied_value_constraint_violation",
                              "supplied_value_invalid",
                              "supplied_parameters_invalid"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameters"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "parameter_declarations_invalid",
                              "parameter_value_required"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameter_declarations",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "supplied_value_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "actual_type"
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_default_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "actual_type"
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameter_declarations",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_undeclared"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "parameter"
                            ],
                            "allOf": [
                              {
                                "not": {
                                  "required": [
                                    "expected_type"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "constraint"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "domain"
                                  ]
                                }
                              }
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_value_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "parameter",
                              "expected_type"
                            ],
                            "not": {
                              "required": [
                                "actual_type"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_unused"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "parameter"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "parameter": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameter_declarations",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "supplied_value_constraint_violation"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "constraint"
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "expression_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "expected_type"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "expected_type": {
                                "enum": [
                                  "number",
                                  "boolean",
                                  "string"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "operation_parameter_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "domain"
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameters",
                                  "parameter_declarations"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "binding_json_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "document",
                              "issue"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "document": {
                                "enum": [
                                  "parameters",
                                  "parameter_declarations"
                                ]
                              },
                              "issue": {
                                "enum": [
                                  "invalid_unicode",
                                  "unexpected_end",
                                  "unexpected_token",
                                  "invalid_string",
                                  "invalid_escape",
                                  "invalid_number",
                                  "number_out_of_range",
                                  "negative_zero",
                                  "expected_colon",
                                  "expected_array_separator",
                                  "expected_object_separator",
                                  "duplicate_key",
                                  "trailing_content"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "if": {
                              "properties": {
                                "facts": {
                                  "properties": {
                                    "document": {
                                      "const": "parameters"
                                    }
                                  }
                                }
                              }
                            },
                            "then": {
                              "properties": {
                                "location": {
                                  "properties": {
                                    "document_id": {
                                      "const": "parameters"
                                    }
                                  }
                                }
                              }
                            }
                          },
                          {
                            "if": {
                              "properties": {
                                "facts": {
                                  "properties": {
                                    "document": {
                                      "const": "parameter_declarations"
                                    }
                                  }
                                }
                              }
                            },
                            "then": {
                              "properties": {
                                "location": {
                                  "properties": {
                                    "document_id": {
                                      "const": "parameter_declarations"
                                    }
                                  }
                                }
                              }
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_lexical_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "unexpected_end",
                                  "unexpected_token",
                                  "invalid_escape",
                                  "invalid_scalar",
                                  "empty_identifier",
                                  "unterminated_comment",
                                  "invalid_number",
                                  "invalid_parameter"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_expression_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "unknown_reference",
                                  "invalid_arguments",
                                  "invalid_number",
                                  "expected_boolean"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_frame_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "invalid_bounds"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "graph_operation_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "operation",
                              "issue"
                            ],
                            "properties": {
                              "operation": {
                                "enum": [
                                  "components",
                                  "subgraph"
                                ]
                              },
                              "issue": {
                                "enum": [
                                  "invalid_kind",
                                  "invalid_output_rows",
                                  "invalid_node_selector"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "source_selector_unregistered"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "namespace",
                              "connector",
                              "resource"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "namespace": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              },
                              "connector": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 65536
                              },
                              "resource": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 65536
                              },
                              "view": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 65536
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "program"
                              }
                            }
                          }
                        },
                        "not": {
                          "required": [
                            "fixes"
                          ]
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_alias_absent"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "namespace",
                              "reference"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "namespace": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              },
                              "reference": {
                                "type": "array",
                                "minItems": 1,
                                "maxItems": 8192,
                                "items": {
                                  "type": "object",
                                  "required": [
                                    "value",
                                    "quoted"
                                  ],
                                  "additionalProperties": false,
                                  "properties": {
                                    "value": {
                                      "type": "string",
                                      "minLength": 1,
                                      "maxLength": 65536
                                    },
                                    "quoted": {
                                      "type": "boolean"
                                    }
                                  }
                                }
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        },
                        "not": {
                          "required": [
                            "fixes"
                          ]
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "enum": [
                                "supplied_value_type_mismatch",
                                "parameter_default_type_mismatch",
                                "parameter_value_required",
                                "parameter_undeclared",
                                "parameter_unused",
                                "supplied_value_constraint_violation",
                                "binding_json_invalid",
                                "query_lexical_invalid",
                                "query_expression_invalid",
                                "query_frame_invalid",
                                "graph_operation_invalid",
                                "operation_parameter_invalid",
                                "expression_type_mismatch",
                                "implementation_limit",
                                "host_capacity_policy_required",
                                "numeric_reduction_profile_required",
                                "program_structure_invalid",
                                "source_selector_unregistered",
                                "query_alias_absent",
                                "parameter_consumer_condition"
                              ]
                            }
                          }
                        }
                      },
                      "then": {
                        "not": {
                          "required": [
                            "facts"
                          ]
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_consumer_condition"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "argument",
                              "constraint",
                              "expected_type",
                              "maximum",
                              "minimum",
                              "operation",
                              "parameter",
                              "stage"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "argument": {
                                "enum": [
                                  "count",
                                  "offset"
                                ]
                              },
                              "constraint": {
                                "const": "safe_integer"
                              },
                              "expected_type": {
                                "enum": [
                                  "number",
                                  "int64"
                                ]
                              },
                              "maximum": {
                                "const": 9007199254740991
                              },
                              "minimum": {
                                "enum": [
                                  0,
                                  1
                                ]
                              },
                              "operation": {
                                "const": "take"
                              },
                              "parameter": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              },
                              "stage": {
                                "const": "binding"
                              }
                            },
                            "allOf": [
                              {
                                "if": {
                                  "properties": {
                                    "argument": {
                                      "const": "count"
                                    }
                                  }
                                },
                                "then": {
                                  "properties": {
                                    "minimum": {
                                      "const": 1
                                    }
                                  }
                                }
                              },
                              {
                                "if": {
                                  "properties": {
                                    "argument": {
                                      "const": "offset"
                                    }
                                  }
                                },
                                "then": {
                                  "properties": {
                                    "minimum": {
                                      "const": 0
                                    }
                                  }
                                }
                              }
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameter_declarations",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "parameter_consumer_condition"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "argument"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "not": {
                        "properties": {
                          "code": {
                            "enum": [
                              "parameter_value_required",
                              "parameter_consumer_condition",
                              "host_capacity_policy_required",
                              "numeric_reduction_profile_required"
                            ]
                          }
                        }
                      }
                    }
                  ]
                }
              },
              "requirements": {
                "type": "array",
                "maxItems": 1024,
                "items": {
                  "type": "object",
                  "required": [
                    "code",
                    "facts"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "code": {
                      "enum": [
                        "parameter_value_required",
                        "parameter_consumer_condition",
                        "host_capacity_policy_required",
                        "numeric_reduction_profile_required"
                      ]
                    },
                    "location": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "kind",
                            "document_id",
                            "revision",
                            "start_byte",
                            "end_byte",
                            "precision"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "kind": {
                              "const": "text"
                            },
                            "document_id": {
                              "const": "source"
                            },
                            "revision": {
                              "type": "string",
                              "pattern": "^rev:[0-9a-f]{64}$"
                            },
                            "start_byte": {
                              "type": "integer",
                              "minimum": 0,
                              "maximum": 1048576
                            },
                            "end_byte": {
                              "type": "integer",
                              "minimum": 0,
                              "maximum": 1048576
                            },
                            "precision": {
                              "enum": [
                                "exact",
                                "approximate"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "kind",
                            "document_id",
                            "revision",
                            "pointer"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "kind": {
                              "const": "structured"
                            },
                            "document_id": {
                              "enum": [
                                "program",
                                "parameter_declarations",
                                "parameters"
                              ]
                            },
                            "revision": {
                              "type": "string",
                              "pattern": "^rev:[0-9a-f]{64}$"
                            },
                            "pointer": {
                              "type": "string",
                              "pattern": "^(?:/(?:[^~]|~[01])*)*$",
                              "maxLength": 4096
                            }
                          }
                        }
                      ]
                    },
                    "fixes": {
                      "type": "array",
                      "minItems": 1,
                      "maxItems": 1,
                      "items": {
                        "type": "object",
                        "required": [
                          "code",
                          "applicability",
                          "risk",
                          "target",
                          "edits"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "code": {
                            "const": "close_block_comment"
                          },
                          "applicability": {
                            "const": "requires_review"
                          },
                          "risk": {
                            "const": "syntax_structure"
                          },
                          "target": {
                            "type": "object",
                            "required": [
                              "document_id",
                              "revision"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "document_id": {
                                "const": "source"
                              },
                              "revision": {
                                "type": "string",
                                "pattern": "^rev:[0-9a-f]{64}$"
                              }
                            }
                          },
                          "edits": {
                            "type": "array",
                            "minItems": 1,
                            "maxItems": 1,
                            "items": {
                              "type": "object",
                              "required": [
                                "start_byte",
                                "end_byte",
                                "replacement"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "start_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "end_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "replacement": {
                                  "const": "*/"
                                }
                              }
                            }
                          }
                        }
                      }
                    },
                    "facts": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "parameter"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "expected_type",
                            "actual_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "expected_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "content_ref",
                                "int64"
                              ]
                            },
                            "actual_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "content_ref",
                                "int64"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "expected_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "expected_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "content_ref",
                                "int64"
                              ]
                            },
                            "admission": {
                              "type": "object",
                              "required": [
                                "kind",
                                "contract_schema_cid",
                                "contract",
                                "constraints",
                                "supplier"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "contract_schema_cid": {
                                  "const": "sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1"
                                },
                                "kind": {
                                  "const": "parameter_declaration"
                                },
                                "contract": {
                                  "$ref": "value_contract"
                                },
                                "supplier": {
                                  "const": "caller"
                                },
                                "constraints": {
                                  "type": "array",
                                  "maxItems": 8192,
                                  "items": {
                                    "oneOf": [
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path",
                                          "integer"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "numeric"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
                                                    }
                                                  }
                                                },
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          },
                                          "integer": {
                                            "type": "boolean"
                                          },
                                          "minimum": {
                                            "type": "number"
                                          },
                                          "maximum": {
                                            "type": "number"
                                          }
                                        }
                                      },
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "duration"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
                                                    }
                                                  }
                                                },
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          }
                                        }
                                      },
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path",
                                          "length"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "array_length"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
                                                    }
                                                  }
                                                },
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          },
                                          "length": {
                                            "type": "integer",
                                            "minimum": 1,
                                            "maximum": 9007199254740991
                                          }
                                        }
                                      }
                                    ]
                                  }
                                }
                              }
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "constraint"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "constraint": {
                              "enum": [
                                "numeric",
                                "duration",
                                "array_length",
                                "array_size"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "expected_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "expected_type": {
                              "enum": [
                                "number",
                                "boolean",
                                "string"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "domain"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "domain": {
                              "enum": [
                                "positive_safe_integer",
                                "nonnegative_safe_integer",
                                "unit_fraction",
                                "finite_number",
                                "duration",
                                "positive_milliseconds",
                                "signed_milliseconds",
                                "timestamp"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "operation",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "operation": {
                              "const": "components"
                            },
                            "issue": {
                              "enum": [
                                "invalid_kind",
                                "invalid_output_rows"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "operation",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "operation": {
                              "const": "subgraph"
                            },
                            "issue": {
                              "enum": [
                                "invalid_node_selector"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "document",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "document": {
                              "enum": [
                                "parameters",
                                "parameter_declarations"
                              ]
                            },
                            "issue": {
                              "enum": [
                                "invalid_unicode",
                                "unexpected_end",
                                "unexpected_token",
                                "invalid_string",
                                "invalid_escape",
                                "invalid_number",
                                "number_out_of_range",
                                "negative_zero",
                                "expected_colon",
                                "expected_array_separator",
                                "expected_object_separator",
                                "duplicate_key",
                                "trailing_content"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "issue": {
                              "enum": [
                                "unexpected_end",
                                "unexpected_token",
                                "invalid_escape",
                                "invalid_scalar",
                                "empty_identifier",
                                "unterminated_comment",
                                "invalid_number",
                                "invalid_parameter",
                                "unknown_reference",
                                "invalid_arguments",
                                "expected_boolean",
                                "invalid_bounds",
                                "function_lowering_unresolved",
                                "missing_field",
                                "wrong_type",
                                "unexpected_null",
                                "invalid_structure"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "contract_cid",
                            "schema_cid",
                            "schema_pointer",
                            "supplier",
                            "stage"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "contract_cid": {
                              "const": "sha256:6a419d77cad73380825177f80901a12e24eb742055e89bbb27ffa5a3cc9e7da9"
                            },
                            "schema_cid": {
                              "const": "sha256:3cc98bb9d2850a8070a6c9e66f6e3baf52e5f32e997488a3d91dd809fe95b265"
                            },
                            "schema_pointer": {
                              "const": "/schema"
                            },
                            "supplier": {
                              "const": "checking_context_owner"
                            },
                            "stage": {
                              "const": "checking"
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "profile_cid",
                            "supplier",
                            "stage"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "profile_cid": {
                              "const": "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df"
                            },
                            "supplier": {
                              "const": "checking_context_owner"
                            },
                            "stage": {
                              "const": "checking"
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "namespace",
                            "connector",
                            "resource"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "namespace": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "connector": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 65536
                            },
                            "resource": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 65536
                            },
                            "view": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 65536
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "namespace",
                            "reference"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "namespace": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "reference": {
                              "type": "array",
                              "minItems": 1,
                              "maxItems": 8192,
                              "items": {
                                "type": "object",
                                "required": [
                                  "value",
                                  "quoted"
                                ],
                                "additionalProperties": false,
                                "properties": {
                                  "value": {
                                    "type": "string",
                                    "minLength": 1,
                                    "maxLength": 65536
                                  },
                                  "quoted": {
                                    "type": "boolean"
                                  }
                                }
                              }
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "argument",
                            "constraint",
                            "expected_type",
                            "maximum",
                            "minimum",
                            "operation",
                            "parameter",
                            "stage"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "argument": {
                              "enum": [
                                "count",
                                "offset"
                              ]
                            },
                            "constraint": {
                              "const": "safe_integer"
                            },
                            "expected_type": {
                              "enum": [
                                "number",
                                "int64"
                              ]
                            },
                            "maximum": {
                              "const": 9007199254740991
                            },
                            "minimum": {
                              "enum": [
                                0,
                                1
                              ]
                            },
                            "operation": {
                              "const": "take"
                            },
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "stage": {
                              "const": "binding"
                            }
                          },
                          "allOf": [
                            {
                              "if": {
                                "properties": {
                                  "argument": {
                                    "const": "count"
                                  }
                                }
                              },
                              "then": {
                                "properties": {
                                  "minimum": {
                                    "const": 1
                                  }
                                }
                              }
                            },
                            {
                              "if": {
                                "properties": {
                                  "argument": {
                                    "const": "offset"
                                  }
                                }
                              },
                              "then": {
                                "properties": {
                                  "minimum": {
                                    "const": 0
                                  }
                                }
                              }
                            }
                          ]
                        }
                      ]
                    }
                  },
                  "allOf": [
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "program_structure_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "issue"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "issue": {
                                "enum": [
                                  "missing_field",
                                  "wrong_type",
                                  "unexpected_null",
                                  "invalid_structure"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "program"
                              }
                            }
                          }
                        },
                        "not": {
                          "required": [
                            "fixes"
                          ]
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "numeric_reduction_profile_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "profile_cid",
                              "supplier",
                              "stage"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "profile_cid": {
                                "const": "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df"
                              },
                              "supplier": {
                                "const": "checking_context_owner"
                              },
                              "stage": {
                                "const": "checking"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "not": {
                              "required": [
                                "location"
                              ]
                            }
                          },
                          {
                            "not": {
                              "required": [
                                "fixes"
                              ]
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "numeric_reduction_profile_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "profile_cid"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "host_capacity_policy_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "contract_cid",
                              "schema_cid",
                              "schema_pointer",
                              "supplier",
                              "stage"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "contract_cid": {
                                "const": "sha256:6a419d77cad73380825177f80901a12e24eb742055e89bbb27ffa5a3cc9e7da9"
                              },
                              "schema_cid": {
                                "const": "sha256:3cc98bb9d2850a8070a6c9e66f6e3baf52e5f32e997488a3d91dd809fe95b265"
                              },
                              "schema_pointer": {
                                "const": "/schema"
                              },
                              "supplier": {
                                "const": "checking_context_owner"
                              },
                              "stage": {
                                "const": "checking"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "not": {
                              "required": [
                                "location"
                              ]
                            }
                          },
                          {
                            "not": {
                              "required": [
                                "fixes"
                              ]
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "host_capacity_policy_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "schema_pointer"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "implementation_limit"
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "const": "function_lowering_unresolved"
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "parameter_value_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "admission"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "required": [
                          "fixes"
                        ]
                      },
                      "then": {
                        "required": [
                          "facts",
                          "location"
                        ],
                        "properties": {
                          "code": {
                            "const": "query_lexical_invalid"
                          },
                          "facts": {
                            "properties": {
                              "issue": {
                                "const": "unterminated_comment"
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "precision": {
                                "const": "exact"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "query_syntax_invalid",
                              "parameter_undeclared"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "supplied_value_type_mismatch",
                              "supplied_value_constraint_violation",
                              "supplied_value_invalid",
                              "supplied_parameters_invalid"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameters"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "parameter_declarations_invalid",
                              "parameter_value_required"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameter_declarations",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "supplied_value_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "actual_type"
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_default_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "actual_type"
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameter_declarations",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_undeclared"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "parameter"
                            ],
                            "allOf": [
                              {
                                "not": {
                                  "required": [
                                    "expected_type"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "constraint"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "domain"
                                  ]
                                }
                              }
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_value_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "parameter",
                              "expected_type"
                            ],
                            "not": {
                              "required": [
                                "actual_type"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_unused"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "parameter"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "parameter": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameter_declarations",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "supplied_value_constraint_violation"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "constraint"
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "expression_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "expected_type"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "expected_type": {
                                "enum": [
                                  "number",
                                  "boolean",
                                  "string"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "operation_parameter_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "domain"
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameters",
                                  "parameter_declarations"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "binding_json_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "document",
                              "issue"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "document": {
                                "enum": [
                                  "parameters",
                                  "parameter_declarations"
                                ]
                              },
                              "issue": {
                                "enum": [
                                  "invalid_unicode",
                                  "unexpected_end",
                                  "unexpected_token",
                                  "invalid_string",
                                  "invalid_escape",
                                  "invalid_number",
                                  "number_out_of_range",
                                  "negative_zero",
                                  "expected_colon",
                                  "expected_array_separator",
                                  "expected_object_separator",
                                  "duplicate_key",
                                  "trailing_content"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "if": {
                              "properties": {
                                "facts": {
                                  "properties": {
                                    "document": {
                                      "const": "parameters"
                                    }
                                  }
                                }
                              }
                            },
                            "then": {
                              "properties": {
                                "location": {
                                  "properties": {
                                    "document_id": {
                                      "const": "parameters"
                                    }
                                  }
                                }
                              }
                            }
                          },
                          {
                            "if": {
                              "properties": {
                                "facts": {
                                  "properties": {
                                    "document": {
                                      "const": "parameter_declarations"
                                    }
                                  }
                                }
                              }
                            },
                            "then": {
                              "properties": {
                                "location": {
                                  "properties": {
                                    "document_id": {
                                      "const": "parameter_declarations"
                                    }
                                  }
                                }
                              }
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_lexical_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "unexpected_end",
                                  "unexpected_token",
                                  "invalid_escape",
                                  "invalid_scalar",
                                  "empty_identifier",
                                  "unterminated_comment",
                                  "invalid_number",
                                  "invalid_parameter"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_expression_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "unknown_reference",
                                  "invalid_arguments",
                                  "invalid_number",
                                  "expected_boolean"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_frame_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "invalid_bounds"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "graph_operation_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "operation",
                              "issue"
                            ],
                            "properties": {
                              "operation": {
                                "enum": [
                                  "components",
                                  "subgraph"
                                ]
                              },
                              "issue": {
                                "enum": [
                                  "invalid_kind",
                                  "invalid_output_rows",
                                  "invalid_node_selector"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "source_selector_unregistered"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "namespace",
                              "connector",
                              "resource"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "namespace": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              },
                              "connector": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 65536
                              },
                              "resource": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 65536
                              },
                              "view": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 65536
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "program"
                              }
                            }
                          }
                        },
                        "not": {
                          "required": [
                            "fixes"
                          ]
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_alias_absent"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "namespace",
                              "reference"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "namespace": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              },
                              "reference": {
                                "type": "array",
                                "minItems": 1,
                                "maxItems": 8192,
                                "items": {
                                  "type": "object",
                                  "required": [
                                    "value",
                                    "quoted"
                                  ],
                                  "additionalProperties": false,
                                  "properties": {
                                    "value": {
                                      "type": "string",
                                      "minLength": 1,
                                      "maxLength": 65536
                                    },
                                    "quoted": {
                                      "type": "boolean"
                                    }
                                  }
                                }
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        },
                        "not": {
                          "required": [
                            "fixes"
                          ]
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "enum": [
                                "supplied_value_type_mismatch",
                                "parameter_default_type_mismatch",
                                "parameter_value_required",
                                "parameter_undeclared",
                                "parameter_unused",
                                "supplied_value_constraint_violation",
                                "binding_json_invalid",
                                "query_lexical_invalid",
                                "query_expression_invalid",
                                "query_frame_invalid",
                                "graph_operation_invalid",
                                "operation_parameter_invalid",
                                "expression_type_mismatch",
                                "implementation_limit",
                                "host_capacity_policy_required",
                                "numeric_reduction_profile_required",
                                "program_structure_invalid",
                                "source_selector_unregistered",
                                "query_alias_absent",
                                "parameter_consumer_condition"
                              ]
                            }
                          }
                        }
                      },
                      "then": {
                        "not": {
                          "required": [
                            "facts"
                          ]
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_consumer_condition"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "argument",
                              "constraint",
                              "expected_type",
                              "maximum",
                              "minimum",
                              "operation",
                              "parameter",
                              "stage"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "argument": {
                                "enum": [
                                  "count",
                                  "offset"
                                ]
                              },
                              "constraint": {
                                "const": "safe_integer"
                              },
                              "expected_type": {
                                "enum": [
                                  "number",
                                  "int64"
                                ]
                              },
                              "maximum": {
                                "const": 9007199254740991
                              },
                              "minimum": {
                                "enum": [
                                  0,
                                  1
                                ]
                              },
                              "operation": {
                                "const": "take"
                              },
                              "parameter": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              },
                              "stage": {
                                "const": "binding"
                              }
                            },
                            "allOf": [
                              {
                                "if": {
                                  "properties": {
                                    "argument": {
                                      "const": "count"
                                    }
                                  }
                                },
                                "then": {
                                  "properties": {
                                    "minimum": {
                                      "const": 1
                                    }
                                  }
                                }
                              },
                              {
                                "if": {
                                  "properties": {
                                    "argument": {
                                      "const": "offset"
                                    }
                                  }
                                },
                                "then": {
                                  "properties": {
                                    "minimum": {
                                      "const": 0
                                    }
                                  }
                                }
                              }
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameter_declarations",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "parameter_consumer_condition"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "argument"
                              ]
                            }
                          }
                        }
                      }
                    }
                  ]
                }
              },
              "scope": {
                "type": "object",
                "required": [
                  "kind"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "enum": [
                      "template_only",
                      "bound_input"
                    ]
                  }
                }
              },
              "verdict": {
                "enum": [
                  "invalid",
                  "undetermined",
                  "verified"
                ]
              }
            },
            "allOf": [
              {
                "if": {
                  "properties": {
                    "verdict": {
                      "const": "invalid"
                    }
                  }
                },
                "then": {
                  "properties": {
                    "runnable": {
                      "properties": {
                        "verdict": {
                          "const": "no"
                        }
                      }
                    }
                  }
                }
              },
              {
                "if": {
                  "properties": {
                    "verdict": {
                      "const": "undetermined"
                    }
                  }
                },
                "then": {
                  "properties": {
                    "runnable": {
                      "properties": {
                        "verdict": {
                          "const": "no"
                        }
                      }
                    }
                  }
                }
              },
              {
                "if": {
                  "properties": {
                    "verdict": {
                      "const": "verified"
                    }
                  }
                },
                "then": {
                  "properties": {
                    "reasons": {
                      "type": "array",
                      "maxItems": 0,
                      "items": {}
                    },
                    "coverage": {
                      "properties": {
                        "limits": {
                          "type": "array",
                          "maxItems": 0,
                          "items": {}
                        },
                        "unresolved": {
                          "type": "array",
                          "maxItems": 0,
                          "items": {}
                        }
                      }
                    }
                  },
                  "allOf": [
                    {
                      "if": {
                        "properties": {
                          "scope": {
                            "properties": {
                              "kind": {
                                "const": "bound_input"
                              }
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "requirements": {
                            "type": "array",
                            "maxItems": 0,
                            "items": {}
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "scope": {
                            "properties": {
                              "kind": {
                                "const": "template_only"
                              }
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "requirements": {
                            "items": {
                              "properties": {
                                "code": {
                                  "enum": [
                                    "parameter_value_required",
                                    "parameter_consumer_condition"
                                  ]
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  ],
                  "not": {
                    "required": [
                      "omissions"
                    ]
                  }
                }
              },
              {
                "if": {
                  "properties": {
                    "verdict": {
                      "const": "invalid"
                    }
                  }
                },
                "then": {
                  "properties": {
                    "reasons": {
                      "type": "array",
                      "minItems": 1,
                      "items": {}
                    }
                  }
                }
              },
              {
                "if": {
                  "properties": {
                    "verdict": {
                      "const": "undetermined"
                    }
                  }
                },
                "then": {
                  "properties": {
                    "reasons": {
                      "type": "array",
                      "maxItems": 0,
                      "items": {}
                    },
                    "coverage": {
                      "not": {
                        "properties": {
                          "limits": {
                            "type": "array",
                            "maxItems": 0,
                            "items": {}
                          },
                          "unresolved": {
                            "type": "array",
                            "maxItems": 0,
                            "items": {}
                          }
                        }
                      }
                    }
                  }
                }
              }
            ]
          },
          "outcome_schema_cid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "reason_schema_cid": {
            "const": "sha256:93e2d1285a3136da858996545d957273d70acad3cf180c07d59aa61cfa126ca5"
          },
          "version": {
            "const": "actql-check-outcome/0.1"
          }
        }
      },
      {
        "type": "object",
        "required": [
          "outcome",
          "problem",
          "version",
          "reason_schema_cid",
          "outcome_schema_cid",
          "correlation_ref"
        ],
        "additionalProperties": false,
        "properties": {
          "outcome": {
            "const": "failed"
          },
          "partial_report": {
            "type": "object",
            "required": [
              "context_ref",
              "coverage",
              "inputs",
              "reasons",
              "requirements",
              "runnable",
              "scope",
              "verdict"
            ],
            "additionalProperties": false,
            "properties": {
              "runnable": {
                "type": "object",
                "required": [
                  "verdict",
                  "reasons"
                ],
                "additionalProperties": false,
                "properties": {
                  "verdict": {
                    "enum": [
                      "yes",
                      "no"
                    ]
                  },
                  "reasons": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "required": [
                        "code"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "code": {
                          "type": "string",
                          "pattern": "^[a-z][a-z0-9_]{0,63}$"
                        }
                      }
                    }
                  }
                },
                "allOf": [
                  {
                    "if": {
                      "properties": {
                        "verdict": {
                          "const": "yes"
                        }
                      }
                    },
                    "then": {
                      "properties": {
                        "reasons": {
                          "maxItems": 0
                        }
                      }
                    }
                  },
                  {
                    "if": {
                      "properties": {
                        "verdict": {
                          "const": "no"
                        }
                      }
                    },
                    "then": {
                      "properties": {
                        "reasons": {
                          "minItems": 1
                        }
                      }
                    }
                  }
                ]
              },
              "context_ref": {
                "type": "string",
                "pattern": "^[A-Za-z0-9:_-]+$",
                "minLength": 1,
                "maxLength": 128
              },
              "omissions": {
                "type": "object",
                "required": [
                  "requirements"
                ],
                "additionalProperties": false,
                "properties": {
                  "requirements": {
                    "const": true
                  }
                }
              },
              "inputs": {
                "type": "array",
                "minItems": 1,
                "maxItems": 3,
                "items": {
                  "type": "object",
                  "required": [
                    "document_id",
                    "revision",
                    "kind",
                    "byte_length"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "document_id": {
                      "enum": [
                        "source",
                        "program",
                        "parameter_declarations",
                        "parameters"
                      ]
                    },
                    "revision": {
                      "type": "string",
                      "pattern": "^rev:[0-9a-f]{64}$"
                    },
                    "kind": {
                      "enum": [
                        "text",
                        "structured"
                      ]
                    },
                    "byte_length": {
                      "type": "integer",
                      "minimum": 0,
                      "maximum": 9007199254740991
                    }
                  }
                }
              },
              "coverage": {
                "type": "object",
                "required": [
                  "limits",
                  "unresolved"
                ],
                "additionalProperties": false,
                "properties": {
                  "limits": {
                    "type": "array",
                    "items": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "code"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "code": {
                              "type": "string",
                              "pattern": "^[a-z][a-z0-9_]{0,63}$"
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "code",
                            "location"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "code": {
                              "enum": [
                                "implementation_limit",
                                "analysis_budget_exhausted"
                              ]
                            },
                            "location": {
                              "type": "object",
                              "required": [
                                "kind",
                                "document_id",
                                "revision",
                                "pointer"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "kind": {
                                  "const": "structured"
                                },
                                "document_id": {
                                  "const": "program"
                                },
                                "revision": {
                                  "type": "string",
                                  "pattern": "^rev:[0-9a-f]{64}$"
                                },
                                "pointer": {
                                  "type": "string",
                                  "pattern": "^(?:/(?:[^~]|~[01])*)*$",
                                  "maxLength": 4096
                                }
                              }
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "code",
                            "facts"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "code": {
                              "const": "implementation_limit"
                            },
                            "facts": {
                              "type": "object",
                              "required": [
                                "issue"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "issue": {
                                  "const": "function_lowering_unresolved"
                                }
                              }
                            },
                            "location": {
                              "type": "object",
                              "required": [
                                "kind",
                                "document_id",
                                "revision",
                                "start_byte",
                                "end_byte",
                                "precision"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "kind": {
                                  "const": "text"
                                },
                                "document_id": {
                                  "const": "source"
                                },
                                "revision": {
                                  "type": "string",
                                  "pattern": "^rev:[0-9a-f]{64}$"
                                },
                                "start_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "end_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "precision": {
                                  "enum": [
                                    "exact",
                                    "approximate"
                                  ]
                                }
                              }
                            }
                          }
                        }
                      ]
                    }
                  },
                  "unresolved": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "required": [
                        "boundary",
                        "reason"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "boundary": {
                          "type": "string",
                          "pattern": "^[a-z][a-z0-9_]{0,63}$"
                        },
                        "reason": {
                          "const": "unresolved_protected"
                        }
                      }
                    }
                  }
                }
              },
              "reasons": {
                "type": "array",
                "maxItems": 1024,
                "items": {
                  "type": "object",
                  "required": [
                    "code"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "code": {
                      "type": "string",
                      "pattern": "^[a-z][a-z0-9_]{0,63}$"
                    },
                    "location": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "kind",
                            "document_id",
                            "revision",
                            "start_byte",
                            "end_byte",
                            "precision"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "kind": {
                              "const": "text"
                            },
                            "document_id": {
                              "const": "source"
                            },
                            "revision": {
                              "type": "string",
                              "pattern": "^rev:[0-9a-f]{64}$"
                            },
                            "start_byte": {
                              "type": "integer",
                              "minimum": 0,
                              "maximum": 1048576
                            },
                            "end_byte": {
                              "type": "integer",
                              "minimum": 0,
                              "maximum": 1048576
                            },
                            "precision": {
                              "enum": [
                                "exact",
                                "approximate"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "kind",
                            "document_id",
                            "revision",
                            "pointer"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "kind": {
                              "const": "structured"
                            },
                            "document_id": {
                              "enum": [
                                "program",
                                "parameter_declarations",
                                "parameters"
                              ]
                            },
                            "revision": {
                              "type": "string",
                              "pattern": "^rev:[0-9a-f]{64}$"
                            },
                            "pointer": {
                              "type": "string",
                              "pattern": "^(?:/(?:[^~]|~[01])*)*$",
                              "maxLength": 4096
                            }
                          }
                        }
                      ]
                    },
                    "fixes": {
                      "type": "array",
                      "minItems": 1,
                      "maxItems": 1,
                      "items": {
                        "type": "object",
                        "required": [
                          "code",
                          "applicability",
                          "risk",
                          "target",
                          "edits"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "code": {
                            "const": "close_block_comment"
                          },
                          "applicability": {
                            "const": "requires_review"
                          },
                          "risk": {
                            "const": "syntax_structure"
                          },
                          "target": {
                            "type": "object",
                            "required": [
                              "document_id",
                              "revision"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "document_id": {
                                "const": "source"
                              },
                              "revision": {
                                "type": "string",
                                "pattern": "^rev:[0-9a-f]{64}$"
                              }
                            }
                          },
                          "edits": {
                            "type": "array",
                            "minItems": 1,
                            "maxItems": 1,
                            "items": {
                              "type": "object",
                              "required": [
                                "start_byte",
                                "end_byte",
                                "replacement"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "start_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "end_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "replacement": {
                                  "const": "*/"
                                }
                              }
                            }
                          }
                        }
                      }
                    },
                    "facts": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "parameter"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "expected_type",
                            "actual_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "expected_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "content_ref",
                                "int64"
                              ]
                            },
                            "actual_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "content_ref",
                                "int64"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "expected_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "expected_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "content_ref",
                                "int64"
                              ]
                            },
                            "admission": {
                              "type": "object",
                              "required": [
                                "kind",
                                "contract_schema_cid",
                                "contract",
                                "constraints",
                                "supplier"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "contract_schema_cid": {
                                  "const": "sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1"
                                },
                                "kind": {
                                  "const": "parameter_declaration"
                                },
                                "contract": {
                                  "$ref": "value_contract"
                                },
                                "supplier": {
                                  "const": "caller"
                                },
                                "constraints": {
                                  "type": "array",
                                  "maxItems": 8192,
                                  "items": {
                                    "oneOf": [
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path",
                                          "integer"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "numeric"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
                                                    }
                                                  }
                                                },
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          },
                                          "integer": {
                                            "type": "boolean"
                                          },
                                          "minimum": {
                                            "type": "number"
                                          },
                                          "maximum": {
                                            "type": "number"
                                          }
                                        }
                                      },
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "duration"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
                                                    }
                                                  }
                                                },
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          }
                                        }
                                      },
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path",
                                          "length"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "array_length"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
                                                    }
                                                  }
                                                },
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          },
                                          "length": {
                                            "type": "integer",
                                            "minimum": 1,
                                            "maximum": 9007199254740991
                                          }
                                        }
                                      }
                                    ]
                                  }
                                }
                              }
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "constraint"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "constraint": {
                              "enum": [
                                "numeric",
                                "duration",
                                "array_length",
                                "array_size"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "expected_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "expected_type": {
                              "enum": [
                                "number",
                                "boolean",
                                "string"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "domain"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "domain": {
                              "enum": [
                                "positive_safe_integer",
                                "nonnegative_safe_integer",
                                "unit_fraction",
                                "finite_number",
                                "duration",
                                "positive_milliseconds",
                                "signed_milliseconds",
                                "timestamp"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "operation",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "operation": {
                              "const": "components"
                            },
                            "issue": {
                              "enum": [
                                "invalid_kind",
                                "invalid_output_rows"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "operation",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "operation": {
                              "const": "subgraph"
                            },
                            "issue": {
                              "enum": [
                                "invalid_node_selector"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "document",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "document": {
                              "enum": [
                                "parameters",
                                "parameter_declarations"
                              ]
                            },
                            "issue": {
                              "enum": [
                                "invalid_unicode",
                                "unexpected_end",
                                "unexpected_token",
                                "invalid_string",
                                "invalid_escape",
                                "invalid_number",
                                "number_out_of_range",
                                "negative_zero",
                                "expected_colon",
                                "expected_array_separator",
                                "expected_object_separator",
                                "duplicate_key",
                                "trailing_content"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "issue": {
                              "enum": [
                                "unexpected_end",
                                "unexpected_token",
                                "invalid_escape",
                                "invalid_scalar",
                                "empty_identifier",
                                "unterminated_comment",
                                "invalid_number",
                                "invalid_parameter",
                                "unknown_reference",
                                "invalid_arguments",
                                "expected_boolean",
                                "invalid_bounds",
                                "function_lowering_unresolved",
                                "missing_field",
                                "wrong_type",
                                "unexpected_null",
                                "invalid_structure"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "contract_cid",
                            "schema_cid",
                            "schema_pointer",
                            "supplier",
                            "stage"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "contract_cid": {
                              "const": "sha256:6a419d77cad73380825177f80901a12e24eb742055e89bbb27ffa5a3cc9e7da9"
                            },
                            "schema_cid": {
                              "const": "sha256:3cc98bb9d2850a8070a6c9e66f6e3baf52e5f32e997488a3d91dd809fe95b265"
                            },
                            "schema_pointer": {
                              "const": "/schema"
                            },
                            "supplier": {
                              "const": "checking_context_owner"
                            },
                            "stage": {
                              "const": "checking"
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "profile_cid",
                            "supplier",
                            "stage"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "profile_cid": {
                              "const": "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df"
                            },
                            "supplier": {
                              "const": "checking_context_owner"
                            },
                            "stage": {
                              "const": "checking"
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "namespace",
                            "connector",
                            "resource"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "namespace": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "connector": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 65536
                            },
                            "resource": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 65536
                            },
                            "view": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 65536
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "namespace",
                            "reference"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "namespace": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "reference": {
                              "type": "array",
                              "minItems": 1,
                              "maxItems": 8192,
                              "items": {
                                "type": "object",
                                "required": [
                                  "value",
                                  "quoted"
                                ],
                                "additionalProperties": false,
                                "properties": {
                                  "value": {
                                    "type": "string",
                                    "minLength": 1,
                                    "maxLength": 65536
                                  },
                                  "quoted": {
                                    "type": "boolean"
                                  }
                                }
                              }
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "argument",
                            "constraint",
                            "expected_type",
                            "maximum",
                            "minimum",
                            "operation",
                            "parameter",
                            "stage"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "argument": {
                              "enum": [
                                "count",
                                "offset"
                              ]
                            },
                            "constraint": {
                              "const": "safe_integer"
                            },
                            "expected_type": {
                              "enum": [
                                "number",
                                "int64"
                              ]
                            },
                            "maximum": {
                              "const": 9007199254740991
                            },
                            "minimum": {
                              "enum": [
                                0,
                                1
                              ]
                            },
                            "operation": {
                              "const": "take"
                            },
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "stage": {
                              "const": "binding"
                            }
                          },
                          "allOf": [
                            {
                              "if": {
                                "properties": {
                                  "argument": {
                                    "const": "count"
                                  }
                                }
                              },
                              "then": {
                                "properties": {
                                  "minimum": {
                                    "const": 1
                                  }
                                }
                              }
                            },
                            {
                              "if": {
                                "properties": {
                                  "argument": {
                                    "const": "offset"
                                  }
                                }
                              },
                              "then": {
                                "properties": {
                                  "minimum": {
                                    "const": 0
                                  }
                                }
                              }
                            }
                          ]
                        }
                      ]
                    }
                  },
                  "allOf": [
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "program_structure_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "issue"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "issue": {
                                "enum": [
                                  "missing_field",
                                  "wrong_type",
                                  "unexpected_null",
                                  "invalid_structure"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "program"
                              }
                            }
                          }
                        },
                        "not": {
                          "required": [
                            "fixes"
                          ]
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "numeric_reduction_profile_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "profile_cid",
                              "supplier",
                              "stage"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "profile_cid": {
                                "const": "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df"
                              },
                              "supplier": {
                                "const": "checking_context_owner"
                              },
                              "stage": {
                                "const": "checking"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "not": {
                              "required": [
                                "location"
                              ]
                            }
                          },
                          {
                            "not": {
                              "required": [
                                "fixes"
                              ]
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "numeric_reduction_profile_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "profile_cid"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "host_capacity_policy_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "contract_cid",
                              "schema_cid",
                              "schema_pointer",
                              "supplier",
                              "stage"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "contract_cid": {
                                "const": "sha256:6a419d77cad73380825177f80901a12e24eb742055e89bbb27ffa5a3cc9e7da9"
                              },
                              "schema_cid": {
                                "const": "sha256:3cc98bb9d2850a8070a6c9e66f6e3baf52e5f32e997488a3d91dd809fe95b265"
                              },
                              "schema_pointer": {
                                "const": "/schema"
                              },
                              "supplier": {
                                "const": "checking_context_owner"
                              },
                              "stage": {
                                "const": "checking"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "not": {
                              "required": [
                                "location"
                              ]
                            }
                          },
                          {
                            "not": {
                              "required": [
                                "fixes"
                              ]
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "host_capacity_policy_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "schema_pointer"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "implementation_limit"
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "const": "function_lowering_unresolved"
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "parameter_value_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "admission"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "required": [
                          "fixes"
                        ]
                      },
                      "then": {
                        "required": [
                          "facts",
                          "location"
                        ],
                        "properties": {
                          "code": {
                            "const": "query_lexical_invalid"
                          },
                          "facts": {
                            "properties": {
                              "issue": {
                                "const": "unterminated_comment"
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "precision": {
                                "const": "exact"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "query_syntax_invalid",
                              "parameter_undeclared"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "supplied_value_type_mismatch",
                              "supplied_value_constraint_violation",
                              "supplied_value_invalid",
                              "supplied_parameters_invalid"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameters"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "parameter_declarations_invalid",
                              "parameter_value_required"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameter_declarations",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "supplied_value_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "actual_type"
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_default_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "actual_type"
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameter_declarations",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_undeclared"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "parameter"
                            ],
                            "allOf": [
                              {
                                "not": {
                                  "required": [
                                    "expected_type"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "constraint"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "domain"
                                  ]
                                }
                              }
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_value_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "parameter",
                              "expected_type"
                            ],
                            "not": {
                              "required": [
                                "actual_type"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_unused"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "parameter"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "parameter": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameter_declarations",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "supplied_value_constraint_violation"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "constraint"
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "expression_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "expected_type"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "expected_type": {
                                "enum": [
                                  "number",
                                  "boolean",
                                  "string"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "operation_parameter_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "domain"
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameters",
                                  "parameter_declarations"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "binding_json_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "document",
                              "issue"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "document": {
                                "enum": [
                                  "parameters",
                                  "parameter_declarations"
                                ]
                              },
                              "issue": {
                                "enum": [
                                  "invalid_unicode",
                                  "unexpected_end",
                                  "unexpected_token",
                                  "invalid_string",
                                  "invalid_escape",
                                  "invalid_number",
                                  "number_out_of_range",
                                  "negative_zero",
                                  "expected_colon",
                                  "expected_array_separator",
                                  "expected_object_separator",
                                  "duplicate_key",
                                  "trailing_content"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "if": {
                              "properties": {
                                "facts": {
                                  "properties": {
                                    "document": {
                                      "const": "parameters"
                                    }
                                  }
                                }
                              }
                            },
                            "then": {
                              "properties": {
                                "location": {
                                  "properties": {
                                    "document_id": {
                                      "const": "parameters"
                                    }
                                  }
                                }
                              }
                            }
                          },
                          {
                            "if": {
                              "properties": {
                                "facts": {
                                  "properties": {
                                    "document": {
                                      "const": "parameter_declarations"
                                    }
                                  }
                                }
                              }
                            },
                            "then": {
                              "properties": {
                                "location": {
                                  "properties": {
                                    "document_id": {
                                      "const": "parameter_declarations"
                                    }
                                  }
                                }
                              }
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_lexical_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "unexpected_end",
                                  "unexpected_token",
                                  "invalid_escape",
                                  "invalid_scalar",
                                  "empty_identifier",
                                  "unterminated_comment",
                                  "invalid_number",
                                  "invalid_parameter"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_expression_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "unknown_reference",
                                  "invalid_arguments",
                                  "invalid_number",
                                  "expected_boolean"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_frame_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "invalid_bounds"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "graph_operation_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "operation",
                              "issue"
                            ],
                            "properties": {
                              "operation": {
                                "enum": [
                                  "components",
                                  "subgraph"
                                ]
                              },
                              "issue": {
                                "enum": [
                                  "invalid_kind",
                                  "invalid_output_rows",
                                  "invalid_node_selector"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "source_selector_unregistered"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "namespace",
                              "connector",
                              "resource"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "namespace": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              },
                              "connector": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 65536
                              },
                              "resource": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 65536
                              },
                              "view": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 65536
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "program"
                              }
                            }
                          }
                        },
                        "not": {
                          "required": [
                            "fixes"
                          ]
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_alias_absent"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "namespace",
                              "reference"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "namespace": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              },
                              "reference": {
                                "type": "array",
                                "minItems": 1,
                                "maxItems": 8192,
                                "items": {
                                  "type": "object",
                                  "required": [
                                    "value",
                                    "quoted"
                                  ],
                                  "additionalProperties": false,
                                  "properties": {
                                    "value": {
                                      "type": "string",
                                      "minLength": 1,
                                      "maxLength": 65536
                                    },
                                    "quoted": {
                                      "type": "boolean"
                                    }
                                  }
                                }
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        },
                        "not": {
                          "required": [
                            "fixes"
                          ]
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "enum": [
                                "supplied_value_type_mismatch",
                                "parameter_default_type_mismatch",
                                "parameter_value_required",
                                "parameter_undeclared",
                                "parameter_unused",
                                "supplied_value_constraint_violation",
                                "binding_json_invalid",
                                "query_lexical_invalid",
                                "query_expression_invalid",
                                "query_frame_invalid",
                                "graph_operation_invalid",
                                "operation_parameter_invalid",
                                "expression_type_mismatch",
                                "implementation_limit",
                                "host_capacity_policy_required",
                                "numeric_reduction_profile_required",
                                "program_structure_invalid",
                                "source_selector_unregistered",
                                "query_alias_absent",
                                "parameter_consumer_condition"
                              ]
                            }
                          }
                        }
                      },
                      "then": {
                        "not": {
                          "required": [
                            "facts"
                          ]
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_consumer_condition"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "argument",
                              "constraint",
                              "expected_type",
                              "maximum",
                              "minimum",
                              "operation",
                              "parameter",
                              "stage"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "argument": {
                                "enum": [
                                  "count",
                                  "offset"
                                ]
                              },
                              "constraint": {
                                "const": "safe_integer"
                              },
                              "expected_type": {
                                "enum": [
                                  "number",
                                  "int64"
                                ]
                              },
                              "maximum": {
                                "const": 9007199254740991
                              },
                              "minimum": {
                                "enum": [
                                  0,
                                  1
                                ]
                              },
                              "operation": {
                                "const": "take"
                              },
                              "parameter": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              },
                              "stage": {
                                "const": "binding"
                              }
                            },
                            "allOf": [
                              {
                                "if": {
                                  "properties": {
                                    "argument": {
                                      "const": "count"
                                    }
                                  }
                                },
                                "then": {
                                  "properties": {
                                    "minimum": {
                                      "const": 1
                                    }
                                  }
                                }
                              },
                              {
                                "if": {
                                  "properties": {
                                    "argument": {
                                      "const": "offset"
                                    }
                                  }
                                },
                                "then": {
                                  "properties": {
                                    "minimum": {
                                      "const": 0
                                    }
                                  }
                                }
                              }
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameter_declarations",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "parameter_consumer_condition"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "argument"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "not": {
                        "properties": {
                          "code": {
                            "enum": [
                              "parameter_value_required",
                              "parameter_consumer_condition",
                              "host_capacity_policy_required",
                              "numeric_reduction_profile_required"
                            ]
                          }
                        }
                      }
                    }
                  ]
                }
              },
              "requirements": {
                "type": "array",
                "maxItems": 1024,
                "items": {
                  "type": "object",
                  "required": [
                    "code",
                    "facts"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "code": {
                      "enum": [
                        "parameter_value_required",
                        "parameter_consumer_condition",
                        "host_capacity_policy_required",
                        "numeric_reduction_profile_required"
                      ]
                    },
                    "location": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "kind",
                            "document_id",
                            "revision",
                            "start_byte",
                            "end_byte",
                            "precision"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "kind": {
                              "const": "text"
                            },
                            "document_id": {
                              "const": "source"
                            },
                            "revision": {
                              "type": "string",
                              "pattern": "^rev:[0-9a-f]{64}$"
                            },
                            "start_byte": {
                              "type": "integer",
                              "minimum": 0,
                              "maximum": 1048576
                            },
                            "end_byte": {
                              "type": "integer",
                              "minimum": 0,
                              "maximum": 1048576
                            },
                            "precision": {
                              "enum": [
                                "exact",
                                "approximate"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "kind",
                            "document_id",
                            "revision",
                            "pointer"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "kind": {
                              "const": "structured"
                            },
                            "document_id": {
                              "enum": [
                                "program",
                                "parameter_declarations",
                                "parameters"
                              ]
                            },
                            "revision": {
                              "type": "string",
                              "pattern": "^rev:[0-9a-f]{64}$"
                            },
                            "pointer": {
                              "type": "string",
                              "pattern": "^(?:/(?:[^~]|~[01])*)*$",
                              "maxLength": 4096
                            }
                          }
                        }
                      ]
                    },
                    "fixes": {
                      "type": "array",
                      "minItems": 1,
                      "maxItems": 1,
                      "items": {
                        "type": "object",
                        "required": [
                          "code",
                          "applicability",
                          "risk",
                          "target",
                          "edits"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "code": {
                            "const": "close_block_comment"
                          },
                          "applicability": {
                            "const": "requires_review"
                          },
                          "risk": {
                            "const": "syntax_structure"
                          },
                          "target": {
                            "type": "object",
                            "required": [
                              "document_id",
                              "revision"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "document_id": {
                                "const": "source"
                              },
                              "revision": {
                                "type": "string",
                                "pattern": "^rev:[0-9a-f]{64}$"
                              }
                            }
                          },
                          "edits": {
                            "type": "array",
                            "minItems": 1,
                            "maxItems": 1,
                            "items": {
                              "type": "object",
                              "required": [
                                "start_byte",
                                "end_byte",
                                "replacement"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "start_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "end_byte": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 1048576
                                },
                                "replacement": {
                                  "const": "*/"
                                }
                              }
                            }
                          }
                        }
                      }
                    },
                    "facts": {
                      "oneOf": [
                        {
                          "type": "object",
                          "required": [
                            "parameter"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "expected_type",
                            "actual_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "expected_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "content_ref",
                                "int64"
                              ]
                            },
                            "actual_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "content_ref",
                                "int64"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "expected_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "expected_type": {
                              "enum": [
                                "null",
                                "boolean",
                                "number",
                                "string",
                                "array",
                                "object",
                                "date",
                                "timestamp",
                                "decimal",
                                "json",
                                "vector",
                                "resource_ref",
                                "content_ref",
                                "int64"
                              ]
                            },
                            "admission": {
                              "type": "object",
                              "required": [
                                "kind",
                                "contract_schema_cid",
                                "contract",
                                "constraints",
                                "supplier"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "contract_schema_cid": {
                                  "const": "sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1"
                                },
                                "kind": {
                                  "const": "parameter_declaration"
                                },
                                "contract": {
                                  "$ref": "value_contract"
                                },
                                "supplier": {
                                  "const": "caller"
                                },
                                "constraints": {
                                  "type": "array",
                                  "maxItems": 8192,
                                  "items": {
                                    "oneOf": [
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path",
                                          "integer"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "numeric"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
                                                    }
                                                  }
                                                },
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          },
                                          "integer": {
                                            "type": "boolean"
                                          },
                                          "minimum": {
                                            "type": "number"
                                          },
                                          "maximum": {
                                            "type": "number"
                                          }
                                        }
                                      },
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "duration"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
                                                    }
                                                  }
                                                },
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          }
                                        }
                                      },
                                      {
                                        "type": "object",
                                        "required": [
                                          "kind",
                                          "path",
                                          "length"
                                        ],
                                        "additionalProperties": false,
                                        "properties": {
                                          "kind": {
                                            "const": "array_length"
                                          },
                                          "path": {
                                            "type": "array",
                                            "maxItems": 64,
                                            "items": {
                                              "oneOf": [
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind",
                                                    "name"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "field"
                                                    },
                                                    "name": {
                                                      "type": "string",
                                                      "minLength": 1,
                                                      "maxLength": 65536
                                                    }
                                                  }
                                                },
                                                {
                                                  "type": "object",
                                                  "required": [
                                                    "kind"
                                                  ],
                                                  "additionalProperties": false,
                                                  "properties": {
                                                    "kind": {
                                                      "const": "items"
                                                    }
                                                  }
                                                }
                                              ]
                                            }
                                          },
                                          "length": {
                                            "type": "integer",
                                            "minimum": 1,
                                            "maximum": 9007199254740991
                                          }
                                        }
                                      }
                                    ]
                                  }
                                }
                              }
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "constraint"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "constraint": {
                              "enum": [
                                "numeric",
                                "duration",
                                "array_length",
                                "array_size"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "expected_type"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "expected_type": {
                              "enum": [
                                "number",
                                "boolean",
                                "string"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "parameter",
                            "domain"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "domain": {
                              "enum": [
                                "positive_safe_integer",
                                "nonnegative_safe_integer",
                                "unit_fraction",
                                "finite_number",
                                "duration",
                                "positive_milliseconds",
                                "signed_milliseconds",
                                "timestamp"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "operation",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "operation": {
                              "const": "components"
                            },
                            "issue": {
                              "enum": [
                                "invalid_kind",
                                "invalid_output_rows"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "operation",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "operation": {
                              "const": "subgraph"
                            },
                            "issue": {
                              "enum": [
                                "invalid_node_selector"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "document",
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "document": {
                              "enum": [
                                "parameters",
                                "parameter_declarations"
                              ]
                            },
                            "issue": {
                              "enum": [
                                "invalid_unicode",
                                "unexpected_end",
                                "unexpected_token",
                                "invalid_string",
                                "invalid_escape",
                                "invalid_number",
                                "number_out_of_range",
                                "negative_zero",
                                "expected_colon",
                                "expected_array_separator",
                                "expected_object_separator",
                                "duplicate_key",
                                "trailing_content"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "issue"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "issue": {
                              "enum": [
                                "unexpected_end",
                                "unexpected_token",
                                "invalid_escape",
                                "invalid_scalar",
                                "empty_identifier",
                                "unterminated_comment",
                                "invalid_number",
                                "invalid_parameter",
                                "unknown_reference",
                                "invalid_arguments",
                                "expected_boolean",
                                "invalid_bounds",
                                "function_lowering_unresolved",
                                "missing_field",
                                "wrong_type",
                                "unexpected_null",
                                "invalid_structure"
                              ]
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "contract_cid",
                            "schema_cid",
                            "schema_pointer",
                            "supplier",
                            "stage"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "contract_cid": {
                              "const": "sha256:6a419d77cad73380825177f80901a12e24eb742055e89bbb27ffa5a3cc9e7da9"
                            },
                            "schema_cid": {
                              "const": "sha256:3cc98bb9d2850a8070a6c9e66f6e3baf52e5f32e997488a3d91dd809fe95b265"
                            },
                            "schema_pointer": {
                              "const": "/schema"
                            },
                            "supplier": {
                              "const": "checking_context_owner"
                            },
                            "stage": {
                              "const": "checking"
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "profile_cid",
                            "supplier",
                            "stage"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "profile_cid": {
                              "const": "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df"
                            },
                            "supplier": {
                              "const": "checking_context_owner"
                            },
                            "stage": {
                              "const": "checking"
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "namespace",
                            "connector",
                            "resource"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "namespace": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "connector": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 65536
                            },
                            "resource": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 65536
                            },
                            "view": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 65536
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "namespace",
                            "reference"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "namespace": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "reference": {
                              "type": "array",
                              "minItems": 1,
                              "maxItems": 8192,
                              "items": {
                                "type": "object",
                                "required": [
                                  "value",
                                  "quoted"
                                ],
                                "additionalProperties": false,
                                "properties": {
                                  "value": {
                                    "type": "string",
                                    "minLength": 1,
                                    "maxLength": 65536
                                  },
                                  "quoted": {
                                    "type": "boolean"
                                  }
                                }
                              }
                            }
                          }
                        },
                        {
                          "type": "object",
                          "required": [
                            "argument",
                            "constraint",
                            "expected_type",
                            "maximum",
                            "minimum",
                            "operation",
                            "parameter",
                            "stage"
                          ],
                          "additionalProperties": false,
                          "properties": {
                            "argument": {
                              "enum": [
                                "count",
                                "offset"
                              ]
                            },
                            "constraint": {
                              "const": "safe_integer"
                            },
                            "expected_type": {
                              "enum": [
                                "number",
                                "int64"
                              ]
                            },
                            "maximum": {
                              "const": 9007199254740991
                            },
                            "minimum": {
                              "enum": [
                                0,
                                1
                              ]
                            },
                            "operation": {
                              "const": "take"
                            },
                            "parameter": {
                              "type": "string",
                              "minLength": 1,
                              "maxLength": 256
                            },
                            "stage": {
                              "const": "binding"
                            }
                          },
                          "allOf": [
                            {
                              "if": {
                                "properties": {
                                  "argument": {
                                    "const": "count"
                                  }
                                }
                              },
                              "then": {
                                "properties": {
                                  "minimum": {
                                    "const": 1
                                  }
                                }
                              }
                            },
                            {
                              "if": {
                                "properties": {
                                  "argument": {
                                    "const": "offset"
                                  }
                                }
                              },
                              "then": {
                                "properties": {
                                  "minimum": {
                                    "const": 0
                                  }
                                }
                              }
                            }
                          ]
                        }
                      ]
                    }
                  },
                  "allOf": [
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "program_structure_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "issue"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "issue": {
                                "enum": [
                                  "missing_field",
                                  "wrong_type",
                                  "unexpected_null",
                                  "invalid_structure"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "program"
                              }
                            }
                          }
                        },
                        "not": {
                          "required": [
                            "fixes"
                          ]
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "numeric_reduction_profile_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "profile_cid",
                              "supplier",
                              "stage"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "profile_cid": {
                                "const": "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df"
                              },
                              "supplier": {
                                "const": "checking_context_owner"
                              },
                              "stage": {
                                "const": "checking"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "not": {
                              "required": [
                                "location"
                              ]
                            }
                          },
                          {
                            "not": {
                              "required": [
                                "fixes"
                              ]
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "numeric_reduction_profile_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "profile_cid"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "host_capacity_policy_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "contract_cid",
                              "schema_cid",
                              "schema_pointer",
                              "supplier",
                              "stage"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "contract_cid": {
                                "const": "sha256:6a419d77cad73380825177f80901a12e24eb742055e89bbb27ffa5a3cc9e7da9"
                              },
                              "schema_cid": {
                                "const": "sha256:3cc98bb9d2850a8070a6c9e66f6e3baf52e5f32e997488a3d91dd809fe95b265"
                              },
                              "schema_pointer": {
                                "const": "/schema"
                              },
                              "supplier": {
                                "const": "checking_context_owner"
                              },
                              "stage": {
                                "const": "checking"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "not": {
                              "required": [
                                "location"
                              ]
                            }
                          },
                          {
                            "not": {
                              "required": [
                                "fixes"
                              ]
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "host_capacity_policy_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "schema_pointer"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "implementation_limit"
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "const": "function_lowering_unresolved"
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "parameter_value_required"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "admission"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "required": [
                          "fixes"
                        ]
                      },
                      "then": {
                        "required": [
                          "facts",
                          "location"
                        ],
                        "properties": {
                          "code": {
                            "const": "query_lexical_invalid"
                          },
                          "facts": {
                            "properties": {
                              "issue": {
                                "const": "unterminated_comment"
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "precision": {
                                "const": "exact"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "query_syntax_invalid",
                              "parameter_undeclared"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "supplied_value_type_mismatch",
                              "supplied_value_constraint_violation",
                              "supplied_value_invalid",
                              "supplied_parameters_invalid"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "parameters"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "enum": [
                              "parameter_declarations_invalid",
                              "parameter_value_required"
                            ]
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameter_declarations",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "supplied_value_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "actual_type"
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_default_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "actual_type"
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameter_declarations",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_undeclared"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "parameter"
                            ],
                            "allOf": [
                              {
                                "not": {
                                  "required": [
                                    "expected_type"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "constraint"
                                  ]
                                }
                              },
                              {
                                "not": {
                                  "required": [
                                    "domain"
                                  ]
                                }
                              }
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_value_required"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "parameter",
                              "expected_type"
                            ],
                            "not": {
                              "required": [
                                "actual_type"
                              ]
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_unused"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "parameter"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "parameter": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameter_declarations",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "supplied_value_constraint_violation"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "constraint"
                            ]
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "expression_type_mismatch"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "expected_type"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "expected_type": {
                                "enum": [
                                  "number",
                                  "boolean",
                                  "string"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "operation_parameter_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "domain"
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameters",
                                  "parameter_declarations"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "binding_json_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "document",
                              "issue"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "document": {
                                "enum": [
                                  "parameters",
                                  "parameter_declarations"
                                ]
                              },
                              "issue": {
                                "enum": [
                                  "invalid_unicode",
                                  "unexpected_end",
                                  "unexpected_token",
                                  "invalid_string",
                                  "invalid_escape",
                                  "invalid_number",
                                  "number_out_of_range",
                                  "negative_zero",
                                  "expected_colon",
                                  "expected_array_separator",
                                  "expected_object_separator",
                                  "duplicate_key",
                                  "trailing_content"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              }
                            }
                          }
                        },
                        "allOf": [
                          {
                            "if": {
                              "properties": {
                                "facts": {
                                  "properties": {
                                    "document": {
                                      "const": "parameters"
                                    }
                                  }
                                }
                              }
                            },
                            "then": {
                              "properties": {
                                "location": {
                                  "properties": {
                                    "document_id": {
                                      "const": "parameters"
                                    }
                                  }
                                }
                              }
                            }
                          },
                          {
                            "if": {
                              "properties": {
                                "facts": {
                                  "properties": {
                                    "document": {
                                      "const": "parameter_declarations"
                                    }
                                  }
                                }
                              }
                            },
                            "then": {
                              "properties": {
                                "location": {
                                  "properties": {
                                    "document_id": {
                                      "const": "parameter_declarations"
                                    }
                                  }
                                }
                              }
                            }
                          }
                        ]
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_lexical_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "unexpected_end",
                                  "unexpected_token",
                                  "invalid_escape",
                                  "invalid_scalar",
                                  "empty_identifier",
                                  "unterminated_comment",
                                  "invalid_number",
                                  "invalid_parameter"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_expression_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "unknown_reference",
                                  "invalid_arguments",
                                  "invalid_number",
                                  "expected_boolean"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_frame_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "issue"
                            ],
                            "properties": {
                              "issue": {
                                "enum": [
                                  "invalid_bounds"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "graph_operation_invalid"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "required": [
                              "operation",
                              "issue"
                            ],
                            "properties": {
                              "operation": {
                                "enum": [
                                  "components",
                                  "subgraph"
                                ]
                              },
                              "issue": {
                                "enum": [
                                  "invalid_kind",
                                  "invalid_output_rows",
                                  "invalid_node_selector"
                                ]
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "enum": [
                                  "text",
                                  "structured"
                                ]
                              },
                              "document_id": {
                                "enum": [
                                  "source",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "source_selector_unregistered"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "namespace",
                              "connector",
                              "resource"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "namespace": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              },
                              "connector": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 65536
                              },
                              "resource": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 65536
                              },
                              "view": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 65536
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "const": "program"
                              }
                            }
                          }
                        },
                        "not": {
                          "required": [
                            "fixes"
                          ]
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "query_alias_absent"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "namespace",
                              "reference"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "namespace": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              },
                              "reference": {
                                "type": "array",
                                "minItems": 1,
                                "maxItems": 8192,
                                "items": {
                                  "type": "object",
                                  "required": [
                                    "value",
                                    "quoted"
                                  ],
                                  "additionalProperties": false,
                                  "properties": {
                                    "value": {
                                      "type": "string",
                                      "minLength": 1,
                                      "maxLength": 65536
                                    },
                                    "quoted": {
                                      "type": "boolean"
                                    }
                                  }
                                }
                              }
                            }
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "text"
                              },
                              "document_id": {
                                "const": "source"
                              }
                            }
                          }
                        },
                        "not": {
                          "required": [
                            "fixes"
                          ]
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "enum": [
                                "supplied_value_type_mismatch",
                                "parameter_default_type_mismatch",
                                "parameter_value_required",
                                "parameter_undeclared",
                                "parameter_unused",
                                "supplied_value_constraint_violation",
                                "binding_json_invalid",
                                "query_lexical_invalid",
                                "query_expression_invalid",
                                "query_frame_invalid",
                                "graph_operation_invalid",
                                "operation_parameter_invalid",
                                "expression_type_mismatch",
                                "implementation_limit",
                                "host_capacity_policy_required",
                                "numeric_reduction_profile_required",
                                "program_structure_invalid",
                                "source_selector_unregistered",
                                "query_alias_absent",
                                "parameter_consumer_condition"
                              ]
                            }
                          }
                        }
                      },
                      "then": {
                        "not": {
                          "required": [
                            "facts"
                          ]
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "const": "parameter_consumer_condition"
                          }
                        }
                      },
                      "then": {
                        "required": [
                          "facts"
                        ],
                        "properties": {
                          "facts": {
                            "type": "object",
                            "required": [
                              "argument",
                              "constraint",
                              "expected_type",
                              "maximum",
                              "minimum",
                              "operation",
                              "parameter",
                              "stage"
                            ],
                            "additionalProperties": false,
                            "properties": {
                              "argument": {
                                "enum": [
                                  "count",
                                  "offset"
                                ]
                              },
                              "constraint": {
                                "const": "safe_integer"
                              },
                              "expected_type": {
                                "enum": [
                                  "number",
                                  "int64"
                                ]
                              },
                              "maximum": {
                                "const": 9007199254740991
                              },
                              "minimum": {
                                "enum": [
                                  0,
                                  1
                                ]
                              },
                              "operation": {
                                "const": "take"
                              },
                              "parameter": {
                                "type": "string",
                                "minLength": 1,
                                "maxLength": 256
                              },
                              "stage": {
                                "const": "binding"
                              }
                            },
                            "allOf": [
                              {
                                "if": {
                                  "properties": {
                                    "argument": {
                                      "const": "count"
                                    }
                                  }
                                },
                                "then": {
                                  "properties": {
                                    "minimum": {
                                      "const": 1
                                    }
                                  }
                                }
                              },
                              {
                                "if": {
                                  "properties": {
                                    "argument": {
                                      "const": "offset"
                                    }
                                  }
                                },
                                "then": {
                                  "properties": {
                                    "minimum": {
                                      "const": 0
                                    }
                                  }
                                }
                              }
                            ]
                          },
                          "location": {
                            "properties": {
                              "kind": {
                                "const": "structured"
                              },
                              "document_id": {
                                "enum": [
                                  "parameter_declarations",
                                  "program"
                                ]
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "code": {
                            "not": {
                              "const": "parameter_consumer_condition"
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "facts": {
                            "not": {
                              "required": [
                                "argument"
                              ]
                            }
                          }
                        }
                      }
                    }
                  ]
                }
              },
              "scope": {
                "type": "object",
                "required": [
                  "kind"
                ],
                "additionalProperties": false,
                "properties": {
                  "kind": {
                    "enum": [
                      "template_only",
                      "bound_input"
                    ]
                  }
                }
              },
              "verdict": {
                "enum": [
                  "invalid",
                  "undetermined"
                ]
              }
            },
            "allOf": [
              {
                "if": {
                  "properties": {
                    "verdict": {
                      "const": "invalid"
                    }
                  }
                },
                "then": {
                  "properties": {
                    "runnable": {
                      "properties": {
                        "verdict": {
                          "const": "no"
                        }
                      }
                    }
                  }
                }
              },
              {
                "if": {
                  "properties": {
                    "verdict": {
                      "const": "undetermined"
                    }
                  }
                },
                "then": {
                  "properties": {
                    "runnable": {
                      "properties": {
                        "verdict": {
                          "const": "no"
                        }
                      }
                    }
                  }
                }
              },
              {
                "if": {
                  "properties": {
                    "verdict": {
                      "const": "verified"
                    }
                  }
                },
                "then": {
                  "properties": {
                    "reasons": {
                      "type": "array",
                      "maxItems": 0,
                      "items": {}
                    },
                    "coverage": {
                      "properties": {
                        "limits": {
                          "type": "array",
                          "maxItems": 0,
                          "items": {}
                        },
                        "unresolved": {
                          "type": "array",
                          "maxItems": 0,
                          "items": {}
                        }
                      }
                    }
                  },
                  "allOf": [
                    {
                      "if": {
                        "properties": {
                          "scope": {
                            "properties": {
                              "kind": {
                                "const": "bound_input"
                              }
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "requirements": {
                            "type": "array",
                            "maxItems": 0,
                            "items": {}
                          }
                        }
                      }
                    },
                    {
                      "if": {
                        "properties": {
                          "scope": {
                            "properties": {
                              "kind": {
                                "const": "template_only"
                              }
                            }
                          }
                        }
                      },
                      "then": {
                        "properties": {
                          "requirements": {
                            "items": {
                              "properties": {
                                "code": {
                                  "enum": [
                                    "parameter_value_required",
                                    "parameter_consumer_condition"
                                  ]
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  ],
                  "not": {
                    "required": [
                      "omissions"
                    ]
                  }
                }
              },
              {
                "if": {
                  "properties": {
                    "verdict": {
                      "const": "invalid"
                    }
                  }
                },
                "then": {
                  "properties": {
                    "reasons": {
                      "type": "array",
                      "minItems": 1,
                      "items": {}
                    }
                  }
                }
              },
              {
                "if": {
                  "properties": {
                    "verdict": {
                      "const": "undetermined"
                    }
                  }
                },
                "then": {
                  "properties": {
                    "reasons": {
                      "type": "array",
                      "maxItems": 0,
                      "items": {}
                    },
                    "coverage": {
                      "not": {
                        "properties": {
                          "limits": {
                            "type": "array",
                            "maxItems": 0,
                            "items": {}
                          },
                          "unresolved": {
                            "type": "array",
                            "maxItems": 0,
                            "items": {}
                          }
                        }
                      }
                    }
                  }
                }
              }
            ]
          },
          "problem": {
            "type": "object",
            "required": [
              "code"
            ],
            "additionalProperties": false,
            "properties": {
              "code": {
                "type": "string",
                "pattern": "^[a-z][a-z0-9_]{0,63}$"
              }
            }
          },
          "correlation_ref": {
            "type": "string",
            "pattern": "^[A-Za-z0-9:_-]+$",
            "minLength": 1,
            "maxLength": 128
          },
          "outcome_schema_cid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "reason_schema_cid": {
            "const": "sha256:93e2d1285a3136da858996545d957273d70acad3cf180c07d59aa61cfa126ca5"
          },
          "version": {
            "const": "actql-check-outcome/0.1"
          }
        }
      },
      {
        "type": "object",
        "required": [
          "correlation_ref",
          "outcome",
          "problem",
          "version",
          "reason_schema_cid",
          "outcome_schema_cid"
        ],
        "additionalProperties": false,
        "properties": {
          "correlation_ref": {
            "type": "string",
            "pattern": "^[A-Za-z0-9:_-]+$",
            "minLength": 1,
            "maxLength": 128
          },
          "outcome": {
            "const": "unavailable"
          },
          "problem": {
            "type": "object",
            "required": [
              "code"
            ],
            "additionalProperties": false,
            "properties": {
              "code": {
                "type": "string",
                "pattern": "^[a-z][a-z0-9_]{0,63}$"
              }
            }
          },
          "outcome_schema_cid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "reason_schema_cid": {
            "const": "sha256:93e2d1285a3136da858996545d957273d70acad3cf180c07d59aa61cfa126ca5"
          },
          "version": {
            "const": "actql-check-outcome/0.1"
          }
        }
      }
    ]
  },
  "value_contract": {
    "oneOf": [
      {
        "type": "object",
        "required": [
          "type",
          "nullable",
          "precision",
          "scale"
        ],
        "additionalProperties": false,
        "properties": {
          "type": {
            "const": "decimal"
          },
          "nullable": {
            "type": "boolean"
          },
          "precision": {
            "type": "integer",
            "minimum": 1,
            "maximum": 38
          },
          "scale": {
            "type": "integer",
            "minimum": 0,
            "maximum": 38
          }
        },
        "allOf": [
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 1
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 1
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 2
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 2
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 3
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 3
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 4
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 4
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 5
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 5
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 6
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 6
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 7
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 7
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 8
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 8
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 9
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 9
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 10
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 10
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 11
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 11
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 12
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 12
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 13
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 13
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 14
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 14
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 15
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 15
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 16
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 16
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 17
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 17
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 18
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 18
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 19
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 19
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 20
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 20
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 21
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 21
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 22
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 22
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 23
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 23
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 24
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 24
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 25
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 25
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 26
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 26
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 27
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 27
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 28
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 28
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 29
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 29
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 30
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 30
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 31
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 31
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 32
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 32
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 33
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 33
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 34
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 34
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 35
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 35
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 36
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 36
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 37
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 37
                }
              }
            }
          },
          {
            "if": {
              "required": [
                "precision"
              ],
              "properties": {
                "precision": {
                  "const": 38
                }
              }
            },
            "then": {
              "properties": {
                "scale": {
                  "maximum": 38
                }
              }
            }
          }
        ]
      },
      {
        "type": "object",
        "required": [
          "type",
          "nullable"
        ],
        "additionalProperties": false,
        "properties": {
          "type": {
            "const": "string"
          },
          "nullable": {
            "type": "boolean"
          },
          "min_length": {
            "type": "integer",
            "minimum": 0
          },
          "max_codepoints": {
            "type": "integer",
            "minimum": 0
          },
          "max_utf8_bytes": {
            "type": "integer",
            "minimum": 0
          },
          "enum": {
            "type": "array",
            "items": {
              "type": "string"
            }
          }
        }
      },
      {
        "type": "object",
        "required": [
          "type",
          "nullable"
        ],
        "additionalProperties": false,
        "properties": {
          "type": {
            "enum": [
              "number",
              "boolean",
              "timestamp",
              "date",
              "json"
            ]
          },
          "nullable": {
            "type": "boolean"
          }
        }
      },
      {
        "type": "object",
        "required": [
          "type",
          "nullable",
          "items"
        ],
        "additionalProperties": false,
        "properties": {
          "type": {
            "const": "array"
          },
          "nullable": {
            "type": "boolean"
          },
          "items": {
            "$ref": "value_contract"
          },
          "max_items": {
            "type": "integer",
            "minimum": 0
          }
        }
      },
      {
        "type": "object",
        "required": [
          "type",
          "nullable",
          "additional_properties",
          "fields"
        ],
        "additionalProperties": false,
        "properties": {
          "type": {
            "const": "object"
          },
          "nullable": {
            "type": "boolean"
          },
          "additional_properties": {
            "const": false
          },
          "fields": {
            "type": "object",
            "additionalProperties": {
              "$ref": "value_contract"
            },
            "propertyNames": {
              "pattern": "^(?!__cid$)(?!__actql_)(?![\\s\\S]*\\.)(?=[\\s\\S]*\\S)[\\s\\S]+$"
            }
          }
        }
      },
      {
        "type": "object",
        "required": [
          "type",
          "nullable",
          "dimensions",
          "element_type"
        ],
        "additionalProperties": false,
        "properties": {
          "type": {
            "const": "vector"
          },
          "nullable": {
            "type": "boolean"
          },
          "dimensions": {
            "type": "integer",
            "minimum": 1
          },
          "element_type": {
            "const": "f32"
          }
        }
      },
      {
        "type": "object",
        "required": [
          "type",
          "nullable",
          "resource_kind"
        ],
        "additionalProperties": false,
        "properties": {
          "type": {
            "const": "resource_ref"
          },
          "nullable": {
            "type": "boolean"
          },
          "resource_kind": {
            "type": "string",
            "minLength": 1
          }
        }
      },
      {
        "type": "object",
        "required": [
          "type",
          "nullable"
        ],
        "additionalProperties": false,
        "properties": {
          "type": {
            "const": "content_ref"
          },
          "nullable": {
            "type": "boolean"
          },
          "media_type": {
            "type": "string",
            "minLength": 1
          }
        }
      },
      {
        "type": "object",
        "required": [
          "type",
          "nullable"
        ],
        "additionalProperties": false,
        "properties": {
          "type": {
            "const": "int64"
          },
          "nullable": {
            "type": "boolean"
          }
        }
      }
    ]
  },
  "run_plan_view": {
    "type": "object",
    "required": [
      "version",
      "run_ref",
      "plan_view"
    ],
    "additionalProperties": false,
    "properties": {
      "version": {
        "const": "actql-run-plan-view/0.1"
      },
      "run_ref": {
        "type": "object",
        "required": [
          "namespaceId",
          "authorityScopeCid",
          "runDefinitionCid"
        ],
        "additionalProperties": false,
        "properties": {
          "namespaceId": {
            "type": "string",
            "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
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
      "plan_view": {
        "type": "object",
        "required": [
          "version",
          "compiled_plan_cid",
          "logical_map",
          "observation",
          "provider_io",
          "quantities",
          "capabilities"
        ],
        "additionalProperties": false,
        "properties": {
          "version": {
            "const": "actql-plan-view/0.1"
          },
          "compiled_plan_cid": {
            "type": "string",
            "pattern": "^sha256:[0-9a-f]{64}$"
          },
          "logical_map": {
            "type": "object",
            "required": [
              "version",
              "compiled_plan_cid",
              "program_definition_cid",
              "steps",
              "self_cid"
            ],
            "additionalProperties": false,
            "properties": {
              "version": {
                "const": "actql-logical-map/0.1"
              },
              "compiled_plan_cid": {
                "type": "string",
                "pattern": "^sha256:[0-9a-f]{64}$"
              },
              "program_definition_cid": {
                "type": "string",
                "pattern": "^sha256:[0-9a-f]{64}$"
              },
              "steps": {
                "type": "array",
                "minItems": 0,
                "items": {
                  "type": "object",
                  "required": [
                    "step_id",
                    "key",
                    "names",
                    "operator",
                    "ports",
                    "can_stop_before",
                    "can_stop_after",
                    "stop_reason"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "step_id": {
                      "type": "string",
                      "pattern": "^sha256:[0-9a-f]{64}$"
                    },
                    "key": {
                      "type": "object",
                      "required": [
                        "version",
                        "compiled_plan_cid",
                        "stage_ordinal",
                        "occurrence",
                        "self_cid"
                      ],
                      "additionalProperties": false,
                      "properties": {
                        "version": {
                          "const": "actql-logical-step-key/0.1"
                        },
                        "compiled_plan_cid": {
                          "type": "string",
                          "pattern": "^sha256:[0-9a-f]{64}$"
                        },
                        "stage_ordinal": {
                          "type": "integer",
                          "minimum": 0,
                          "maximum": 2147483647
                        },
                        "occurrence": {
                          "oneOf": [
                            {
                              "type": "object",
                              "required": [
                                "kind",
                                "operation_ordinal"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "kind": {
                                  "const": "operation"
                                },
                                "operation_ordinal": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 2147483647
                                }
                              }
                            },
                            {
                              "type": "object",
                              "required": [
                                "kind",
                                "input_port_ordinal"
                              ],
                              "additionalProperties": false,
                              "properties": {
                                "kind": {
                                  "const": "input_output"
                                },
                                "input_port_ordinal": {
                                  "type": "integer",
                                  "minimum": 0,
                                  "maximum": 2147483647
                                }
                              }
                            }
                          ]
                        },
                        "self_cid": {
                          "type": "string",
                          "pattern": "^sha256:[0-9a-f]{64}$"
                        }
                      }
                    },
                    "names": {
                      "type": "array",
                      "uniqueItems": true,
                      "minItems": 0,
                      "items": {
                        "type": "string",
                        "minLength": 1
                      }
                    },
                    "operator": {
                      "oneOf": [
                        {
                          "const": null
                        },
                        {
                          "type": "string",
                          "enum": [
                            "analytic",
                            "append",
                            "apply_graph_delta",
                            "asof_join",
                            "assert_rows",
                            "calendar_bucket",
                            "calendar_series",
                            "components",
                            "cross_join",
                            "dedupe_events",
                            "dedupe_rows",
                            "degree",
                            "derive",
                            "distinct",
                            "drop",
                            "edge_rows",
                            "events",
                            "except",
                            "filter",
                            "graft_graph",
                            "graph",
                            "graph_bounds",
                            "graph_diff",
                            "graphs_equal",
                            "group",
                            "infer",
                            "intersect",
                            "interval_join",
                            "join",
                            "json_pick",
                            "lag",
                            "match_edges",
                            "match_nodes",
                            "mean_graphs",
                            "merge_rankings",
                            "nearest",
                            "nest",
                            "node_rows",
                            "normalize_graph",
                            "normalize_vectors",
                            "pivot",
                            "pool_vectors",
                            "reach",
                            "rename",
                            "row_window",
                            "score_vectors",
                            "select",
                            "sequence",
                            "session",
                            "shortest_path",
                            "sort",
                            "subgraph",
                            "subtract_graphs",
                            "take",
                            "text_rank",
                            "time_series",
                            "to_events",
                            "to_vectors",
                            "top_k",
                            "top_k_by",
                            "traverse",
                            "union_graphs",
                            "unnest",
                            "unpivot",
                            "values",
                            "vectors",
                            "watermark_events",
                            "watermark_rows",
                            "window_events",
                            "window_group"
                          ]
                        }
                      ]
                    },
                    "ports": {
                      "type": "array",
                      "minItems": 1,
                      "items": {
                        "type": "object",
                        "required": [
                          "port_id",
                          "role",
                          "port_ordinal",
                          "carrier",
                          "carrier_contract_cid",
                          "source",
                          "can_sample",
                          "sample_reason"
                        ],
                        "additionalProperties": false,
                        "properties": {
                          "port_id": {
                            "type": "string",
                            "pattern": "^sha256:[0-9a-f]{64}$"
                          },
                          "role": {
                            "type": "string",
                            "enum": [
                              "input",
                              "output"
                            ]
                          },
                          "port_ordinal": {
                            "type": "integer",
                            "minimum": 0,
                            "maximum": 2147483647
                          },
                          "carrier": {
                            "type": "string",
                            "enum": [
                              "relation",
                              "graph",
                              "vectors",
                              "events"
                            ]
                          },
                          "carrier_contract_cid": {
                            "type": "string",
                            "pattern": "^sha256:[0-9a-f]{64}$"
                          },
                          "source": {
                            "oneOf": [
                              {
                                "type": "object",
                                "required": [
                                  "kind",
                                  "stage_ordinal",
                                  "input_port_ordinal"
                                ],
                                "additionalProperties": false,
                                "properties": {
                                  "kind": {
                                    "const": "stage_input"
                                  },
                                  "stage_ordinal": {
                                    "type": "integer",
                                    "minimum": 0,
                                    "maximum": 2147483647
                                  },
                                  "input_port_ordinal": {
                                    "type": "integer",
                                    "minimum": 0,
                                    "maximum": 2147483647
                                  }
                                }
                              },
                              {
                                "type": "object",
                                "required": [
                                  "kind",
                                  "step_id",
                                  "output_port_id"
                                ],
                                "additionalProperties": false,
                                "properties": {
                                  "kind": {
                                    "const": "logical_output"
                                  },
                                  "step_id": {
                                    "type": "string",
                                    "pattern": "^sha256:[0-9a-f]{64}$"
                                  },
                                  "output_port_id": {
                                    "type": "string",
                                    "pattern": "^sha256:[0-9a-f]{64}$"
                                  }
                                }
                              }
                            ]
                          },
                          "can_sample": {
                            "type": "boolean"
                          },
                          "sample_reason": {
                            "oneOf": [
                              {
                                "const": null
                              },
                              {
                                "type": "string",
                                "minLength": 1
                              }
                            ]
                          }
                        }
                      }
                    },
                    "can_stop_before": {
                      "type": "boolean"
                    },
                    "can_stop_after": {
                      "type": "boolean"
                    },
                    "stop_reason": {
                      "oneOf": [
                        {
                          "const": null
                        },
                        {
                          "type": "string",
                          "minLength": 1
                        }
                      ]
                    }
                  }
                }
              },
              "self_cid": {
                "type": "string",
                "pattern": "^sha256:[0-9a-f]{64}$"
              }
            }
          },
          "observation": {
            "const": "static"
          },
          "provider_io": {
            "const": 0
          },
          "quantities": {
            "type": "array",
            "minItems": 0,
            "items": {
              "oneOf": [
                {
                  "type": "object",
                  "required": [
                    "kind",
                    "value",
                    "unit",
                    "scope_cid",
                    "basis_cid"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "kind": {
                      "type": "string",
                      "enum": [
                        "exact",
                        "bound",
                        "estimate"
                      ]
                    },
                    "value": {
                      "type": "string",
                      "pattern": "^(0|[1-9][0-9]*)$(?![\\s\\S])"
                    },
                    "unit": {
                      "type": "string",
                      "minLength": 1
                    },
                    "scope_cid": {
                      "type": "string",
                      "pattern": "^sha256:[0-9a-f]{64}$"
                    },
                    "basis_cid": {
                      "type": "string",
                      "pattern": "^sha256:[0-9a-f]{64}$"
                    }
                  }
                },
                {
                  "type": "object",
                  "required": [
                    "kind",
                    "unit",
                    "reason"
                  ],
                  "additionalProperties": false,
                  "properties": {
                    "kind": {
                      "const": "unknown"
                    },
                    "unit": {
                      "type": "string",
                      "minLength": 1
                    },
                    "reason": {
                      "type": "string",
                      "minLength": 1
                    }
                  }
                }
              ]
            }
          },
          "capabilities": {
            "type": "object",
            "required": [
              "static_plan",
              "inspect",
              "durable_control",
              "sample_capture",
              "full_intermediate_retention",
              "cost_guard",
              "execution_batch",
              "policy_revision_cid"
            ],
            "additionalProperties": false,
            "properties": {
              "static_plan": {
                "type": "boolean"
              },
              "inspect": {
                "type": "boolean"
              },
              "durable_control": {
                "type": "boolean"
              },
              "sample_capture": {
                "type": "array",
                "uniqueItems": true,
                "minItems": 0,
                "items": {
                  "type": "string",
                  "enum": [
                    "relation",
                    "graph",
                    "vectors",
                    "events"
                  ]
                }
              },
              "full_intermediate_retention": {
                "type": "array",
                "uniqueItems": true,
                "minItems": 0,
                "items": {
                  "type": "string",
                  "enum": [
                    "relation",
                    "graph",
                    "vectors",
                    "events"
                  ]
                }
              },
              "cost_guard": {
                "type": "boolean"
              },
              "execution_batch": {
                "type": "boolean"
              },
              "policy_revision_cid": {
                "type": "string",
                "pattern": "^sha256:[0-9a-f]{64}$"
              }
            }
          }
        }
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
  "submit-intent": [
    "connection",
    "submissionRef",
    "intentCid",
    "kind",
    "input",
    "parameters",
    "attemptRef"
  ],
  "submit-named-intent": [
    "connection",
    "requestName",
    "submissionRef",
    "intentCid",
    "kind",
    "input",
    "parameters",
    "attemptRef"
  ],
  "restart-intent": [
    "connection",
    "submissionRef",
    "intentCid",
    "kind",
    "input",
    "parameters",
    "unresolvedHistory",
    "attemptRef"
  ],
  "lookup-submission": [
    "connection",
    "submissionRef"
  ],
  "check": [
    "connection",
    "kind",
    "input",
    "scope",
    "parameters"
  ],
  "plan": [
    "connection",
    "kind",
    "input",
    "parameters",
    "maxWireBytes",
    "maxNodes",
    "maxDepth"
  ],
  "inspect-run": [
    "connection",
    "ref",
    "maxWireBytes",
    "maxNodes",
    "maxDepth"
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
    "until",
    "since"
  ],
  "cancel": [
    "connection",
    "ref",
    "cancelId",
    "expectedRevision",
    "attemptRef"
  ],
  "lookup-cancellation": [
    "connection",
    "ref",
    "cancelId",
    "expectedRevision"
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
  "result-describe": [
    "connection",
    "ref",
    "resultName",
    "format",
    "attemptId",
    "maxWireBytes",
    "maxNodes",
    "maxDepth"
  ],
  "delivery-attempt": [
    "connection",
    "ref",
    "resultName",
    "attemptId"
  ],
  "checkpoints": [
    "connection",
    "after",
    "limit"
  ],
  "checkpoint-review": [
    "connection",
    "checkpointCid",
    "maxBytes"
  ],
  "resolve": [
    "connection",
    "items"
  ],
  "cancel-request": [
    "connection",
    "requestId"
  ],
  "resources": [
    "connection",
    "resourceConnection",
    "query",
    "limit"
  ],
  "resource-inspect": [
    "connection",
    "resourceConnection",
    "resource",
    "maxBytes"
  ],
  "resource-peek": [
    "connection",
    "resourceConnection",
    "resource",
    "fields",
    "maxRows",
    "maxBytes"
  ],
  "owner-observations": [
    "connection",
    "ref",
    "cursors",
    "maxEntries",
    "maxWireBytes"
  ],
  "run-plan": [
    "connection",
    "ref",
    "maxWireBytes",
    "maxNodes",
    "maxDepth"
  ]
};

const optionalRequestFields = {
  "checkpoints": {
    "checkpointId": {
      "type": "string",
      "pattern": "^[^\\u0000-\\u001f\\u007f]+(?![\\s\\S])",
      "minLength": 1,
      "maxLength": 256
    }
  },
  "submit": {
    "stopBefore": {
      "const": "commit"
    },
    "readOnly": {
      "const": true
    }
  },
  "submit-intent": {
    "stopBefore": {
      "const": "commit"
    },
    "readOnly": {
      "const": true
    }
  },
  "submit-named-intent": {
    "stopBefore": {
      "const": "commit"
    },
    "readOnly": {
      "const": true
    }
  },
  "restart-intent": {
    "stopBefore": {
      "const": "commit"
    },
    "readOnly": {
      "const": true
    }
  }
};

export const checkReasonSchemaCid = "sha256:93e2d1285a3136da858996545d957273d70acad3cf180c07d59aa61cfa126ca5";
export const checkOutcomeSchemaCid = "sha256:abc1f9da9c6394f61d780139fe10ce220a25f6579ef80ed043a46c5704cf5f3b";
export const checkOutcomeProtocol = Object.freeze({version: "actql-check-outcome/0.1", reasonSchemaCid: checkReasonSchemaCid, outcomeSchemaCid: checkOutcomeSchemaCid, outcomes: Object.freeze(["completed","failed","unavailable"])});
export const runStateProtocol = Object.freeze({version: "actql-run-state/0.1", statuses: Object.freeze(["preparing","running","waiting_checkpoint","resuming","needs_reconciliation","succeeded","failed","cancelled"])});
function finiteWireNumber(value) {
  return Number.isFinite(value) && !Object.is(value, -0);
}

function valid(value, schema) {
  if (typeof value === 'number' && !finiteWireNumber(value)) return false;
  if (typeof value === 'string' && !value.isWellFormed()) return false;
  if (schema.$ref) return valid(value, schemas[schema.$ref]);
  if (schema.oneOf && schema.oneOf.filter(rule => valid(value, rule)).length !== 1) return false;
  if (schema.not && valid(value, schema.not)) return false;
  if (schema.if && valid(value, schema.if) && !valid(value, schema.then)) return false;
  if (schema.allOf && !schema.allOf.every(rule => valid(value, rule))) return false;
  if (Object.hasOwn(schema, 'const') && value !== schema.const) return false;
  if (schema.enum && !schema.enum.includes(value)) return false;
  if (typeof value === 'number' &&
      (schema.minimum !== undefined && value < schema.minimum ||
       schema.maximum !== undefined && value > schema.maximum)) return false;
  if (typeof value === 'string' &&
      ((schema.minLength !== undefined && [...value].length < schema.minLength) ||
        (schema.maxLength !== undefined && value.length > schema.maxLength) ||
        (schema.pattern !== undefined && !new RegExp(schema.pattern, 'u').test(value))))
    return false;
  if (schema.type === 'string') return typeof value === 'string';
  if (schema.type === 'number') return typeof value === 'number';
  if (schema.type === 'integer') return Number.isSafeInteger(value) &&
    (schema.minimum === undefined || value >= schema.minimum) &&
    (schema.maximum === undefined || value <= schema.maximum);
  if (schema.type === 'boolean') return typeof value === 'boolean';
  if (schema.type === 'array') return Array.isArray(value) &&
    (schema.minItems === undefined || value.length >= schema.minItems) &&
    (schema.maxItems === undefined || value.length <= schema.maxItems) &&
    value.every(item => valid(item, schema.items)) &&
    (!schema.uniqueItems || new Set(value).size === value.length);
  if (value !== null && typeof value === 'object' && !Array.isArray(value) &&
      ((schema.minProperties !== undefined && Object.keys(value).length < schema.minProperties) ||
       (schema.maxProperties !== undefined && Object.keys(value).length > schema.maxProperties))) return false;
  if (schema.type === 'object' || schema.properties || schema.required) {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
    if (schema.required?.some(key => !Object.hasOwn(value, key))) return false;
    if (schema.propertyNames && Object.keys(value).some(key =>
        !valid(key, schema.propertyNames))) return false;
    if (schema.additionalProperties === false &&
        Object.keys(value).some(key => !Object.hasOwn(schema.properties, key))) return false;
    if (schema.additionalProperties &&
        typeof schema.additionalProperties === 'object' &&
        Object.entries(value).some(([key, item]) =>
          !Object.hasOwn(schema.properties ?? {}, key) &&
          !valid(item, schema.additionalProperties))) return false;
    return Object.entries(schema.properties ?? {}).every(([key, field]) =>
      !Object.hasOwn(value, key) || valid(value[key], field));
  }
  return true;
}

export const clientHostOperations = Object.freeze(Object.keys(operationKeys));
export const clientHostRequestKeys = (operation, body = {}) => (Object.hasOwn(operationKeys, operation) ? [...operationKeys[operation], ...Object.keys(optionalRequestFields[operation] ?? {}).filter(key => body !== null && typeof body === 'object' && Object.hasOwn(body, key))] : undefined);
export const validClientRequestOptionalFields = (operation, body) => Object.entries(optionalRequestFields[operation] ?? {}).every(([key, schema]) => !Object.hasOwn(body, key) || valid(body[key], schema));
export const validSubmissionEpochShape = value => valid(value, schemas.submission_epoch);
export const validSubmissionRefShape = value => valid(value, schemas.submission_ref);
export const validSubmissionOutcomeShape = value => valid(value, schemas.submission_outcome);
export const validSubmissionLookupShape = value => valid(value, schemas.submission_lookup);
export const validSubmissionRestartShape = value => valid(value, schemas.submission_restart);
export const validSubmissionAttemptShape = value => valid(value, schemas.submission_attempt);
export const validSubmissionNameShape = value => valid(value, schemas.submission_name);
export const validNamedSubmissionAttemptShape = value => valid(value, schemas.named_submission_attempt);
export const validRunRefShape = value => valid(value, schemas.run_ref);
export const validConnectionShape = value => valid(value, schemas.connection);
export const validProfileShape = value => valid(value, schemas.profile);
export const validAdmissionShape = value => valid(value, schemas.admission);
export const validLookupFoundShape = value => valid(value, schemas.lookup_found);
export const validLookupNotFoundShape = value => valid(value, schemas.lookup_not_found);
export const validLookupUnknownShape = value => valid(value, schemas.lookup_unknown);
export const validHeldShape = value => valid(value, schemas.held);
export const validCheckpointSummaryShape = value => valid(value, schemas.checkpoint_summary);
export const validCheckpointReviewShape = value => valid(value, schemas.checkpoint_review);
export const validResolveItemShape = value => valid(value, schemas.resolve_item);
export const validResolveResultShape = value => valid(value, schemas.resolve_result);
export const validSubmitPreparationErrorShape = value => valid(value, schemas.submit_preparation_error);
export const validCancellationShape = value => valid(value, schemas.cancellation);
export const validCancellationRefShape = value => valid(value, schemas.cancellation_ref);
export const validCancellationLookupShape = value => valid(value, schemas.cancellation_lookup);
export const validOperationAttemptRefShape = value => valid(value, schemas.operation_attempt_ref);
export const validCancellationAttemptShape = value => valid(value, schemas.cancellation_attempt);
export const validRequestCancellationShape = value => valid(value, schemas.request_cancellation);
export const validResourceListingShape = value => valid(value, schemas.resource_listing);
export const validResourceInspectionShape = value => valid(value, schemas.resource_inspection);
export const validResourcePeekShape = value => valid(value, schemas.resource_peek);
export const validResultDescriptionShape = value => valid(value, schemas.result_description);
export const validOwnerRefShape = value => valid(value, schemas.owner_ref);
export const validOwnerCursorShape = value => valid(value, schemas.owner_cursor);
export const validOwnerObservationsShape = value => valid(value, schemas.owner_observations);
export const validRunStateShape = value => valid(value, schemas.run_state);
export const validCheckOutcomeShape = value => valid(value, schemas.check_outcome) && value.outcome_schema_cid === checkOutcomeSchemaCid;
export const validProfileContract = (value, selected) =>
  validConnectionShape(selected) && validProfileShape(value) &&
  value.mode === selected.mode &&
  value.owner === selected.owner &&
  value.workspaceId === selected.workspaceId &&
  !(selected.durability === "durable" && value.durability !== "durable");
export const validAdmissionContract = (value, selected) =>
  validConnectionShape(selected) && validAdmissionShape(value) &&
  !(selected.durability === "durable" && value.durability !== "durable");
export const validRunWaitContract = (value, since) =>
  valid(value, schemas.run_state) &&
  (since === null || valid(since, schemas.run_state.properties.revision)) &&
  ["waiting_checkpoint","needs_reconciliation","succeeded","failed","cancelled"].includes(value.status) &&
  (since === null || value.revision > since);
export const validHeldContract = (value, expected) =>
  valid(expected, schemas.held.properties.requestId) &&
  ((valid(value, schemas.held) && value.requestId === expected));
export const validRequestLookupContract = (value, expected) =>
  valid(expected, schemas.lookup_found.properties.requestId) &&
  ((valid(value, schemas.lookup_found) && value.requestId === expected) ||
   valid(value, schemas.lookup_not_found) ||
   valid(value, schemas.lookup_unknown) ||
   (valid(value, schemas.held) && value.requestId === expected));
export const validCheckOutcomeContract = value => {
  if (!validCheckOutcomeShape(value)) return false;
  const report = value.report ?? value.partial_report;
  if (!report) return true;
  const documents = new Map(report.inputs.map(input => [input.document_id, input]));
  const occurrences = [...report.reasons, ...report.requirements, ...report.coverage.limits];
  if (documents.size !== report.inputs.length) return false;
  const program = documents.get('program');
    if (program ? program.kind !== 'structured' || documents.has('source') ||
        documents.has('parameter_declarations') : documents.get('source')?.kind !== 'text') return false;
    if (report.inputs.some(input => input.document_id !== 'source' && input.kind !== 'structured')) return false;
  for (const reason of occurrences) {
      const location = reason.location;
      if (!location) continue;
      const input = documents.get(location.document_id);
      if (!input || input.revision !== location.revision || input.kind !== location.kind) return false;
      if (location.kind === 'text' && (location.start_byte > location.end_byte ||
          location.end_byte > input.byte_length)) return false;
    }
  for (const reason of occurrences) for (const fix of reason.fixes ?? []) {
      const input = documents.get(fix.target.document_id);
      if (!input || input.kind !== 'text' || input.revision !== fix.target.revision) return false;
      if (fix.edits.some(edit => edit.start_byte !== input.byte_length ||
          edit.end_byte !== input.byte_length)) return false;
    }
  return true;
};

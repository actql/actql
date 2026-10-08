"""Physical Iceberg presence encoding, not an execution or approval owner.

The caller supplies the mapping admitted by the common contract. Validate it
again at I/O and inspect physical Parquet fields before Iceberg can synthesize
defaults. No data string is normalized, and omitted values remain omitted.
"""
import hashlib
import json
import math
import unicodedata
from importlib.metadata import version

import pyarrow as pa
from pyiceberg.schema import Schema
from pyiceberg.types import BooleanType, DoubleType, NestedField, StringType


class PhysicalRefusal(ValueError):
    pass


def canonical_envelope(value):
    """The provider envelope subset: exact text, integers, booleans, null.

    Floating point/data values do not use this helper. Common Core owns their
    canonical content identity. Keys use canonical UTF-16 ordering.
    """
    if isinstance(value, dict):
        return "{" + ",".join(
            json.dumps(k, ensure_ascii=False) + ":" + canonical_envelope(value[k])
            for k in sorted(value, key=lambda k: k.encode("utf-16-be"))
        ) + "}"
    if isinstance(value, list):
        return "[" + ",".join(canonical_envelope(v) for v in value) + "]"
    if value is None or type(value) in (str, int, bool):
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    raise PhysicalRefusal("UnsupportedEnvelopeValue")


def envelope_cid(value):
    return "sha256:" + hashlib.sha256(canonical_envelope(value).encode("utf-8")).hexdigest()


def seal(value, field):
    return {**value, field: envelope_cid(value)}


def check_mapping(mapping):
    if version("pyiceberg") != "0.10.0" or version("pyarrow") != "21.0.0":
        raise PhysicalRefusal("UnsupportedHostDependencyVersion")
    if set(mapping) != {"version", "schema_cid", "iceberg_format_version", "columns", "mapping_cid"}:
        raise PhysicalRefusal("StorageMappingShape")
    body = {k: v for k, v in mapping.items() if k != "mapping_cid"}
    if mapping["version"] != "actql-table-storage-mapping/0.1" or mapping["iceberg_format_version"] != 2:
        raise PhysicalRefusal("StorageMappingVersion")
    if envelope_cid(body) != mapping["mapping_cid"]:
        raise PhysicalRefusal("StorageMappingIdentity")
    schema_cid = mapping["schema_cid"]
    if not isinstance(schema_cid, str) or len(schema_cid) != 71 or not schema_cid.startswith("sha256:"):
        raise PhysicalRefusal("SchemaIdentity")
    try:
        int(schema_cid[7:], 16)
    except ValueError as e:
        raise PhysicalRefusal("SchemaIdentity") from e
    columns = mapping["columns"]
    if not isinstance(columns, list) or not 1 <= len(columns) <= 1024:
        raise PhysicalRefusal("UnsupportedColumnCount")
    names, ids = set(), set()
    for column in columns:
        if set(column) != {"name", "value_field_id", "presence_field_id", "physical_type", "nullable", "presence"}:
            raise PhysicalRefusal("StorageColumnShape")
        name = column["name"]
        if not isinstance(name, str) or not 1 <= len(name) <= 256:
            raise PhysicalRefusal("StorageColumnName")
        try:
            name.encode("utf-8")
        except UnicodeError as e:
            raise PhysicalRefusal("StorageColumnName") from e
        if unicodedata.normalize("NFC", name) != name or any(c in name for c in "\0\r\n"):
            raise PhysicalRefusal("StorageColumnName")
        # This namespace is reserved only by this provider's physical mapping.
        if name.lower().startswith("__actql_presence_") or name.lower() in names:
            raise PhysicalRefusal("StorageColumnCollision")
        names.add(name.lower())
        if column["physical_type"] not in ("boolean", "double", "string"):
            raise PhysicalRefusal("UnsupportedPhysicalType")
        if type(column["nullable"]) is not bool or column["presence"] not in ("required", "conditional"):
            raise PhysicalRefusal("StorageColumnContract")
        value_id, presence_id = column["value_field_id"], column["presence_field_id"]
        if column["presence"] == "required" and presence_id is not None:
            raise PhysicalRefusal("UnexpectedPresenceField")
        if column["presence"] == "conditional" and presence_id is None:
            raise PhysicalRefusal("MissingPresenceField")
        for field_id in [value_id] + ([presence_id] if presence_id is not None else []):
            if type(field_id) is not int or not 1 <= field_id <= 2147483647 or field_id in ids:
                raise PhysicalRefusal("StorageFieldId")
            ids.add(field_id)
    # The pinned new-table constructor assigns fresh IDs in physical field
    # order. Refuse a mapping it would silently renumber before any write.
    ordered_ids = [i for c in columns for i in
                   [c["value_field_id"]] + ([c["presence_field_id"]]
                   if c["presence_field_id"] is not None else [])]
    if ordered_ids != list(range(1, len(ordered_ids) + 1)):
        raise PhysicalRefusal("UnsupportedFieldIdLayout")
    return mapping


def physical_fields(mapping):
    check_mapping(mapping)
    fields = []
    arrow_types = {"boolean": pa.bool_(), "double": pa.float64(), "string": pa.string()}
    iceberg_types = {"boolean": BooleanType(), "double": DoubleType(), "string": StringType()}
    for column in mapping["columns"]:
        # Conditional missing values use physical NULL even for logically
        # nonnullable columns. Logical validation is independent below.
        required = column["presence"] == "required" and not column["nullable"]
        fields.append((column["name"], column["value_field_id"],
                       arrow_types[column["physical_type"]], iceberg_types[column["physical_type"]], required))
        if column["presence_field_id"] is not None:
            fields.append((f'__actql_presence_{column["presence_field_id"]}',
                           column["presence_field_id"], pa.bool_(), BooleanType(), True))
    return fields


def arrow_schema(mapping):
    return pa.schema([pa.field(name, typ, nullable=not required,
                              metadata={b"PARQUET:field_id": str(field_id).encode("ascii")})
                      for name, field_id, typ, _, required in physical_fields(mapping)])


def iceberg_schema(mapping):
    return Schema(*[NestedField(field_id=field_id, name=name, field_type=typ, required=required)
                    for name, field_id, _, typ, required in physical_fields(mapping)])


def validate_value(column, value):
    if value is None:
        if not column["nullable"]:
            raise PhysicalRefusal("NonnullableValue")
        return
    typ = column["physical_type"]
    if typ == "boolean" and type(value) is bool:
        return
    if typ == "double" and type(value) in (int, float):
        try:
            finite = math.isfinite(value)
        except OverflowError as e:
            raise PhysicalRefusal("InexactNumber") from e
        if not finite:
            raise PhysicalRefusal("ValueType")
        # Require a value exactly representable by the declared binary64
        # contract. In particular do not silently round arbitrary Python ints.
        if type(value) is int and int(float(value)) != value:
            raise PhysicalRefusal("InexactNumber")
        return
    if typ == "string" and isinstance(value, str):
        try:
            value.encode("utf-8")
        except UnicodeError as e:
            raise PhysicalRefusal("InvalidString") from e
        return
    raise PhysicalRefusal("ValueType")


def encode_rows(mapping, rows):
    schema = arrow_schema(mapping)
    names = {c["name"] for c in mapping["columns"]}
    encoded = []
    for row in rows:
        if not isinstance(row, dict) or not set(row) <= names:
            raise PhysicalRefusal("RowShape")
        result = {}
        for column in mapping["columns"]:
            name = column["name"]
            present = name in row
            if not present and column["presence"] == "required":
                raise PhysicalRefusal("RequiredColumnMissing")
            if present:
                validate_value(column, row[name])
            result[name] = row[name] if present else None
            if column["presence_field_id"] is not None:
                result[f'__actql_presence_{column["presence_field_id"]}'] = present
        encoded.append(result)
    return pa.Table.from_pylist(encoded, schema=schema)


def decode_physical(mapping, table):
    """Read an actual file, never a default-filled Iceberg projection."""
    expected = {field_id: (name, typ) for name, field_id, typ, _, _ in physical_fields(mapping)}
    actual = {}
    for field in table.schema:
        raw = (field.metadata or {}).get(b"PARQUET:field_id")
        try:
            field_id = int(raw) if raw is not None else None
        except ValueError as e:
            raise PhysicalRefusal("PhysicalFieldId") from e
        if field_id in actual or field_id not in expected:
            raise PhysicalRefusal("PhysicalFieldId")
        name, typ = expected[field_id]
        if field.name != name or field.type != typ:
            raise PhysicalRefusal("PhysicalFieldType")
        actual[field_id] = field.name
    if set(actual) != set(expected):
        raise PhysicalRefusal("PhysicalFieldMissing")
    output = []
    for physical in table.to_pylist():
        row = {}
        for column in mapping["columns"]:
            value = physical[actual[column["value_field_id"]]]
            companion = column["presence_field_id"]
            present = True if companion is None else physical[actual[companion]]
            if type(present) is not bool:
                raise PhysicalRefusal("PhysicalPresenceInvalid")
            if not present:
                if value is not None:
                    raise PhysicalRefusal("AbsentWithValue")
                continue
            validate_value(column, value)
            row[column["name"]] = value
        output.append(row)
    return output

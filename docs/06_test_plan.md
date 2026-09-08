# 06 – Test plan

## 1. ABAP Unit (shipped, `RISK LEVEL HARMLESS`, no BP/HCM data)

Run via ADT *Run As → ABAP Unit Test* on the package or per class.

### `ZCL_BP_CUST_MAPPER` (`ltcl_mapper`)
| Test | Asserts |
|---|---|
| `street_and_city_from_one_comma` | `"1 Marina Road, Lagos"` → street / city / country |
| `single_token_becomes_street` | no comma → whole string is street, city empty |
| `multi_comma_last_is_city` | last comma segment wins as city |
| `country_default_applied` | country falls back to `c_default-country` |
| `empty_text_is_safe` | empty input → empty result, no dump |

### `ZCL_BP_CUST_CREATE` (`ltcl_create`, local friend)
| Test | Asserts |
|---|---|
| `control_defaults_are_applied` | blank `partnerRole` → default `FLCU01`; blank category → `2` |
| `control_explicit_values_win` | request `bpGrouping` / `custAcctGrp` preserved |
| `build_sets_insert_task` | `partner-header-object_task = 'I'` |
| `build_maps_org_name_split` | `bp_organization-name1 = 'Acme Ltd'` |
| `build_stores_ids_in_search_terms` | `bp_centraldata-searchterm1 = customerId` |
| `build_adds_customer_role` | one role row, `data_key = FLCU01` |
| `build_adds_customer_node` | `customer-header-object_task = 'I'`, `kna1-ktokd` filled |
| `validate_requires_business_name` | raises `ZCX_BP_CUST` msg 003 |
| `validate_requires_grouping` | raises `ZCX_BP_CUST` msg 012 |

### `ZCL_BP_CUST_ICF_HANDLER` (`ltcl_handler`)
| Test | Asserts |
|---|---|
| `post_routes_to_create` / `get_routes_to_read` / `put_is_not_supported` | routing |
| `lowercase_method_ok` | method upper-cased before routing |
| `json_request_roundtrip` | camelCase JSON → `ZBP_CUST_S_CREATE_REQ` (nested struct + string array) |
| `json_response_camelcase` | response serialised as `customerId` / `partner` |

## 2. Integration test (manual, needs Customizing + a test client)

| # | Step | Expected |
|---|---|---|
| I1 | `POST` sample `create_request.json` | 201, `success=true`, `partner` assigned, `logId` returned |
| I2 | `BP` transaction on `partner` | org name, Search Term 1 = `CUST-000123`, role `FLCU01`, address, tax no, identification, industries |
| I3 | `GET ?customerId=CUST-000123` | 200, `orgName1`, address, `taxNumbers`, `salesAreas`, `companyCodes` |
| I4 | `GET /sap/bc/zbp_customer/CUST-000123` (path form) | same as I3 |
| I5 | `POST` same body again | 200, `W` "already exists", **no** second BP |
| I6 | `GET ?customerId=NOPE` | 404 |
| I7 | `POST` with `custAcctGrp = "ZZZZ"` (invalid) | 422, `ZBP_CUST_LOG` row status `E`, `REQUEST_JSON` populated |
| I8 | `ZBP_CUST_LOG_REPORT`, `P_LOGID` = I7 row, fix Customizing, execute | status `R`, `retry_count = 1`, BP now created |
| I9 | `ZBP_CUST_LOG_REPORT`, date = today, `P_REPRO` = X | summary message “n reprocessed: x ok, y failing” |
| I10 | double-click any row in the report | message popup from `ZBP_CUST_LOG_MSG` |

## 3. Negative / robustness

| # | Input | Expected |
|---|---|---|
| N1 | empty body | 400 |
| N2 | `{ not json` | 400 |
| N3 | missing `businessName` | 422 msg 003 |
| N4 | missing `bpGrouping` and no default | 422 msg 012 |
| N5 | `customerId` > 20 chars | JSON truncates to field length; document to client |
| N6 | `PUT /sap/bc/zbp_customer` | 405 |
| N7 | very large `documents[]` array | accepted, stored in log, response echoes count |

## 4. Performance / volume

* Single BP create: dominated by `CL_MD_BP_MAINTAIN` + commit (~ standard BP
  create cost). No extra round-trips.
* `ZBP_CUST_LOG` grows one row per call + n message rows — size an archiving job
  for the expected daily volume.

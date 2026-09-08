# 01 – Solution architecture

## 1. Scope

| # | Requirement | Delivered by |
|---|---|---|
| 1 | Create the customer BP from the client's existing data | `POST /sap/bc/zcust_bp` → `ZCL_CUST_BP_CREATE` → `CL_MD_BP_MAINTAIN=>MAINTAIN` |
| 2 | Read customer data; caller passes only the customer ID | `GET /sap/bc/zcust_bp?customerId=…` → `ZCL_CUST_BP_READ` → `CMD_EI_API=>GET_DATA` |
| 3 | Log failures with date/time; allow manual re-trigger / re-call | `ZT_CUST_BP_LOG` + `ZCUST_BP_LOG_REPORT` + `ZCL_CUST_BP_LOG=>reprocess` |
| 4 | Mandatory custom DDIC payload structure | `ZCUST_BP_S_CREATE_REQ` / `ZCUST_BP_S_READ_RES` and the sub-structures |

Out of scope for this delivery: outbound push to the client system, document
(DMS/GOS) storage of the `documents[]` entries, and delta/update of an existing
BP. Hooks are in place (`documents[]` echoed to the response and log;
`ZCL_CUST_BP_LOG` already generic over direction `I`/`O`).

## 2. Component flow

### Create (inbound)

```
client ──POST JSON──▶ ICF /sap/bc/zcust_bp
                        │
                 ZCL_CUST_BP_ICF_HANDLER
                   • determine_action(POST) → CREATE
                   • /ui2/cl_json → ZCUST_BP_S_CREATE_REQ
                        │
                 ZCL_CUST_BP_CREATE=>execute
                   • check_authorization (B_BUPA_RLT, ACTVT 01)
                   • validate (mandatory fields, control keys)
                   • idempotency: BU_SORT1 = customerId already? → return existing
                   • resolve_control (defaults)
                   • build_cvi  → CVIS_EI_EXTERN_T           (pure, unit-tested)
                   • SIMULATE: CL_MD_BP_MAINTAIN=>VALIDATE_SINGLE (no DB update)
                       error? → log 'E', HTTP 422, RETURN   (nothing created)
                   • CL_MD_BP_MAINTAIN=>MAINTAIN
                   • error?  → BAPI_TRANSACTION_ROLLBACK, log 'E', HTTP 422
                   • ok?     → BAPI_TRANSACTION_COMMIT, resolve keys, log 'S', HTTP 201
                        │
                 ZCL_CUST_BP_LOG=>record   (own LUW, survives rollback)
                        │
   client ◀──JSON────  ZCUST_BP_S_CREATE_RES { partner, customer, success, messages, logId }
```

### Read (inbound)

```
client ──GET ?customerId──▶ ICF /sap/bc/zcust_bp
                 ZCL_CUST_BP_ICF_HANDLER  → determine_action(GET) → READ
                 ZCL_CUST_BP_READ=>execute
                   • BUT000-BU_SORT1 = customerId  → PARTNER            (else 404)
                   • BUT000 → PARTNER_GUID → CVI_CUST_LINK → KUNNR      (else 404)
                   • CMD_EI_API=>GET_DATA( is_master_data{ kunnr } )
                   • ZCL_CUST_BP_MAPPER=>cvi_to_read_res
                        - sales areas / company codes from the CVI image
                        - name / address / tax / created-by from KNA1+ADRC (stable)
                        - roles / ids / industries / banks from BUT100/BUT0ID/BUT0IS/BUT0BK
   client ◀──JSON──  ZCUST_BP_S_READ_RES
```

## 3. Why these building blocks

* **Plain `IF_HTTP_EXTENSION`** – works identically on every S/4 stack, no
  dependency on the REST library being configured, trivial to unit-test the
  routing.
* **`CL_MD_BP_MAINTAIN=>MAINTAIN`** – single call creates the BP *and*, through
  CVI, the customer master for the `FLCU01` role. Same `CVIS_EI_EXTERN`
  structure the MDG / BP transaction uses.
* **Internal BP number + Search Term 1** – keeps standard number ranges; the
  client ID (`CUST-000123`, 11 chars) does not fit `BU_PARTNER` (10) so it is
  **not** used as the BP number. Search Term 1 is exactly what the reference
  screenshot (`P1234`, Search Term 1/2 = `TEST` / `CUST`) already does.
* **`CMD_EI_API=>GET_DATA`** – returns the full customer image (general + sales
  + company + tax) in one shot; supplemented with direct reads for the
  BP-central attributes it does not carry.
* **Own-LUW logging** – `ZCL_CUST_BP_LOG=>record` issues its own `COMMIT WORK`
  after the BP `COMMIT`/`ROLLBACK`, so a failed create is still logged with its
  full request payload for re-trigger.

## 4. Idempotency & re-trigger

* Re-`POST` of a `customerId` that already resolves to a BP returns HTTP 200
  with the existing keys and a `W` message (no duplicate BP).
* `ZT_CUST_BP_LOG` stores the verbatim request body. `ZCL_CUST_BP_LOG=>reprocess`
  re-runs it (`iv_write_log = abap_false`, updates the same row, `retry_count++`,
  status `R` on success).
* `ZCUST_BP_LOG_REPORT`: `P_LOGID` for one entry, `P_REPRO` for every `E` entry
  in the selection (batch-job friendly).

## 5. Error handling / HTTP status

| Situation | HTTP | Log status |
|---|---|---|
| BP created | 201 | S |
| BP already exists for customerId | 200 | S (warning message) |
| Empty / invalid JSON | 400 | – (rejected before processing) |
| Mandatory field / control key missing | 422 | E |
| `CL_MD_BP_MAINTAIN` returned `E`/`A` | 422 | E |
| Read: customerId unknown / no linked customer | 404 | E |
| Unexpected | 500 | E |

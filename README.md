# Dangote – Customer Business Partner ICF REST API

Inbound REST service on SAP S/4HANA (on-prem) to **create** and **read** a
customer Business Partner from the data the client already holds in its
onboarding / approval system.

| | |
|---|---|
| Transport | ICF service + `IF_HTTP_EXTENSION` handler (no `CL_REST_*` dependency) |
| Service node | `/sap/bc/zcust_bp` |
| Create | `POST /sap/bc/zcust_bp` → `CL_MD_BP_MAINTAIN=>MAINTAIN` (organisation BP + customer role, **internal** BP number) |
| Read | `GET /sap/bc/zcust_bp?customerId=CUST-000123` → `CMD_EI_API_EXTRACT=>GET_DATA` |
| External key | client `customerId` stored in **Search Term 1** (`BUT000-BU_SORT1`); `applicationId` in Search Term 2 |
| Payload | flat custom DDIC structures `ZCUST_BP_S_*`, mapped internally to `CVIS_EI_EXTERN` |
| Processing log | every call recorded in `ZT_CUST_BP_LOG` / `ZT_CUST_BP_LOG_MSG`; failures re-triggerable |
| Report | `ZCUST_BP_LOG_REPORT` – ALV of the log + reprocess (single / bulk) |
| Package | **ZABAP_UTIL** |
| abapGit | `FOLDER_LOGIC = PREFIX`, source under `/src/` |

## Repository layout

```
src/
  zif_cust_bp_types                 constants & contract, c_default adaptation block
  zcx_cust_bp                       exception (T100 + if_t100_dyn_msg, carries HTTP status)
  zmsg_cust_bp (msag)               message class 001-016
  zcust_bp_text / _id / _flag /
  zcust_bp_json / _seqnr (dtel)     5 data elements
  zcust_bp_t_* (ttyp)               9 table types
  zcust_bp_s_* (tabl / INTTAB)      13 flat payload / read structures
  zt_cust_bp_log, zt_cust_bp_log_msg  transparent log tables
  zcl_cust_bp_mapper                id resolution, address parsing, CVI->read mapping  (+ AUnit)
  zcl_cust_bp_create               payload -> CVIS_EI_EXTERN -> CL_MD_BP_MAINTAIN       (+ AUnit)
  zcl_cust_bp_read                 customerId -> CMD_EI_API_EXTRACT=>GET_DATA -> read
  zcl_cust_bp_log                  processing log + reprocess
  zcl_cust_bp_icf_handler          HTTP routing / JSON / status codes                  (+ AUnit)
  zcust_bp_log_report (prog)       ALV log viewer + reprocess
  package.devc.xml
docs/
  01_solution_architecture.md
  02_ddic_and_customizing.md
  03_deployment_sicf.md
  04_api_contract.md
  05_verification_checklist.md   <- release-dependent CVI node names to confirm in SE11
  06_test_plan.md
```

## Install (abapGit)

1. abapGit -> *New Online* -> this repo URL -> package **ZABAP_UTIL** -> *Pull*.
2. Activate everything (DDIC first: data elements -> table types -> structures ->
   tables; then classes / report). The `docs/` folder is ignored by abapGit.
3. Do the Customizing in [`docs/02_ddic_and_customizing.md`](docs/02_ddic_and_customizing.md) section 2.
4. Create + activate the ICF node per [`docs/03_deployment_sicf.md`](docs/03_deployment_sicf.md).
5. Run the unit tests: `ZCL_CUST_BP_MAPPER`, `ZCL_CUST_BP_CREATE`,
   `ZCL_CUST_BP_ICF_HANDLER` (all `RISK LEVEL HARMLESS`, no BP / HCM data touched).

## Before go-live - verify against your S/4 release

The deep component paths inside `CVIS_EI_EXTERN` / `CMDS_EI_MAIN` are release
dependent. Every such line is marked `VERIFY NODE` in the source, and
[`docs/05_verification_checklist.md`](docs/05_verification_checklist.md) lists
each one with the SE11 check to run.

## Engineering rulebook

Naming follows the Vernasoft ABAP & RAP Engineering Rulebook: `ZT_` tables,
`ZMSG_` message class, `ZCL_` / `ZIF_`, inline declarations / `VALUE` /
`CORRESPONDING`, no `TABLES` statement, `AUTHORITY-CHECK` before create, message
class for all errors. This is a freestyle ICF component (no RAP BO), so the
CDS / BDEF / service-binding layers of the rulebook do not apply.

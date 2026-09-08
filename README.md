# Dangote – Customer Business Partner ICF REST API

Inbound REST service on SAP S/4HANA (on-prem) to **create** and **read** a
customer Business Partner from the data the client already holds in its
onboarding/approval system.

| | |
|---|---|
| Transport | ICF service + `IF_HTTP_EXTENSION` handler (no `CL_REST_*` dependency) |
| Service node | `/sap/bc/zbp_customer` |
| Create | `POST /sap/bc/zbp_customer` → `CL_MD_BP_MAINTAIN=>MAINTAIN` (organisation BP + customer role, **internal** BP number) |
| Read | `GET /sap/bc/zbp_customer?customerId=CUST-000123` → `CMD_EI_API=>GET_DATA` |
| External key | client `customerId` stored in **Search Term 1** (`BUT000-BU_SORT1`); `applicationId` in Search Term 2 |
| Payload | custom DDIC structures `ZBP_CUST_S_*`, mapped internally to `CVIS_EI_EXTERN` |
| Processing log | every call recorded in `ZBP_CUST_LOG` / `ZBP_CUST_LOG_MSG`; failures re-triggerable |
| Report | `ZBP_CUST_LOG_REPORT` – ALV of the log + reprocess |
| Package | **ZSD** |
| abapGit | `FOLDER_LOGIC = PREFIX`, source under `/src/` |

## Repository layout

```
src/
  zif_bp_cust_types              constants & contract
  zcx_bp_cust                    exception (T100, carries HTTP status)
  zbp_cust_msg (msag)            message class 001–015
  zbp_cust_*  (dtel)             10 data elements (generic text + ids)
  zbp_cust_t_* (ttyp)            10 table types
  zbp_cust_s_* (tabl/INTTAB)     15 payload / read structures
  zbp_cust_log, zbp_cust_log_msg transparent log tables
  zcl_bp_cust_mapper             id resolution, address parsing, CVI→read mapping   (+ AUnit)
  zcl_bp_cust_create            payload → CVIS_EI_EXTERN → CL_MD_BP_MAINTAIN         (+ AUnit)
  zcl_bp_cust_read             customerId → CMD_EI_API=>GET_DATA → read response
  zcl_bp_cust_log              processing log + reprocess
  zcl_bp_cust_icf_handler      HTTP routing / JSON / status codes                   (+ AUnit)
  zbp_cust_log_report (prog)   ALV log viewer + reprocess
docs/
  01_solution_architecture.md
  02_ddic_and_customizing.md
  03_deployment_sicf.md
  04_api_contract.md
  05_verification_checklist.md   ← the release-dependent CVI node names to confirm
  06_test_plan.md
```

## Install (abapGit)

1. abapGit → *New Online* → this repo URL → package **ZSD** → *Pull*.
2. Activate everything (DDIC first, then classes/report). The `docs/` folder is
   ignored by abapGit.
3. Do the Customizing in [`docs/02_ddic_and_customizing.md`](docs/02_ddic_and_customizing.md).
4. Create + activate the ICF node per [`docs/03_deployment_sicf.md`](docs/03_deployment_sicf.md).
5. Run the unit tests: `ZCL_BP_CUST_MAPPER`, `ZCL_BP_CUST_CREATE`,
   `ZCL_BP_CUST_ICF_HANDLER` (all `RISK LEVEL HARMLESS`, no HCM/BP data touched).

## Before go-live — verify against your S/4 release

The deep component paths inside `CVIS_EI_EXTERN` / `CMDS_EI_MAIN` are release
dependent. Every such line is marked `VERIFY NODE` in the source. Walk
[`docs/05_verification_checklist.md`](docs/05_verification_checklist.md) with SE11
open before the first productive call.

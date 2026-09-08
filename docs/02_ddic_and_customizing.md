# 02 – DDIC objects & Customizing

## 1. DDIC created by this repo (abapGit pull, package ZABAP_UTIL)

### Data elements
| Name | Type | Purpose |
|---|---|---|
| `ZCUST_BP_ID` | CHAR 20 | external customer ID |
| `ZCUST_BP_APPID` | CHAR 40 | external application ID |
| `ZCUST_BP_STATUS` | CHAR 20 | external approval status |
| `ZCUST_BP_TS` | CHAR 30 | ISO-8601 timestamp text |
| `ZCUST_BP_TEXT40/60/80/132/255` | CHAR n | generic payload text |
| `ZCUST_BP_JSON` | STRING | stored request / response body |
| `ZCUST_BP_FLAG` | CHAR 1 | direction / status code |
| `ZCUST_BP_HTTP_RC` | NUMC 3 | HTTP status code / message seq. |

### Structures (`INTTAB`)
`ZCUST_BP_S_COMPANY_INFO`, `_S_DOCUMENT`, `_S_CONTROL`, `_S_CREATE_REQ`,
`_S_MESSAGE`, `_S_CREATE_RES`, `_S_READ_REQ`, `_S_ADDRESS`, `_S_ROLE`,
`_S_TAXNUM`, `_S_IDENT`, `_S_BANK`, `_S_SALESAREA`, `_S_COMPANYCODE`,
`_S_READ_RES`.

### Table types
`ZCUST_BP_T_TEXT60`, `_T_IND`, `_T_DOCUMENT`, `_T_MESSAGE`, `_T_ROLE`,
`_T_TAXNUM`, `_T_BANK`, `_T_SALESAREA`, `_T_COMPANYCODE`, `_T_IDENT`.

### Transparent tables
| Table | Key | Notes |
|---|---|---|
| `ZT_CUST_BP_LOG` | `MANDT, LOG_ID` | one row per inbound call, holds verbatim `REQUEST_JSON` |
| `ZT_CUST_BP_LOG_MSG` | `MANDT, LOG_ID, SEQNR` | message detail for the ALV drill-down |

Delivery class `A`, no buffering. `LOG_ID` = `SYSUUID_C22`
(`cl_system_uuid=>create_uuid_c22_static`).

## 2. Customizing to be done in the target client

These are **not** transportable via abapGit – hand to the functional/Basis team.

| # | What | Transaction / view | Used by |
|---|---|---|---|
| 1 | **Customer account group** for the API (e.g. `0001` or a dedicated `Z…`) | OBD2 | `custAcctGrp` → `KNA1-KTOKD` |
| 2 | **BP grouping** for the customer role, internal number assignment | `BUCF` / SPRO *SAP Business Partner → Basic Settings → Number Ranges and Groupings* | `bpGrouping` |
| 3 | **CVI** customer ↔ BP link active for the account group, role `FLCU01` mapped | SPRO *Master Data Synchronization → Customer/Vendor Integration* | `CL_MD_BP_MAINTAIN` |
| 4 | **Tax number category** for TIN/VAT (e.g. `ZTIN` or a standard `NG…`) | `V_TFKTAXNUMTYPE` | `taxTypeTin` |
| 5 | **Identification type** for the company registration / CAC number (e.g. `ZCRN`) | SPRO *SAP Business Partner → Business Partner → Basic Settings → Identification Numbers → Define Identification Types* (view `TB039A`) | `idTypeReg` |
| 6 | **Legal form** values for `businessType` ("Limited Liability Company", …) | `V_TB004` | `legalForm` |
| 7 | **BP type** values for `gradeType` ("Domestic", …) | `V_TB003` | `bpType` |
| 8 | **Industry system + industry keys** for `natureOfBusiness` / `product` | SPRO *SAP Business Partner → Business Partner → Basic Settings → Industries* | `industrySystem` (default `0001`) + `industryKeys[]` |
| 9 | (optional) default reconciliation account / sales area if `createFi` / `createSales` are used | FS00 / OVX* | `reconAcct`, `salesOrg` … |

## 3. Mapping – payload → standard BP fields

| JSON | SAP target | Notes |
|---|---|---|
| `customerId` | `BUT000-BU_SORT1` (Search Term 1) | resolution key for GET |
| `applicationId` | `BUT000-BU_SORT2` (Search Term 2), truncated to 20 | full value kept in `ZT_CUST_BP_LOG` |
| `businessName` | `NAME_ORG1` / `NAME_ORG2` (split at 40) | |
| `firstName` / `lastName` | address *c/o name* | contact-person-as-relationship = later phase |
| `email` / `.mobile` | address e-mail / phone (`R_3_USER='3'` = mobile) | |
| `hqAddress` | address street / city / country | best-effort split on last comma – see checklist |
| `tinVatRegNo` | BP tax number, type `taxTypeTin` | |
| `companyRegNo` | BP identification, type `idTypeReg` | |
| `businessType` | `BU_LEGFORM` via `legalForm` | `W` message if key not supplied |
| `gradeType[]` | `BPKIND` via `bpType` | `W` message if key not supplied |
| `natureOfBusiness` + `product[]` | BP industries via `industryKeys[]` | `W` message if keys not supplied |
| `documents[]` | not persisted this phase | echoed to response + `ZT_CUST_BP_LOG` |
| `status`, `approvedAt` | not stored on BP | kept in `ZT_CUST_BP_LOG` (`EXT_STATUS`, request JSON) |

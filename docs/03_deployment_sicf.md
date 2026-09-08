# 03 – Deployment: ICF service node

## 1. Create the service (SICF)

1. `SICF` → *Execute* (hierarchy type `SERVICE`).
2. Navigate to `default_host / sap / bc`.
3. Right-click `bc` → **New Sub-Element** → name `zcust_bp`.
4. **Service data** tab
   * *Description*: `Dangote – Customer BP inbound REST API`
5. **Logon Data** tab
   * *Procedure*: `Standard` (`Required`)
   * Assign a **dedicated technical user** (service/communication user) with the
     roles in §3. Do **not** use `Alternative Logon` with a stored password in
     production unless the client cannot send Basic/OAuth.
   * *Security*: set **SSL** (`Required`) for productive systems.
6. **Handler List** tab
   * Row 1: `ZCL_CUST_BP_ICF_HANDLER`
7. Save (assign to package **ZABAP_UTIL** / transport).
8. Right-click the new node → **Activate Service**.

## 2. Endpoints

| Method | URL | Body | Success |
|---|---|---|---|
| POST | `/sap/bc/zcust_bp` | `ZCUST_BP_S_CREATE_REQ` JSON | 201 + `ZCUST_BP_S_CREATE_RES` |
| GET | `/sap/bc/zcust_bp?customerId=CUST-000123` | – | 200 + `ZCUST_BP_S_READ_RES` |
| GET | `/sap/bc/zcust_bp/CUST-000123` | – | 200 + `ZCUST_BP_S_READ_RES` |

`GET` accepts the id either as query parameter `customerId` **or** as the last
path segment.

## 3. Authorisations for the technical user

| Object | Values |
|---|---|
| `S_ICF` | `ICF_FIELD = SERVICE`, `ICF_VALUE` = SICF service SID |
| `B_BUPA_RLT` | role category `FLCU01` (and `BUP001` general) |
| `B_BUPA_GRP` | the BP grouping from Customizing |
| `B_BUPA_FDG` | field groups as required (`*` for the technical user) |
| `F_KNA1_APP` / `F_KNA1_GEN` / `F_KNA1_BED` / `F_KNA1_BUK` | `ACTVT 01/02/03`, account group, company code |
| `V_KNA1_VKO` | sales area (only if `createSales`) |
| `S_TCODE` | `SM30` not needed; keep minimal |

## 4. Smoke test (curl)

```bash
# create
curl -sk -X POST "https://<host>:<https_port>/sap/bc/zcust_bp" \
  -u "<TECH_USER>:<PWD>" \
  -H "Content-Type: application/json" \
  --data @docs/samples/create_request.json | jq

# read
curl -sk "https://<host>:<https_port>/sap/bc/zcust_bp?customerId=CUST-000123" \
  -u "<TECH_USER>:<PWD>" | jq
```

`SMICM` → *Goto → Services* for the port. Trace with `SICF` → *Recording* or
transaction ` SRT_UTIL` / `SICF` error log; application errors are in
`ZT_CUST_BP_LOG` (report `ZCUST_BP_LOG_REPORT`).

## 5. Operations

* **Monitor**: `ZCUST_BP_LOG_REPORT`, status = `E`.
* **Re-trigger one**: report → `P_LOGID` = the log id → execute.
* **Re-trigger a batch**: report → set date/customer selection → tick
  `P_REPRO` → execute (schedulable in `SM36`).
* **Housekeeping**: add an archiving/deletion job for `ZT_CUST_BP_LOG` /
  `ZT_CUST_BP_LOG_MSG` older than the retention period (not shipped).

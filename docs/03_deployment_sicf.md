# 03 – Deployment: ICF service node

## 1. Create the service (SICF)

1. `SICF` → *Execute* (hierarchy type `SERVICE`).
2. Navigate to `default_host / sap / bc`.
3. Right-click `bc` → **New Sub-Element** → name `zbp_customer`.
4. **Service data** tab
   * *Description*: `Dangote – Customer BP inbound REST API`
5. **Logon Data** tab
   * *Procedure*: `Standard` (`Required`)
   * Assign a **dedicated technical user** (service/communication user) with the
     roles in §3. Do **not** use `Alternative Logon` with a stored password in
     production unless the client cannot send Basic/OAuth.
   * *Security*: set **SSL** (`Required`) for productive systems.
6. **Handler List** tab
   * Row 1: `ZCL_BP_CUST_ICF_HANDLER`
7. Save (assign to package **ZSD** / transport).
8. Right-click the new node → **Activate Service**.

## 2. Endpoints

| Method | URL | Body | Success |
|---|---|---|---|
| POST | `/sap/bc/zbp_customer` | `ZBP_CUST_S_CREATE_REQ` JSON | 201 + `ZBP_CUST_S_CREATE_RES` |
| GET | `/sap/bc/zbp_customer?customerId=CUST-000123` | – | 200 + `ZBP_CUST_S_READ_RES` |
| GET | `/sap/bc/zbp_customer/CUST-000123` | – | 200 + `ZBP_CUST_S_READ_RES` |

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
curl -sk -X POST "https://<host>:<https_port>/sap/bc/zbp_customer" \
  -u "<TECH_USER>:<PWD>" \
  -H "Content-Type: application/json" \
  --data @docs/samples/create_request.json | jq

# read
curl -sk "https://<host>:<https_port>/sap/bc/zbp_customer?customerId=CUST-000123" \
  -u "<TECH_USER>:<PWD>" | jq
```

`SMICM` → *Goto → Services* for the port. Trace with `SICF` → *Recording* or
transaction ` SRT_UTIL` / `SICF` error log; application errors are in
`ZBP_CUST_LOG` (report `ZBP_CUST_LOG_REPORT`).

## 5. Operations

* **Monitor**: `ZBP_CUST_LOG_REPORT`, status = `E`.
* **Re-trigger one**: report → `P_LOGID` = the log id → execute.
* **Re-trigger a batch**: report → set date/customer selection → tick
  `P_REPRO` → execute (schedulable in `SM36`).
* **Housekeeping**: add an archiving/deletion job for `ZBP_CUST_LOG` /
  `ZBP_CUST_LOG_MSG` older than the retention period (not shipped).

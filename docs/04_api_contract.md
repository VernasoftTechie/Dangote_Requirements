# 04 – API contract

JSON uses **camelCase** (`/ui2/cl_json`, `pretty_mode-camel_case`). The payload
is **flat** (no nested `companyInfo` / `control` objects) – the client maps its
current keys (e.g. `"Business Name"`) to the keys below.

DDIC: request = `ZCUST_BP_S_CREATE_REQ`, response = `ZCUST_BP_S_CREATE_RES`,
read response = `ZCUST_BP_S_READ_RES`.

## POST /sap/bc/zcust_bp — request

```json
{
  "customerId": "CUST-000123",
  "applicationId": "076b0117-0154-7561-b0f8-8785ce57d561",
  "status": "Approved",
  "approvedAt": "2026-08-19T10:15:00Z",

  "businessName": "Acme Ltd",
  "tinVatRegNo": "12345678-0001",
  "natureOfBusiness": "Manufacturing",
  "businessType": "Limited Liability Company",
  "companyRegNo": "RC123456",
  "hqAddress": "1 Marina Road, Lagos",
  "firstName": "Ada",
  "lastName": "Lovelace",
  "email": "ada@acme.com",
  "mobile": "+2348012345678",
  "product": ["Oil and Gas"],
  "gradeType": ["Domestic"],

  "bpGrouping": "BP02",
  "custAcctGrp": "0001",
  "legalForm": "0002",
  "bpType": "Z1",
  "industrySystem": "0001",
  "industryKeys": ["0800"],
  "taxTypeTin": "ZTIN",
  "idTypeReg": "ZCRN",
  "defaultCountry": "NG",
  "salesOrg": "1000",
  "distrChannel": "10",
  "division": "00",
  "companyCode": "1000",
  "reconAcct": "0000140000",
  "createFi": true,
  "createSales": true,

  "documents": [
    { "fieldId": "nda", "name": "Non-Disclosure Agreement", "path": "CUST-000123/nda/Non-Disclosure-Agreement.pdf/final", "contentType": "application/pdf" },
    { "fieldId": "cac", "name": "CAC Certificate",          "path": "CUST-000123/cac/CAC-Certificate.pdf/final",          "contentType": "application/pdf" }
  ]
}
```

### Field groups

| Group | Fields | Notes |
|---|---|---|
| Identity | `customerId` ✔, `applicationId`, `status`, `approvedAt` | `customerId` ≤ 20 chars, unique, stored in Search Term 1; `applicationId` in Search Term 2 (20 chars) + full value in the log |
| Company | `businessName` ✔, `tinVatRegNo`, `natureOfBusiness`, `businessType`, `companyRegNo`, `hqAddress`, `firstName`, `lastName`, `email`, `mobile`, `product[]`, `gradeType[]` | human data |
| SAP keys | `bpGrouping` ✔, `custAcctGrp` (✔ if `createFi`/`createSales`), `legalForm`, `bpType`, `industrySystem`, `industryKeys[]`, `taxTypeTin`, `idTypeReg`, `defaultCountry`, `salesOrg`, `distrChannel`, `division`, `companyCode`, `reconAcct`, `createFi`, `createSales` | already-resolved Customizing keys; omitted values fall back to `ZIF_CUST_BP_TYPES=>c_default` |
| Attachments | `documents[]` — **optional** | when present, each entry is `{ fieldId, name, path, contentType }`; echoed to the response + processing log this phase (no DMS/GOS yet) |

✔ = required; every other field is optional. Anything that maps to a text value
but no SAP key (e.g. `businessType` without `legalForm`) produces a `W` message
in the response – nothing drops silently.

## POST — response (`ZCUST_BP_S_CREATE_RES`)

**`success` and `messages` are always present** — on every outcome, success or
failure. `messages` carries the full return table from `CL_MD_BP_MAINTAIN` plus
any `W` warnings; when the BP API returns none, an explicit `S` line (`ZMSG_CUST_BP 017`)
is added so the caller always has an outcome message.

```json
{
  "customerId": "CUST-000123",
  "partner": "0001000123",
  "partnerGuid": "0050568A2B1C1EDEA1E4F1C0A8C0000A",
  "customer": "0001000123",
  "success": true,
  "logId": "0050568A2B1C1EDEA1E4F1C0A8C10012",
  "messages": [
    { "type": "S", "id": "ZMSG_CUST_BP", "number": "017", "message": "Business partner 0001000123 (customer 0001000123) created for external ID CUST-000123", "field": "" },
    { "type": "S", "id": "R11", "number": "102", "message": "Business partner 0001000123 created", "field": "" }
  ]
}
```

Failure example (HTTP 422):

```json
{
  "customerId": "CUST-000123",
  "partner": "",
  "customer": "",
  "success": false,
  "logId": "0050568A2B1C1EDEA1E4F1C0A8C10099",
  "messages": [
    { "type": "E", "id": "R1", "number": "807", "message": "Account group 0001 does not exist", "field": "KTOKD" }
  ]
}
```

| HTTP | `success` | meaning |
|---|---|---|
| 201 | true | created |
| 200 | true | already existed – `partner` / `customer` are the existing keys, `W` message |
| 400 | false | body empty or not JSON |
| 403 | false | no authorization (`B_BUPA_RLT`) |
| 422 | false | validation failed, **simulation** (`VALIDATE_SINGLE`) reported errors, or `MAINTAIN` returned `E`/`A` — see `messages` |
| 500 | false | unexpected |

**Nothing is committed until the simulation is clean.** `execute` runs
`CL_MD_BP_MAINTAIN=>VALIDATE_SINGLE` (no database update) first; if it returns
any `E`/`A` message the call stops there with 422 and those messages, and no BP
is created. Only a clean simulation proceeds to `MAINTAIN` + `BAPI_TRANSACTION_COMMIT`.

`message[].type`: `S` success · `I` info · `W` warning · `E` error · `A` abort.
Every `E`/`A` line also carries `id` + `number` (SAP message key) and, where
`CL_MD_BP_MAINTAIN` supplied it, the offending `field`.

## GET /sap/bc/zcust_bp?customerId=CUST-000123 — response (`ZCUST_BP_S_READ_RES`)

Also carries `success` + `messages` (same envelope as POST). On 404 the body is
`{ "customerId": "...", "success": false, "messages": [ { "type": "E", ... } ] }`.

```json
{
  "customerId": "CUST-000123",
  "partner": "0001000123",
  "partnerGuid": "0050568A2B1C1EDEA1E4F1C0A8C0000A",
  "customer": "0001000123",
  "success": true,
  "messages": [ { "type": "S", "id": "ZMSG_CUST_BP", "number": "018", "message": "Customer data read for external ID CUST-000123 (BP 0001000123)", "field": "" } ],
  "bpCategory": "2",
  "bpGrouping": "BP02",
  "orgName1": "Acme Ltd",
  "orgName2": "",
  "searchTerm1": "CUST-000123",
  "searchTerm2": "076b0117-0154-7561-b0f8",
  "bpType": "Z1",
  "legalForm": "0002",
  "addrStreet": "1 Marina Road",
  "addrHouseNo": "",
  "addrCity": "Lagos",
  "addrPostlCode": "",
  "addrRegion": "",
  "addrCountry": "NG",
  "addrPhone": "",
  "addrMobile": "",
  "addrEmail": "ada@acme.com",
  "contactName": "Ada Lovelace",
  "roles":         [ { "role": "FLCU01", "validFrom": "0000-00-00", "validTo": "0000-00-00" } ],
  "identification":[ { "idType": "ZCRN", "idNumber": "RC123456" } ],
  "taxNumbers":    [ { "taxType": "STCD1", "taxNumber": "12345678-0001" } ],
  "bankDetails":   [],
  "salesAreas":    [ { "salesOrg": "1000", "distrChannel": "10", "division": "00" } ],
  "companyCodes":  [ { "companyCode": "1000", "reconAcct": "0000140000" } ],
  "industries":    [],
  "createdOn": "2026-08-19",
  "createdBy": "RFC_DANGOTE"
}
```

### Round-trip (POST → GET)

| POST field | GET field(s) | notes |
|---|---|---|
| `customerId` | `searchTerm1` | exact |
| `applicationId` | `searchTerm2` | first 20 chars (full value in the log) |
| `businessName` | `orgName1` + `orgName2` | split at 40 |
| `firstName` + `lastName` | `contactName` | stored as address c/o name |
| `hqAddress` | `addrStreet` / `addrCity` / `addrCountry` | free-text split |
| `email` / `mobile` | `addrEmail` / `addrPhone` | default communication record |
| `bpGrouping` / `bpCategory` | `bpGrouping` / `bpCategory` | exact |
| `partnerRole` | `roles[]` | + any other roles on the BP |
| `bpType` | `bpType` | `BUT000-BPKIND` |
| `legalForm` | `legalForm` | `BUT000-LEGAL_ENTY` |
| `companyRegNo` (+ `idTypeReg`) | `identification[]` | all id types on the BP |
| `tinVatRegNo` (+ `taxTypeTin`) | `taxNumbers[]` | echoed as the `KNA1-STCDx` field it landed in (category→field is Customizing) |
| `salesOrg`/`distrChannel`/`division` | `salesAreas[]` | when `createSales` |
| `companyCode`/`reconAcct` | `companyCodes[]` | when `createFi` |
| `industryKeys[]` | `industries[]` | **not echoed** – `BUT0IS` field names vary by release (adaptation point D3) |

| HTTP | meaning |
|---|---|
| 200 | found |
| 400 | `customerId` missing |
| 403 | no display authorization |
| 404 | `customerId` unknown, or BP has no linked customer |
| 500 | unexpected |

Sample: [`samples/create_request.json`](samples/create_request.json).

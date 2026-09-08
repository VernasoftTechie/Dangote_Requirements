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
| Attachments | `documents[]` | stored in the log only this phase |

✔ = required. Anything that maps to a text value but no SAP key (e.g.
`businessType` without `legalForm`) produces a `W` message in the response –
nothing drops silently.

## POST — response (`ZCUST_BP_S_CREATE_RES`)

```json
{
  "customerId": "CUST-000123",
  "partner": "0001000123",
  "partnerGuid": "0050568A2B1C1EDEA1E4F1C0A8C0000A",
  "customer": "0001000123",
  "success": true,
  "logId": "0050568A2B1C1EDEA1E4F1C0A8C10012",
  "messages": [
    { "type": "S", "id": "R11", "number": "102", "message": "Business partner 0001000123 created", "field": "" }
  ]
}
```

| HTTP | meaning |
|---|---|
| 201 | created |
| 200 | already existed – `partner` / `customer` are the existing keys, `W` message |
| 400 | body empty or not JSON |
| 422 | validation failed, no authorization, or `CL_MD_BP_MAINTAIN` returned `E`/`A` |
| 500 | unexpected |

## GET /sap/bc/zcust_bp?customerId=CUST-000123 — response (`ZCUST_BP_S_READ_RES`)

```json
{
  "customerId": "CUST-000123",
  "partner": "0001000123",
  "partnerGuid": "0050568A2B1C1EDEA1E4F1C0A8C0000A",
  "customer": "0001000123",
  "bpCategory": "2",
  "bpGrouping": "BP02",
  "orgName1": "Acme Ltd",
  "orgName2": "",
  "searchTerm1": "CUST-000123",
  "searchTerm2": "076b0117-0154-7561-b0f8",
  "bpType": "Z1",
  "addrStreet": "1 Marina Road",
  "addrHouseNo": "",
  "addrCity": "Lagos",
  "addrPostlCode": "",
  "addrRegion": "",
  "addrCountry": "NG",
  "addrPhone": "",
  "addrMobile": "",
  "addrEmail": "ada@acme.com",
  "roles":         [ { "role": "FLCU01", "validFrom": "0000-00-00", "validTo": "0000-00-00" } ],
  "identification":[ { "idType": "ZCRN", "idNumber": "RC123456" } ],
  "taxNumbers":    [ { "taxType": "ZTIN", "taxNumber": "12345678-0001" } ],
  "bankDetails":   [],
  "salesAreas":    [ { "salesOrg": "1000", "distrChannel": "10", "division": "00" } ],
  "companyCodes":  [ { "companyCode": "1000", "reconAcct": "0000140000" } ],
  "industries":    [],
  "createdOn": "2026-08-19",
  "createdBy": "RFC_DANGOTE"
}
```

| HTTP | meaning |
|---|---|
| 200 | found |
| 400 | `customerId` missing |
| 404 | `customerId` unknown, or BP has no linked customer |
| 500 | unexpected |

Sample: [`samples/create_request.json`](samples/create_request.json).

# 04 – API contract

JSON uses **camelCase** (`/ui2/cl_json`, `pretty_mode-camel_case`). The client
transforms its current keys (e.g. `"Business Name"`) to the keys below.

## POST /sap/bc/zbp_customer — request

```json
{
  "customerId": "CUST-000123",
  "applicationId": "076b0117-0154-7561-b0f8-8785ce57d561",
  "status": "Approved",
  "approvedAt": "2026-08-19T10:15:00Z",
  "companyInfo": {
    "product": ["Oil and Gas"],
    "gradeType": ["Domestic"],
    "businessName": "Acme Ltd",
    "tinVatRegNo": "12345678-0001",
    "natureOfBusiness": "Manufacturing",
    "businessType": "Limited Liability Company",
    "companyRegNo": "RC123456",
    "hqAddress": "1 Marina Road, Lagos",
    "firstName": "Ada",
    "lastName": "Lovelace",
    "email": "ada@acme.com",
    "mobile": "+2348012345678"
  },
  "documents": [
    { "fieldId": "nda", "name": "Non-Disclosure Agreement", "path": "CUST-000123/nda/Non-Disclosure-Agreement.pdf/final", "contentType": "application/pdf" },
    { "fieldId": "cac", "name": "CAC Certificate",          "path": "CUST-000123/cac/CAC-Certificate.pdf/final",          "contentType": "application/pdf" }
  ],
  "control": {
    "bpCategory": "2",
    "bpGrouping": "BP02",
    "partnerRole": "FLCU01",
    "custAcctGrp": "0001",
    "legalForm": "0002",
    "bpType": "Z1",
    "industrySystem": "0001",
    "industryKeys": ["0800", "0100"],
    "taxTypeTin": "ZTIN",
    "idTypeReg": "ZCRN",
    "defaultCountry": "NG",
    "salesOrg": "1000",
    "distrChannel": "10",
    "division": "00",
    "companyCode": "1000",
    "reconAcct": "0000140000",
    "createFi": true,
    "createSales": true
  }
}
```

### Field rules

| Field | Req. | Notes |
|---|---|---|
| `customerId` | ✔ | ≤ 20 chars, unique; stored in Search Term 1 |
| `companyInfo.businessName` | ✔ | organisation name |
| `control.bpGrouping` | ✔ | internal-number grouping for the customer role |
| `control.custAcctGrp` | ✔ | `KNA1` account group |
| `control` (rest) | – | omitted values fall back to `ZIF_BP_CUST_TYPES=>c_default` |
| `documents[]` | – | stored in the log only this phase |
| `status`, `approvedAt` | – | stored in the log only |

## POST — response

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
| 200 | already existed – `partner` / `customer` are the existing keys |
| 400 | body empty or not JSON |
| 422 | validation failed or `CL_MD_BP_MAINTAIN` returned `E`/`A` (see `messages`) |
| 500 | unexpected |

## GET /sap/bc/zbp_customer?customerId=CUST-000123 — response

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
  "address": {
    "street": "1 Marina Road", "houseNo": "", "city": "Lagos",
    "postlCode": "", "region": "", "country": "NG",
    "phone": "", "mobile": "", "email": "ada@acme.com"
  },
  "roles":          [ { "role": "FLCU01", "validFrom": "0000-00-00", "validTo": "0000-00-00" } ],
  "identification": [ { "idType": "ZCRN", "idNumber": "RC123456" } ],
  "taxNumbers":     [ { "taxType": "ZTIN", "taxNumber": "12345678-0001" } ],
  "bankDetails":    [],
  "salesAreas":     [ { "salesOrg": "1000", "distrChannel": "10", "division": "00" } ],
  "companyCodes":   [ { "companyCode": "1000", "reconAcct": "0000140000" } ],
  "industries":     [ "0800" ],
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

Sample files: [`samples/create_request.json`](samples/create_request.json).

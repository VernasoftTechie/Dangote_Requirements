# 05 – Pre‑go‑live verification checklist (S/4HANA release specific)

The generic ABAP is written against the well‑documented shapes of
`CVIS_EI_EXTERN` and `CMDS_EI_MAIN`. A handful of deep component names have
shifted across S/4 releases. Open each type in **SE11** and confirm, adjusting
the marked lines. All marked lines carry a `VERIFY NODE` comment.

## A. `ZCL_CUST_BP_CREATE=>build_cvi` — `CVIS_EI_EXTERN`

| # | Path used | Check |
|---|---|---|
| A1 | `partner-header-object_task` | `= 'I'` for insert |
| A2 | `partner-central_data-common-data-bp_control-category` / `-grouping` (+ `datax`) | category `'2'`, grouping = your internal grouping |
| A3 | `partner-central_data-common-data-bp_organization-name1` / `-name2` (+ `datax`) | org name fields |
| A4 | `partner-central_data-common-data-bp_organization-legalform` (+ `datax`) | some releases: `-legal_form` |
| A5 | `partner-central_data-common-data-bp_centraldata-searchterm1` / `-searchterm2` (+ `datax`) | search terms |
| A6 | `partner-central_data-common-data-bp_centraldata-partnertype` (+ `datax`) | `BPKIND`; some releases: `-bpkind` |
| A7 | `partner-central_data-address-addresses` (line `BUS_EI_BUPA_ADDRESS`) | `task`, `data-postal-data-{street,city,country,c_o_name,langu}` + `datax` |
| A8 | `…-address-…-communication-smtp-smtp` line `contact-data-e_mail` / `-std_no` | e-mail node |
| A9 | `…-address-…-communication-phone-phone` line `contact-data-telephone` / `-r_3_user` / `-std_no` | phone node, `r_3_user='3'` = mobile |
| A10 | `partner-central_data-role-roles` line: `task`, `data_key`, `data-rolecategory`, `data-valid_from` | role node |
| A11 | `partner-central_data-taxnumber-taxnumbers` line `data_key-taxtype` / `-taxnumber` | tax number node |
| A12 | `partner-central_data-identification-identification` line `data_key-identificationcategory` / `-identificationnumber`, `data-identificationtype` / `-entrydate` | identification node |
| A13 | `partner-central_data-industrysector-industrysectors` line `data_key-indsector` / `-industrysector`, `data-ind_sector_std` | **most likely to differ** – confirm field names |
| A14 | `customer-header-object_task` | `= 'I'` |
| A15 | `customer-central_data-central-data-kna1-ktokd` (+ `datax`) | account group |
| A16 | `customer-central_data-sales_data-sales` line `task`, `data_key-{vkorg,vtweg,spart}` | sales node |
| A17 | `customer-central_data-company_data-company` line `task`, `data_key-bukrs`, `data-akont` (+ `datax`) | company-code node |

## B. `CL_MD_BP_MAINTAIN=>MAINTAIN`

| # | Check |
|---|---|
| B1 | Importing param name is `I_DATA` type `CVIS_EI_EXTERN_T` |
| B2 | Exporting param name is `E_RETURN` type `BAPIRETM` (table; line has `OBJECT_MSG` sub-table) |
| B3 | No implicit commit → `BAPI_TRANSACTION_COMMIT` / `_ROLLBACK` as coded |
| B4 | Optional: add `CL_MD_BP_MAINTAIN=>VALIDATE_SINGLE` before `MAINTAIN` for a dry run |

## C. `ZCL_CUST_BP_READ` — `CMD_EI_API=>GET_DATA`

| # | Path used | Check |
|---|---|---|
| C1 | `IS_MASTER_DATA` type `CMDS_EI_MAIN`, `ES_MASTER_DATA` type `CMDS_EI_MAIN`, `ES_ERROR` type `CVIS_MESSAGE` | signature |
| C2 | `cmds_ei_main-customers` line `header-object_instance-kunnr`, `header-object_task = 'M'` | key passing |
| C3 | `central_data-sales_data-sales` line `data_key-{vkorg,vtweg,spart}` | sales read |
| C4 | `central_data-company_data-company` line `data_key-bukrs`, `data-akont` | company read |
| C5 | If `CMD_EI_API=>GET_DATA` is not present, switch to `CMD_EI_API_EXTRACT=>GET_DATA` (same params) | fallback |

## D. `ZCL_CUST_BP_MAPPER` — direct table reads (stable, low risk)

| # | Check |
|---|---|
| D1 | `CVI_CUST_LINK` has `PARTNER_GUID` + `CUSTOMER` (S/4). Older CVI: `CVI_CUST_LINK` unchanged. |
| D2 | `KNA1` + `ADRC` join fields: `adrnr`/`addrnumber`, `street`, `house_num1`, `city1`, `post_code1`, `region`, `country`, `tel_number`, `smtp_addr` |
| D3 | `BUT000`, `BUT100`, `BUT0ID`, `BUT0IS`, `BUT0BK` field names as used |
| D4 | Legal form field on `BUT000` (add to `enrich_from_bp` once known – `LEGAL_ORG` on most S/4) |

## E. Address quality

`companyInfo.hqAddress` is a single free-text line. `parse_address` splits on
the last comma. **Recommend** the client sends structured address fields in a
contract revision; until then, a `W` message is returned when only one token is
found.

## F. Functional smoke test

1. Customizing per `02_ddic_and_customizing.md` complete.
2. `POST` the sample → expect 201, note `partner`.
3. `BP` transaction → open `partner` → Search Term 1 = `CUST-000123`, role
   `FLCU01`, address, tax number, identification present.
4. `GET ?customerId=CUST-000123` → 200, payload matches.
5. `POST` the same again → 200 + "already exists" warning, no new BP.
6. Force an error (bad `custAcctGrp`) → 422, row in `ZT_CUST_BP_LOG` status `E`.
7. `ZCUST_BP_LOG_REPORT` → `P_LOGID` of that row → fix Customizing → execute →
   status `R`, `retry_count = 1`.

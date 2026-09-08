"! <p class="shorttext synchronized">BP Customer ICF API - mapping helpers</p>
"! Stateless helpers shared by the create and read services:
"! <ul>
"! <li>external <em>customerId</em> &lt;-&gt; SAP BP / customer keys (search term 1)</li>
"! <li>free-text head-quarter address -&gt; structured address</li>
"! <li>CVI customer image ( <em>cmds_ei_extern</em> ) -&gt; ZBP_CUST_S_READ_RES</li>
"! </ul>
"!
"! Field paths inside <em>cmds_ei_extern</em> are release dependent - each one
"! is flagged &quot;VERIFY NODE&quot;. Open the type in SE11 for the target S/4
"! release and adjust if activation complains.
CLASS zcl_bp_cust_mapper DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    "! Resolve the external customer id to a BP number via search term 1
    "! ( BUT000-BU_SORT1 ). Returns INITIAL when nothing is found.
    CLASS-METHODS resolve_partner
      IMPORTING iv_customer_id   TYPE zbp_cust_id
      RETURNING VALUE(rv_partner) TYPE bu_partner.

    "! BP number -&gt; linked customer number ( CVI_CUST_LINK ).
    CLASS-METHODS resolve_customer
      IMPORTING iv_partner        TYPE bu_partner
      RETURNING VALUE(rv_customer) TYPE kunnr.

    "! Best-effort split of a single free-text address line.
    "! &quot;1 Marina Road, Lagos&quot; -&gt; street=&quot;1 Marina Road&quot; city=&quot;Lagos&quot;.
    CLASS-METHODS parse_address
      IMPORTING iv_text          TYPE csequence
                iv_country       TYPE land1 OPTIONAL
      RETURNING VALUE(rs_address) TYPE zbp_cust_s_address.

    "! Build the read response from the CVI customer image plus a few
    "! direct BP reads (roles / identification / industries / legal form).
    CLASS-METHODS cvi_to_read_res
      IMPORTING iv_customer_id  TYPE zbp_cust_id
                iv_partner      TYPE bu_partner
                is_customer     TYPE cmds_ei_extern
      RETURNING VALUE(rs_result) TYPE zbp_cust_s_read_res.

  PRIVATE SECTION.
    CLASS-METHODS enrich_from_bp
      IMPORTING iv_partner TYPE bu_partner
      CHANGING  cs_result  TYPE zbp_cust_s_read_res.

    CLASS-METHODS enrich_from_kna1
      IMPORTING iv_customer TYPE kunnr
      CHANGING  cs_result   TYPE zbp_cust_s_read_res.
ENDCLASS.


CLASS zcl_bp_cust_mapper IMPLEMENTATION.

  METHOD resolve_partner.
    IF iv_customer_id IS INITIAL.
      RETURN.
    ENDIF.
    SELECT SINGLE partner FROM but000
      INTO @rv_partner
      WHERE bu_sort1 = @iv_customer_id.
  ENDMETHOD.


  METHOD resolve_customer.
    DATA lv_guid TYPE bu_partner_guid.

    SELECT SINGLE partner_guid FROM but000
      INTO @lv_guid
      WHERE partner = @iv_partner.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " CVI link table (S/4: CVI_CUST_LINK, key = partner_guid)
    SELECT SINGLE customer FROM cvi_cust_link
      INTO @rv_customer
      WHERE partner_guid = @lv_guid.
  ENDMETHOD.


  METHOD parse_address.
    DATA lv_rest TYPE string.

    rs_address-country = COND #( WHEN iv_country IS NOT INITIAL
                                THEN iv_country
                                ELSE zif_bp_cust_types=>c_default-country ).

    DATA(lv_text) = condense( CONV string( iv_text ) ).
    IF lv_text IS INITIAL.
      RETURN.
    ENDIF.

    IF lv_text CS ','.
      SPLIT lv_text AT ',' INTO rs_address-street lv_rest.
      rs_address-street = condense( rs_address-street ).
      " last comma segment -> city (drop any trailing region/postcode token)
      SPLIT lv_rest AT ',' INTO TABLE DATA(lt_seg).
      rs_address-city = condense( lt_seg[ lines( lt_seg ) ] ).
    ELSE.
      rs_address-street = lv_text.
    ENDIF.
  ENDMETHOD.


  METHOD cvi_to_read_res.
    rs_result-customer_id = iv_customer_id.
    rs_result-partner     = iv_partner.
    rs_result-customer    = is_customer-header-object_instance-kunnr.

    " ---- sales areas  (VERIFY NODE: central_data-sales_data-sales) ----
    LOOP AT is_customer-central_data-sales_data-sales INTO DATA(ls_sales).
      APPEND VALUE #( sales_org     = ls_sales-data_key-vkorg
                      distr_channel = ls_sales-data_key-vtweg
                      division      = ls_sales-data_key-spart )
             TO rs_result-sales_areas.
    ENDLOOP.

    " ---- company codes (VERIFY NODE: central_data-company_data-company) ----
    LOOP AT is_customer-central_data-company_data-company INTO DATA(ls_comp).
      APPEND VALUE #( company_code = ls_comp-data_key-bukrs
                      recon_acct   = ls_comp-data-akont )
             TO rs_result-company_codes.
    ENDLOOP.

    " ---- everything else from bullet-proof direct reads ----
    IF rs_result-customer IS INITIAL.
      rs_result-customer = resolve_customer( iv_partner ).
    ENDIF.
    enrich_from_kna1( EXPORTING iv_customer = rs_result-customer CHANGING cs_result = rs_result ).
    enrich_from_bp(   EXPORTING iv_partner  = iv_partner        CHANGING cs_result = rs_result ).
  ENDMETHOD.


  METHOD enrich_from_kna1.
    IF iv_customer IS INITIAL.
      RETURN.
    ENDIF.

    SELECT SINGLE k~name1, k~name2, k~stcd1, k~erdat, k~ernam,
                  a~street, a~house_num1, a~city1, a~post_code1,
                  a~region, a~country, a~tel_number, a~smtp_addr
      FROM kna1 AS k
      LEFT OUTER JOIN adrc AS a ON a~addrnumber = k~adrnr
      INTO @DATA(ls_k)
      WHERE k~kunnr = @iv_customer.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    cs_result-org_name1          = ls_k-name1.
    cs_result-org_name2          = ls_k-name2.
    cs_result-address-street     = ls_k-street.
    cs_result-address-house_no   = ls_k-house_num1.
    cs_result-address-city       = ls_k-city1.
    cs_result-address-postl_code = ls_k-post_code1.
    cs_result-address-region     = ls_k-region.
    cs_result-address-country    = ls_k-country.
    cs_result-address-phone      = ls_k-tel_number.
    cs_result-address-email      = ls_k-smtp_addr.
    cs_result-created_on         = ls_k-erdat.
    cs_result-created_by         = ls_k-ernam.

    IF ls_k-stcd1 IS NOT INITIAL.
      APPEND VALUE #( tax_type = 'STCD1' tax_number = ls_k-stcd1 ) TO cs_result-tax_numbers.
    ENDIF.
  ENDMETHOD.


  METHOD enrich_from_bp.
    " ---- central BP (BUT000) ----
    "   Legal form lives in BUT000-LEGAL_ORG on most S/4 releases - add it
    "   here once verified in SE11; it is a display-only nicety.
    SELECT SINGLE partner_guid, type, bu_group, bpkind,
                  bu_sort1, bu_sort2, name_org1, name_org2
      FROM but000
      INTO @DATA(ls_bp)
      WHERE partner = @iv_partner.
    IF sy-subrc = 0.
      cs_result-partner_guid = ls_bp-partner_guid.
      cs_result-bp_category  = ls_bp-type.
      cs_result-bp_grouping  = ls_bp-bu_group.
      cs_result-bp_type      = ls_bp-bpkind.
      cs_result-search_term1 = ls_bp-bu_sort1.
      cs_result-search_term2 = ls_bp-bu_sort2.
      IF cs_result-org_name1 IS INITIAL.
        cs_result-org_name1 = ls_bp-name_org1.
        cs_result-org_name2 = ls_bp-name_org2.
      ENDIF.
    ENDIF.

    " ---- roles (BUT100) ----
    SELECT rltyp FROM but100
      INTO TABLE @DATA(lt_role)
      WHERE partner = @iv_partner.
    LOOP AT lt_role INTO DATA(ls_role).
      APPEND VALUE #( role = ls_role-rltyp ) TO cs_result-roles.
    ENDLOOP.

    " ---- identification numbers (BUT0ID) ----
    SELECT type, idnumber FROM but0id
      INTO TABLE @DATA(lt_id)
      WHERE partner = @iv_partner.
    LOOP AT lt_id INTO DATA(ls_id).
      APPEND VALUE #( id_type = ls_id-type id_number = ls_id-idnumber ) TO cs_result-identification.
    ENDLOOP.

    " ---- industry sectors (BUT0IS) ----
    SELECT ind_sector FROM but0is
      INTO TABLE @DATA(lt_is)
      WHERE partner = @iv_partner.
    LOOP AT lt_is INTO DATA(ls_is).
      APPEND CONV zbp_cust_text60( ls_is-ind_sector ) TO cs_result-industries.
    ENDLOOP.

    " ---- bank details (BUT0BK) ----
    SELECT banks, bankl, bankn FROM but0bk
      INTO TABLE @DATA(lt_bk)
      WHERE partner = @iv_partner.
    LOOP AT lt_bk INTO DATA(ls_bk).
      APPEND VALUE #( bank_ctry = ls_bk-banks
                      bank_key  = ls_bk-bankl
                      bank_acct = ls_bk-bankn ) TO cs_result-bank_details.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

"! <p class="shorttext synchronized">Customer BP API - mapping helpers</p>
"! Stateless helpers shared by the create and read services:
"! <ul>
"! <li>external <em>customerId</em> &lt;-&gt; SAP BP / customer keys ( search term 1 )</li>
"! <li>free-text head-quarter address -&gt; structured address</li>
"! <li>CVI customer image ( CMDS_EI_EXTERN ) -&gt; ZCUST_BP_S_READ_RES</li>
"! </ul>
"! Field paths inside the CVI structures are release dependent - see
"! docs/05_verification_checklist.md.
CLASS zcl_cust_bp_mapper DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    "! External customer id -&gt; BP number via search term 1
    "! ( BUT000-BU_SORT1 ). INITIAL when nothing is found.
    CLASS-METHODS resolve_partner
      IMPORTING iv_customer_id   TYPE zcust_bp_id
      RETURNING VALUE(rv_partner) TYPE bu_partner.

    "! BP number -&gt; linked customer number ( CVI_CUST_LINK ).
    CLASS-METHODS resolve_customer
      IMPORTING iv_partner        TYPE bu_partner
      RETURNING VALUE(rv_customer) TYPE kunnr.

    "! Best-effort split of a single free-text address line.
    "! "1 Marina Road, Lagos" -&gt; street="1 Marina Road" city="Lagos".
    CLASS-METHODS parse_address
      IMPORTING iv_text    TYPE csequence
                iv_country TYPE land1 OPTIONAL
      EXPORTING ev_street  TYPE string
                ev_city    TYPE string
                ev_country TYPE land1.

    "! Build the read response from the CVI customer image plus a few
    "! direct BP reads ( roles / identification / industries ).
    CLASS-METHODS cvi_to_read_res
      IMPORTING iv_customer_id   TYPE zcust_bp_id
                iv_partner       TYPE bu_partner
                is_customer      TYPE cmds_ei_extern
      RETURNING VALUE(rs_result) TYPE zcust_bp_s_read_res.

  PRIVATE SECTION.
    CLASS-METHODS enrich_from_kna1
      IMPORTING iv_customer TYPE kunnr
      CHANGING  cs_result   TYPE zcust_bp_s_read_res.

    CLASS-METHODS enrich_from_bp
      IMPORTING iv_partner TYPE bu_partner
      CHANGING  cs_result  TYPE zcust_bp_s_read_res.
ENDCLASS.


CLASS zcl_cust_bp_mapper IMPLEMENTATION.

  METHOD resolve_partner.
    IF iv_customer_id IS INITIAL.
      RETURN.
    ENDIF.
    SELECT SINGLE partner FROM but000
      INTO @rv_partner
      WHERE bu_sort1 = @iv_customer_id.
  ENDMETHOD.


  METHOD resolve_customer.
    SELECT SINGLE partner_guid FROM but000
      INTO @DATA(lv_guid)
      WHERE partner = @iv_partner.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    SELECT SINGLE customer FROM cvi_cust_link
      INTO @rv_customer
      WHERE partner_guid = @lv_guid.
  ENDMETHOD.


  METHOD parse_address.
    ev_country = COND #( WHEN iv_country IS NOT INITIAL
                         THEN iv_country
                         ELSE CONV land1( zif_cust_bp_types=>c_default-country ) ).

    DATA(lv_text) = condense( CONV string( iv_text ) ).
    IF lv_text IS INITIAL.
      RETURN.
    ENDIF.

    IF lv_text CS ','.
      SPLIT lv_text AT ',' INTO TABLE DATA(lt_seg).
      ev_street = condense( CONV string( lt_seg[ 1 ] ) ).
      ev_city   = condense( CONV string( lt_seg[ lines( lt_seg ) ] ) ).
    ELSE.
      ev_street = lv_text.
    ENDIF.
  ENDMETHOD.


  METHOD cvi_to_read_res.
    rs_result-customer_id = iv_customer_id.
    rs_result-partner     = iv_partner.
    rs_result-customer    = is_customer-header-object_instance-kunnr.

    " ---- sales areas ( CMDS_EI_EXTERN-SALES_DATA-SALES ) ----
    LOOP AT is_customer-sales_data-sales INTO DATA(ls_sales).
      APPEND VALUE #( sales_org     = ls_sales-data_key-vkorg
                      distr_channel = ls_sales-data_key-vtweg
                      division      = ls_sales-data_key-spart )
             TO rs_result-sales_areas.
    ENDLOOP.

    " ---- company codes ( CMDS_EI_EXTERN-COMPANY_DATA-COMPANY ) ----
    LOOP AT is_customer-company_data-company INTO DATA(ls_comp).
      APPEND VALUE #( company_code = ls_comp-data_key-bukrs
                      recon_acct   = ls_comp-data-akont )
             TO rs_result-company_codes.
    ENDLOOP.

    IF rs_result-customer IS INITIAL.
      rs_result-customer = resolve_customer( iv_partner ).
    ENDIF.
    enrich_from_kna1( EXPORTING iv_customer = rs_result-customer CHANGING cs_result = rs_result ).
    enrich_from_bp(   EXPORTING iv_partner  = iv_partner         CHANGING cs_result = rs_result ).
  ENDMETHOD.


  METHOD enrich_from_kna1.
    IF iv_customer IS INITIAL.
      RETURN.
    ENDIF.

    SELECT SINGLE k~name1, k~name2, k~erdat, k~ernam, k~adrnr,
                  k~stcd1, k~stcd2, k~stcd3, k~stcd4, k~stcd5, k~stceg,
                  a~street, a~str_suppl3, a~house_num1, a~city1, a~post_code1,
                  a~region, a~country, a~name_co
      FROM kna1 AS k
      LEFT OUTER JOIN adrc AS a ON a~addrnumber = k~adrnr
      INTO @DATA(ls_k)
      WHERE k~kunnr = @iv_customer.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    cs_result-org_name1       = ls_k-name1.
    cs_result-org_name2       = ls_k-name2.
    cs_result-contact_name    = ls_k-name_co.
    cs_result-addr_street     = COND #( WHEN ls_k-street IS NOT INITIAL
                                        THEN ls_k-street ELSE ls_k-str_suppl3 ).
    cs_result-addr_house_no   = ls_k-house_num1.
    cs_result-addr_city       = ls_k-city1.
    cs_result-addr_postl_code = ls_k-post_code1.
    cs_result-addr_region     = ls_k-region.
    cs_result-addr_country    = ls_k-country.
    cs_result-created_on      = ls_k-erdat.
    cs_result-created_by      = ls_k-ernam.

    IF ls_k-adrnr IS NOT INITIAL.
      SELECT SINGLE tel_number FROM adr2
        INTO @cs_result-addr_phone
        WHERE addrnumber = @ls_k-adrnr AND flgdefault = @abap_true.
      SELECT SINGLE smtp_addr FROM adr6
        INTO @cs_result-addr_email
        WHERE addrnumber = @ls_k-adrnr AND flgdefault = @abap_true.
    ENDIF.

    " tax numbers as held on the customer master ( category -> STCDx is
    " Customizing-driven, view TFKTAXNUMTYPE ); we echo each populated field.
    IF ls_k-stcd1 IS NOT INITIAL. APPEND VALUE #( tax_type = 'STCD1' tax_number = ls_k-stcd1 ) TO cs_result-tax_numbers. ENDIF.
    IF ls_k-stcd2 IS NOT INITIAL. APPEND VALUE #( tax_type = 'STCD2' tax_number = ls_k-stcd2 ) TO cs_result-tax_numbers. ENDIF.
    IF ls_k-stcd3 IS NOT INITIAL. APPEND VALUE #( tax_type = 'STCD3' tax_number = ls_k-stcd3 ) TO cs_result-tax_numbers. ENDIF.
    IF ls_k-stcd4 IS NOT INITIAL. APPEND VALUE #( tax_type = 'STCD4' tax_number = ls_k-stcd4 ) TO cs_result-tax_numbers. ENDIF.
    IF ls_k-stcd5 IS NOT INITIAL. APPEND VALUE #( tax_type = 'STCD5' tax_number = ls_k-stcd5 ) TO cs_result-tax_numbers. ENDIF.
    IF ls_k-stceg IS NOT INITIAL. APPEND VALUE #( tax_type = 'STCEG' tax_number = ls_k-stceg ) TO cs_result-tax_numbers. ENDIF.
  ENDMETHOD.


  METHOD enrich_from_bp.
    " BUT000-LEGAL_ENTY = "BP: Legal form of organization" (data elem BU_LEGENT)
    SELECT SINGLE partner_guid, type, bu_group, bpkind, legal_enty,
                  bu_sort1, bu_sort2, name_org1, name_org2
      FROM but000
      INTO @DATA(ls_bp)
      WHERE partner = @iv_partner.
    IF sy-subrc = 0.
      cs_result-partner_guid = ls_bp-partner_guid.
      cs_result-bp_category  = ls_bp-type.
      cs_result-bp_grouping  = ls_bp-bu_group.
      cs_result-bp_type      = ls_bp-bpkind.
      cs_result-legal_form   = ls_bp-legal_enty.
      cs_result-search_term1 = ls_bp-bu_sort1.
      cs_result-search_term2 = ls_bp-bu_sort2.
      IF cs_result-org_name1 IS INITIAL.
        cs_result-org_name1 = ls_bp-name_org1.
        cs_result-org_name2 = ls_bp-name_org2.
      ENDIF.
    ENDIF.

    SELECT rltyp FROM but100
      INTO TABLE @DATA(lt_role)
      WHERE partner = @iv_partner.
    LOOP AT lt_role INTO DATA(ls_role).
      APPEND VALUE #( role = ls_role-rltyp ) TO cs_result-roles.
    ENDLOOP.

    SELECT type, idnumber FROM but0id
      INTO TABLE @DATA(lt_id)
      WHERE partner = @iv_partner.
    LOOP AT lt_id INTO DATA(ls_id).
      APPEND VALUE #( id_type = ls_id-type id_number = ls_id-idnumber ) TO cs_result-identification.
    ENDLOOP.

    " BP industries ( BUT0IS ) - field names vary by release; left as an
    " adaptation point ( see docs/05_verification_checklist.md D3 ).

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

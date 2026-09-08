"! <p class="shorttext synchronized">BP Customer ICF API - create customer BP</p>
"! Maps the JSON payload ( ZBP_CUST_S_CREATE_REQ ) to the CVI structure
"! CVIS_EI_EXTERN and creates an <em>organisation</em> business partner with
"! the customer role via <em>CL_MD_BP_MAINTAIN=&gt;MAINTAIN</em> (internal
"! number assignment). The external <em>customerId</em> is stored in search
"! term 1 ( BUT000-BU_SORT1 ); <em>applicationId</em> in search term 2.
"!
"! Deep component paths in CVIS_EI_EXTERN are release dependent - each is
"! flagged &quot;VERIFY NODE&quot;. Confirm against SE11 for the target S/4 release.
CLASS zcl_bp_cust_create DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS execute
      IMPORTING is_request       TYPE zbp_cust_s_create_req
                iv_raw_json      TYPE string   OPTIONAL
                iv_write_log     TYPE abap_bool DEFAULT abap_true
      RETURNING VALUE(rs_result) TYPE zbp_cust_s_create_res.

    "! Exposed for ABAP Unit - pure mapping, no DB / no commit.
    METHODS build_cvi
      IMPORTING is_request     TYPE zbp_cust_s_create_req
      RETURNING VALUE(rt_data) TYPE cvis_ei_extern_t.

    METHODS resolve_control
      IMPORTING is_request       TYPE zbp_cust_s_create_req
      RETURNING VALUE(rs_control) TYPE zbp_cust_s_control.

  PRIVATE SECTION.
    DATA mt_warning TYPE zbp_cust_t_message.

    METHODS validate
      IMPORTING is_request TYPE zbp_cust_s_create_req
      RAISING   zcx_bp_cust.

    METHODS warn
      IMPORTING iv_text TYPE string.

    METHODS has_error
      IMPORTING it_return       TYPE bapiretm
      RETURNING VALUE(rv_error) TYPE abap_bool.

    METHODS map_return
      IMPORTING it_return         TYPE bapiretm
      RETURNING VALUE(rt_message) TYPE zbp_cust_t_message.

    METHODS keys_after_commit
      IMPORTING iv_customer_id TYPE zbp_cust_id
      CHANGING  cs_result      TYPE zbp_cust_s_create_res.
ENDCLASS.


CLASS zcl_bp_cust_create IMPLEMENTATION.

  METHOD execute.
    rs_result-customer_id = is_request-customer_id.
    CLEAR mt_warning.

    TRY.
        validate( is_request ).

        " ---- idempotency: customerId already mapped to a BP? ----
        DATA(lv_existing) = zcl_bp_cust_mapper=>resolve_partner( is_request-customer_id ).
        IF lv_existing IS NOT INITIAL.
          rs_result-partner  = lv_existing.
          rs_result-customer = zcl_bp_cust_mapper=>resolve_customer( lv_existing ).
          rs_result-success  = abap_true.
          APPEND VALUE #( type    = 'W'
                          id      = 'ZBP_CUST_MSG'
                          number  = '004'
                          message = |Customer { is_request-customer_id } already exists (BP { lv_existing })| )
                 TO rs_result-messages.
          IF iv_write_log = abap_true.
            rs_result-log_id = zcl_bp_cust_log=>record(
              iv_operation      = zif_bp_cust_types=>c_operation-create
              iv_customer_id    = is_request-customer_id
              iv_application_id = is_request-application_id
              iv_ext_status     = is_request-status
              iv_status         = zif_bp_cust_types=>c_log_status-success
              iv_http_status    = zif_bp_cust_types=>c_http-ok
              iv_raw_json       = iv_raw_json
              is_result         = rs_result
              it_messages       = rs_result-messages ).
          ENDIF.
          RETURN.
        ENDIF.

        " ---- create ----
        DATA(lt_data)  = build_cvi( is_request ).
        DATA lt_return TYPE bapiretm.

        cl_md_bp_maintain=>maintain(
          EXPORTING i_data   = lt_data
          IMPORTING e_return = lt_return ).

        rs_result-messages = map_return( lt_return ).
        APPEND LINES OF mt_warning TO rs_result-messages.

        IF has_error( lt_return ) = abap_true.
          CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
          rs_result-success = abap_false.
          IF iv_write_log = abap_true.
            rs_result-log_id = zcl_bp_cust_log=>record(
              iv_operation      = zif_bp_cust_types=>c_operation-create
              iv_customer_id    = is_request-customer_id
              iv_application_id = is_request-application_id
              iv_ext_status     = is_request-status
              iv_status         = zif_bp_cust_types=>c_log_status-error
              iv_http_status    = zif_bp_cust_types=>c_http-unprocessable
              iv_raw_json       = iv_raw_json
              is_result         = rs_result
              it_messages       = rs_result-messages ).
          ENDIF.
          RETURN.
        ENDIF.

        CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
          EXPORTING wait = abap_true.

        keys_after_commit( EXPORTING iv_customer_id = is_request-customer_id
                           CHANGING  cs_result      = rs_result ).
        rs_result-success = abap_true.

        IF iv_write_log = abap_true.
          rs_result-log_id = zcl_bp_cust_log=>record(
            iv_operation      = zif_bp_cust_types=>c_operation-create
            iv_customer_id    = is_request-customer_id
            iv_application_id = is_request-application_id
            iv_ext_status     = is_request-status
            iv_status         = zif_bp_cust_types=>c_log_status-success
            iv_http_status    = zif_bp_cust_types=>c_http-created
            iv_raw_json       = iv_raw_json
            is_result         = rs_result
            it_messages       = rs_result-messages ).
        ENDIF.

      CATCH zcx_bp_cust INTO DATA(lx).
        rs_result-success = abap_false.
        APPEND VALUE #( type    = 'E'
                        id      = lx->if_t100_message~t100key-msgid
                        number  = lx->if_t100_message~t100key-msgno
                        message = lx->get_text( ) ) TO rs_result-messages.
        IF iv_write_log = abap_true.
          rs_result-log_id = zcl_bp_cust_log=>record(
            iv_operation      = zif_bp_cust_types=>c_operation-create
            iv_customer_id    = is_request-customer_id
            iv_application_id = is_request-application_id
            iv_ext_status     = is_request-status
            iv_status         = zif_bp_cust_types=>c_log_status-error
            iv_http_status    = lx->http_status
            iv_raw_json       = iv_raw_json
            is_result         = rs_result
            it_messages       = rs_result-messages ).
        ENDIF.
    ENDTRY.
  ENDMETHOD.


  METHOD validate.
    IF is_request-customer_id IS INITIAL.
      RAISE EXCEPTION TYPE zcx_bp_cust
        MESSAGE e003(zbp_cust_msg) WITH 'customerId'.
    ENDIF.
    IF is_request-company_info-business_name IS INITIAL.
      RAISE EXCEPTION TYPE zcx_bp_cust
        MESSAGE e003(zbp_cust_msg) WITH 'companyInfo.businessName'.
    ENDIF.

    DATA(ls_ctrl) = resolve_control( is_request ).
    IF ls_ctrl-bp_grouping IS INITIAL.
      RAISE EXCEPTION TYPE zcx_bp_cust
        MESSAGE e012(zbp_cust_msg) WITH 'bpGrouping'.
    ENDIF.
    " custAcctGrp is only required when the customer master account group
    " is not derived from the BP grouping via CVI Customizing, or when
    " createFi / createSales fill the customer node explicitly.
    IF ls_ctrl-cust_acct_grp IS INITIAL
       AND ( ls_ctrl-create_fi = abap_true OR ls_ctrl-create_sales = abap_true ).
      RAISE EXCEPTION TYPE zcx_bp_cust
        MESSAGE e012(zbp_cust_msg) WITH 'custAcctGrp'.
    ENDIF.
  ENDMETHOD.


  METHOD warn.
    APPEND VALUE #( type = 'W' message = iv_text ) TO mt_warning.
  ENDMETHOD.


  METHOD resolve_control.
    rs_control = is_request-control.
    IF rs_control-bp_category    IS INITIAL. rs_control-bp_category    = zif_bp_cust_types=>c_default-bp_category.    ENDIF.
    IF rs_control-bp_grouping    IS INITIAL. rs_control-bp_grouping    = zif_bp_cust_types=>c_default-bp_grouping.    ENDIF.
    IF rs_control-partner_role   IS INITIAL. rs_control-partner_role   = zif_bp_cust_types=>c_default-partner_role.   ENDIF.
    IF rs_control-cust_acct_grp  IS INITIAL. rs_control-cust_acct_grp  = zif_bp_cust_types=>c_default-cust_acct_grp.  ENDIF.
    IF rs_control-industry_system IS INITIAL. rs_control-industry_system = zif_bp_cust_types=>c_default-industry_system. ENDIF.
    IF rs_control-default_country IS INITIAL. rs_control-default_country = zif_bp_cust_types=>c_default-country.       ENDIF.
  ENDMETHOD.


  METHOD build_cvi.
    DATA(ls_ctrl) = resolve_control( is_request ).
    DATA(ls_ci)   = is_request-company_info.
    DATA ls_bp    TYPE cvis_ei_extern.

    "================================================================
    " PARTNER  (organisation, internal number)
    "================================================================
    ls_bp-partner-header-object_task = zif_bp_cust_types=>c_task-insert.

    " ---- category + grouping ---- VERIFY NODE
    ls_bp-partner-central_data-common-data-bp_control-category  = ls_ctrl-bp_category.
    ls_bp-partner-central_data-common-data-bp_control-grouping  = ls_ctrl-bp_grouping.
    ls_bp-partner-central_data-common-datax-bp_control-category = abap_true.
    ls_bp-partner-central_data-common-datax-bp_control-grouping = abap_true.

    " ---- organisation name (split at 40) ---- VERIFY NODE
    ls_bp-partner-central_data-common-data-bp_organization-name1  = ls_ci-business_name(40).
    ls_bp-partner-central_data-common-data-bp_organization-name2  = ls_ci-business_name+40.
    ls_bp-partner-central_data-common-datax-bp_organization-name1 = abap_true.
    ls_bp-partner-central_data-common-datax-bp_organization-name2 = abap_true.

    " ---- search terms: customerId / applicationId ---- VERIFY NODE
    ls_bp-partner-central_data-common-data-bp_centraldata-searchterm1  = is_request-customer_id.
    ls_bp-partner-central_data-common-data-bp_centraldata-searchterm2  = is_request-application_id(20).
    ls_bp-partner-central_data-common-datax-bp_centraldata-searchterm1 = abap_true.
    ls_bp-partner-central_data-common-datax-bp_centraldata-searchterm2 = abap_true.

    " ---- legal form / BP type (control keys, else warn) ----
    IF ls_ctrl-legal_form IS NOT INITIAL.
      ls_bp-partner-central_data-common-data-bp_organization-legalform  = ls_ctrl-legal_form.
      ls_bp-partner-central_data-common-datax-bp_organization-legalform = abap_true.
    ELSEIF ls_ci-business_type IS NOT INITIAL.
      warn( |businessType "{ ls_ci-business_type }" not mapped to a legal form (control.legalForm)| ).
    ENDIF.

    IF ls_ctrl-bp_type IS NOT INITIAL.
      ls_bp-partner-central_data-common-data-bp_centraldata-partnertype  = ls_ctrl-bp_type.
      ls_bp-partner-central_data-common-datax-bp_centraldata-partnertype = abap_true.
    ELSEIF ls_ci-grade_type IS NOT INITIAL.
      warn( |gradeType not mapped to a BP type (control.bpType)| ).
    ENDIF.

    " ---- address ---- VERIFY NODE
    DATA(ls_padr) = zcl_bp_cust_mapper=>parse_address( iv_text    = ls_ci-hq_address
                                                       iv_country = ls_ctrl-default_country ).
    DATA ls_addr TYPE bus_ei_bupa_address.
    ls_addr-task                      = zif_bp_cust_types=>c_task-insert.
    ls_addr-data-postal-data-c_o_name = condense( |{ ls_ci-first_name } { ls_ci-last_name }| ).
    ls_addr-data-postal-data-street   = ls_padr-street.
    ls_addr-data-postal-data-city     = ls_padr-city.
    ls_addr-data-postal-data-country  = ls_padr-country.
    ls_addr-data-postal-data-langu    = sy-langu.
    ls_addr-data-postal-datax-c_o_name = abap_true.
    ls_addr-data-postal-datax-street   = abap_true.
    ls_addr-data-postal-datax-city     = abap_true.
    ls_addr-data-postal-datax-country  = abap_true.
    ls_addr-data-postal-datax-langu    = abap_true.

    IF ls_ci-email IS NOT INITIAL.
      APPEND VALUE #( contact-task  = zif_bp_cust_types=>c_task-insert
                      contact-data  = VALUE #( e_mail = ls_ci-email std_no = abap_true )
                      contact-datax = VALUE #( e_mail = abap_true    std_no = abap_true ) )
             TO ls_addr-data-communication-smtp-smtp.
    ENDIF.
    IF ls_ci-mobile IS NOT INITIAL.
      APPEND VALUE #( contact-task  = zif_bp_cust_types=>c_task-insert
                      contact-data  = VALUE #( telephone = ls_ci-mobile r_3_user = '3' std_no = abap_true )
                      contact-datax = VALUE #( telephone = abap_true r_3_user = abap_true std_no = abap_true ) )
             TO ls_addr-data-communication-phone-phone.
    ENDIF.
    APPEND ls_addr TO ls_bp-partner-central_data-address-addresses.

    " ---- role ---- VERIFY NODE
    APPEND VALUE #( task     = zif_bp_cust_types=>c_task-insert
                    data_key = ls_ctrl-partner_role
                    data     = VALUE #( rolecategory = ls_ctrl-partner_role
                                        valid_from   = sy-datum ) )
           TO ls_bp-partner-central_data-role-roles.

    " ---- tax number (TIN / VAT) ---- VERIFY NODE
    IF ls_ci-tin_vat_reg_no IS NOT INITIAL AND ls_ctrl-tax_type_tin IS NOT INITIAL.
      APPEND VALUE #( task     = zif_bp_cust_types=>c_task-insert
                      data_key = VALUE #( taxtype   = ls_ctrl-tax_type_tin
                                          taxnumber = ls_ci-tin_vat_reg_no ) )
             TO ls_bp-partner-central_data-taxnumber-taxnumbers.
    ELSEIF ls_ci-tin_vat_reg_no IS NOT INITIAL.
      warn( |tinVatRegNo supplied but control.taxTypeTin is empty - not stored| ).
    ENDIF.

    " ---- identification: company registration number ---- VERIFY NODE
    IF ls_ci-company_reg_no IS NOT INITIAL AND ls_ctrl-id_type_reg IS NOT INITIAL.
      APPEND VALUE #( task     = zif_bp_cust_types=>c_task-insert
                      data_key = VALUE #( identificationcategory = ls_ctrl-id_type_reg
                                          identificationnumber   = ls_ci-company_reg_no )
                      data     = VALUE #( identificationtype = ls_ctrl-id_type_reg
                                          entrydate          = sy-datum ) )
             TO ls_bp-partner-central_data-identification-identification.
    ELSEIF ls_ci-company_reg_no IS NOT INITIAL.
      warn( |companyRegNo supplied but control.idTypeReg is empty - not stored| ).
    ENDIF.

    " ---- industries (natureOfBusiness + product[]) ---- VERIFY NODE
    LOOP AT ls_ctrl-industry_keys INTO DATA(lv_ind).
      APPEND VALUE #( task     = zif_bp_cust_types=>c_task-insert
                      data_key = VALUE #( indsector      = ls_ctrl-industry_system
                                          industrysector = lv_ind )
                      data     = VALUE #( ind_sector_std = abap_true ) )
             TO ls_bp-partner-central_data-industrysector-industrysectors.
    ENDLOOP.
    IF ls_ctrl-industry_keys IS INITIAL
       AND ( ls_ci-nature_of_business IS NOT INITIAL OR ls_ci-product IS NOT INITIAL ).
      warn( |natureOfBusiness / product not mapped to industry keys (control.industryKeys)| ).
    ENDIF.

    "================================================================
    " CUSTOMER  (FLCU01)
    "   The customer master is auto-created by CVI from the role above;
    "   the account group is derived from the BP grouping via CVI
    "   Customizing. The customer node is only filled explicitly when
    "   an account group override or FI / sales data is requested.
    "================================================================
    IF ls_ctrl-cust_acct_grp IS NOT INITIAL
       OR ls_ctrl-create_fi = abap_true
       OR ls_ctrl-create_sales = abap_true.

      ls_bp-customer-header-object_task = zif_bp_cust_types=>c_task-insert.

      IF ls_ctrl-cust_acct_grp IS NOT INITIAL.
        " VERIFY NODE: on some S/4 releases this is -central-data-kna1-ktokd
        ls_bp-customer-central_data-central-data-ktokd  = ls_ctrl-cust_acct_grp.
        ls_bp-customer-central_data-central-datax-ktokd = abap_true.
      ENDIF.

      IF ls_ctrl-create_sales = abap_true AND ls_ctrl-sales_org IS NOT INITIAL.
        APPEND VALUE #( task     = zif_bp_cust_types=>c_task-insert
                        data_key = VALUE #( vkorg = ls_ctrl-sales_org
                                            vtweg = ls_ctrl-distr_channel
                                            spart = ls_ctrl-division ) )
               TO ls_bp-customer-central_data-sales_data-sales.
      ENDIF.

      IF ls_ctrl-create_fi = abap_true AND ls_ctrl-company_code IS NOT INITIAL.
        APPEND VALUE #( task      = zif_bp_cust_types=>c_task-insert
                        data_key  = VALUE #( bukrs = ls_ctrl-company_code )
                        data-akont  = ls_ctrl-recon_acct
                        datax-akont = abap_true )
               TO ls_bp-customer-central_data-company_data-company.
      ENDIF.
    ENDIF.

    APPEND ls_bp TO rt_data.
  ENDMETHOD.


  METHOD has_error.
    LOOP AT it_return INTO DATA(ls_obj).
      LOOP AT ls_obj-object_msg TRANSPORTING NO FIELDS WHERE type = 'E' OR type = 'A'.
        rv_error = abap_true.
        RETURN.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD map_return.
    LOOP AT it_return INTO DATA(ls_obj).
      LOOP AT ls_obj-object_msg INTO DATA(ls_msg).
        APPEND VALUE #( type    = ls_msg-type
                        id      = ls_msg-id
                        number  = ls_msg-number
                        message = ls_msg-message
                        field   = ls_msg-field ) TO rt_message.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD keys_after_commit.
    DATA(lv_partner) = zcl_bp_cust_mapper=>resolve_partner( iv_customer_id ).
    cs_result-partner  = lv_partner.
    cs_result-customer = zcl_bp_cust_mapper=>resolve_customer( lv_partner ).
    SELECT SINGLE partner_guid FROM but000
      INTO @cs_result-partner_guid
      WHERE partner = @lv_partner.
  ENDMETHOD.

ENDCLASS.

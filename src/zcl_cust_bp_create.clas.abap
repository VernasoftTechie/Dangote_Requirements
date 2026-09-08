"! <p class="shorttext synchronized">Customer BP API - create customer BP</p>
"! Maps the JSON payload ( ZCUST_BP_S_CREATE_REQ ) to the CVI structure
"! CVIS_EI_EXTERN and creates an <em>organisation</em> business partner with
"! the customer role via <em>CL_MD_BP_MAINTAIN=&gt;MAINTAIN</em> ( internal
"! number assignment ).
"!
"! Flow: authorize -&gt; validate -&gt; idempotency check -&gt;
"! <em>CL_MD_BP_MAINTAIN=&gt;VALIDATE_SINGLE</em> ( simulation, no update ) -&gt;
"! only if the simulation is clean: <em>MAINTAIN</em> + <em>BAPI_TRANSACTION_COMMIT</em>.
"! Every branch writes ZCUST_BP_LOG and returns <em>success</em> + <em>messages</em>.
"!
"! The external <em>customerId</em> is stored in search term 1
"! ( BUT000-BU_SORT1 ); <em>applicationId</em> in search term 2. Deep component
"! paths in CVIS_EI_EXTERN are release dependent - flagged "VERIFY NODE";
"! see docs/05_verification_checklist.md.
CLASS zcl_cust_bp_create DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS execute
      IMPORTING is_request       TYPE zcust_bp_s_create_req
                iv_raw_json      TYPE string    OPTIONAL
                iv_write_log     TYPE abap_bool DEFAULT abap_true
      RETURNING VALUE(rs_result) TYPE zcust_bp_s_create_res.

    "! Exposed for ABAP Unit - pure mapping, no DB / no commit.
    METHODS build_cvi
      IMPORTING is_request     TYPE zcust_bp_s_create_req
      RETURNING VALUE(rt_data) TYPE cvis_ei_extern_t.

    METHODS resolve_control
      IMPORTING is_request       TYPE zcust_bp_s_create_req
      RETURNING VALUE(rs_control) TYPE zcust_bp_s_control.

  PRIVATE SECTION.
    DATA mt_warning TYPE zcust_bp_t_message.

    METHODS validate
      IMPORTING is_request TYPE zcust_bp_s_create_req
      RAISING   zcx_cust_bp.

    METHODS check_authorization
      RAISING zcx_cust_bp.

    METHODS warn
      IMPORTING iv_text TYPE string.

    "! Extension point for release-dependent CVI nodes ( legal form, BP type,
    "! identification, industry ). Ships as warnings; complete per S/4 release.
    METHODS enrich_optional
      IMPORTING is_request TYPE zcust_bp_s_create_req
                is_control TYPE zcust_bp_s_control
      CHANGING  cs_bp      TYPE cvis_ei_extern.

    "! Simulation via CL_MD_BP_MAINTAIN=>VALIDATE_SINGLE - no database update.
    METHODS simulate
      IMPORTING it_data      TYPE cvis_ei_extern_t
      EXPORTING et_message   TYPE zcust_bp_t_message
                ev_has_error TYPE abap_bool.

    METHODS has_error
      IMPORTING it_return       TYPE bapiretm
      RETURNING VALUE(rv_error) TYPE abap_bool.

    METHODS map_return
      IMPORTING it_return         TYPE bapiretm
      RETURNING VALUE(rt_message) TYPE zcust_bp_t_message.

    METHODS write_log
      IMPORTING is_request  TYPE zcust_bp_s_create_req
                iv_raw_json TYPE string
                iv_status   TYPE c LENGTH 1
                iv_http     TYPE i
      CHANGING  cs_result   TYPE zcust_bp_s_create_res.

    METHODS keys_after_commit
      IMPORTING iv_customer_id TYPE zcust_bp_id
      CHANGING  cs_result      TYPE zcust_bp_s_create_res.
ENDCLASS.


CLASS zcl_cust_bp_create IMPLEMENTATION.

  METHOD execute.
    rs_result-customer_id = is_request-customer_id.
    CLEAR mt_warning.

    TRY.
        check_authorization( ).
        validate( is_request ).

        " ---- idempotency: customerId already mapped to a BP? ----
        DATA(lv_existing) = zcl_cust_bp_mapper=>resolve_partner( is_request-customer_id ).
        IF lv_existing IS NOT INITIAL.
          rs_result-partner  = lv_existing.
          rs_result-customer = zcl_cust_bp_mapper=>resolve_customer( lv_existing ).
          rs_result-success  = abap_true.
          APPEND VALUE #( type    = 'W'
                          id      = zif_cust_bp_types=>c_msg_class
                          msgno   = '004'
                          message = |Customer { is_request-customer_id } already exists (BP { lv_existing })| )
                 TO rs_result-messages.
          IF iv_write_log = abap_true.
            write_log( EXPORTING is_request  = is_request
                                 iv_raw_json = iv_raw_json
                                 iv_status   = zif_cust_bp_types=>c_log_status-success
                                 iv_http     = zif_cust_bp_types=>c_http-ok
                       CHANGING  cs_result   = rs_result ).
          ENDIF.
          RETURN.
        ENDIF.

        DATA(lt_data) = build_cvi( is_request ).

        " ---- 1. simulation ( VALIDATE_SINGLE ) - no update ----
        simulate( EXPORTING it_data      = lt_data
                  IMPORTING et_message   = DATA(lt_sim_msg)
                            ev_has_error = DATA(lv_sim_error) ).
        APPEND LINES OF lt_sim_msg TO rs_result-messages.
        APPEND LINES OF mt_warning TO rs_result-messages.

        IF lv_sim_error = abap_true.
          rs_result-success = abap_false.
          APPEND VALUE #( type    = 'E'
                          id      = zif_cust_bp_types=>c_msg_class
                          msgno   = '019'
                          message = |Simulation reported errors for external ID { is_request-customer_id } - nothing was created| )
                 TO rs_result-messages.
          IF iv_write_log = abap_true.
            write_log( EXPORTING is_request  = is_request
                                 iv_raw_json = iv_raw_json
                                 iv_status   = zif_cust_bp_types=>c_log_status-error
                                 iv_http     = zif_cust_bp_types=>c_http-unprocessable
                       CHANGING  cs_result   = rs_result ).
          ENDIF.
          RETURN.
        ENDIF.

        " ---- 2. real maintain ----
        DATA lt_return TYPE bapiretm.
        cl_md_bp_maintain=>maintain(
          EXPORTING i_data   = lt_data
          IMPORTING e_return = lt_return ).
        APPEND LINES OF map_return( lt_return ) TO rs_result-messages.

        IF has_error( lt_return ) = abap_true.
          CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
          rs_result-success = abap_false.
          IF iv_write_log = abap_true.
            write_log( EXPORTING is_request  = is_request
                                 iv_raw_json = iv_raw_json
                                 iv_status   = zif_cust_bp_types=>c_log_status-error
                                 iv_http     = zif_cust_bp_types=>c_http-unprocessable
                       CHANGING  cs_result   = rs_result ).
          ENDIF.
          RETURN.
        ENDIF.

        CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
          EXPORTING wait = abap_true.

        keys_after_commit( EXPORTING iv_customer_id = is_request-customer_id
                           CHANGING  cs_result      = rs_result ).
        rs_result-success = abap_true.

        IF NOT line_exists( rs_result-messages[ type = 'S' ] )
           AND NOT line_exists( rs_result-messages[ type = 'I' ] ).
          INSERT VALUE #( type    = 'S'
                          id      = zif_cust_bp_types=>c_msg_class
                          msgno   = '017'
                          message = |Business partner { rs_result-partner } (customer { rs_result-customer }) | &&
                                    |created for external ID { is_request-customer_id }| )
                 INTO rs_result-messages INDEX 1.
        ENDIF.

        IF iv_write_log = abap_true.
          write_log( EXPORTING is_request  = is_request
                               iv_raw_json = iv_raw_json
                               iv_status   = zif_cust_bp_types=>c_log_status-success
                               iv_http     = zif_cust_bp_types=>c_http-created
                     CHANGING  cs_result   = rs_result ).
        ENDIF.

      CATCH zcx_cust_bp INTO DATA(lx).
        rs_result-success = abap_false.
        APPEND VALUE #( type    = 'E'
                        id      = lx->if_t100_message~t100key-msgid
                        msgno   = lx->if_t100_message~t100key-msgno
                        message = lx->get_text( ) ) TO rs_result-messages.
        IF iv_write_log = abap_true.
          write_log( EXPORTING is_request  = is_request
                               iv_raw_json = iv_raw_json
                               iv_status   = zif_cust_bp_types=>c_log_status-error
                               iv_http     = lx->http_status
                     CHANGING  cs_result   = rs_result ).
        ENDIF.
    ENDTRY.
  ENDMETHOD.


  METHOD check_authorization.
    AUTHORITY-CHECK OBJECT zif_cust_bp_types=>c_auth-object
      ID 'RLTYP' FIELD zif_cust_bp_types=>c_default-partner_role
      ID 'ACTVT' FIELD zif_cust_bp_types=>c_auth-actvt_01.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_cust_bp
        MESSAGE e016(zmsg_cust_bp) WITH zif_cust_bp_types=>c_auth-object.
    ENDIF.
  ENDMETHOD.


  METHOD validate.
    IF is_request-customer_id IS INITIAL.
      RAISE EXCEPTION TYPE zcx_cust_bp
        MESSAGE e003(zmsg_cust_bp) WITH 'customerId'.
    ENDIF.
    IF is_request-business_name IS INITIAL.
      RAISE EXCEPTION TYPE zcx_cust_bp
        MESSAGE e003(zmsg_cust_bp) WITH 'businessName'.
    ENDIF.

    DATA(ls_ctrl) = resolve_control( is_request ).
    IF ls_ctrl-bp_grouping IS INITIAL.
      RAISE EXCEPTION TYPE zcx_cust_bp
        MESSAGE e012(zmsg_cust_bp) WITH 'bpGrouping'.
    ENDIF.
    IF ls_ctrl-cust_acct_grp IS INITIAL
       AND ( ls_ctrl-create_fi = abap_true OR ls_ctrl-create_sales = abap_true ).
      RAISE EXCEPTION TYPE zcx_cust_bp
        MESSAGE e012(zmsg_cust_bp) WITH 'custAcctGrp'.
    ENDIF.
  ENDMETHOD.


  METHOD warn.
    APPEND VALUE #( type = 'W' message = iv_text ) TO mt_warning.
  ENDMETHOD.


  METHOD resolve_control.
    rs_control = CORRESPONDING #( is_request ).
    IF rs_control-bp_category     IS INITIAL. rs_control-bp_category     = zif_cust_bp_types=>c_default-bp_category.     ENDIF.
    IF rs_control-bp_grouping     IS INITIAL. rs_control-bp_grouping     = zif_cust_bp_types=>c_default-bp_grouping.     ENDIF.
    IF rs_control-partner_role    IS INITIAL. rs_control-partner_role    = zif_cust_bp_types=>c_default-partner_role.    ENDIF.
    IF rs_control-cust_acct_grp   IS INITIAL. rs_control-cust_acct_grp   = zif_cust_bp_types=>c_default-cust_acct_grp.   ENDIF.
    IF rs_control-industry_system IS INITIAL. rs_control-industry_system = zif_cust_bp_types=>c_default-industry_system. ENDIF.
    IF rs_control-default_country IS INITIAL. rs_control-default_country = zif_cust_bp_types=>c_default-country.         ENDIF.
  ENDMETHOD.


  METHOD build_cvi.
    " All component paths below are taken from working productive
    " CL_MD_BP_MAINTAIN examples ( see docs/05_verification_checklist.md ).
    " Legal form, BP type, identification and industry sectors are handled
    " in enrich_optional( ) - a documented extension point - because their
    " CVI node names differ between S/4 releases.
    DATA(ls_ctrl) = resolve_control( is_request ).
    DATA ls_bp    TYPE cvis_ei_extern.
    DATA ls_addr  TYPE bus_ei_bupa_address.

    "================================================================
    " PARTNER  ( organisation, internal number )
    "================================================================
    ls_bp-partner-header-object_task = zif_cust_bp_types=>c_task-insert.

    " ---- category + grouping ----
    ls_bp-partner-central_data-common-data-bp_control-category  = ls_ctrl-bp_category.
    ls_bp-partner-central_data-common-data-bp_control-grouping  = ls_ctrl-bp_grouping.
    ls_bp-partner-central_data-common-datax-bp_control-category = abap_true.
    ls_bp-partner-central_data-common-datax-bp_control-grouping = abap_true.

    " ---- organisation name ( split at 40 ) ----
    ls_bp-partner-central_data-common-data-bp_organization-name1  = is_request-business_name(40).
    ls_bp-partner-central_data-common-data-bp_organization-name2  = is_request-business_name+40(40).
    ls_bp-partner-central_data-common-datax-bp_organization-name1 = abap_true.
    ls_bp-partner-central_data-common-datax-bp_organization-name2 = abap_true.

    " ---- search terms: customerId / applicationId ----
    ls_bp-partner-central_data-common-data-bp_centraldata-searchterm1  = is_request-customer_id.
    ls_bp-partner-central_data-common-data-bp_centraldata-searchterm2  = is_request-application_id(20).
    ls_bp-partner-central_data-common-datax-bp_centraldata-searchterm1 = abap_true.
    ls_bp-partner-central_data-common-datax-bp_centraldata-searchterm2 = abap_true.

    " ---- address ----
    zcl_cust_bp_mapper=>parse_address(
      EXPORTING iv_text    = is_request-hq_address
                iv_country = ls_ctrl-default_country
      IMPORTING ev_street  = DATA(lv_street)
                ev_city    = DATA(lv_city)
                ev_country = DATA(lv_country) ).

    ls_addr-task                      = zif_cust_bp_types=>c_task-insert.
    ls_addr-data_key-operation        = 'XXDFLT'.
    ls_addr-data-postal-data-street   = lv_street.
    ls_addr-data-postal-data-city     = lv_city.
    ls_addr-data-postal-data-country  = lv_country.
    ls_addr-data-postal-data-langu    = sy-langu.
    ls_addr-data-postal-datax-street  = abap_true.
    ls_addr-data-postal-datax-city    = abap_true.
    ls_addr-data-postal-datax-country = abap_true.
    ls_addr-data-postal-datax-langu   = abap_true.

    IF is_request-email IS NOT INITIAL.
      APPEND VALUE #( contact-task  = zif_cust_bp_types=>c_task-insert
                      contact-data  = VALUE #( e_mail = is_request-email )
                      contact-datax = VALUE #( e_mail = abap_true ) )
             TO ls_addr-data-communication-smtp-smtp.
    ENDIF.
    IF is_request-mobile IS NOT INITIAL.
      APPEND VALUE #( contact-task  = zif_cust_bp_types=>c_task-insert
                      contact-data  = VALUE #( telephone = is_request-mobile r_3_user = '3' )
                      contact-datax = VALUE #( telephone = abap_true r_3_user = abap_true ) )
             TO ls_addr-data-communication-phone-phone.
    ENDIF.
    APPEND ls_addr TO ls_bp-partner-central_data-address-addresses.

    " ---- role ----
    APPEND VALUE #( task     = zif_cust_bp_types=>c_task-insert
                    data_key = ls_ctrl-partner_role )
           TO ls_bp-partner-central_data-role-roles.

    " ---- tax number ( TIN / VAT ) ----
    IF is_request-tin_vat_reg_no IS NOT INITIAL AND ls_ctrl-tax_type_tin IS NOT INITIAL.
      APPEND VALUE #( task     = zif_cust_bp_types=>c_task-insert
                      data_key = VALUE #( taxtype   = ls_ctrl-tax_type_tin
                                          taxnumber = is_request-tin_vat_reg_no ) )
             TO ls_bp-partner-central_data-taxnumber-taxnumbers.
    ELSEIF is_request-tin_vat_reg_no IS NOT INITIAL.
      warn( |tinVatRegNo supplied but taxTypeTin is empty - not stored| ).
    ENDIF.

    " ---- release-dependent enrichment ( extension point ) ----
    enrich_optional( EXPORTING is_request = is_request
                               is_control = ls_ctrl
                     CHANGING  cs_bp      = ls_bp ).

    "================================================================
    " CUSTOMER  ( FLCU01 )  - only filled when an account-group
    " override or FI / sales data is requested; otherwise CVI
    " auto-creates the customer from the role above.
    "================================================================
    IF ls_ctrl-cust_acct_grp IS NOT INITIAL
       OR ls_ctrl-create_fi = abap_true
       OR ls_ctrl-create_sales = abap_true.

      ls_bp-customer-header-object_task = zif_cust_bp_types=>c_task-insert.

      IF ls_ctrl-cust_acct_grp IS NOT INITIAL.
        ls_bp-customer-central_data-central-data-ktokd  = ls_ctrl-cust_acct_grp.
        ls_bp-customer-central_data-central-datax-ktokd = abap_true.
      ENDIF.

      IF ls_ctrl-create_sales = abap_true AND ls_ctrl-sales_org IS NOT INITIAL.
        APPEND VALUE #( task     = zif_cust_bp_types=>c_task-insert
                        data_key = VALUE #( vkorg = ls_ctrl-sales_org
                                            vtweg = ls_ctrl-distr_channel
                                            spart = ls_ctrl-division ) )
               TO ls_bp-customer-sales_data-sales.
      ENDIF.

      IF ls_ctrl-create_fi = abap_true AND ls_ctrl-company_code IS NOT INITIAL.
        APPEND VALUE #( task     = zif_cust_bp_types=>c_task-insert
                        data_key = VALUE #( bukrs = ls_ctrl-company_code ) )
               TO ls_bp-customer-company_data-company.
      ENDIF.
    ENDIF.

    APPEND ls_bp TO rt_data.
  ENDMETHOD.


  METHOD enrich_optional.
    "! EXTENSION POINT - complete against your S/4 release's CVIS_EI_EXTERN.
    "! Each block is release dependent; verify the node / field names in SE11
    "! ( type BUS_EI_EXTERN ) and un-comment. Until then the values are
    "! reported back as W messages so nothing is silently lost.
    "!
    "! Legal form   -> partner-central_data-common-data-bp_organization-legalform (+ datax)
    "! BP type      -> partner-central_data-common-data-bp_centraldata-partnertype (+ datax)
    "! Identification-> partner-central_data-ident_number-ident_numbers, line:
    "!                    task, data_key-identificationcategory,
    "!                    data_key-identificationnumber, data-identrydate
    "! Industry     -> partner-central_data-industrysector-industrysectors, line:
    "!                    task, data_key-indsector, data_key-industrysector

    IF is_control-legal_form IS NOT INITIAL OR is_request-business_type IS NOT INITIAL.
      warn( |legalForm / businessType not written - complete enrich_optional( ) for your release| ).
    ENDIF.
    IF is_control-bp_type IS NOT INITIAL OR is_request-grade_type IS NOT INITIAL.
      warn( |bpType / gradeType not written - complete enrich_optional( ) for your release| ).
    ENDIF.
    IF is_request-company_reg_no IS NOT INITIAL.
      warn( |companyRegNo not written - complete enrich_optional( ) for your release| ).
    ENDIF.
    IF is_request-industry_keys IS NOT INITIAL
       OR is_request-nature_of_business IS NOT INITIAL
       OR is_request-product IS NOT INITIAL.
      warn( |natureOfBusiness / product / industryKeys not written - complete enrich_optional( )| ).
    ENDIF.
  ENDMETHOD.


  METHOD simulate.
    CLEAR: et_message, ev_has_error.
    IF it_data IS INITIAL.
      RETURN.
    ENDIF.

    " VALIDATE_SINGLE takes a single CVIS_EI_EXTERN and never updates the DB.
    " et_return_map is MDG_BS_BP_MSGMAP_T ( BAPIRET2-compatible message rows ).
    cl_md_bp_maintain=>validate_single(
      EXPORTING i_data        = it_data[ 1 ]
      IMPORTING et_return_map = DATA(lt_map) ).

    LOOP AT lt_map INTO DATA(ls_map).
      APPEND VALUE #( type    = ls_map-type
                      id      = ls_map-id
                      msgno   = ls_map-number
                      message = ls_map-message
                      field   = ls_map-field ) TO et_message.
      IF ls_map-type = 'E' OR ls_map-type = 'A'.
        ev_has_error = abap_true.
      ENDIF.
    ENDLOOP.
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
                        msgno   = ls_msg-number
                        message = ls_msg-message
                        field   = ls_msg-field ) TO rt_message.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD write_log.
    cs_result-log_id = zcl_cust_bp_log=>record(
      iv_operation      = zif_cust_bp_types=>c_operation-create
      iv_customer_id    = is_request-customer_id
      iv_application_id = is_request-application_id
      iv_ext_status     = is_request-status
      iv_status         = iv_status
      iv_http_status    = iv_http
      iv_raw_json       = iv_raw_json
      is_result         = cs_result
      it_messages       = cs_result-messages ).
  ENDMETHOD.


  METHOD keys_after_commit.
    DATA(lv_partner) = zcl_cust_bp_mapper=>resolve_partner( iv_customer_id ).
    cs_result-partner  = lv_partner.
    cs_result-customer = zcl_cust_bp_mapper=>resolve_customer( lv_partner ).
    SELECT SINGLE partner_guid FROM but000
      INTO @cs_result-partner_guid
      WHERE partner = @lv_partner.
  ENDMETHOD.

ENDCLASS.

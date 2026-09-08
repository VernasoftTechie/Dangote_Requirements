"! ABAP Unit - payload -> CVIS_EI_EXTERN mapping and validation.
"! Pure logic only: build_cvi / resolve_control / validate touch no database
"! and issue no COMMIT.
CLASS zcl_bp_cust_create DEFINITION LOCAL FRIENDS ltcl_create.

CLASS ltcl_create DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO zcl_bp_cust_create.

    METHODS setup.
    METHODS request
      RETURNING VALUE(rs_req) TYPE zbp_cust_s_create_req.

    METHODS control_defaults_are_applied      FOR TESTING.
    METHODS control_explicit_values_win       FOR TESTING.
    METHODS build_sets_insert_task            FOR TESTING.
    METHODS build_maps_org_name_split         FOR TESTING.
    METHODS build_stores_ids_in_search_terms  FOR TESTING.
    METHODS build_adds_customer_role          FOR TESTING.
    METHODS build_adds_customer_node          FOR TESTING.
    METHODS validate_requires_business_name   FOR TESTING.
    METHODS validate_requires_grouping        FOR TESTING.
ENDCLASS.


CLASS ltcl_create IMPLEMENTATION.

  METHOD setup.
    mo_cut = NEW #( ).
  ENDMETHOD.

  METHOD request.
    rs_req = VALUE #(
      customer_id    = 'CUST-000123'
      application_id = '076b0117-0154-7561-b0f8-8785ce57d561'
      status         = 'Approved'
      company_info   = VALUE #(
        business_name      = 'Acme Ltd'
        tin_vat_reg_no     = '12345678-0001'
        nature_of_business = 'Manufacturing'
        business_type      = 'Limited Liability Company'
        company_reg_no     = 'RC123456'
        hq_address         = '1 Marina Road, Lagos'
        first_name         = 'Ada'
        last_name          = 'Lovelace'
        email              = 'ada@acme.com'
        mobile             = '+2348012345678'
        product            = VALUE #( ( `Oil and Gas` ) )
        grade_type         = VALUE #( ( `Domestic` ) ) )
      control        = VALUE #(
        bp_grouping   = 'BP02'
        cust_acct_grp = '0001'
        tax_type_tin  = 'ZTIN'
        id_type_reg   = 'ZCRN' ) ).
  ENDMETHOD.


  METHOD control_defaults_are_applied.
    DATA(ls_req) = request( ).
    CLEAR ls_req-control-partner_role.
    DATA(ls_ctrl) = mo_cut->resolve_control( ls_req ).
    cl_abap_unit_assert=>assert_equals(
      exp = zif_bp_cust_types=>c_default-partner_role
      act = ls_ctrl-partner_role
      msg = 'partner role should fall back to the default' ).
    cl_abap_unit_assert=>assert_equals(
      exp = zif_bp_cust_types=>c_default-bp_category
      act = ls_ctrl-bp_category ).
  ENDMETHOD.


  METHOD control_explicit_values_win.
    DATA(ls_ctrl) = mo_cut->resolve_control( request( ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'BP02' act = ls_ctrl-bp_grouping ).
    cl_abap_unit_assert=>assert_equals( exp = '0001' act = ls_ctrl-cust_acct_grp ).
  ENDMETHOD.


  METHOD build_sets_insert_task.
    DATA(lt) = mo_cut->build_cvi( request( ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = zif_bp_cust_types=>c_task-insert
      act = lt[ 1 ]-partner-header-object_task ).
  ENDMETHOD.


  METHOD build_maps_org_name_split.
    DATA(lt) = mo_cut->build_cvi( request( ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = 'Acme Ltd'
      act = lt[ 1 ]-partner-central_data-common-data-bp_organization-name1 ).
  ENDMETHOD.


  METHOD build_stores_ids_in_search_terms.
    DATA(lt) = mo_cut->build_cvi( request( ) ).
    DATA(ls_central) = lt[ 1 ]-partner-central_data-common-data-bp_centraldata.
    cl_abap_unit_assert=>assert_equals( exp = 'CUST-000123' act = ls_central-searchterm1 ).
  ENDMETHOD.


  METHOD build_adds_customer_role.
    DATA(lt) = mo_cut->build_cvi( request( ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = 1
      act = lines( lt[ 1 ]-partner-central_data-role-roles ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = zif_bp_cust_types=>c_default-partner_role
      act = lt[ 1 ]-partner-central_data-role-roles[ 1 ]-data_key ).
  ENDMETHOD.


  METHOD build_adds_customer_node.
    " request() carries control-cust_acct_grp = '0001' -> customer node filled
    DATA(lt) = mo_cut->build_cvi( request( ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = zif_bp_cust_types=>c_task-insert
      act = lt[ 1 ]-customer-header-object_task ).
    cl_abap_unit_assert=>assert_equals(
      exp = '0001'
      act = lt[ 1 ]-customer-central_data-central-data-ktokd ).
  ENDMETHOD.


  METHOD validate_requires_business_name.
    DATA(ls_req) = request( ).
    CLEAR ls_req-company_info-business_name.
    TRY.
        mo_cut->validate( ls_req ).
        cl_abap_unit_assert=>fail( 'missing businessName must raise' ).
      CATCH zcx_bp_cust INTO DATA(lx).
        cl_abap_unit_assert=>assert_equals( exp = '003' act = lx->if_t100_message~t100key-msgno ).
    ENDTRY.
  ENDMETHOD.


  METHOD validate_requires_grouping.
    DATA(ls_req) = request( ).
    CLEAR ls_req-control-bp_grouping.
    TRY.
        mo_cut->validate( ls_req ).
        cl_abap_unit_assert=>fail( 'missing bpGrouping must raise' ).
      CATCH zcx_bp_cust INTO DATA(lx).
        cl_abap_unit_assert=>assert_equals( exp = '012' act = lx->if_t100_message~t100key-msgno ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

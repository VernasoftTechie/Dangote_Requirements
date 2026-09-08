"! ABAP Unit - routing decision and JSON contract round-trip.
CLASS ltcl_handler DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS post_routes_to_create   FOR TESTING.
    METHODS get_routes_to_read      FOR TESTING.
    METHODS put_is_not_supported    FOR TESTING.
    METHODS lowercase_method_ok     FOR TESTING.
    METHODS json_request_roundtrip  FOR TESTING.
    METHODS json_response_camelcase FOR TESTING.
ENDCLASS.


CLASS ltcl_handler IMPLEMENTATION.

  METHOD post_routes_to_create.
    cl_abap_unit_assert=>assert_equals(
      exp = zif_cust_bp_types=>c_operation-create
      act = zcl_cust_bp_icf_handler=>determine_action( 'POST' ) ).
  ENDMETHOD.

  METHOD get_routes_to_read.
    cl_abap_unit_assert=>assert_equals(
      exp = zif_cust_bp_types=>c_operation-read
      act = zcl_cust_bp_icf_handler=>determine_action( 'GET' ) ).
  ENDMETHOD.

  METHOD put_is_not_supported.
    cl_abap_unit_assert=>assert_initial(
      zcl_cust_bp_icf_handler=>determine_action( 'PUT' ) ).
  ENDMETHOD.

  METHOD lowercase_method_ok.
    cl_abap_unit_assert=>assert_equals(
      exp = zif_cust_bp_types=>c_operation-create
      act = zcl_cust_bp_icf_handler=>determine_action( 'post' ) ).
  ENDMETHOD.

  METHOD json_request_roundtrip.
    DATA(lv_json) =
      `{"customerId":"CUST-000123","applicationId":"076b0117",` &&
      `"status":"Approved","businessName":"Acme Ltd",` &&
      `"product":["Oil and Gas"],"email":"ada@acme.com",` &&
      `"bpGrouping":"BP02","custAcctGrp":"0001","createFi":true}`.

    DATA ls_req TYPE zcust_bp_s_create_req.
    /ui2/cl_json=>deserialize(
      EXPORTING json        = lv_json
                pretty_name = /ui2/cl_json=>pretty_mode-camel_case
      CHANGING  data        = ls_req ).

    cl_abap_unit_assert=>assert_equals( exp = 'CUST-000123' act = ls_req-customer_id ).
    cl_abap_unit_assert=>assert_equals( exp = 'Acme Ltd'    act = ls_req-business_name ).
    cl_abap_unit_assert=>assert_equals( exp = 'BP02'        act = ls_req-bp_grouping ).
    cl_abap_unit_assert=>assert_equals( exp = 1             act = lines( ls_req-product ) ).
    cl_abap_unit_assert=>assert_equals( exp = abap_true     act = ls_req-create_fi ).
  ENDMETHOD.

  METHOD json_response_camelcase.
    DATA(ls_res) = VALUE zcust_bp_s_create_res(
      customer_id = 'CUST-000123' partner = '0001000123' success = abap_true ).

    DATA(lv_out) = /ui2/cl_json=>serialize(
      data = ls_res pretty_name = /ui2/cl_json=>pretty_mode-camel_case compress = abap_false ).

    cl_abap_unit_assert=>assert_true( xsdbool( lv_out CS '"customerId"' ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( lv_out CS '"partner"' ) ).
  ENDMETHOD.

ENDCLASS.

"! ABAP Unit - free-text address parsing ( no database ).
CLASS ltcl_mapper DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS street_and_city_from_one_comma FOR TESTING.
    METHODS single_token_becomes_street    FOR TESTING.
    METHODS multi_comma_last_is_city       FOR TESTING.
    METHODS country_default_applied         FOR TESTING.
    METHODS empty_text_is_safe              FOR TESTING.
ENDCLASS.


CLASS ltcl_mapper IMPLEMENTATION.

  METHOD street_and_city_from_one_comma.
    zcl_cust_bp_mapper=>parse_address(
      EXPORTING iv_text    = '1 Marina Road, Lagos'
                iv_country = 'NG'
      IMPORTING ev_street  = DATA(lv_street)
                ev_city    = DATA(lv_city)
                ev_country = DATA(lv_country) ).
    cl_abap_unit_assert=>assert_equals( exp = '1 Marina Road' act = lv_street ).
    cl_abap_unit_assert=>assert_equals( exp = 'Lagos'         act = lv_city ).
    cl_abap_unit_assert=>assert_equals( exp = 'NG'            act = lv_country ).
  ENDMETHOD.

  METHOD single_token_becomes_street.
    zcl_cust_bp_mapper=>parse_address(
      EXPORTING iv_text   = '1 Marina Road'
      IMPORTING ev_street = DATA(lv_street)
                ev_city   = DATA(lv_city) ).
    cl_abap_unit_assert=>assert_equals( exp = '1 Marina Road' act = lv_street ).
    cl_abap_unit_assert=>assert_initial( lv_city ).
  ENDMETHOD.

  METHOD multi_comma_last_is_city.
    zcl_cust_bp_mapper=>parse_address(
      EXPORTING iv_text   = '1 Marina Road, Victoria Island, Lagos'
      IMPORTING ev_street = DATA(lv_street)
                ev_city   = DATA(lv_city) ).
    cl_abap_unit_assert=>assert_equals( exp = 'Lagos'         act = lv_city ).
    cl_abap_unit_assert=>assert_equals( exp = '1 Marina Road' act = lv_street ).
  ENDMETHOD.

  METHOD country_default_applied.
    zcl_cust_bp_mapper=>parse_address(
      EXPORTING iv_text    = 'x, y'
      IMPORTING ev_country = DATA(lv_country) ).
    cl_abap_unit_assert=>assert_equals(
      exp = CONV land1( zif_cust_bp_types=>c_default-country )
      act = lv_country ).
  ENDMETHOD.

  METHOD empty_text_is_safe.
    zcl_cust_bp_mapper=>parse_address(
      EXPORTING iv_text   = ''
      IMPORTING ev_street = DATA(lv_street)
                ev_city   = DATA(lv_city) ).
    cl_abap_unit_assert=>assert_initial( lv_street ).
    cl_abap_unit_assert=>assert_initial( lv_city ).
  ENDMETHOD.

ENDCLASS.

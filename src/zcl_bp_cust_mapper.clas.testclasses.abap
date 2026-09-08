"! ABAP Unit - free-text address parsing (no database).
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
    DATA(ls) = zcl_bp_cust_mapper=>parse_address(
                 iv_text = '1 Marina Road, Lagos' iv_country = 'NG' ).
    cl_abap_unit_assert=>assert_equals( exp = '1 Marina Road' act = ls-street ).
    cl_abap_unit_assert=>assert_equals( exp = 'Lagos'         act = ls-city ).
    cl_abap_unit_assert=>assert_equals( exp = 'NG'            act = ls-country ).
  ENDMETHOD.

  METHOD single_token_becomes_street.
    DATA(ls) = zcl_bp_cust_mapper=>parse_address( iv_text = '1 Marina Road' ).
    cl_abap_unit_assert=>assert_equals( exp = '1 Marina Road' act = ls-street ).
    cl_abap_unit_assert=>assert_initial( ls-city ).
  ENDMETHOD.

  METHOD multi_comma_last_is_city.
    DATA(ls) = zcl_bp_cust_mapper=>parse_address(
                 iv_text = '1 Marina Road, Victoria Island, Lagos' ).
    cl_abap_unit_assert=>assert_equals( exp = 'Lagos' act = ls-city ).
  ENDMETHOD.

  METHOD country_default_applied.
    DATA(ls) = zcl_bp_cust_mapper=>parse_address( iv_text = 'x, y' ).
    cl_abap_unit_assert=>assert_equals(
      exp = zif_bp_cust_types=>c_default-country act = ls-country ).
  ENDMETHOD.

  METHOD empty_text_is_safe.
    DATA(ls) = zcl_bp_cust_mapper=>parse_address( iv_text = '' ).
    cl_abap_unit_assert=>assert_initial( ls-street ).
    cl_abap_unit_assert=>assert_initial( ls-city ).
  ENDMETHOD.

ENDCLASS.

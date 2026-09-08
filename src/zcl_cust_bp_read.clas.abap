"! <p class="shorttext synchronized">Customer BP API - read customer BP</p>
"! Resolves the external <em>customerId</em> ( search term 1 ) to the linked
"! customer number and reads the customer master image via
"! <em>CMD_EI_API_EXTRACT=&gt;GET_DATA</em>, then maps it to ZCUST_BP_S_READ_RES.
CLASS zcl_cust_bp_read DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS execute
      IMPORTING iv_customer_id   TYPE zcust_bp_id
      RETURNING VALUE(rs_result) TYPE zcust_bp_s_read_res
      RAISING   zcx_cust_bp.
ENDCLASS.


CLASS zcl_cust_bp_read IMPLEMENTATION.

  METHOD execute.
    " ---- 1. external id -> BP ----
    DATA(lv_partner) = zcl_cust_bp_mapper=>resolve_partner( iv_customer_id ).
    IF lv_partner IS INITIAL.
      RAISE EXCEPTION TYPE zcx_cust_bp
        MESSAGE e006(zmsg_cust_bp) WITH iv_customer_id.
    ENDIF.

    " ---- 2. BP -> customer ----
    DATA(lv_customer) = zcl_cust_bp_mapper=>resolve_customer( lv_partner ).
    IF lv_customer IS INITIAL.
      RAISE EXCEPTION TYPE zcx_cust_bp
        MESSAGE e007(zmsg_cust_bp) WITH iv_customer_id lv_partner.
    ENDIF.

    " ---- 3. read the customer master image ----
    "   GET_DATA lives on CMD_EI_API_EXTRACT (CMD_EI_API itself has no
    "   GET_DATA). Signature: IS_MASTER_DATA (in) / ES_MASTER_DATA (out) /
    "   ES_ERROR. INITIALIZE clears the buffer so we read from the database.
    cmd_ei_api=>initialize( ).

    DATA(ls_in) = VALUE cmds_ei_main(
      customers = VALUE #( ( header = VALUE #(
                                object_task     = zif_cust_bp_types=>c_task-modify
                                object_instance = VALUE #( kunnr = lv_customer ) ) ) ) ).

    cmd_ei_api_extract=>get_data(
      EXPORTING
        is_master_data = ls_in
      IMPORTING
        es_master_data = DATA(ls_out)
        es_error       = DATA(ls_err) ).

    IF ls_out-customers IS INITIAL.
      RAISE EXCEPTION TYPE zcx_cust_bp
        MESSAGE e009(zmsg_cust_bp) WITH lv_customer.
    ENDIF.

    " ---- 4. map ----
    rs_result = zcl_cust_bp_mapper=>cvi_to_read_res(
                  iv_customer_id = iv_customer_id
                  iv_partner     = lv_partner
                  is_customer    = ls_out-customers[ 1 ] ).
  ENDMETHOD.

ENDCLASS.

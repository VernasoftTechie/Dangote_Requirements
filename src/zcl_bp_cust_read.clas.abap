"! <p class="shorttext synchronized">BP Customer ICF API - read customer BP</p>
"! Resolves the external <em>customerId</em> ( search term 1 ) to the linked
"! customer number and reads the customer master image via
"! <em>CMD_EI_API=&gt;GET_DATA</em>, then maps it to ZBP_CUST_S_READ_RES.
CLASS zcl_bp_cust_read DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS execute
      IMPORTING iv_customer_id   TYPE zbp_cust_id
      RETURNING VALUE(rs_result) TYPE zbp_cust_s_read_res
      RAISING   zcx_bp_cust.
ENDCLASS.


CLASS zcl_bp_cust_read IMPLEMENTATION.

  METHOD execute.
    " ---- 1. external id -> BP ----
    DATA(lv_partner) = zcl_bp_cust_mapper=>resolve_partner( iv_customer_id ).
    IF lv_partner IS INITIAL.
      RAISE EXCEPTION TYPE zcx_bp_cust
        MESSAGE e006(zbp_cust_msg) WITH iv_customer_id.
    ENDIF.

    " ---- 2. BP -> customer ----
    DATA(lv_customer) = zcl_bp_cust_mapper=>resolve_customer( lv_partner ).
    IF lv_customer IS INITIAL.
      RAISE EXCEPTION TYPE zcx_bp_cust
        MESSAGE e007(zbp_cust_msg) WITH iv_customer_id lv_partner.
    ENDIF.

    " ---- 3. CMD_EI_API=>GET_DATA (customer master image) ----
    "   Parameter names verified against S/4HANA: IS_MASTER_DATA (in) /
    "   ES_MASTER_DATA (out) / ES_ERROR. On some releases the read is
    "   delegated to CMD_EI_API_EXTRACT=>GET_DATA with the same signature.
    DATA(ls_in) = VALUE cmds_ei_main(
      customers = VALUE #( ( header = VALUE #(
                                object_task     = zif_bp_cust_types=>c_task-modify
                                object_instance = VALUE #( kunnr = lv_customer ) ) ) ) ).

    cmd_ei_api=>get_data(
      EXPORTING
        is_master_data = ls_in
      IMPORTING
        es_master_data = DATA(ls_out)
        es_error       = DATA(ls_err) ).

    IF ls_out-customers IS INITIAL.
      RAISE EXCEPTION TYPE zcx_bp_cust
        MESSAGE e009(zbp_cust_msg) WITH lv_customer.
    ENDIF.

    " ---- 4. map ----
    rs_result = zcl_bp_cust_mapper=>cvi_to_read_res(
                  iv_customer_id = iv_customer_id
                  iv_partner     = lv_partner
                  is_customer    = ls_out-customers[ 1 ] ).
  ENDMETHOD.

ENDCLASS.

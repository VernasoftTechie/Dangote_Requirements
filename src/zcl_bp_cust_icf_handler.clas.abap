"! <p class="shorttext synchronized">BP Customer ICF API - HTTP handler</p>
"! ICF handler for service node <em>/sap/bc/zbp_customer</em>.
"! <ul>
"! <li>POST  /sap/bc/zbp_customer                       -&gt; create customer BP</li>
"! <li>GET   /sap/bc/zbp_customer?customerId=CUST-000123 -&gt; read customer BP</li>
"! <li>GET   /sap/bc/zbp_customer/CUST-000123            -&gt; read customer BP</li>
"! </ul>
CLASS zcl_bp_cust_icf_handler DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_http_extension.

    "! Pure routing decision - exposed for ABAP Unit.
    CLASS-METHODS determine_action
      IMPORTING iv_method        TYPE string
      RETURNING VALUE(rv_action) TYPE string.

  PRIVATE SECTION.
    DATA mo_server TYPE REF TO if_http_server.

    METHODS do_create.
    METHODS do_read.

    METHODS get_customer_id
      RETURNING VALUE(rv_customer_id) TYPE zbp_cust_id.

    METHODS send
      IMPORTING iv_status TYPE i
                iv_body   TYPE string.

    METHODS error_json
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_json) TYPE string.
ENDCLASS.


CLASS zcl_bp_cust_icf_handler IMPLEMENTATION.

  METHOD determine_action.
    rv_action = SWITCH #( to_upper( iv_method )
                          WHEN zif_bp_cust_types=>c_method-post THEN zif_bp_cust_types=>c_operation-create
                          WHEN zif_bp_cust_types=>c_method-get  THEN zif_bp_cust_types=>c_operation-read
                          ELSE space ).
  ENDMETHOD.


  METHOD if_http_extension~handle_request.
    mo_server = server.
    DATA(lv_method) = to_upper( server->request->get_header_field( '~request_method' ) ).

    CASE determine_action( lv_method ).
      WHEN zif_bp_cust_types=>c_operation-create. do_create( ).
      WHEN zif_bp_cust_types=>c_operation-read.   do_read( ).
      WHEN OTHERS.
        send( iv_status = zif_bp_cust_types=>c_http-not_allowed
              iv_body   = error_json( |HTTP { lv_method } is not supported on this resource| ) ).
    ENDCASE.
  ENDMETHOD.


  METHOD do_create.
    DATA(lv_body) = mo_server->request->get_cdata( ).
    IF lv_body IS INITIAL.
      send( zif_bp_cust_types=>c_http-bad_request
            error_json( 'Request body is empty or not valid JSON' ) ).
      RETURN.
    ENDIF.

    DATA ls_req TYPE zbp_cust_s_create_req.
    TRY.
        /ui2/cl_json=>deserialize(
          EXPORTING json        = lv_body
                    pretty_name = /ui2/cl_json=>pretty_mode-camel_case
          CHANGING  data        = ls_req ).
      CATCH cx_root.
        send( zif_bp_cust_types=>c_http-bad_request
              error_json( 'Request body is empty or not valid JSON' ) ).
        RETURN.
    ENDTRY.

    DATA(ls_res) = NEW zcl_bp_cust_create( )->execute(
                     is_request = ls_req
                     iv_raw_json = lv_body ).

    DATA(lv_out) = /ui2/cl_json=>serialize(
                     data        = ls_res
                     pretty_name = /ui2/cl_json=>pretty_mode-camel_case
                     compress    = abap_false ).

    send( iv_status = COND #( WHEN ls_res-success = abap_true
                              THEN zif_bp_cust_types=>c_http-created
                              ELSE zif_bp_cust_types=>c_http-unprocessable )
          iv_body   = lv_out ).
  ENDMETHOD.


  METHOD do_read.
    DATA(lv_id) = get_customer_id( ).
    IF lv_id IS INITIAL.
      send( zif_bp_cust_types=>c_http-bad_request
            error_json( 'Query parameter customerId is required' ) ).
      RETURN.
    ENDIF.

    TRY.
        DATA(ls_res) = NEW zcl_bp_cust_read( )->execute( lv_id ).
        send( zif_bp_cust_types=>c_http-ok
              /ui2/cl_json=>serialize( data        = ls_res
                                       pretty_name = /ui2/cl_json=>pretty_mode-camel_case
                                       compress    = abap_false ) ).

      CATCH zcx_bp_cust INTO DATA(lx).
        DATA(lv_code) = COND i(
          WHEN lx->if_t100_message~t100key-msgno = '006'
            OR lx->if_t100_message~t100key-msgno = '007'
          THEN zif_bp_cust_types=>c_http-not_found
          ELSE lx->http_status ).
        send( lv_code error_json( lx->get_text( ) ) ).
    ENDTRY.
  ENDMETHOD.


  METHOD get_customer_id.
    rv_customer_id = mo_server->request->get_form_field( 'customerId' ).
    IF rv_customer_id IS NOT INITIAL.
      RETURN.
    ENDIF.
    " trailing path segment: /sap/bc/zbp_customer/CUST-000123
    DATA(lv_path) = mo_server->request->get_header_field( '~path_info' ).
    IF lv_path CA '/'.
      SPLIT lv_path AT '/' INTO TABLE DATA(lt_seg).
      DELETE lt_seg WHERE table_line IS INITIAL.
      IF lt_seg IS NOT INITIAL.
        rv_customer_id = lt_seg[ lines( lt_seg ) ].
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD send.
    mo_server->response->set_header_field( name  = 'Content-Type'
                                           value = zif_bp_cust_types=>c_content_json ).
    mo_server->response->set_status(
      code   = iv_status
      reason = SWITCH #( iv_status
                 WHEN zif_bp_cust_types=>c_http-ok            THEN 'OK'
                 WHEN zif_bp_cust_types=>c_http-created        THEN 'Created'
                 WHEN zif_bp_cust_types=>c_http-bad_request    THEN 'Bad Request'
                 WHEN zif_bp_cust_types=>c_http-not_found      THEN 'Not Found'
                 WHEN zif_bp_cust_types=>c_http-not_allowed    THEN 'Method Not Allowed'
                 WHEN zif_bp_cust_types=>c_http-unprocessable  THEN 'Unprocessable Entity'
                 ELSE 'Internal Server Error' ) ).
    mo_server->response->set_cdata( iv_body ).
  ENDMETHOD.


  METHOD error_json.
    rv_json = /ui2/cl_json=>serialize(
                data        = VALUE zbp_cust_s_create_res(
                                success  = abap_false
                                messages = VALUE #( ( type = 'E' message = iv_text ) ) )
                pretty_name = /ui2/cl_json=>pretty_mode-camel_case
                compress    = abap_false ).
  ENDMETHOD.

ENDCLASS.

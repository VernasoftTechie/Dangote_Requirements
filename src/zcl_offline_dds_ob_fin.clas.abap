"! <p class="shorttext synchronized">Offline DDS / TMS outbound - ICF REST handler</p>
"! Freestyle ICF handler (IF_HTTP_EXTENSION), stateless Basic Auth, no session logic.
"! CSRF handshake (needed by the PI/PO REST sender channel):
"! <ul>
"! <li>GET / HEAD with header <em>X-CSRF-Token: Fetch</em> -&gt; 200 + response header
"!     <em>x-csrf-token: &lt;token&gt;</em> (no function module is called)</li>
"! <li>POST &lt;SICF node&gt; -&gt; runs the offline TMS / eATC function modules for
"!     every section present in the JSON body (all sections are optional).
"!     A token sent in <em>X-CSRF-Token</em> is validated (403 if wrong / expired);
"!     a POST without a token is accepted unless GC_ENFORCE_TOKEN = abap_true.</li>
"! </ul>
"! The token is stateless (hash of user + client + hour), valid for the current and the
"! previous hour, so it survives without a server session. It is a handshake
"! compatibility token - the security boundary is Basic Auth over HTTPS.
"! Request keys (case-insensitive, no camel-case conversion):
"! create_trip, approve_trip, trip_id, dispatch_trip, fuelissue_trip, close_trip,
"! ISSUE_CNG1_OFFLINE, change_trip, cancel_trip, eATC_achnowledge, Change_eATC.
"! Response: { "LV_DOC_NO": .., "IT_PRINT_PREV": [..], "RETURN_MESSAGE": [..] }
CLASS zcl_offline_dds_ob_fin DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_http_extension.

  PRIVATE SECTION.

    TYPES:
      BEGIN OF ty_root,
        create_trip        TYPE ztms_create_trip,
        approve_trip       TYPE ztms_approve_trip,
        trip_id            TYPE ztrip_id,
        dispatch_trip      TYPE ztms_dispatch_trip,
        fuelissue_trip     TYPE ztms_fuelissue_trip,
        close_trip         TYPE ztms_close_trip,
        issue_cng1_offline TYPE ztms_issue_cng1_offline,
        change_trip        TYPE ztms_change_trip,
        cancel_trip        TYPE ztms_cancel_trip,
        eatc_achnowledge   TYPE zttsds_atc_offline,
        change_eatc        TYPE ztt_tms_change_eatc,
      END OF ty_root,

      BEGIN OF ty_response,
        lv_doc_no      TYPE zdoc_no,
        it_print_prev  TYPE tsfotf,
        return_message TYPE ztmtt_offline_trip_msg,
      END OF ty_response,

      BEGIN OF ty_error,
        error TYPE string,
      END OF ty_error.

    CONSTANTS:
      gc_method_post      TYPE string VALUE 'POST',
      gc_method_get       TYPE string VALUE 'GET',
      gc_method_head      TYPE string VALUE 'HEAD',
      gc_csrf_header      TYPE string VALUE 'x-csrf-token',
      gc_csrf_fetch       TYPE string VALUE 'FETCH',
      gc_csrf_salt        TYPE string VALUE 'ZCL_OFFLINE_DDS_OB_FIN',
      gc_enforce_token    TYPE abap_bool VALUE abap_false, " abap_true = POST without token -> 403
      gc_content_json     TYPE string VALUE 'application/json; charset=utf-8',
      gc_http_ok          TYPE i      VALUE 200,
      gc_http_bad_request TYPE i      VALUE 400,
      gc_http_forbidden   TYPE i      VALUE 403,
      gc_http_not_allowed TYPE i      VALUE 405,
      gc_http_server_err  TYPE i      VALUE 500,
      gc_fm_tms           TYPE string VALUE 'ZTMF_OFFLINE_TMS_OB',
      gc_fm_eatc          TYPE string VALUE 'ZTMF_EATC_OFFLINE_TMS_OB'.

    DATA go_server TYPE REF TO if_http_server.

    METHODS do_post.

    METHODS do_fetch_token.

    METHODS build_token
      IMPORTING iv_bucket       TYPE i
      RETURNING VALUE(rv_token) TYPE string.

    METHODS get_bucket
      RETURNING VALUE(rv_bucket) TYPE i.

    METHODS is_token_valid
      RETURNING VALUE(rv_valid) TYPE abap_bool.

    METHODS has_tms_data
      IMPORTING is_root         TYPE ty_root
      RETURNING VALUE(rv_found) TYPE abap_bool.

    METHODS get_error_text
      IMPORTING iv_function    TYPE string
                iv_subrc       TYPE sy-subrc
      RETURNING VALUE(rv_text) TYPE string.

    METHODS send
      IMPORTING iv_status TYPE i
                iv_body   TYPE string.

    METHODS error_json
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_json) TYPE string.

    METHODS to_json
      IMPORTING is_data        TYPE any
      RETURNING VALUE(rv_json) TYPE string.
ENDCLASS.



CLASS zcl_offline_dds_ob_fin IMPLEMENTATION.

  METHOD if_http_extension~handle_request.

    go_server = server.
    DATA(lv_method) = to_upper( server->request->get_header_field( '~request_method' ) ).

    CASE lv_method.

      WHEN gc_method_get OR gc_method_head.
        " CSRF handshake: the PI/PO REST channel first sends  X-CSRF-Token: Fetch
        IF to_upper( server->request->get_header_field( gc_csrf_header ) ) = gc_csrf_fetch.
          do_fetch_token( ).
        ELSE.
          send( iv_status = gc_http_not_allowed
                iv_body   = error_json( |HTTP { lv_method } is only supported to fetch a CSRF token (header X-CSRF-Token: Fetch) - use POST| ) ).
        ENDIF.

      WHEN gc_method_post.
        IF is_token_valid( ) = abap_false.
          send( iv_status = gc_http_forbidden
                iv_body   = error_json( 'CSRF token validation failed - fetch a new token (GET with header X-CSRF-Token: Fetch)' ) ).
          RETURN.
        ENDIF.
        do_post( ).

      WHEN OTHERS.
        send( iv_status = gc_http_not_allowed
              iv_body   = error_json( |HTTP { lv_method } is not supported on this resource - use POST| ) ).

    ENDCASE.

  ENDMETHOD.


  METHOD do_fetch_token.

    go_server->response->set_header_field( name  = gc_csrf_header
                                           value = build_token( get_bucket( ) ) ).
    send( iv_status = gc_http_ok
          iv_body   = to_json( VALUE ty_error( ) ) ).

  ENDMETHOD.


  METHOD get_bucket.

    " running hour number: days since 1900-01-01 * 24 + hour of the day
    DATA(lv_hour) = CONV i( sy-uzeit(2) ).
    rv_bucket = ( sy-datum - CONV d( '19000101' ) ) * 24 + lv_hour.

  ENDMETHOD.


  METHOD build_token.

    DATA lv_hash TYPE string.

    TRY.
        cl_abap_message_digest=>calculate_hash_for_char(
          EXPORTING if_algorithm  = 'SHA256'
                    if_data       = |{ gc_csrf_salt }{ sy-sysid }{ sy-mandt }{ sy-uname }{ iv_bucket }|
          IMPORTING ef_hashstring = lv_hash ).
      CATCH cx_root.
        CLEAR lv_hash.
    ENDTRY.

    rv_token = to_upper( lv_hash ).

  ENDMETHOD.


  METHOD is_token_valid.

    DATA(lv_sent) = to_upper( go_server->request->get_header_field( gc_csrf_header ) ).

    IF lv_sent IS INITIAL.
      rv_valid = xsdbool( gc_enforce_token = abap_false ).
      RETURN.
    ENDIF.

    " current hour or the previous one
    DATA(lv_bucket) = get_bucket( ).
    rv_valid = xsdbool( lv_sent = build_token( lv_bucket )
                     OR lv_sent = build_token( lv_bucket - 1 ) ).

  ENDMETHOD.


  METHOD do_post.

    DATA: ls_root     TYPE ty_root,
          ls_response TYPE ty_response,
          lt_msg_tms  TYPE ztmtt_offline_trip_msg,
          lt_msg_atc  TYPE ztmtt_offline_trip_msg.

    DATA(lv_body) = go_server->request->get_cdata( ).
    IF lv_body IS INITIAL.
      send( iv_status = gc_http_bad_request
            iv_body   = error_json( 'Request body is empty' ) ).
      RETURN.
    ENDIF.

    TRY.
        /ui2/cl_json=>deserialize( EXPORTING json = lv_body
                                   CHANGING  data = ls_root ).
      CATCH cx_root.
        send( iv_status = gc_http_bad_request
              iv_body   = error_json( 'Request body is not valid JSON' ) ).
        RETURN.
    ENDTRY.

    DATA(lv_tms_found) = has_tms_data( ls_root ).
    DATA(lv_atc_found) = xsdbool( ls_root-eatc_achnowledge IS NOT INITIAL
                               OR ls_root-change_eatc      IS NOT INITIAL ).

    IF lv_tms_found = abap_false AND lv_atc_found = abap_false.
      send( iv_status = gc_http_bad_request
            iv_body   = error_json( 'No trip or eATC section with data found in the request body' ) ).
      RETURN.
    ENDIF.

    " --- Trip operations (create / approve / print / dispatch / fuel / close / CNG / change / cancel)
    IF lv_tms_found = abap_true.
      TRY.
          CALL FUNCTION 'ZTMF_OFFLINE_TMS_OB'
            EXPORTING
              i_create_trip    = ls_root-create_trip
              i_approval       = ls_root-approve_trip
              i_print_trip     = ls_root-trip_id
              i_dispatch_trip  = ls_root-dispatch_trip
              i_fuelissue_trip = ls_root-fuelissue_trip
              i_close_trip     = ls_root-close_trip
              i_issue_cng      = ls_root-issue_cng1_offline
              i_change_trip    = ls_root-change_trip
              i_cancel_trip    = ls_root-cancel_trip
              iv_offline       = abap_true
            IMPORTING
              print_prev       = ls_response-it_print_prev
              return_message   = lt_msg_tms
            EXCEPTIONS
              error_message    = 1
              OTHERS           = 2.
          IF sy-subrc <> 0.
            send( iv_status = gc_http_server_err
                  iv_body   = error_json( get_error_text( iv_function = gc_fm_tms
                                                          iv_subrc    = sy-subrc ) ) ).
            RETURN.
          ENDIF.
        CATCH cx_root INTO DATA(lo_tms_error).
          send( iv_status = gc_http_server_err
                iv_body   = error_json( |{ gc_fm_tms } failed: { lo_tms_error->get_text( ) }| ) ).
          RETURN.
      ENDTRY.
    ENDIF.

    " --- eATC acknowledge / change eATC
    IF lv_atc_found = abap_true.
      TRY.
          CALL FUNCTION 'ZTMF_EATC_OFFLINE_TMS_OB'
            EXPORTING
              is_eatc           = ls_root-eatc_achnowledge
              i_change_eatc     = ls_root-change_eatc
              iv_offline        = abap_true
            IMPORTING
              lt_return_message = lt_msg_atc
              ev_doc_no         = ls_response-lv_doc_no
            EXCEPTIONS
              error_message     = 1
              OTHERS            = 2.
          IF sy-subrc <> 0.
            send( iv_status = gc_http_server_err
                  iv_body   = error_json( get_error_text( iv_function = gc_fm_eatc
                                                          iv_subrc    = sy-subrc ) ) ).
            RETURN.
          ENDIF.
        CATCH cx_root INTO DATA(lo_atc_error).
          send( iv_status = gc_http_server_err
                iv_body   = error_json( |{ gc_fm_eatc } failed: { lo_atc_error->get_text( ) }| ) ).
          RETURN.
      ENDTRY.
    ENDIF.

    " Messages of both calls are returned together (the 2nd call must not overwrite the 1st)
    ls_response-return_message = VALUE #( ( LINES OF lt_msg_tms )
                                          ( LINES OF lt_msg_atc ) ).

    send( iv_status = gc_http_ok
          iv_body   = to_json( ls_response ) ).

  ENDMETHOD.


  METHOD has_tms_data.

    rv_found = xsdbool( is_root-create_trip        IS NOT INITIAL
                     OR is_root-approve_trip       IS NOT INITIAL
                     OR is_root-trip_id            IS NOT INITIAL
                     OR is_root-dispatch_trip      IS NOT INITIAL
                     OR is_root-fuelissue_trip     IS NOT INITIAL
                     OR is_root-close_trip         IS NOT INITIAL
                     OR is_root-issue_cng1_offline IS NOT INITIAL
                     OR is_root-change_trip        IS NOT INITIAL
                     OR is_root-cancel_trip        IS NOT INITIAL ).

  ENDMETHOD.


  METHOD get_error_text.

    DATA lv_text TYPE string.

    " 1 = ERROR_MESSAGE: the function module issued an E/A message -> sy-msg* is filled
    IF iv_subrc = 1 AND sy-msgid IS NOT INITIAL.
      MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4
              INTO lv_text.
      rv_text = |{ iv_function }: { lv_text }|.
    ELSE.
      rv_text = |{ iv_function } raised an exception (sy-subrc { iv_subrc })|.
    ENDIF.

  ENDMETHOD.


  METHOD send.

    go_server->response->set_header_field( name  = 'Content-Type'
                                           value = gc_content_json ).
    go_server->response->set_status(
      code   = iv_status
      reason = SWITCH string( iv_status
                 WHEN gc_http_ok          THEN `OK`
                 WHEN gc_http_bad_request THEN `Bad Request`
                 WHEN gc_http_forbidden   THEN `Forbidden`
                 WHEN gc_http_not_allowed THEN `Method Not Allowed`
                 ELSE `Internal Server Error` ) ).
    go_server->response->set_cdata( iv_body ).

  ENDMETHOD.


  METHOD error_json.

    rv_json = to_json( VALUE ty_error( error = iv_text ) ).

  ENDMETHOD.


  METHOD to_json.

    rv_json = /ui2/cl_json=>serialize( data     = is_data
                                       compress = abap_false ).

  ENDMETHOD.

ENDCLASS.

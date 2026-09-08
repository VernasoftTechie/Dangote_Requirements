"! <p class="shorttext synchronized">Customer BP API - processing log</p>
"! Persists every inbound call ( success and failure ) in ZCUST_BP_LOG /
"! ZCUST_BP_LOG_MSG so that failed requests can be analysed in report
"! ZCUST_BP_LOG_REPORT and re-triggered from the stored payload.
CLASS zcl_cust_bp_log DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    "! Write one log entry (own LUW - safe to call after COMMIT/ROLLBACK
    "! of the BP maintain).
    "! @parameter iv_raw_json | verbatim inbound body, kept for reprocessing
    CLASS-METHODS record
      IMPORTING iv_operation      TYPE zcust_bp_log-operation
                iv_customer_id    TYPE zcust_bp_id
                iv_application_id TYPE zcust_bp_text OPTIONAL
                iv_ext_status     TYPE zcust_bp_id   OPTIONAL
                iv_status         TYPE zcust_bp_flag
                iv_http_status    TYPE i
                iv_raw_json     TYPE string OPTIONAL
                is_result       TYPE zcust_bp_s_create_res OPTIONAL
                it_messages     TYPE zcust_bp_t_message OPTIONAL
      RETURNING VALUE(rv_log_id) TYPE sysuuid_c22.

    "! Re-run a failed entry from its stored payload and update the row.
    CLASS-METHODS reprocess
      IMPORTING iv_log_id       TYPE sysuuid_c22
      RETURNING VALUE(rs_result) TYPE zcust_bp_s_create_res
      RAISING   zcx_cust_bp.

    TYPES:
      BEGIN OF ty_reprocess_summary,
        total     TYPE i,
        succeeded TYPE i,
        failed    TYPE i,
      END OF ty_reprocess_summary.

    "! Reprocess many entries; returns counts for the report toolbar.
    CLASS-METHODS reprocess_multi
      IMPORTING it_log_id        TYPE STANDARD TABLE
      RETURNING VALUE(rs_summary) TYPE ty_reprocess_summary.

  PRIVATE SECTION.
    CLASS-METHODS now
      RETURNING VALUE(rv_ts) TYPE timestampl.

    CLASS-METHODS save_messages
      IMPORTING iv_log_id   TYPE sysuuid_c22
                it_messages TYPE zcust_bp_t_message.
ENDCLASS.


CLASS zcl_cust_bp_log IMPLEMENTATION.

  METHOD now.
    GET TIME STAMP FIELD rv_ts.
  ENDMETHOD.


  METHOD record.
    rv_log_id = cl_system_uuid=>create_uuid_c22_static( ).

    DATA(ls_log) = VALUE zcust_bp_log(
      log_id         = rv_log_id
      direction      = zif_cust_bp_types=>c_direction-inbound
      operation      = iv_operation
      customer_id    = iv_customer_id
      application_id = iv_application_id
      ext_status     = iv_ext_status
      partner        = is_result-partner
      customer       = is_result-customer
      status         = iv_status
      http_status    = iv_http_status
      retry_count    = 0
      request_json   = iv_raw_json
      created_at     = now( )
      created_by     = sy-uname ).

    LOOP AT it_messages INTO DATA(ls_m) WHERE type CA 'EAX'.
      ls_log-lead_msg = ls_m-message.
      EXIT.
    ENDLOOP.
    IF ls_log-lead_msg IS INITIAL AND it_messages IS NOT INITIAL.
      ls_log-lead_msg = it_messages[ 1 ]-message.
    ENDIF.

    IF is_result IS NOT INITIAL.
      ls_log-response_json = /ui2/cl_json=>serialize(
        data        = is_result
        pretty_name = /ui2/cl_json=>pretty_mode-camel_case
        compress    = abap_false ).
    ENDIF.

    INSERT zcust_bp_log FROM ls_log.
    save_messages( iv_log_id = rv_log_id it_messages = it_messages ).
    COMMIT WORK.
  ENDMETHOD.


  METHOD save_messages.
    DATA lt_msg TYPE STANDARD TABLE OF zcust_bp_log_msg.
    DATA lv_seq TYPE zcust_bp_log_msg-seqnr.

    DELETE FROM zcust_bp_log_msg WHERE log_id = @iv_log_id.
    LOOP AT it_messages INTO DATA(ls_m).
      lv_seq += 1.
      APPEND VALUE #( log_id = iv_log_id
                      seqnr  = lv_seq
                      msgty  = ls_m-type
                      msgid  = ls_m-id
                      msgno  = ls_m-msgno
                      msgtx  = ls_m-message ) TO lt_msg.
    ENDLOOP.
    IF lt_msg IS NOT INITIAL.
      INSERT zcust_bp_log_msg FROM TABLE @lt_msg.
    ENDIF.
  ENDMETHOD.


  METHOD reprocess.
    SELECT SINGLE * FROM zcust_bp_log
      INTO @DATA(ls_log)
      WHERE log_id = @iv_log_id.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_cust_bp
        MESSAGE e013(zmsg_cust_bp) WITH iv_log_id.
    ENDIF.
    IF ls_log-request_json IS INITIAL.
      RAISE EXCEPTION TYPE zcx_cust_bp
        MESSAGE e014(zmsg_cust_bp) WITH iv_log_id.
    ENDIF.

    CASE ls_log-operation.
      WHEN zif_cust_bp_types=>c_operation-create.
        DATA ls_req TYPE zcust_bp_s_create_req.
        /ui2/cl_json=>deserialize(
          EXPORTING json        = ls_log-request_json
                    pretty_name = /ui2/cl_json=>pretty_mode-camel_case
          CHANGING  data        = ls_req ).
        rs_result = NEW zcl_cust_bp_create( )->execute(
                      is_request  = ls_req
                      iv_raw_json  = ls_log-request_json
                      iv_write_log = abap_false ).

      WHEN zif_cust_bp_types=>c_operation-read.
        TRY.
            DATA(ls_read) = NEW zcl_cust_bp_read( )->execute( ls_log-customer_id ).
            rs_result = VALUE #( customer_id = ls_log-customer_id
                                 partner     = ls_read-partner
                                 customer    = ls_read-customer
                                 success     = abap_true ).
          CATCH zcx_cust_bp INTO DATA(lx_read).
            rs_result = VALUE #( customer_id = ls_log-customer_id
                                 success     = abap_false
                                 messages    = VALUE #( ( type = 'E' message = lx_read->get_text( ) ) ) ).
        ENDTRY.
    ENDCASE.

    " ---- update the same row ----
    ls_log-retry_count += 1.
    ls_log-status       = COND #( WHEN rs_result-success = abap_true
                                  THEN zif_cust_bp_types=>c_log_status-reprocessed
                                  ELSE zif_cust_bp_types=>c_log_status-error ).
    ls_log-http_status  = COND #( WHEN rs_result-success = abap_true
                                  THEN zif_cust_bp_types=>c_http-created
                                  ELSE zif_cust_bp_types=>c_http-unprocessable ).
    ls_log-partner      = rs_result-partner.
    ls_log-customer     = rs_result-customer.
    ls_log-changed_at   = now( ).
    ls_log-changed_by   = sy-uname.
    ls_log-response_json = /ui2/cl_json=>serialize(
      data = rs_result pretty_name = /ui2/cl_json=>pretty_mode-camel_case compress = abap_false ).
    LOOP AT rs_result-messages INTO DATA(ls_rm) WHERE type CA 'EAX'.
      ls_log-lead_msg = ls_rm-message.
      EXIT.
    ENDLOOP.

    UPDATE zcust_bp_log FROM ls_log.
    save_messages( iv_log_id = iv_log_id it_messages = rs_result-messages ).
    COMMIT WORK.

    rs_result-log_id = iv_log_id.
  ENDMETHOD.


  METHOD reprocess_multi.
    FIELD-SYMBOLS <lv_id> TYPE sysuuid_c22.
    LOOP AT it_log_id ASSIGNING <lv_id>.
      rs_summary-total += 1.
      TRY.
          DATA(ls_res) = reprocess( <lv_id> ).
          IF ls_res-success = abap_true.
            rs_summary-succeeded += 1.
          ELSE.
            rs_summary-failed += 1.
          ENDIF.
        CATCH zcx_cust_bp.
          rs_summary-failed += 1.
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

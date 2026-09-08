"! <p class="shorttext synchronized">Customer BP API - processing log &amp; reprocess</p>
"! Displays ZT_CUST_BP_LOG as an ALV grid ( date / time, external id, status,
"! HTTP code, BP / customer, leading message, retry count ) and lets the
"! user re-trigger failed entries from the stored payload.
"!
"! Reprocess options ( selection screen ):
"! <ul>
"! <li>P_LOGID  - reprocess exactly one entry</li>
"! <li>P_REPRO  - reprocess every ERROR entry in the current selection</li>
"! </ul>
"! Double-click a row to see its full message list.
REPORT zcust_bp_log_report.

TYPE-POOLS icon.

DATA gs_log TYPE zt_cust_bp_log.

TYPES: BEGIN OF ty_row,
         log_id         TYPE zt_cust_bp_log-log_id,
         created_date   TYPE d,
         created_time   TYPE t,
         operation      TYPE zt_cust_bp_log-operation,
         customer_id    TYPE zt_cust_bp_log-customer_id,
         application_id TYPE zt_cust_bp_log-application_id,
         status         TYPE zt_cust_bp_log-status,
         status_icon    TYPE icon_d,
         http_status    TYPE zt_cust_bp_log-http_status,
         partner        TYPE zt_cust_bp_log-partner,
         customer       TYPE zt_cust_bp_log-customer,
         retry_count    TYPE zt_cust_bp_log-retry_count,
         message        TYPE zt_cust_bp_log-message,
         created_by     TYPE zt_cust_bp_log-created_by,
       END OF ty_row.

TYPES gtt_ts_range TYPE RANGE OF timestampl.

DATA gt_row  TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.
DATA gv_date TYPE d.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-b01.
SELECT-OPTIONS s_date FOR gv_date DEFAULT sy-datum TO sy-datum.
SELECT-OPTIONS s_cust FOR gs_log-customer_id.
SELECT-OPTIONS s_stat FOR gs_log-status.
SELECT-OPTIONS s_op   FOR gs_log-operation.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-b02.
PARAMETERS p_logid TYPE zt_cust_bp_log-log_id.
PARAMETERS p_repro AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK b2.


CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
    METHODS on_double_click FOR EVENT double_click OF cl_salv_events_table
      IMPORTING row column.
  PRIVATE SECTION.
    CLASS-DATA go_app TYPE REF TO lcl_app.

    METHODS ts_range RETURNING VALUE(rt_range) TYPE gtt_ts_range.
    METHODS reprocess.
    METHODS select_rows.
    METHODS show_alv.
    METHODS show_messages IMPORTING iv_log_id TYPE zt_cust_bp_log-log_id.
ENDCLASS.


CLASS lcl_app IMPLEMENTATION.

  METHOD run.
    go_app = NEW #( ).
    go_app->reprocess( ).
    go_app->select_rows( ).
    go_app->show_alv( ).
  ENDMETHOD.


  METHOD ts_range.
    LOOP AT s_date INTO DATA(ls_d).
      DATA lv_lo TYPE timestampl.
      DATA lv_hi TYPE timestampl.
      CONVERT DATE ls_d-low TIME '000000'
              INTO TIME STAMP lv_lo TIME ZONE sy-zonlo.
      CONVERT DATE COND d( WHEN ls_d-high IS NOT INITIAL THEN ls_d-high ELSE ls_d-low ) TIME '235959'
              INTO TIME STAMP lv_hi TIME ZONE sy-zonlo.
      APPEND VALUE #( sign = 'I' option = 'BT' low = lv_lo high = lv_hi ) TO rt_range.
    ENDLOOP.
  ENDMETHOD.


  METHOD reprocess.
    DATA lt_id TYPE STANDARD TABLE OF zt_cust_bp_log-log_id.

    IF p_logid IS NOT INITIAL.
      APPEND p_logid TO lt_id.
    ENDIF.

    IF p_repro = abap_true.
      DATA(lr_ts) = ts_range( ).
      SELECT log_id FROM zt_cust_bp_log
        APPENDING TABLE @lt_id
        WHERE created_at  IN @lr_ts
          AND customer_id IN @s_cust
          AND operation   IN @s_op
          AND status      =  @zif_cust_bp_types=>c_log_status-error.
    ENDIF.

    IF lt_id IS INITIAL.
      RETURN.
    ENDIF.
    SORT lt_id.
    DELETE ADJACENT DUPLICATES FROM lt_id.

    DATA(ls_sum) = zcl_cust_bp_log=>reprocess_multi( lt_id ).
    MESSAGE i015(zmsg_cust_bp) WITH ls_sum-total ls_sum-succeeded ls_sum-failed.
  ENDMETHOD.


  METHOD select_rows.
    DATA(lr_ts) = ts_range( ).

    SELECT * FROM zt_cust_bp_log
      INTO TABLE @DATA(lt_log)
      WHERE created_at  IN @lr_ts
        AND customer_id IN @s_cust
        AND status      IN @s_stat
        AND operation   IN @s_op
      ORDER BY created_at DESCENDING.

    CLEAR gt_row.
    LOOP AT lt_log INTO DATA(ls).
      DATA lv_date TYPE d.
      DATA lv_time TYPE t.
      CONVERT TIME STAMP ls-created_at TIME ZONE sy-zonlo
              INTO DATE lv_date TIME lv_time.
      APPEND VALUE ty_row(
        log_id         = ls-log_id
        created_date   = lv_date
        created_time   = lv_time
        operation      = ls-operation
        customer_id    = ls-customer_id
        application_id = ls-application_id
        status         = ls-status
        status_icon    = SWITCH #( ls-status
                           WHEN zif_cust_bp_types=>c_log_status-success     THEN icon_green_light
                           WHEN zif_cust_bp_types=>c_log_status-reprocessed THEN icon_green_light
                           WHEN zif_cust_bp_types=>c_log_status-pending     THEN icon_yellow_light
                           ELSE icon_red_light )
        http_status    = ls-http_status
        partner        = ls-partner
        customer       = ls-customer
        retry_count    = ls-retry_count
        message        = ls-message
        created_by     = ls-created_by ) TO gt_row.
    ENDLOOP.
  ENDMETHOD.


  METHOD show_alv.
    DATA lo_alv TYPE REF TO cl_salv_table.
    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = lo_alv
          CHANGING  t_table      = gt_row ).

        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->get_display_settings( )->set_striped_pattern( abap_true ).
        lo_alv->get_display_settings( )->set_list_header( |Customer BP API - processing log| ).

        DATA(lo_cols) = lo_alv->get_columns( ).
        lo_cols->set_optimize( abap_true ).
        lo_cols->get_column( 'LOG_ID' )->set_technical( abap_true ).
        lo_cols->get_column( 'STATUS' )->set_technical( abap_true ).
        lo_cols->set_column_position( columnname = 'STATUS_ICON' position = 1 ).
        lo_cols->get_column( 'STATUS_ICON'  )->set_medium_text( 'Status' ).
        lo_cols->get_column( 'CREATED_DATE' )->set_medium_text( 'Date' ).
        lo_cols->get_column( 'CREATED_TIME' )->set_medium_text( 'Time' ).
        lo_cols->get_column( 'HTTP_STATUS'  )->set_medium_text( 'HTTP' ).
        lo_cols->get_column( 'RETRY_COUNT'  )->set_medium_text( 'Retries' ).

        SET HANDLER go_app->on_double_click FOR lo_alv->get_event( ).

        lo_alv->display( ).

      CATCH cx_salv_error INTO DATA(lx).
        MESSAGE lx->get_text( ) TYPE 'I'.
    ENDTRY.
  ENDMETHOD.


  METHOD on_double_click.
    READ TABLE gt_row INDEX row INTO DATA(ls_row).
    IF sy-subrc = 0.
      show_messages( ls_row-log_id ).
    ENDIF.
  ENDMETHOD.


  METHOD show_messages.
    SELECT seqnr, type, msgid, msgno, message
      FROM zt_cust_bp_log_msg
      INTO TABLE @DATA(lt_msg)
      WHERE log_id = @iv_log_id
      ORDER BY seqnr.
    IF sy-subrc <> 0.
      MESSAGE 'No detail messages stored for this entry' TYPE 'I'.
      RETURN.
    ENDIF.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = DATA(lo_pop)
          CHANGING  t_table      = lt_msg ).
        lo_pop->get_functions( )->set_all( abap_true ).
        lo_pop->set_screen_popup( start_column = 10 end_column = 120
                                  start_line   = 3  end_line   = 22 ).
        lo_pop->get_display_settings( )->set_list_header( |Messages for log { iv_log_id }| ).
        lo_pop->display( ).
      CATCH cx_salv_error.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.
  lcl_app=>run( ).

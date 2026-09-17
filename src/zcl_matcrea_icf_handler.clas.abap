"! <p class="shorttext synchronized">Material Master API - ICF HTTP handler</p>
"! ICF handler for service node <em>/sap/zmcs_mate_crea</em>.
"! <ul>
"! <li>POST /sap/zmcs_mate_crea                          -&gt; create material master(s) via BAPI_MATERIAL_SAVEDATA</li>
"! <li>GET  /sap/zmcs_mate_crea?materialCode=...&amp;plant=... -&gt; read material master via BAPI_MATERIAL_GET_DETAIL</li>
"! </ul>
"! Freestyle IF_HTTP_EXTENSION handler, deliberately mirroring ZCL_CUST_BP_ICF_HANDLER
"! instead of the REST-resource framework (IF_REST_RESOURCE / CL_REST_HTTP_HANDLER).
"! The REST-resource base class auto-enforces HTTP Security Session Management
"! (session cookie + CSRF token) with no way to opt out from the handler itself.
"! A freestyle handler gets no automatic session/CSRF behavior at all - this class
"! does not check or issue one, matching the stateless Basic-Auth call pattern the
"! integration client expects.
"!
"! NOTE (GET): BAPI_MATERIAL_GET_DETAIL's IMPORTING/TABLES parameter names below are
"! reproduced from standard usage and should be double-checked in SE37 against this
"! system's release before activating - I could not verify them live.
CLASS zcl_matcrea_icf_handler DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_http_extension.

  PRIVATE SECTION.
    CONSTANTS c_content_json TYPE string VALUE 'application/json; charset=utf-8'.

    CONSTANTS:
      BEGIN OF c_http,
        ok           TYPE i VALUE 200,
        bad_request  TYPE i VALUE 400,
        not_allowed  TYPE i VALUE 405,
        server_error TYPE i VALUE 500,
      END OF c_http.

    CONSTANTS : lc_e        TYPE c VALUE 'E',
                lc_a        TYPE c VALUE 'A',
                lc_s        TYPE c VALUE 'S',
                lc_best     TYPE tdid VALUE 'BEST',
                lc_material TYPE tdobject VALUE 'MATERIAL'.

    TYPES: BEGIN OF ty_message,
             material_code TYPE matnr,
             type          TYPE bapi_mtype,
             message       TYPE bapi_msg,
           END OF ty_message.
    TYPES tt_message TYPE STANDARD TABLE OF ty_message WITH EMPTY KEY.

    TYPES: BEGIN OF ty_root,
             material TYPE zmm_material_creation_tt,
           END OF ty_root.

    TYPES: BEGIN OF ty_read_response,
             material TYPE zmm_material_creation_tt,
             messages TYPE tt_message,
           END OF ty_read_response.

    DATA mo_server TYPE REF TO if_http_server.

    METHODS do_create.
    METHODS do_read.

    "! Checks the fields BAPI_MATERIAL_SAVEDATA needs given the views this handler
    "! always requests (basic/purchase/storage/account). Appends one combined
    "! E-type message per material to ct_messages and returns space if invalid,
    "! so the caller can skip that material the same way it skips duplicates.
    METHODS validate_material
      IMPORTING is_material    TYPE zmm_material_creation_st
      CHANGING  ct_messages    TYPE tt_message
      RETURNING VALUE(rv_valid) TYPE abap_bool.

    METHODS send
      IMPORTING iv_status TYPE i
                iv_body   TYPE string.

    METHODS error_json
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_json) TYPE string.
ENDCLASS.


CLASS zcl_matcrea_icf_handler IMPLEMENTATION.

  METHOD if_http_extension~handle_request.
    mo_server = server.
    DATA(lv_method) = to_upper( server->request->get_header_field( '~request_method' ) ).

    CASE lv_method.
      WHEN 'POST'.
        do_create( ).
      WHEN 'GET'.
        do_read( ).
      WHEN OTHERS.
        send( iv_status = c_http-not_allowed
              iv_body   = error_json( |HTTP { lv_method } is not supported on this resource| ) ).
    ENDCASE.
  ENDMETHOD.


  METHOD validate_material.

    DATA lt_missing TYPE string_table.

    IF is_material-materialcode IS INITIAL.
      APPEND 'materialCode' TO lt_missing.
    ENDIF.
    IF is_material-industrysector IS INITIAL.
      APPEND 'industrySector' TO lt_missing.
    ENDIF.
    IF is_material-materialtype IS INITIAL.
      APPEND 'materialType' TO lt_missing.
    ENDIF.
    IF is_material-baseuom IS INITIAL.
      APPEND 'baseUom' TO lt_missing.
    ENDIF.
    IF is_material-plant IS INITIAL.
      APPEND 'plant' TO lt_missing.
    ENDIF.
    IF is_material-storagelocation IS INITIAL.
      APPEND 'storageLocation' TO lt_missing.
    ENDIF.

    IF lt_missing IS INITIAL.
      rv_valid = abap_true.
      RETURN.
    ENDIF.

    rv_valid = abap_false.
    APPEND VALUE #(
      material_code = is_material-materialcode
      type          = lc_e
      message       = |Material code { is_material-materialcode }: required field(s) missing - { concat_lines_of( table = lt_missing sep = ', ' ) }|
    ) TO ct_messages.

  ENDMETHOD.


  METHOD do_create.

    DATA: lt_messages TYPE tt_message.

    DATA: ls_data    TYPE ty_root,
          lt_stream  TYPE string_table,
          lt_lines   TYPE STANDARD TABLE OF tline WITH EMPTY KEY,
          ls_header  TYPE thead,
          lv_message TYPE string,
          ls_json    TYPE string.

    DATA: ls_headdata             TYPE bapimathead,
          ls_clientdata           TYPE bapi_mara,
          ls_clientdatax          TYPE bapi_marax,
          ls_plantdata            TYPE bapi_marc,
          ls_plantdatax           TYPE bapi_marcx,
          ls_storagelocationdata  TYPE bapi_mard,
          ls_storagelocationdatax TYPE bapi_mardx,
          ls_valuationdata        TYPE bapi_mbew,
          ls_valuationdatax       TYPE bapi_mbewx,
          lt_description          TYPE STANDARD TABLE OF bapi_makt WITH EMPTY KEY,
          lt_return               TYPE bapiret2_t.

    DATA(lv_data) = mo_server->request->get_cdata( ).

    IF lv_data IS INITIAL.
      send( iv_status = c_http-bad_request
            iv_body   = error_json( 'Request body is empty or not valid JSON' ) ).
      RETURN.
    ENDIF.

    DATA(lo_convert) = NEW zcl_json_abap_dynamic_convert( ).

    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_data WITH ''.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_data WITH ''.
    REPLACE ALL OCCURRENCES OF `'##'` IN lv_data WITH ''.
    CONDENSE lv_data NO-GAPS.

    lo_convert->json_to_abap(
      EXPORTING
        iv_json = lv_data
      CHANGING
        c_data  = ls_data
    ).

    IF ls_data IS NOT INITIAL.

      " duplicate check
      LOOP AT ls_data-material INTO DATA(ls_mat).
        DATA(lv_material) = |{ ls_mat-materialcode ALPHA = IN WIDTH = 18 }|.

        SELECT SINGLE matnr
        FROM mara
        WHERE matnr = @lv_material
        INTO @DATA(lv_matnr).

        IF lv_matnr IS NOT INITIAL.
          APPEND VALUE #(
           material_code = ls_mat-materialcode
           type          = lc_e
           message       = |Material code { ls_mat-materialcode } already exists|
          ) TO lt_messages.
          DELETE ls_data-material WHERE materialcode = ls_mat-materialcode.
        ENDIF.
      ENDLOOP.

      " mandatory-field validation - anything missing goes into lt_messages and
      " is excluded from the BAPI call below, same treatment as a duplicate.
      LOOP AT ls_data-material INTO DATA(ls_check).
        IF validate_material( is_material = ls_check CHANGING ct_messages = lt_messages ) = abap_false.
          DELETE ls_data-material WHERE materialcode = ls_check-materialcode.
        ENDIF.
      ENDLOOP.

      LOOP AT ls_data-material INTO DATA(ls_material).
        "HEADER
        ls_headdata-material   = |{ ls_material-materialcode ALPHA = IN WIDTH = 18 }|.
        ls_headdata-ind_sector = ls_material-industrysector.
        ls_headdata-matl_type  = ls_material-materialtype.

        ls_headdata-basic_view    = abap_true.
        ls_headdata-purchase_view = abap_true.
        ls_headdata-storage_view  = abap_true.
        ls_headdata-account_view  = abap_true.

        IF ls_material-plant IS NOT INITIAL.
          ls_headdata-mrp_view = abap_true.
        ENDIF.

        IF ls_material-shorttext IS NOT INITIAL.
          APPEND VALUE #( langu = sy-langu matl_desc = ls_material-shorttext ) TO lt_description.
        ENDIF.

        "CLIENT DATA
        ls_clientdata-base_uom = ls_material-baseuom.
        ls_clientdatax-base_uom = xsdbool( ls_material-baseuom IS NOT INITIAL ).

        ls_clientdata-matl_group = ls_material-materialgroup.
        ls_clientdatax-matl_group = xsdbool( ls_material-materialgroup IS NOT INITIAL ).

        ls_clientdata-old_mat_no = ls_material-oldmaterialnumber.
        ls_clientdatax-old_mat_no = xsdbool( ls_material-oldmaterialnumber IS NOT INITIAL ).

        ls_clientdata-prod_hier = ls_material-producthierarchy.
        ls_clientdatax-prod_hier = xsdbool( ls_material-producthierarchy IS NOT INITIAL ).

        ls_clientdata-basic_matl = ls_material-basicmaterial.
        ls_clientdatax-basic_matl = xsdbool( ls_material-basicmaterial IS NOT INITIAL ).

        IF ls_material-orderunit IS NOT INITIAL.
          ls_clientdata-po_unit = ls_material-orderunit.
          ls_clientdatax-po_unit = xsdbool( ls_material-standardprice IS NOT INITIAL ).
        ENDIF.

        ls_clientdata-var_ord_un = ls_material-variableorderunit.
        ls_clientdatax-var_ord_un = xsdbool( ls_material-variableorderunit IS NOT INITIAL ).

        ls_clientdata-pur_valkey = ls_material-purchasevaluekey.
        ls_clientdatax-pur_valkey = xsdbool( ls_material-purchasevaluekey IS NOT INITIAL ).

        IF ls_material-orderunit IS NOT INITIAL.
          ls_clientdata-po_unit = ls_material-orderunit.
          ls_clientdatax-po_unit = abap_true.
        ENDIF.

        "Material long text
        APPEND CONV string( ls_material-description ) TO lt_stream.

        CALL FUNCTION 'CONVERT_STREAM_TO_ITF_TEXT'
          EXPORTING
            stream_lines = lt_stream
            language     = sy-langu
            lf           = abap_true
          TABLES
            text_stream  = lt_stream
            itf_text     = lt_lines.

        ls_header-tdobject = lc_material.
        ls_header-tdname   = |{ ls_headdata-material ALPHA = IN  WIDTH = 18 }|.
        ls_header-tdid     = lc_best.
        ls_header-tdspras  = sy-langu.

        CALL FUNCTION 'SAVE_TEXT'
          EXPORTING
            header          = ls_header
            savemode_direct = abap_false
          TABLES
            lines           = lt_lines
          EXCEPTIONS
            id              = 1
            language        = 2
            name            = 3
            object          = 4
            OTHERS          = 5.

        IF sy-subrc <> 0.
          APPEND VALUE #(
            material_code = ls_material-materialcode
            type          = lc_e
            message       = |Material long text save failed. SY-SUBRC { sy-subrc }| ) TO lt_messages.
        ELSE.
          CALL FUNCTION 'COMMIT_TEXT'.
          COMMIT WORK.
          DATA(lv_msg1) = 'Material long text saved successfully'.
          APPEND VALUE #(
            material_code = ls_material-materialcode
            type          = lc_s
            message       = lv_msg1 ) TO lt_messages.
        ENDIF.

        "PLANT
        ls_plantdata-pur_group = ls_material-purchasinggroup.
        ls_plantdatax-pur_group = xsdbool( ls_material-purchasinggroup IS NOT INITIAL ).

        ls_plantdata-profit_ctr = ls_material-profitcenter.
        ls_plantdatax-profit_ctr = xsdbool( ls_material-profitcenter IS NOT INITIAL ).

        ls_plantdata-plant = ls_material-plant.
        ls_plantdatax-plant = ls_material-plant.

        ls_plantdata-mrp_type = 'ND'.
        ls_plantdatax-mrp_type = abap_true.

        ls_plantdata-availcheck = 'KP'.
        ls_plantdatax-availcheck = abap_true.

        "storage
        ls_storagelocationdata-plant = ls_material-plant.
        ls_storagelocationdata-stge_loc = ls_material-storagelocation.
        ls_storagelocationdatax-plant = ls_material-plant.
        ls_storagelocationdatax-stge_loc = ls_material-storagelocation.

        ls_storagelocationdata-stge_bin = ls_material-storagebin.
        ls_storagelocationdatax-stge_bin = xsdbool( ls_material-storagebin IS NOT INITIAL ).

        "valuation
        ls_valuationdata-val_area = ls_material-plant.
        ls_valuationdatax-val_area = ls_material-plant.

        ls_valuationdata-val_cat = ls_material-valuationcategory.
        ls_valuationdatax-val_cat = xsdbool( ls_material-valuationcategory IS NOT INITIAL ).

        ls_valuationdata-ml_settle = ls_material-pricedetermination.
        ls_valuationdatax-ml_settle = xsdbool( ls_material-pricedetermination IS NOT INITIAL ).

        ls_valuationdata-val_class = ls_material-valuationclass.
        ls_valuationdatax-val_class = xsdbool( ls_material-valuationclass IS NOT INITIAL ).

        ls_valuationdata-price_unit = ls_material-priceunit.
        ls_valuationdatax-price_unit = xsdbool( ls_material-priceunit IS NOT INITIAL ).

        ls_valuationdata-price_ctrl = ls_material-pricecontrol.
        ls_valuationdatax-price_ctrl = xsdbool( ls_material-pricecontrol IS NOT INITIAL ).

        IF ls_material-pricecontrol = 'V'.
          ls_valuationdata-moving_pr = ls_material-movingaverageprice.
          ls_valuationdatax-moving_pr = xsdbool( ls_material-movingaverageprice IS NOT INITIAL ).
        ELSEIF ls_material-pricecontrol = 'S'.
          ls_valuationdata-std_price = ls_material-standardprice.
          ls_valuationdatax-std_price = xsdbool( ls_material-standardprice IS NOT INITIAL ).
        ENDIF.

        CALL FUNCTION 'BAPI_MATERIAL_SAVEDATA'
          EXPORTING
            headdata             = ls_headdata
            clientdata           = ls_clientdata
            clientdatax          = ls_clientdatax
            plantdata            = ls_plantdata
            plantdatax           = ls_plantdatax
            storagelocationdata  = ls_storagelocationdata
            storagelocationdatax = ls_storagelocationdatax
            valuationdata        = ls_valuationdata
            valuationdatax       = ls_valuationdatax
          TABLES
            materialdescription  = lt_description
            returnmessages       = lt_return.

        CLEAR lv_message.
        LOOP AT lt_return INTO DATA(ls_return).

          lv_message = COND #(
                          WHEN lv_message IS INITIAL
                          THEN ls_return-message
                          ELSE |{ lv_message }, { ls_return-message }| ).

          IF ls_return-type = lc_e OR ls_return-type = lc_a.
            CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.

          ELSEIF NOT line_exists( lt_return[ type = lc_e ] )
         AND NOT line_exists( lt_return[ type = lc_a ] ).
            CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
              EXPORTING
                wait = abap_true.

            WAIT UP TO 2 SECONDS.
          ENDIF.

        ENDLOOP.

        APPEND VALUE #(
          material_code = ls_material-materialcode
          type          = COND #( WHEN line_exists( lt_return[ type = lc_e ] )
                                    OR line_exists( lt_return[ type = lc_a ] )
                                  THEN lc_e
                                  ELSE lc_s )
          message       = lv_message
        ) TO lt_messages.

      ENDLOOP.
    ENDIF.

    IF lt_messages IS NOT INITIAL.
      /ui2/cl_json=>serialize(
        EXPORTING
          data   = lt_messages
        RECEIVING
          r_json = ls_json
      ).
    ENDIF.

    send( iv_status = c_http-ok
          iv_body   = ls_json ).
  ENDMETHOD.


  METHOD do_read.

    DATA: ls_response TYPE ty_read_response,
          ls_row      TYPE zmm_material_creation_st.

    DATA(lv_code_ext) = mo_server->request->get_form_field( 'materialCode' ).
    DATA(lv_plant)    = mo_server->request->get_form_field( 'plant' ).

    IF lv_code_ext IS INITIAL.
      send( iv_status = c_http-bad_request
            iv_body   = error_json( 'Query parameter materialCode is required' ) ).
      RETURN.
    ENDIF.

    DATA(lv_matnr) = |{ lv_code_ext ALPHA = IN WIDTH = 18 }|.

    SELECT SINGLE matnr
    FROM mara
    WHERE matnr = @lv_matnr
    INTO @DATA(lv_found).

    IF lv_found IS INITIAL.
      APPEND VALUE #(
        material_code = lv_code_ext
        type          = lc_e
        message       = |Material code { lv_code_ext } does not exist|
      ) TO ls_response-messages.
      send( iv_status = c_http-ok
            iv_body   = /ui2/cl_json=>serialize( data = ls_response ) ).
      RETURN.
    ENDIF.

    DATA: ls_general   TYPE bapimatgeneraldata,
          ls_plantdata TYPE bapi_marc,
          ls_valdata   TYPE bapi_mbew,
          lt_desc      TYPE STANDARD TABLE OF bapi_makt WITH EMPTY KEY,
          lt_return    TYPE bapiret2_t.

    CALL FUNCTION 'BAPI_MATERIAL_GET_DETAIL'
      EXPORTING
        material                = lv_matnr
        plant                   = lv_plant
        valuation_area          = lv_plant
      IMPORTING
        material_general_data   = ls_general
        material_plant_data     = ls_plantdata
        material_valuation_data = ls_valdata
      TABLES
        material_description    = lt_desc
        return                  = lt_return.

    LOOP AT lt_return INTO DATA(ls_ret) WHERE type = lc_e OR type = lc_a.
      APPEND VALUE #(
        material_code = lv_code_ext
        type          = lc_e
        message       = ls_ret-message
      ) TO ls_response-messages.
    ENDLOOP.

    " storage location / bin live at plant+storage-location level (BAPI_MARD),
    " not returned by BAPI_MATERIAL_GET_DETAIL's general/plant/valuation exports -
    " read MARD directly instead of guessing at a BAPI table parameter name.
    DATA(lv_lgort) = space.
    DATA(lv_lgpla) = space.
    IF lv_plant IS NOT INITIAL.
      SELECT SINGLE lgort, lgpla
      FROM mard
      WHERE matnr = @lv_matnr
        AND werks = @lv_plant
      INTO (@lv_lgort, @lv_lgpla).
    ENDIF.

    ls_row-materialcode        = |{ lv_matnr ALPHA = OUT }|.
    ls_row-industrysector      = ls_general-ind_sector.
    ls_row-materialtype        = ls_general-matl_type.
    ls_row-plant                = lv_plant.
    ls_row-storagelocation      = lv_lgort.
    ls_row-storagebin           = lv_lgpla.
    ls_row-baseuom              = ls_general-base_uom.
    ls_row-materialgroup        = ls_general-matl_group.
    ls_row-oldmaterialnumber    = ls_general-old_mat_no.
    ls_row-producthierarchy     = ls_general-prod_hier.
    ls_row-basicmaterial        = ls_general-basic_matl.
    ls_row-variableorderunit    = ls_general-var_ord_un.
    ls_row-purchasinggroup      = ls_plantdata-pur_group.
    ls_row-profitcenter         = ls_plantdata-profit_ctr.
    ls_row-valuationcategory    = ls_valdata-val_cat.
    ls_row-pricedetermination   = ls_valdata-ml_settle.
    ls_row-valuationclass       = ls_valdata-val_class.
    ls_row-priceunit            = ls_valdata-price_unit.
    ls_row-pricecontrol         = ls_valdata-price_ctrl.
    ls_row-movingaverageprice   = ls_valdata-moving_pr.
    ls_row-standardprice        = ls_valdata-std_price.

    READ TABLE lt_desc INTO DATA(ls_desc) WITH KEY langu = sy-langu.
    IF sy-subrc = 0.
      ls_row-shorttext = ls_desc-matl_desc.
    ENDIF.

    APPEND ls_row TO ls_response-material.

    IF ls_response-messages IS INITIAL.
      APPEND VALUE #(
        material_code = lv_code_ext
        type          = lc_s
        message       = 'Material read successfully'
      ) TO ls_response-messages.
    ENDIF.

    send( iv_status = c_http-ok
          iv_body   = /ui2/cl_json=>serialize( data = ls_response ) ).
  ENDMETHOD.


  METHOD send.
    mo_server->response->set_header_field( name  = 'Content-Type'
                                           value = c_content_json ).
    mo_server->response->set_status(
      code   = iv_status
      reason = SWITCH #( iv_status
                 WHEN c_http-ok          THEN 'OK'
                 WHEN c_http-bad_request THEN 'Bad Request'
                 WHEN c_http-not_allowed THEN 'Method Not Allowed'
                 ELSE 'Internal Server Error' ) ).
    mo_server->response->set_cdata( iv_body ).
  ENDMETHOD.


  METHOD error_json.
    TYPES: BEGIN OF ty_error,
             type    TYPE bapi_mtype,
             message TYPE string,
           END OF ty_error.
    rv_json = /ui2/cl_json=>serialize( data = VALUE ty_error( type = 'E' message = iv_text ) ).
  ENDMETHOD.

ENDCLASS.

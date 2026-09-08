"! <p class="shorttext synchronized">Customer BP API - exception</p>
CLASS zcx_cust_bp DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_t100_message.
    INTERFACES if_t100_dyn_msg.

    "! HTTP status the ICF handler returns for this error ( default 422 ).
    DATA http_status TYPE i READ-ONLY.

    METHODS constructor
      IMPORTING textid      LIKE if_t100_message=>t100key OPTIONAL
                previous    LIKE previous                 OPTIONAL
                http_status TYPE i DEFAULT 422.
ENDCLASS.


CLASS zcx_cust_bp IMPLEMENTATION.

  METHOD constructor.
    super->constructor( previous = previous ).
    me->http_status = http_status.
    CLEAR me->textid.
    IF textid IS SUPPLIED AND textid IS NOT INITIAL.
      if_t100_message~t100key = textid.
    ELSE.
      if_t100_message~t100key = if_t100_message=>default_textid.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

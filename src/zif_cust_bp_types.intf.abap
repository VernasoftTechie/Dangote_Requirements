"! <p class="shorttext synchronized">Customer BP API - constants &amp; contract</p>
"! Central constant pool for the inbound ICF service
"! <em>/sap/bc/zcust_bp</em> ( POST = create, GET = read ).
"!
"! The <em>c_default</em> block holds the fallback SAP control values used
"! when the JSON request omits them. Adjust to the client's Customizing.
INTERFACE zif_cust_bp_types
  PUBLIC.

  CONSTANTS:
    BEGIN OF c_method,
      get  TYPE string VALUE 'GET',
      post TYPE string VALUE 'POST',
    END OF c_method.

  CONSTANTS:
    BEGIN OF c_http,
      ok            TYPE i VALUE 200,
      created       TYPE i VALUE 201,
      bad_request   TYPE i VALUE 400,
      forbidden     TYPE i VALUE 403,
      not_found     TYPE i VALUE 404,
      not_allowed   TYPE i VALUE 405,
      unprocessable TYPE i VALUE 422,
      server_error  TYPE i VALUE 500,
    END OF c_http.

  CONSTANTS c_content_json TYPE string VALUE 'application/json; charset=utf-8'.

  CONSTANTS:
    BEGIN OF c_operation,
      create TYPE zcust_bp_id VALUE 'CREATE',
      read   TYPE zcust_bp_id VALUE 'READ',
    END OF c_operation.

  CONSTANTS:
    BEGIN OF c_direction,
      inbound  TYPE zcust_bp_flag VALUE 'I',
      outbound TYPE zcust_bp_flag VALUE 'O',
    END OF c_direction.

  "! Values of ZCUST_BP_LOG-STATUS
  CONSTANTS:
    BEGIN OF c_log_status,
      success     TYPE zcust_bp_flag VALUE 'S',
      error       TYPE zcust_bp_flag VALUE 'E',
      reprocessed TYPE zcust_bp_flag VALUE 'R',
      pending     TYPE zcust_bp_flag VALUE 'P',
    END OF c_log_status.

  CONSTANTS:
    BEGIN OF c_bp_category,
      person       TYPE bu_type VALUE '1',
      organization TYPE bu_type VALUE '2',
      group        TYPE bu_type VALUE '3',
    END OF c_bp_category.

  "! CVI task codes ( BUS_EI_OBJECT_TASK / CMDS_EI_...-TASK ).
  CONSTANTS:
    BEGIN OF c_task,
      insert  TYPE zcust_bp_flag VALUE 'I',
      update  TYPE zcust_bp_flag VALUE 'U',
      modify  TYPE zcust_bp_flag VALUE 'M',
      delete  TYPE zcust_bp_flag VALUE 'D',
      current TYPE zcust_bp_flag VALUE 'C',
    END OF c_task.

  "! Message class of this component.
  CONSTANTS c_msg_class TYPE symsgid VALUE 'ZMSG_CUST_BP'.

  "! Authorization object checked on create / read ( adaptation point -
  "! replace with the client's object / values in the classes ).
  CONSTANTS c_auth_object TYPE zcust_bp_id VALUE 'B_BUPA_RLT'.

  "--------------------------------------------------------------------
  " Default control values  ( ADAPTATION POINTS )
  "--------------------------------------------------------------------
  CONSTANTS:
    BEGIN OF c_default,
      bp_category     TYPE bu_type         VALUE '2',
      bp_grouping     TYPE bu_group        VALUE space,
      partner_role    TYPE bu_partnerrole  VALUE 'FLCU01',
      cust_acct_grp   TYPE ktokd           VALUE space,
      industry_system TYPE string          VALUE '0001',
      country         TYPE land1           VALUE space,
    END OF c_default.

ENDINTERFACE.

"! <p class="shorttext synchronized">BP Customer ICF API - constants &amp; contract</p>
"! Central constant pool for the inbound (POST create) / (GET read) ICF
"! service <em>/sap/bc/zbp_customer</em>.
"!
"! <h2>Adaptation points</h2>
"! The <em>c_default</em> block holds the fallback SAP control values used
"! when the JSON request omits the <em>control</em> object. Adjust them to
"! the client's Customizing, or fill <em>control</em> per request.
INTERFACE zif_bp_cust_types
  PUBLIC.

  "--------------------------------------------------------------------
  " HTTP
  "--------------------------------------------------------------------
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
      not_found     TYPE i VALUE 404,
      not_allowed   TYPE i VALUE 405,
      unprocessable TYPE i VALUE 422,
      server_error  TYPE i VALUE 500,
    END OF c_http.

  CONSTANTS c_content_json TYPE string VALUE 'application/json; charset=utf-8'.

  "--------------------------------------------------------------------
  " Processing log
  "--------------------------------------------------------------------
  CONSTANTS:
    BEGIN OF c_operation,
      create TYPE string VALUE 'CREATE',
      read   TYPE string VALUE 'READ',
    END OF c_operation.

  CONSTANTS:
    BEGIN OF c_direction,
      inbound  TYPE c LENGTH 1 VALUE 'I',
      outbound TYPE c LENGTH 1 VALUE 'O',
    END OF c_direction.

  "! Values of ZBP_CUST_LOG-STATUS
  CONSTANTS:
    BEGIN OF c_log_status,
      success     TYPE c LENGTH 1 VALUE 'S',
      error       TYPE c LENGTH 1 VALUE 'E',
      reprocessed TYPE c LENGTH 1 VALUE 'R',
      pending     TYPE c LENGTH 1 VALUE 'P',
    END OF c_log_status.

  "--------------------------------------------------------------------
  " Business Partner
  "--------------------------------------------------------------------
  CONSTANTS:
    BEGIN OF c_bp_category,
      person       TYPE bu_type VALUE '1',
      organization TYPE bu_type VALUE '2',
      group        TYPE bu_type VALUE '3',
    END OF c_bp_category.

  "! CVI task codes (BUS_EI_OBJECT_TASK / CMDS_EI_...-TASK)
  CONSTANTS:
    BEGIN OF c_task,
      insert  TYPE c LENGTH 1 VALUE 'I',
      update  TYPE c LENGTH 1 VALUE 'U',
      modify  TYPE c LENGTH 1 VALUE 'M',
      delete  TYPE c LENGTH 1 VALUE 'D',
      current TYPE c LENGTH 1 VALUE 'C',
    END OF c_task.

  "--------------------------------------------------------------------
  " Default control values  (ADAPTATION POINTS)
  "--------------------------------------------------------------------
  CONSTANTS:
    BEGIN OF c_default,
      bp_category     TYPE bu_type         VALUE '2',
      bp_grouping     TYPE bu_group        VALUE space,
      partner_role    TYPE bu_partnerrole  VALUE 'FLCU01',
      cust_acct_grp   TYPE ktokd           VALUE space,
      industry_system TYPE string          VALUE '0001',
      country         TYPE land1           VALUE space,
      create_fi       TYPE abap_bool       VALUE abap_false,
      create_sales    TYPE abap_bool       VALUE abap_false,
    END OF c_default.

ENDINTERFACE.

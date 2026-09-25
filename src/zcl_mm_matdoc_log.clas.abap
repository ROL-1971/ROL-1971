"! <p class="shorttext synchronized">Application log (SLG1) for EML on I_MaterialDocumentTP</p>
"! Collects the messages returned in REPORTED / FAILED of a MODIFY ENTITIES
"! or COMMIT ENTITIES statement and writes them to the application log.
"! The parameters are typed generically, so any RAP response structure
"! (early or late) of any BO can be passed in.
CLASS zcl_mm_matdoc_log DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    CONSTANTS:
      c_object    TYPE cl_bali_header_setter=>ty_object    VALUE 'ZMM_MATDOC',
      c_subobject TYPE cl_bali_header_setter=>ty_subobject VALUE 'GOODS_MVT'.

    "! Creates a new log
    "! @parameter iv_external_id | External ID shown in SLG1 (e.g. reservation number)
    CLASS-METHODS create
      IMPORTING iv_object       TYPE cl_bali_header_setter=>ty_object    DEFAULT c_object
                iv_subobject    TYPE cl_bali_header_setter=>ty_subobject DEFAULT c_subobject
                iv_external_id  TYPE cl_bali_header_setter=>ty_external_id OPTIONAL
                iv_expiry_days  TYPE i DEFAULT 30
      RETURNING VALUE(ro_log)   TYPE REF TO zcl_mm_matdoc_log
      RAISING   cx_bali_runtime.

    "! Adds all %msg entries of a REPORTED structure (MODIFY or COMMIT ENTITIES)
    METHODS add_reported
      IMPORTING is_reported TYPE any
                iv_step     TYPE csequence OPTIONAL.

    "! Adds one entry per FAILED instance (entity, %cid / key, fail cause)
    METHODS add_failed
      IMPORTING is_failed TYPE any
                iv_step   TYPE csequence OPTIONAL.

    METHODS add_text
      IMPORTING iv_text     TYPE csequence
                iv_severity TYPE if_bali_constants=>ty_severity DEFAULT if_bali_constants=>c_severity_information.

    METHODS has_errors
      RETURNING VALUE(rv_result) TYPE abap_bool.

    "! Saves the log (own DB connection, so it survives a ROLLBACK ENTITIES)
    METHODS save
      RAISING cx_bali_runtime.

  PRIVATE SECTION.
    DATA mo_log       TYPE REF TO if_bali_log.
    DATA mv_has_error TYPE abap_bool.

    METHODS add_behv_message
      IMPORTING io_msg    TYPE REF TO if_abap_behv_message
                iv_prefix TYPE string.

    METHODS add_item
      IMPORTING io_item     TYPE REF TO if_bali_item_setter
                iv_severity TYPE if_bali_constants=>ty_severity.

    METHODS get_instance_prefix
      IMPORTING iv_entity        TYPE csequence
                is_entry         TYPE any
                iv_step          TYPE csequence
      RETURNING VALUE(rv_prefix) TYPE string.

    METHODS map_severity
      IMPORTING iv_behv_severity   TYPE if_abap_behv_message=>t_severity
      RETURNING VALUE(rv_severity) TYPE if_bali_constants=>ty_severity.
ENDCLASS.


CLASS zcl_mm_matdoc_log IMPLEMENTATION.

  METHOD create.
    ro_log = NEW #( ).
    ro_log->mo_log = cl_bali_log=>create_with_header(
        header = cl_bali_header_setter=>create( object      = iv_object
                                                subobject   = iv_subobject
                                                external_id = iv_external_id
                          )->set_expiry( expiry_date       = CONV d( cl_abap_context_info=>get_system_date( ) + iv_expiry_days )
                                         keep_until_expiry = abap_true ) ).
  ENDMETHOD.


  METHOD add_reported.
    FIELD-SYMBOLS <lt_entity> TYPE ANY TABLE.
    FIELD-SYMBOLS <lo_msg>    TYPE REF TO if_abap_behv_message.

    CHECK is_reported IS NOT INITIAL.

    " REPORTED has one table component per entity (materialdocument, materialdocumentitem, ...)
    DATA(lo_struct) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_data( is_reported ) ).
    LOOP AT lo_struct->components INTO DATA(ls_component).
      ASSIGN COMPONENT ls_component-name OF STRUCTURE is_reported TO <lt_entity>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      LOOP AT <lt_entity> ASSIGNING FIELD-SYMBOL(<ls_entry>).
        ASSIGN COMPONENT '%MSG' OF STRUCTURE <ls_entry> TO <lo_msg>.
        IF sy-subrc <> 0 OR <lo_msg> IS NOT BOUND.
          CONTINUE.
        ENDIF.
        add_behv_message( io_msg    = <lo_msg>
                          iv_prefix = get_instance_prefix( iv_entity = ls_component-name
                                                           is_entry  = <ls_entry>
                                                           iv_step   = iv_step ) ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD add_failed.
    FIELD-SYMBOLS <lt_entity> TYPE ANY TABLE.

    CHECK is_failed IS NOT INITIAL.

    DATA(lo_struct) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_data( is_failed ) ).
    LOOP AT lo_struct->components INTO DATA(ls_component).
      ASSIGN COMPONENT ls_component-name OF STRUCTURE is_failed TO <lt_entity>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      LOOP AT <lt_entity> ASSIGNING FIELD-SYMBOL(<ls_entry>).
        DATA(lv_cause) = ``.
        ASSIGN COMPONENT '%FAIL' OF STRUCTURE <ls_entry> TO FIELD-SYMBOL(<ls_fail>).
        IF sy-subrc = 0.
          ASSIGN COMPONENT 'CAUSE' OF STRUCTURE <ls_fail> TO FIELD-SYMBOL(<lv_cause>).
          IF sy-subrc = 0.
            lv_cause = |{ <lv_cause> }|.
          ENDIF.
        ENDIF.

        add_text( iv_severity = if_bali_constants=>c_severity_error
                  iv_text     = |{ get_instance_prefix( iv_entity = ls_component-name
                                                        is_entry  = <ls_entry>
                                                        iv_step   = iv_step ) }| &&
                                |Instance failed (fail cause { lv_cause })| ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD add_text.
    TRY.
        add_item( io_item     = cl_bali_free_text_setter=>create( severity = iv_severity
                                                                   text     = CONV #( iv_text ) )
                  iv_severity = iv_severity ).
      CATCH cx_bali_runtime.
        " logging must never break the business process
    ENDTRY.
  ENDMETHOD.


  METHOD has_errors.
    rv_result = mv_has_error.
  ENDMETHOD.


  METHOD save.
    IF mo_log->get_all_items( ) IS INITIAL.
      RETURN.
    ENDIF.
    cl_bali_log_db=>get_instance( )->save_log( log                        = mo_log
                                               use_2nd_db_connection      = abap_true
                                               assign_to_current_appl_job = abap_true ).
  ENDMETHOD.


  METHOD add_behv_message.
    DATA(lv_severity) = map_severity( io_msg->m_severity ).

    TRY.
        " context line: which entity / instance the message belongs to
        IF iv_prefix IS NOT INITIAL.
          add_item( io_item     = cl_bali_free_text_setter=>create( severity = lv_severity
                                                                     text     = CONV #( iv_prefix ) )
                    iv_severity = lv_severity ).
        ENDIF.

        IF io_msg IS INSTANCE OF cx_root.
          " message is an exception object (e.g. CX_... with T100 attributes)
          add_item( io_item     = cl_bali_exception_setter=>create( severity  = lv_severity
                                                                     exception = CAST cx_root( io_msg ) )
                    iv_severity = lv_severity ).
        ELSEIF io_msg->if_t100_message~t100key-msgid IS NOT INITIAL.
          " T100 message created via new_message( ) / new_message_with_text( )
          add_item( io_item     = cl_bali_message_setter=>create(
                                      severity   = lv_severity
                                      id         = io_msg->if_t100_message~t100key-msgid
                                      number     = io_msg->if_t100_message~t100key-msgno
                                      variable_1 = io_msg->if_t100_dyn_msg~msgv1
                                      variable_2 = io_msg->if_t100_dyn_msg~msgv2
                                      variable_3 = io_msg->if_t100_dyn_msg~msgv3
                                      variable_4 = io_msg->if_t100_dyn_msg~msgv4 )
                    iv_severity = lv_severity ).
        ELSE.
          add_item( io_item     = cl_bali_free_text_setter=>create( severity = lv_severity
                                                                     text     = CONV #( io_msg->if_message~get_text( ) ) )
                    iv_severity = lv_severity ).
        ENDIF.
      CATCH cx_bali_runtime.
        " logging must never break the business process
    ENDTRY.
  ENDMETHOD.


  METHOD add_item.
    mo_log->add_item( io_item ).
    IF iv_severity = if_bali_constants=>c_severity_error.
      mv_has_error = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD get_instance_prefix.
    " e.g. "[MODIFY] MATERIALDOCUMENTITEM %cid=ITEM_1:"
    DATA(lv_ident) = ``.

    ASSIGN COMPONENT '%CID' OF STRUCTURE is_entry TO FIELD-SYMBOL(<lv_cid>).
    IF sy-subrc = 0 AND <lv_cid> IS NOT INITIAL.
      lv_ident = |%cid={ <lv_cid> }|.
    ENDIF.

    " key fields (filled for existing instances / after COMMIT ENTITIES)
    DATA(lt_keys) = VALUE string_table( ( `MATERIALDOCUMENTYEAR` ) ( `MATERIALDOCUMENT` ) ( `MATERIALDOCUMENTITEM` ) ).
    LOOP AT lt_keys INTO DATA(lv_key).
      ASSIGN COMPONENT lv_key OF STRUCTURE is_entry TO FIELD-SYMBOL(<lv_key>).
      IF sy-subrc = 0 AND <lv_key> IS NOT INITIAL.
        lv_ident = |{ lv_ident } { to_mixed( val = lv_key sep = `_` ) }={ <lv_key> }|.
      ENDIF.
    ENDLOOP.

    rv_prefix = condense( |{ COND #( WHEN iv_step IS NOT INITIAL THEN |[{ iv_step }]| ) } { iv_entity } { lv_ident }:| ).
  ENDMETHOD.


  METHOD map_severity.
    rv_severity = SWITCH #( iv_behv_severity
                            WHEN if_abap_behv_message=>severity-error       THEN if_bali_constants=>c_severity_error
                            WHEN if_abap_behv_message=>severity-warning     THEN if_bali_constants=>c_severity_warning
                            WHEN if_abap_behv_message=>severity-success     THEN if_bali_constants=>c_severity_status
                            ELSE                                                 if_bali_constants=>c_severity_information ).
  ENDMETHOD.

ENDCLASS.

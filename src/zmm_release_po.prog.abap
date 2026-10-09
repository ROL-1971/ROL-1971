*&---------------------------------------------------------------------*
*& Report ZMM_RELEASE_PO
*&---------------------------------------------------------------------*
*& Releases (approves) purchase orders in SAP S/4HANA on-premise using
*& BAPI_PO_RELEASE (same function as ME29N / ME28).
*&
*& - one or many POs via select-option
*& - release code = release strategy code (T16FC-FRGCO) of the approver
*& - test mode (default): BAPI is called, then rolled back
*& - result list as ALV
*&---------------------------------------------------------------------*
REPORT zmm_release_po.

TABLES ekko.

TYPES: BEGIN OF ty_result,
         ebeln      TYPE ekko-ebeln,
         icon       TYPE icon_d,
         rel_status TYPE bapimmpara-rel_status,
         rel_ind    TYPE bapimmpara-rel_ind,
         ret_code   TYPE bapimmpara-ret_code,
         message    TYPE string,
       END OF ty_result.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
SELECT-OPTIONS s_ebeln FOR ekko-ebeln OBLIGATORY.
PARAMETERS     p_rel   TYPE bapimmpara-po_rel_code OBLIGATORY.
PARAMETERS     p_test  AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b1.

DATA gt_result TYPE STANDARD TABLE OF ty_result WITH DEFAULT KEY.

START-OF-SELECTION.
  PERFORM release_orders.
  PERFORM display_result.

*&---------------------------------------------------------------------*
FORM release_orders.
  DATA: lt_ebeln      TYPE STANDARD TABLE OF ekko-ebeln WITH DEFAULT KEY,
        lv_ebeln      TYPE ekko-ebeln,
        lv_po         TYPE bapimmpara-po_number,
        lv_rel_status TYPE bapimmpara-rel_status,
        lv_rel_ind    TYPE bapimmpara-rel_ind,
        lv_ret_code   TYPE bapimmpara-ret_code,
        lt_return     TYPE STANDARD TABLE OF bapireturn,
        ls_return     TYPE bapireturn,
        ls_result     TYPE ty_result,
        ls_bapiret    TYPE bapiret2.

  SELECT ebeln FROM ekko
    INTO TABLE lt_ebeln
    WHERE ebeln IN s_ebeln
    ORDER BY ebeln.

  LOOP AT lt_ebeln INTO lv_ebeln.
    CLEAR: ls_result, lv_rel_status, lv_rel_ind, lv_ret_code.
    REFRESH lt_return.
    ls_result-ebeln = lv_ebeln.
    lv_po           = lv_ebeln.

    CALL FUNCTION 'BAPI_PO_RELEASE'
      EXPORTING
        purchaseorder          = lv_po
        po_rel_code            = p_rel
        use_exceptions         = space
        no_commit              = 'X'
      IMPORTING
        rel_status_new         = lv_rel_status
        rel_indicator_new      = lv_rel_ind
        ret_code               = lv_ret_code
      TABLES
        return                 = lt_return
      EXCEPTIONS
        authority_check_fail   = 1
        document_not_found     = 2
        enqueue_fail           = 3
        prerequisite_fail      = 4
        release_already_posted = 5
        responsibility_fail    = 6
        OTHERS                 = 7.

    ls_result-rel_status = lv_rel_status.
    ls_result-rel_ind    = lv_rel_ind.
    ls_result-ret_code   = lv_ret_code.

    IF sy-subrc <> 0.
      " Exceptions are raised by the BAPI even with USE_EXCEPTIONS = space
      " for some conditions; convert the system message to text
      MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4
              INTO ls_result-message.
      ls_result-icon = icon_led_red.
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    ELSE.
      " RETURN of BAPI_PO_RELEASE is typed BAPIRETURN; type E/A = failure
      READ TABLE lt_return INTO ls_return WITH KEY type = 'E'.
      IF sy-subrc <> 0.
        READ TABLE lt_return INTO ls_return WITH KEY type = 'A'.
      ENDIF.

      IF sy-subrc = 0 OR lv_ret_code <> 0.
        ls_result-icon    = icon_led_red.
        ls_result-message = ls_return-message.
        CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
      ELSEIF p_test = abap_true.
        ls_result-icon    = icon_led_yellow.
        ls_result-message = 'Test run: release would be successful (rolled back)'.
        CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
      ELSE.
        CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
          EXPORTING
            wait   = 'X'
          IMPORTING
            return = ls_bapiret.
        IF ls_bapiret-type CA 'EA'.
          ls_result-icon    = icon_led_red.
          ls_result-message = ls_bapiret-message.
        ELSE.
          ls_result-icon    = icon_led_green.
          ls_result-message = 'Purchase order released'.
        ENDIF.
      ENDIF.
    ENDIF.

    APPEND ls_result TO gt_result.
  ENDLOOP.

  IF lt_ebeln IS INITIAL.
    MESSAGE 'No purchase orders found' TYPE 'S' DISPLAY LIKE 'W'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM display_result.
  DATA lo_alv TYPE REF TO cl_salv_table.

  CHECK gt_result IS NOT INITIAL.

  TRY.
      cl_salv_table=>factory(
        IMPORTING r_salv_table = lo_alv
        CHANGING  t_table      = gt_result ).
      lo_alv->get_functions( )->set_all( abap_true ).
      lo_alv->get_columns( )->set_optimize( abap_true ).
      lo_alv->display( ).
    CATCH cx_salv_msg.
      MESSAGE 'ALV could not be displayed' TYPE 'E'.
  ENDTRY.
ENDFORM.

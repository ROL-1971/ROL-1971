*&---------------------------------------------------------------------*
*& Example: log messages of MODIFY / COMMIT ENTITIES on
*& I_MaterialDocumentTP to the application log (SLG1)
*&---------------------------------------------------------------------*
* ... fill lt_header_create / lt_item_create as before ...

    DATA lo_log TYPE REF TO zcl_mm_matdoc_log.
    TRY.
        lo_log = zcl_mm_matdoc_log=>create( iv_external_id = |Reservation { ls_resb-rsnum }| ).
      CATCH cx_bali_runtime.
        " no log possible (object not maintained in SLG0?) - continue without log
    ENDTRY.

    MODIFY ENTITIES OF i_materialdocumenttp
      ENTITY materialdocument
        CREATE FIELDS ( PostingDate DocumentDate GoodsMovementCode MaterialDocumentHeaderText ManualPrintIsTriggered VersionForPrintingSlip )
        WITH lt_header_create

      ENTITY materialdocument
        CREATE BY \_materialdocumentitem
        FIELDS ( GoodsMovementType Reservation ReservationItem EntryUnit QuantityInEntryUnit ) WITH lt_item_create
      MAPPED   FINAL(ls_mapped)
      FAILED   FINAL(ls_failed)
      REPORTED FINAL(ls_reported).

    IF lo_log IS BOUND.
      lo_log->add_reported( is_reported = ls_reported iv_step = 'MODIFY' ).
      lo_log->add_failed(   is_failed   = ls_failed   iv_step = 'MODIFY' ).
    ENDIF.

    IF ls_failed IS NOT INITIAL.
      ROLLBACK ENTITIES.
    ELSE.
      " most goods-movement errors (stock, period, ...) only come in the save phase
      COMMIT ENTITIES BEGIN
        RESPONSE OF i_materialdocumenttp
        FAILED   DATA(ls_commit_failed)
        REPORTED DATA(ls_commit_reported).

      IF lo_log IS BOUND.
        lo_log->add_reported( is_reported = ls_commit_reported iv_step = 'SAVE' ).
        lo_log->add_failed(   is_failed   = ls_commit_failed   iv_step = 'SAVE' ).
      ENDIF.

      IF ls_commit_failed IS INITIAL AND lo_log IS BOUND.
        " late numbering: get the final material document number
        LOOP AT ls_mapped-materialdocument ASSIGNING FIELD-SYMBOL(<ls_mapped>).
          CONVERT KEY OF i_materialdocumenttp
            FROM <ls_mapped>-%pid
            TO DATA(ls_matdoc_key).
          lo_log->add_text( iv_severity = if_bali_constants=>c_severity_status
                            iv_text     = |Material document { ls_matdoc_key-MaterialDocument }/{ ls_matdoc_key-MaterialDocumentYear } posted| ).
        ENDLOOP.
      ENDIF.
      COMMIT ENTITIES END.
    ENDIF.

    IF lo_log IS BOUND.
      TRY.
          " saved via 2nd DB connection -> kept even after ROLLBACK ENTITIES
          lo_log->save( ).
        CATCH cx_bali_runtime INTO FINAL(lx_bali).
          MESSAGE lx_bali->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
      ENDTRY.
    ENDIF.

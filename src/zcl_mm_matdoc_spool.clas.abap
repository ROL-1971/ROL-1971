"! <p class="shorttext synchronized">Spool request number(s) of a material document output</p>
"! Output of a material document (application MD) is stored in NAST with
"! OBJKY = material document number + year. The spool request is not a NAST
"! field: it is written as a message to the NAST processing log
"! (NAST-CMFPNR -> CMFP). This class reads that log.
"! Uses NAST / CMFP, so it needs classic ABAP (not ABAP Cloud language version).
CLASS zcl_mm_matdoc_spool DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_spool_numbers TYPE STANDARD TABLE OF rspoid WITH EMPTY KEY.

    CONSTANTS:
      c_appl_matdoc TYPE nast-kappl  VALUE 'MD',
      c_channel_print TYPE nast-nacha VALUE '1',
      " message of the processing log that carries the spool number in MSGV1
      " (check in NACE > Output types > Processing log, adjust if your release differs)
      c_log_msgid   TYPE cmfp-msgid  VALUE 'VN',
      c_log_msgno   TYPE cmfp-msgnr  VALUE '000'.

    "! Returns all spool requests created for the printed output of a material document
    "! @parameter iv_mblnr | Material document number
    "! @parameter iv_mjahr | Material document year
    "! @parameter iv_kschl | Output type (optional, e.g. WA01); all print output types if empty
    "! @parameter rt_spool | Spool request numbers, oldest first (empty if none yet)
    METHODS get_spool_numbers
      IMPORTING iv_mblnr        TYPE mblnr
                iv_mjahr        TYPE mjahr
                iv_kschl        TYPE nast-kschl OPTIONAL
      RETURNING VALUE(rt_spool) TYPE ty_spool_numbers.

    "! Convenience: latest spool request, initial if none
    METHODS get_last_spool_number
      IMPORTING iv_mblnr        TYPE mblnr
                iv_mjahr        TYPE mjahr
                iv_kschl        TYPE nast-kschl OPTIONAL
      RETURNING VALUE(rv_spool) TYPE rspoid.
ENDCLASS.


CLASS zcl_mm_matdoc_spool IMPLEMENTATION.

  METHOD get_spool_numbers.
    DATA lv_objky TYPE nast-objky.

    lv_objky = |{ iv_mblnr }{ iv_mjahr }|.

    SELECT cmfpnr FROM nast
      WHERE kappl = @c_appl_matdoc
        AND objky = @lv_objky
        AND nacha = @c_channel_print
        AND ( kschl = @iv_kschl OR @iv_kschl = @space )
        AND cmfpnr <> @space
      INTO TABLE @DATA(lt_nast).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    SELECT msgv1 FROM cmfp
      FOR ALL ENTRIES IN @lt_nast
      WHERE nr    = @lt_nast-cmfpnr
        AND msgid = @c_log_msgid
        AND msgnr = @c_log_msgno
      ORDER BY nr, aptyp
      INTO TABLE @DATA(lt_log).

    LOOP AT lt_log INTO DATA(ls_log).
      DATA(lv_spool) = CONV rspoid( condense( ls_log-msgv1 ) ).
      IF lv_spool CO '0123456789 ' AND lv_spool IS NOT INITIAL.
        APPEND lv_spool TO rt_spool.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD get_last_spool_number.
    DATA(lt_spool) = get_spool_numbers( iv_mblnr = iv_mblnr
                                        iv_mjahr = iv_mjahr
                                        iv_kschl = iv_kschl ).
    IF lt_spool IS NOT INITIAL.
      rv_spool = lt_spool[ lines( lt_spool ) ].
    ENDIF.
  ENDMETHOD.

ENDCLASS.

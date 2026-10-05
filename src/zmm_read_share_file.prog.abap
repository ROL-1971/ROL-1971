*&---------------------------------------------------------------------*
*& Report ZMM_READ_SHARE_FILE
*&---------------------------------------------------------------------*
*& Reads the file(s) of a Windows file share, e.g.
*& \\10.249.20.109\Interface\243A\TO-ERP
*& with OPEN DATASET / READ DATASET on the application server and
*& writes the content to the job spool.
*&
*& The share is accessed by the application server, not by the
*& frontend:
*&   - Windows application server: the UNC path is used directly; the
*&     SAP service user (SAPService<SID>, not <sid>adm) needs read
*&     access to the share.
*&   - Unix/Linux application server: UNC paths cannot be read; mount
*&     the share and enter the mount path in P_DIR.
*&
*& P_FILE empty -> all files matching P_MASK are read.
*& P_FILE filled -> only this file is read.
*& The files are only read, never changed, moved or deleted.
*&
*& Prerequisites:
*&   - Authorization S_DATASET for program ZMM_READ_SHARE_FILE,
*&     activity 33 (read), file name = directory / files
*&
*& If started in dialog, the program schedules itself as a background
*& job (immediate start). Content goes to the job spool, the result
*& is summarized in the job log (SM37).
*&---------------------------------------------------------------------*
REPORT zmm_read_share_file.

PARAMETERS:
  p_dir  TYPE char255 LOWER CASE OBLIGATORY
         DEFAULT '\\10.249.20.109\Interface\243A\TO-ERP',
  p_file TYPE char255 LOWER CASE,
  p_mask TYPE char255 LOWER CASE DEFAULT '*',
  p_max  TYPE i DEFAULT 1000.


START-OF-SELECTION.
  IF sy-batch = abap_false.
    PERFORM schedule_in_background.
  ELSE.
    PERFORM process.
  ENDIF.


*&---------------------------------------------------------------------*
*& Determine the file(s) and read each one
*&---------------------------------------------------------------------*
FORM process.
  DATA lv_dir     TYPE string.
  DATA lv_sep     TYPE string.
  DATA lv_mask    TYPE eps2filnam.
  DATA lv_dir_eps TYPE eps2filnam.
  DATA lv_dir_out TYPE eps2filnam.
  DATA lv_files   TYPE i.
  DATA lv_errors  TYPE i.
  DATA lv_name    TYPE string.
  DATA lv_read    TYPE i.
  DATA lv_failed  TYPE i.
  DATA lt_list    TYPE STANDARD TABLE OF eps2fili WITH DEFAULT KEY.
  DATA ls_list    TYPE eps2fili.
  DATA lt_names   TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
  DATA lv_ok      TYPE abap_bool.

  lv_dir = condense( p_dir ).
  IF lv_dir CS '\'.
    lv_sep = '\'.
  ELSE.
    lv_sep = '/'.
  ENDIF.
  lv_dir = replace( val = lv_dir regex = `[\\/]+$` with = `` ).

  IF p_file IS NOT INITIAL.
    APPEND condense( p_file ) TO lt_names.
  ELSE.
    lv_mask = condense( p_mask ).
    IF lv_mask IS INITIAL.
      lv_mask = '*'.
    ENDIF.
    lv_dir_eps = lv_dir.

    CALL FUNCTION 'EPS_GET_DIRECTORY_LISTING'
      EXPORTING
        dir_name               = lv_dir_eps
        file_mask              = lv_mask
      IMPORTING
        dir_name               = lv_dir_out
        file_counter           = lv_files
        error_counter          = lv_errors
      TABLES
        dir_list               = lt_list
      EXCEPTIONS
        invalid_eps_subdir     = 1
        sapgparam_failed       = 2
        build_directory_failed = 3
        no_authorization       = 4
        read_directory_failed  = 5
        too_many_read_errors   = 6
        empty_directory_list   = 7
        OTHERS                 = 8.
    CASE sy-subrc.
      WHEN 0.
        " ok
      WHEN 4.
        MESSAGE |No authorization S_DATASET (read) for { lv_dir }| TYPE 'E'.
      WHEN 7.
        MESSAGE |No file matching { lv_mask } in { lv_dir }| TYPE 'S'.
        RETURN.
      WHEN OTHERS.
        MESSAGE |Cannot read { lv_dir } (rc { sy-subrc }) - is the share reachable from the application server?| TYPE 'E'.
    ENDCASE.

    SORT lt_list BY name.
    LOOP AT lt_list INTO ls_list.
      lv_name = ls_list-name.
      APPEND lv_name TO lt_names.
    ENDLOOP.
  ENDIF.

  LOOP AT lt_names INTO lv_name.
    PERFORM read_file USING lv_dir lv_sep lv_name CHANGING lv_ok.
    IF lv_ok = abap_true.
      lv_read = lv_read + 1.
    ELSE.
      lv_failed = lv_failed + 1.
    ENDIF.
  ENDLOOP.

  MESSAGE |{ lv_read } file(s) read, { lv_failed } failed - content is in the job spool| TYPE 'S'.
ENDFORM.


*&---------------------------------------------------------------------*
*& Read one file line by line and write it to the spool
*&---------------------------------------------------------------------*
FORM read_file USING    iv_dir  TYPE string
                        iv_sep  TYPE string
                        iv_name TYPE string
               CHANGING cv_ok   TYPE abap_bool.
  DATA lv_path  TYPE string.
  DATA lv_line  TYPE string.
  DATA lv_count TYPE i.
  DATA lx_auth  TYPE REF TO cx_sy_file_authority.
  DATA lx_file  TYPE REF TO cx_root.

  cv_ok   = abap_false.
  lv_path = |{ iv_dir }{ iv_sep }{ iv_name }|.

  ULINE.
  WRITE: / 'File:', lv_path.
  ULINE.

  TRY.
      OPEN DATASET lv_path FOR INPUT IN TEXT MODE ENCODING DEFAULT
           IGNORING CONVERSION ERRORS.
      IF sy-subrc <> 0.
        MESSAGE |Cannot open { lv_path }| TYPE 'S'.
        WRITE: / 'ERROR: cannot open file'.
        RETURN.
      ENDIF.

      DO.
        READ DATASET lv_path INTO lv_line.
        IF sy-subrc <> 0.
          EXIT.
        ENDIF.
        lv_count = lv_count + 1.
        IF p_max > 0 AND lv_count > p_max.
          WRITE: / '... truncated after', p_max, 'lines'.
          EXIT.
        ENDIF.
        WRITE: / lv_line.
      ENDDO.
      CLOSE DATASET lv_path.
      cv_ok = abap_true.
      MESSAGE |{ lv_path }: { lv_count } line(s) read| TYPE 'S'.
    CATCH cx_sy_file_authority INTO lx_auth.
      MESSAGE |No authorization S_DATASET (read) for { lv_path }: { lx_auth->get_text( ) }| TYPE 'S'.
      WRITE: / 'ERROR: no authorization'.
    CATCH cx_sy_file_open cx_sy_file_io cx_sy_file_close cx_sy_conversion_codepage INTO lx_file.
      MESSAGE |{ lv_path }: { lx_file->get_text( ) }| TYPE 'S'.
      WRITE: / 'ERROR:', lx_file->get_text( ).
  ENDTRY.
ENDFORM.


*&---------------------------------------------------------------------*
*& Started in dialog: submit this report as a background job
*&---------------------------------------------------------------------*
FORM schedule_in_background.
  DATA lv_jobname  TYPE tbtcjob-jobname VALUE 'ZMM_READ_SHARE_FILE'.
  DATA lv_jobcount TYPE tbtcjob-jobcount.

  CALL FUNCTION 'JOB_OPEN'
    EXPORTING
      jobname  = lv_jobname
    IMPORTING
      jobcount = lv_jobcount
    EXCEPTIONS
      OTHERS   = 1.
  IF sy-subrc <> 0.
    MESSAGE 'Background job could not be created (JOB_OPEN)' TYPE 'E'.
  ENDIF.

  SUBMIT zmm_read_share_file
    WITH p_dir  = p_dir
    WITH p_file = p_file
    WITH p_mask = p_mask
    WITH p_max  = p_max
    VIA JOB lv_jobname NUMBER lv_jobcount
    AND RETURN.

  CALL FUNCTION 'JOB_CLOSE'
    EXPORTING
      jobname   = lv_jobname
      jobcount  = lv_jobcount
      strtimmed = abap_true
    EXCEPTIONS
      OTHERS    = 1.
  IF sy-subrc <> 0.
    MESSAGE 'Background job could not be released (JOB_CLOSE)' TYPE 'E'.
  ENDIF.

  MESSAGE |Job { lv_jobname } / { lv_jobcount } started - see SM37 (job log + spool)| TYPE 'S'.
ENDFORM.

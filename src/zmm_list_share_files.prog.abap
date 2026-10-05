*&---------------------------------------------------------------------*
*& Report ZMM_LIST_SHARE_FILES
*&---------------------------------------------------------------------*
*& Lists the files of an external file share / directory as seen from
*& the application server, e.g. \\10.249.20.109\Interface\243A\TO-ERP
*&
*& The directory is read on the application server (not on the
*& frontend), so the share must be reachable from there:
*&   - Windows application server: the UNC path can be used directly
*&     and the SAP service user needs read access to the share.
*&   - Unix/Linux application server: a UNC path cannot be read; the
*&     share has to be mounted (e.g. /nfs/.../Interface/243A/TO-ERP)
*&     and the mount path entered in P_DIR.
*&
*& Prerequisites:
*&   - Authorization S_DATASET for program ZMM_LIST_SHARE_FILES,
*&     activity 33 (read), file name = directory
*&
*& If started in dialog, the program schedules itself as a background
*& job (immediate start). The file list is written to the job spool
*& and the result is summarized in the job log (SM37).
*&---------------------------------------------------------------------*
REPORT zmm_list_share_files.

PARAMETERS:
  p_dir  TYPE char255 LOWER CASE OBLIGATORY
         DEFAULT '\\10.249.20.109\Interface\243A\TO-ERP',
  p_mask TYPE char255 LOWER CASE DEFAULT '*'.


START-OF-SELECTION.
  IF sy-batch = abap_false.
    PERFORM schedule_in_background.
  ELSE.
    PERFORM list_files.
  ENDIF.


*&---------------------------------------------------------------------*
*& Read the directory and write one line per file
*&---------------------------------------------------------------------*
FORM list_files.
  DATA lv_dir      TYPE eps2filnam.
  DATA lv_mask     TYPE eps2filnam.
  DATA lv_dir_out  TYPE eps2filnam.
  DATA lv_files    TYPE i.
  DATA lv_errors   TYPE i.
  DATA lt_list     TYPE STANDARD TABLE OF eps2fili WITH DEFAULT KEY.
  DATA ls_list     TYPE eps2fili.
  DATA lv_size     TYPE string.

  lv_dir  = condense( p_dir ).
  lv_mask = condense( p_mask ).
  IF lv_mask IS INITIAL.
    lv_mask = '*'.
  ENDIF.

  MESSAGE |Reading directory { lv_dir } (mask { lv_mask })| TYPE 'S'.

  CALL FUNCTION 'EPS_GET_DIRECTORY_LISTING'
    EXPORTING
      dir_name               = lv_dir
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
      MESSAGE |Directory { lv_dir } is empty (no file matches { lv_mask })| TYPE 'S'.
      RETURN.
    WHEN OTHERS.
      MESSAGE |Cannot read { lv_dir } (rc { sy-subrc }) - is the share mounted / reachable from the application server?| TYPE 'E'.
  ENDCASE.

  SORT lt_list BY name.

  WRITE: / 'Directory:', lv_dir.
  WRITE: / 'Files    :', lv_files.
  ULINE.
  LOOP AT lt_list INTO ls_list.
    lv_size = |{ ls_list-size }|.
    WRITE: / ls_list-name, lv_size.
  ENDLOOP.

  MESSAGE |{ lv_files } file(s) found in { lv_dir } (read errors: { lv_errors }) - list is in the job spool| TYPE 'S'.
ENDFORM.


*&---------------------------------------------------------------------*
*& Started in dialog: submit this report as a background job
*&---------------------------------------------------------------------*
FORM schedule_in_background.
  DATA lv_jobname  TYPE tbtcjob-jobname VALUE 'ZMM_LIST_SHARE_FILES'.
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

  SUBMIT zmm_list_share_files
    WITH p_dir  = p_dir
    WITH p_mask = p_mask
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

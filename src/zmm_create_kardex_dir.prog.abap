*&---------------------------------------------------------------------*
*& Report ZMM_CREATE_KARDEX_DIR
*&---------------------------------------------------------------------*
*& Creates a directory on the application server (visible in AL11),
*& e.g. /nfs/a248_sap/SI4/Kardex/Historique
*&
*& ABAP has no statement to create a directory. Without an SM69
*& command, the OS command "mkdir -p" is started through the FILTER
*& addition of OPEN DATASET: the data written to the dataset is piped
*& through the filter command, which runs in a shell on the
*& application server. A temporary file in the base directory is used
*& as the dataset and deleted afterwards.
*&
*& Prerequisites:
*&   - Application server on Unix/Linux (FILTER is not supported on
*&     all platforms)
*&   - Authorization S_DATASET for program ZMM_CREATE_KARDEX_DIR,
*&     activities 34 (write), A7 (write with filter), 06 (delete),
*&     file name = base directory
*&   - OS user <sid>adm may write in the base directory
*&
*& If started in dialog, the program schedules itself as a background
*& job (immediate start). The result is written to the job log (SM37).
*&---------------------------------------------------------------------*
REPORT zmm_create_kardex_dir.

PARAMETERS:
  p_base TYPE char255 LOWER CASE OBLIGATORY DEFAULT '/nfs/a248_sap/SI4/Kardex',
  p_dir  TYPE char255 LOWER CASE OBLIGATORY DEFAULT 'Historique'.


START-OF-SELECTION.
  IF sy-batch = abap_false.
    PERFORM schedule_in_background.
  ELSE.
    PERFORM create_directory.
  ENDIF.


*&---------------------------------------------------------------------*
*& Build /base/dir, validate it and run "mkdir -p <path>"
*&---------------------------------------------------------------------*
FORM create_directory.
  " base and full path, remove duplicate / trailing slashes (a248_sap//SI4)
  DATA(lv_base) = replace( val = condense( p_base ) regex = `/{2,}` with = `/` occ = 0 ).
  lv_base = replace( val = lv_base regex = `/$` with = `` ).
  DATA(lv_path) = replace( val = |{ lv_base }/{ condense( p_dir ) }| regex = `/{2,}` with = `/` occ = 0 ).
  lv_path = replace( val = lv_path regex = `/$` with = `` ).

  " the path goes into a shell command: allow only a plain absolute
  " path - no blanks, quotes, ; | & $ ` or ".."
  IF NOT matches( val = lv_path regex = `^/[A-Za-z0-9_./-]+$` )
     OR lv_path CS '..'.
    MESSAGE |Invalid directory name: { lv_path }| TYPE 'E'.
  ENDIF.

  MESSAGE |Creating directory { lv_path }| TYPE 'S'.

  " 1) run mkdir via FILTER; stdout of the filter goes to the temp file
  DATA(lv_tmp_file) = |{ lv_base }/.zmkdir_{ sy-datum }{ sy-uzeit }.tmp|.
  DATA(lv_filter)   = |mkdir -p { lv_path } 2>&1; echo "RC=$?"|.

  TRY.
      OPEN DATASET lv_tmp_file FOR OUTPUT IN TEXT MODE ENCODING DEFAULT
           FILTER lv_filter.
      IF sy-subrc <> 0.
        MESSAGE |Cannot open { lv_tmp_file } (no write access to { lv_base }?)| TYPE 'E'.
      ENDIF.
      CLOSE DATASET lv_tmp_file.   " waits until the command has finished
    CATCH cx_sy_file_authority INTO DATA(lx_auth).
      MESSAGE |No authorization S_DATASET: { lx_auth->get_text( ) }| TYPE 'E'.
    CATCH cx_sy_file_open cx_sy_file_io cx_sy_file_close INTO DATA(lx_file).
      MESSAGE lx_file->get_text( ) TYPE 'E'.
  ENDTRY.

  " 2) read the command output (mkdir errors + return code) -> job log
  DATA(lv_rc) = ``.
  TRY.
      OPEN DATASET lv_tmp_file FOR INPUT IN TEXT MODE ENCODING DEFAULT.
      IF sy-subrc = 0.
        DO.
          READ DATASET lv_tmp_file INTO DATA(lv_line).
          IF sy-subrc <> 0.
            EXIT.
          ENDIF.
          IF lv_line CP 'RC=*'.
            lv_rc = substring_after( val = lv_line sub = `RC=` ).
          ELSEIF lv_line IS NOT INITIAL.
            MESSAGE lv_line TYPE 'S'.
          ENDIF.
        ENDDO.
        CLOSE DATASET lv_tmp_file.
      ENDIF.
      DELETE DATASET lv_tmp_file.
    CATCH cx_sy_file_authority cx_sy_file_open cx_sy_file_io cx_sy_file_close.
      " temp file is only for diagnostics - the real check follows
  ENDTRY.

  " 3) verify: write and delete a test file inside the new directory
  DATA(lv_test_file) = |{ lv_path }/.zmkdir_check.tmp|.
  TRY.
      OPEN DATASET lv_test_file FOR OUTPUT IN TEXT MODE ENCODING DEFAULT.
      DATA(lv_ok) = xsdbool( sy-subrc = 0 ).
      IF lv_ok = abap_true.
        CLOSE DATASET lv_test_file.
        DELETE DATASET lv_test_file.
      ENDIF.
    CATCH cx_sy_file_authority cx_sy_file_open cx_sy_file_io cx_sy_file_close.
      lv_ok = abap_false.
  ENDTRY.

  IF lv_ok = abap_true.
    " mkdir -p also succeeds if the directory already exists
    MESSAGE |Directory { lv_path } is available (AL11)| TYPE 'S'.
  ELSE.
    MESSAGE |Directory { lv_path } not created (mkdir return code { lv_rc })| TYPE 'E'.
  ENDIF.
ENDFORM.


*&---------------------------------------------------------------------*
*& Started in dialog: submit this report as a background job
*&---------------------------------------------------------------------*
FORM schedule_in_background.
  DATA lv_jobname  TYPE tbtcjob-jobname VALUE 'ZMM_CREATE_KARDEX_DIR'.
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

  SUBMIT zmm_create_kardex_dir
    WITH p_base = p_base
    WITH p_dir  = p_dir
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

  MESSAGE |Job { lv_jobname } / { lv_jobcount } started - see SM37 job log| TYPE 'S'.
ENDFORM.

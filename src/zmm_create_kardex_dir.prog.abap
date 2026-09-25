*&---------------------------------------------------------------------*
*& Report ZMM_CREATE_KARDEX_DIR
*&---------------------------------------------------------------------*
*& Creates a directory on the application server (visible in AL11),
*& e.g. /nfs/a248_sap/SI4/Kardex/Historique
*&
*& ABAP has no statement to create a directory, so the program calls
*& the external OS command ZMKDIR (transaction SM69) via
*& SXPG_COMMAND_EXECUTE. This works in dialog and in background.
*&
*& Prerequisite - SM69, create command:
*&   Command name ............ ZMKDIR
*&   Operating system ........ Linux   (same value as SY-OPSYS)
*&   OS command .............. mkdir
*&   Parameters for OS command -p
*&   [X] Additional parameters allowed
*& Authorization: S_LOG_COM for command ZMKDIR (user of the job step)
*&
*& If started in dialog, the program schedules itself as a background
*& job (immediate start). The result is written to the job log (SM37).
*&---------------------------------------------------------------------*
REPORT zmm_create_kardex_dir.

CONSTANTS gc_command TYPE sxpgcolist-name VALUE 'ZMKDIR'.

PARAMETERS:
  p_base TYPE sxpgcolist-parameters LOWER CASE OBLIGATORY DEFAULT '/nfs/a248_sap/SI4/Kardex',
  p_dir  TYPE sxpgcolist-parameters LOWER CASE OBLIGATORY DEFAULT 'Historique'.


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
  DATA lt_protocol TYPE STANDARD TABLE OF btcxpm WITH EMPTY KEY.
  DATA lv_status   TYPE extcmdexex-status.
  DATA lv_exitcode TYPE extcmdexex-exitcode.

  " full path, remove duplicate / trailing slashes (e.g. a248_sap//SI4)
  DATA(lv_path) = |{ condense( p_base ) }/{ condense( p_dir ) }|.
  lv_path = replace( val = lv_path regex = `/{2,}` with = `/` occ = 0 ).
  lv_path = replace( val = lv_path regex = `/$`    with = ``  ).

  " only allow a plain absolute path - no shell characters, no ".."
  IF NOT matches( val = lv_path regex = `^/[A-Za-z0-9_./-]+$` )
     OR lv_path CS '..'.
    MESSAGE |Invalid directory name: { lv_path }| TYPE 'E'.
  ENDIF.

  MESSAGE |Creating directory { lv_path }| TYPE 'S'.

  CALL FUNCTION 'SXPG_COMMAND_EXECUTE'
    EXPORTING
      commandname                   = gc_command
      additional_parameters         = CONV sxpgcolist-parameters( lv_path )
      operatingsystem               = sy-opsys
      terminationwait               = abap_true
    IMPORTING
      status                        = lv_status
      exitcode                      = lv_exitcode
    TABLES
      exec_protocol                 = lt_protocol
    EXCEPTIONS
      no_permission                 = 1
      command_not_found             = 2
      parameters_too_long           = 3
      security_risk                 = 4
      wrong_check_call_interface    = 5
      program_start_error           = 6
      program_termination_error     = 7
      x_error                       = 8
      parameter_expected            = 9
      too_many_parameters           = 10
      illegal_command               = 11
      wrong_asynchronous_parameters = 12
      cant_enq_tbtco_entry          = 13
      jobcount_generation_error     = 14
      OTHERS                        = 15.
  DATA(lv_subrc) = sy-subrc.

  " OS output (stdout/stderr of mkdir) -> job log
  LOOP AT lt_protocol INTO DATA(ls_protocol).
    MESSAGE ls_protocol-message TYPE 'S'.
  ENDLOOP.

  IF lv_subrc <> 0.
    DATA(lv_reason) = SWITCH string( lv_subrc
      WHEN 1  THEN `no authorization (S_LOG_COM)`
      WHEN 2  THEN |command { gc_command } not defined in SM69 for { sy-opsys }|
      WHEN 4  THEN `security risk - path contains forbidden characters`
      ELSE         |SXPG_COMMAND_EXECUTE sy-subrc = { lv_subrc }| ).
    MESSAGE |Directory { lv_path } not created: { lv_reason }| TYPE 'E'.
  ELSEIF lv_status <> 'O' OR lv_exitcode <> 0.
    MESSAGE |Directory { lv_path } not created: mkdir status { lv_status } exit code { lv_exitcode }| TYPE 'E'.
  ELSE.
    " mkdir -p also returns 0 if the directory already exists
    MESSAGE |Directory { lv_path } is available (AL11)| TYPE 'S'.
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

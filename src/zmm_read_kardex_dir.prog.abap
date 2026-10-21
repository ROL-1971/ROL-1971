*&---------------------------------------------------------------------*
*& Report ZMM_READ_KARDEX_DIR
*&---------------------------------------------------------------------*
*& Lists the files of an application server directory (visible in
*& AL11), e.g. /nfs/a248_sap/SI4/Kardex/Historique, and optionally
*& prints their content.
*&
*& The list is read with function module EPS2_GET_DIRECTORY_LISTING,
*& the content with OPEN DATASET ... FOR INPUT / READ DATASET.
*&
*& Prerequisites:
*&   - Authorization S_DATASET for program ZMM_READ_KARDEX_DIR,
*&     activity 33 (read), file name = directory / files
*&   - OS user <sid>adm may read the directory
*&
*& Can be run in dialog or as background job (SM36/SM37): the output
*& is then written to the spool list.
*&---------------------------------------------------------------------*
REPORT zmm_read_kardex_dir.

PARAMETERS:
  p_dir  TYPE char255 LOWER CASE OBLIGATORY DEFAULT '/nfs/a248_sap/SI4/Kardex/Historique',
  p_mask TYPE char255 LOWER CASE DEFAULT '*',
  p_read AS CHECKBOX DEFAULT abap_true,
  p_max  TYPE i DEFAULT 200.


START-OF-SELECTION.
  PERFORM main.


*&---------------------------------------------------------------------*
*& Validate the directory, list the files and print their content
*&---------------------------------------------------------------------*
FORM main.
  DATA lv_dir      TYPE string.
  DATA lv_mask     TYPE string.
  DATA lv_dir_name TYPE epsf-epsdirnh.
  DATA lv_mask_c   TYPE epsf-epsfilnam.
  DATA lt_files    TYPE STANDARD TABLE OF eps2fili WITH DEFAULT KEY.
  DATA ls_file     TYPE eps2fili.
  DATA lv_count    TYPE i.

  " remove duplicate / trailing slashes (a248_sap//SI4)
  lv_dir = replace( val = condense( p_dir ) regex = `/{2,}` with = `/` occ = 0 ).
  lv_dir = replace( val = lv_dir regex = `/$` with = `` ).

  " plain absolute path only: no blanks, quotes, shell characters or ".."
  IF NOT matches( val = lv_dir regex = `^/[A-Za-z0-9_./-]+$` )
     OR lv_dir CS '..'.
    MESSAGE |Invalid directory name: { lv_dir }| TYPE 'E'.
  ENDIF.

  lv_mask = condense( p_mask ).
  IF lv_mask IS INITIAL.
    lv_mask = `*`.
  ENDIF.
  IF NOT matches( val = lv_mask regex = `^[A-Za-z0-9_.*?-]+$` ).
    MESSAGE |Invalid file mask: { lv_mask }| TYPE 'E'.
  ENDIF.

  IF strlen( lv_dir ) > 60.
    MESSAGE |Directory name longer than 60 characters: { lv_dir }| TYPE 'E'.
  ENDIF.
  lv_dir_name = lv_dir.
  lv_mask_c   = lv_mask.

  CALL FUNCTION 'EPS2_GET_DIRECTORY_LISTING'
    EXPORTING
      iv_dir_name            = lv_dir_name
      file_mask              = lv_mask_c
    TABLES
      dir_list               = lt_files
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
    WHEN 4.
      MESSAGE |No authorization to read { lv_dir }| TYPE 'E'.
    WHEN 7.
      WRITE: / |Directory { lv_dir } is empty (mask { lv_mask })|.
      RETURN.
    WHEN OTHERS.
      MESSAGE |Cannot read directory { lv_dir } (return code { sy-subrc })| TYPE 'E'.
  ENDCASE.

  SORT lt_files BY name.
  lv_count = lines( lt_files ).

  WRITE: / |Directory: { lv_dir }|.
  WRITE: / |Mask:      { lv_mask }|.
  WRITE: / |Files:     { lv_count }|.
  ULINE.
  LOOP AT lt_files INTO ls_file.
    WRITE: / ls_file-name, ls_file-size, ls_file-mtime.
  ENDLOOP.

  IF p_read = abap_true.
    LOOP AT lt_files INTO ls_file.
      PERFORM print_file USING lv_dir ls_file-name.
    ENDLOOP.
  ENDIF.
ENDFORM.


*&---------------------------------------------------------------------*
*& Print the first P_MAX lines of one file
*&---------------------------------------------------------------------*
FORM print_file USING iv_dir  TYPE string
                      iv_name TYPE any.
  DATA lv_file  TYPE string.
  DATA lv_line  TYPE string.
  DATA lv_lines TYPE i.
  DATA lx_file  TYPE REF TO cx_root.

  lv_file = |{ iv_dir }/{ condense( iv_name ) }|.

  ULINE.
  WRITE: / |File: { lv_file }|.

  TRY.
      OPEN DATASET lv_file FOR INPUT IN TEXT MODE ENCODING DEFAULT.
      IF sy-subrc <> 0.
        " sub-directory or file that cannot be opened
        WRITE: / '  (cannot be opened - directory or no access)'.
        RETURN.
      ENDIF.

      DO.
        READ DATASET lv_file INTO lv_line.
        IF sy-subrc <> 0.
          EXIT.
        ENDIF.
        lv_lines = lv_lines + 1.
        IF lv_lines > p_max.
          WRITE: / |  ... truncated after { p_max } lines|.
          EXIT.
        ENDIF.
        WRITE: / lv_line.
      ENDDO.

      CLOSE DATASET lv_file.
    CATCH cx_sy_file_authority INTO lx_file.
      WRITE: / |  No authorization S_DATASET: { lx_file->get_text( ) }|.
    CATCH cx_sy_file_open cx_sy_file_io cx_sy_file_close
          cx_sy_conversion_codepage INTO lx_file.
      WRITE: / |  { lx_file->get_text( ) }|.
  ENDTRY.
ENDFORM.

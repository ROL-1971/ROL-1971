- 👋 Hi, I’m @ROL-1971
- 👀 I’m interested in ...
- 🌱 I’m currently learning ...
- 💞️ I’m looking to collaborate on ...
- 📫 How to reach me ...

<!---
ROL-1971/ROL-1971 is a ✨ special ✨ repository because its `README.md` (this file) appears on your GitHub profile.
You can click the Preview link to take a look at your changes.
--->

## ZCL_MM_MATDOC_LOG – SLG1 log for I_MaterialDocumentTP

Writes REPORTED / FAILED of `MODIFY ENTITIES` and `COMMIT ENTITIES` on
`I_MaterialDocumentTP` to the application log.

Setup: create log object `ZMM_MATDOC` with subobject `GOODS_MVT` in SLG0
(or an Application Log Object in ADT for ABAP Cloud).

See `src/zmm_matdoc_log_usage.prog.abap` for how to call it.

## ZMM_CREATE_KARDEX_DIR – create an AL11 directory in background

Creates `/nfs/a248_sap/SI4/Kardex/Historique` (parameters `P_BASE` / `P_DIR`)
without SM69: `mkdir -p` is started via `OPEN DATASET ... FILTER`, then the
directory is verified by writing/deleting a test file.
Needs S_DATASET (activities 34, A7, 06). Run in dialog → schedules itself as a
background job; result in the SM37 job log.

## ZCL_MM_MATDOC_SPOOL

Returns the spool request number(s) of the printed output of a material document
(NAST application `MD` -> processing log in `CMFP`).

```abap
DATA(lv_spool) = NEW zcl_mm_matdoc_spool( )->get_last_spool_number(
                   iv_mblnr = ls_matdoc_key-MaterialDocument
                   iv_mjahr = ls_matdoc_key-MaterialDocumentYear ).
```

Output is processed after the save (NAST / RSNAST00), so call it after `COMMIT ENTITIES`
and, if output is dispatched by a batch job, only once that job has run. The processing-log
message in `c_log_msgid` / `c_log_msgno` must be verified in the target system.

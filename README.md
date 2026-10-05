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

## ZMM_LIST_SHARE_FILES – list files of an external share in background

Lists the files of `\\10.249.20.109\Interface\243A\TO-ERP` (parameters `P_DIR` /
`P_MASK`) using `EPS_GET_DIRECTORY_LISTING` on the application server. The file
list goes to the job spool, the summary to the SM37 job log.
Windows app server: the UNC path works directly. Unix/Linux app server: mount the
share and enter the mount path in `P_DIR` (UNC paths cannot be read there).
Needs S_DATASET (activity 33). Run in dialog → schedules itself as a background job.

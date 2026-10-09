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

## ZMM_RELEASE_PO – release purchase orders (S/4HANA on-premise)

Releases POs via `BAPI_PO_RELEASE` (equivalent of ME29N). Selection: PO
numbers (`S_EBELN`) and the release code (`P_REL`, T16FC-FRGCO) of the
approving user. `P_TEST` (default on) runs the BAPI and rolls back; untick to
commit. Result list as ALV (green/yellow/red).
Needs authorization object M_EINK_FRG for the release code/group.
For ABAP Cloud / released APIs there is no BAPI – use the PO release action
of the Fiori app "Manage Purchase Orders" instead.

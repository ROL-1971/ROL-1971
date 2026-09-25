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

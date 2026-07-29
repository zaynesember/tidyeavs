# Package datasets referenced by bare name inside functions. Declaring them
# here keeps R CMD check from flagging them as undefined global variables.
utils::globalVariables(c(
  "eavs_manifest",
  "eavs_dictionary",
  "eavs_jurisdictions"
))

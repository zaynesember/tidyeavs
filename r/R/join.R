#' Attach a table to an EAVS frame without fanning out or dropping rows
#'
#' A left join that keeps every row of `x` and adds columns from `y`, guarding
#' the two ways a join on EAVS identifiers goes wrong on its own. A code shared
#' by two published rows matches both and multiplies `x`'s rows, inflating any
#' sum taken afterward; a row with no match in `y` disappears. Base `merge()`
#' does both silently and pandas does the first silently, so this reports each
#' before it reaches a total.
#'
#' The fan-out is Wisconsin's: three town/village pairs share one serial code
#' (`82575` and `84275` in 2020, `31550` in 2022), so joining a panel to
#' [eavs_jurisdictions] on `fips_code` alone turns four rows into eight and
#' overstates the state's 2020 `partic_total` by 0.35%. `eavs_join()` stops and
#' names the shared codes; adding `jurisdiction_name` to `by` matches the pairs
#' exactly, since the town and village differ only in name. The drop is Maine's:
#' its UOCAVA totals sit in a statewide row carrying no county FIPS, so a
#' county-keyed join loses them. `eavs_join()` counts the unmatched rows rather
#' than letting them vanish.
#'
#' Columns already in `x` are kept from `x`; `eavs_join()` adds only `y`'s new
#' columns, so attaching [eavs_jurisdictions] to a panel brings in the county
#' FIPS, structural type, and quirk flags without duplicating the identifiers
#' the panel already carries.
#'
#' Nothing is corrected here: a shared code and a statewide row are how the
#' jurisdictions reported, and the join reports them rather than resolving them.
#'
#' @param x The frame to keep every row of: a panel from [eavs_load()], one
#'   harmonized year, or any frame carrying the join columns.
#' @param y The frame to attach. Defaults to [eavs_jurisdictions], the common
#'   case of adding structural type, county FIPS, and quirk flags to a panel.
#' @param by Character vector of columns to join on. Defaults to whichever of
#'   `"year"` and `"fips_code"` are in both frames.
#' @param multiple What to do when a key matches several rows in `y` and so fans
#'   out `x`. `"error"` (default) stops and names the shared keys; `"all"`
#'   performs the expansion.
#' @param unmatched What to do with rows of `x` that match nothing in `y`.
#'   `"inform"` (default) reports the count, `"warn"` raises a warning, `"error"`
#'   stops, and `"ignore"` says nothing. The rows are kept either way, with `NA`
#'   in `y`'s columns.
#'
#' @return `x` with `y`'s new columns attached, one row per row of `x` unless
#'   `multiple = "all"` expands a shared code.
#' @seealso [eavs_jurisdictions] for the quirk flags this join surfaces,
#'   [eavs_aggregate()] and [eavs_rate()] for rollups that handle these rows
#'   without a join you write yourself.
#' @export
#'
#' @examples
#' \dontrun{
#' panel <- eavs_load(c(2020, 2022))
#'
#' # Attach county FIPS, type, and quirk flags. Stops on Wisconsin's shared
#' # codes rather than fanning them out.
#' eavs_join(panel, by = c("year", "fips_code", "jurisdiction_name"))
#' }
eavs_join <- function(x,
                      y = eavs_jurisdictions,
                      by = NULL,
                      multiple = c("error", "all"),
                      unmatched = c("inform", "warn", "error", "ignore")) {
  multiple <- match.arg(multiple)
  unmatched <- match.arg(unmatched)

  if (is.null(by)) {
    by <- intersect(c("year", "fips_code"), intersect(names(x), names(y)))
    if (length(by) == 0) {
      cli::cli_abort(c(
        "No columns to join on.",
        i = paste(
          "{.arg x} and {.arg y} share neither {.field year} nor",
          "{.field fips_code}; pass {.arg by} explicitly."
        )
      ))
    }
  }
  missing_x <- setdiff(by, names(x))
  missing_y <- setdiff(by, names(y))
  if (length(missing_x) > 0 || length(missing_y) > 0) {
    cli::cli_abort(c(
      "{.arg by} names columns that are not in both frames.",
      "x" = if (length(missing_x) > 0) "Missing from {.arg x}: {.field {missing_x}}.",
      "x" = if (length(missing_y) > 0) "Missing from {.arg y}: {.field {missing_y}}."
    ))
  }

  x_key <- key_string(x, by)
  y_key <- key_string(y, by)

  # Fan-out: a key appearing more than once in y multiplies x's matching rows.
  dup <- unique(y_key[duplicated(y_key)])
  offending <- dup[dup %in% x_key]
  if (length(offending) > 0 && multiple == "error") {
    show_codes <- key_display(utils::head(offending, 5L), by)
    more <- if (length(offending) > 5L) " (first 5 shown)" else ""
    can_disambiguate <- "jurisdiction_name" %in% names(x) &&
      "jurisdiction_name" %in% names(y) &&
      !"jurisdiction_name" %in% by
    cli::cli_abort(c(
      paste(
        "Joining on {.field {by}} would fan out {.arg x}: {length(offending)}",
        "key{?s} match more than one row in {.arg y}."
      ),
      "*" = "Shared: {.val {show_codes}}{more}.",
      i = if (can_disambiguate) paste(
        "These are distinct jurisdictions sharing one published code (Wisconsin",
        "town/village pairs). Add {.val jurisdiction_name} to {.arg by} to match",
        "them exactly."
      ),
      i = "Or pass {.code multiple = \"all\"} to keep the fanned-out rows."
    ))
  }

  # Silent drop: a row of x matching nothing in y.
  unmatched_rows <- !x_key %in% y_key
  n_unmatched <- sum(unmatched_rows)
  if (n_unmatched > 0 && unmatched != "ignore") {
    headline <- paste(
      "{n_unmatched} row{?s} of {.arg x} matched nothing in {.arg y};",
      "their {.arg y} columns are {.field NA}."
    )
    if ("state_abbr" %in% names(x)) {
      states <- sort(unique(x$state_abbr[unmatched_rows]))
      shown <- utils::head(states, 6L)
      more_states <- if (length(states) > length(shown)) " and more" else ""
      where <- "Unmatched rows are in {.val {shown}}{more_states}."
    } else {
      codes <- utils::head(unique(key_display(x_key[unmatched_rows], by)), 6L)
      where <- "Unmatched codes: {.val {codes}}."
    }
    switch(unmatched,
      inform = cli::cli_inform(c("!" = headline, i = where)),
      warn = cli::cli_warn(c(headline, i = where)),
      error = cli::cli_abort(c(headline, i = where))
    )
  }

  # Add only y's new columns, so identifiers the panel already carries are not
  # duplicated into a .x / .y pair.
  overlap <- setdiff(intersect(names(x), names(y)), by)
  if (length(overlap) > 0) {
    y <- y[, setdiff(names(y), overlap), drop = FALSE]
  }

  rel <- if (multiple == "all") "many-to-many" else "many-to-one"
  dplyr::left_join(x, y, by = by, relationship = rel)
}

# Paste the join columns into one comparable key per row. \r cannot occur in a
# FIPS code or name, so it separates columns without colliding with content.
key_string <- function(data, by) {
  cols <- lapply(by, function(b) as.character(data[[b]]))
  do.call(paste, c(cols, sep = "\r"))
}

# Turn internal keys back into something readable: the fips_code alone when it
# is one of the join columns, otherwise the whole key joined with +.
key_display <- function(keys, by) {
  parts <- strsplit(keys, "\r", fixed = TRUE)
  if ("fips_code" %in% by) {
    i <- match("fips_code", by)
    vapply(parts, function(p) p[[i]], character(1))
  } else {
    vapply(parts, function(p) paste(p, collapse = "+"), character(1))
  }
}

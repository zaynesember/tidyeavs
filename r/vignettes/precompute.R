## Knits the vignettes from their .Rmd.orig sources.
##
## The vignettes work with real EAVS data, which means downloading a few
## megabytes per survey year. Code that does that cannot run when the package is
## built: there may be no network, and CRAN would refuse it anyway. So each
## vignette keeps its runnable source as `<name>.Rmd.orig` and ships a knitted
## `<name>.Rmd` with the output already baked in. The shipped file is plain
## markdown with no live code, so building it needs nothing.
##
## The alternative—`eval = FALSE` everywhere—would leave every printed number
## hand-written, and hand-written numbers in a package whose whole claim is that
## the numbers are right will eventually be wrong. This way the output is real,
## and regenerating it is a deliberate act you can diff.
##
## Run from the package root, with a populated cache:
##   Rscript vignettes/precompute.R
##
## Then check the diff before committing. If a number moved, either the data or
## the package changed, and you want to know which.

library(knitr)

vignettes <- c(
  "getting-started",
  "missingness",
  "comparing-across-years",
  "survey-structure"
)

# The source tree, not whatever version happens to be installed. Without this
# the vignettes document a stale library copy, or fail outright if the package
# has never been installed.
pkgload::load_all(".", quiet = TRUE)

# Stop on the first failing chunk. knitr's default is to render the error text
# into the document and carry on, which would ship a vignette full of "could
# not find function" to users while this script reports success.
knitr::opts_chunk$set(error = FALSE)

old <- setwd("vignettes")
on.exit(setwd(old), add = TRUE)

for (v in vignettes) {
  src <- paste0(v, ".Rmd.orig")
  out <- paste0(v, ".Rmd")
  if (!file.exists(src)) {
    stop("missing vignette source: vignettes/", src)
  }
  message("knitting ", src)
  knitr::knit(src, output = out, quiet = TRUE)

  # Belt and braces: an error rendered as output is still an error.
  bad <- grep("^#> (Error|Warning in)", readLines(out), value = TRUE)
  if (length(bad) > 0) {
    stop("vignettes/", out, " contains rendered errors:\n  ",
         paste(utils::head(bad, 3), collapse = "\n  "))
  }
}

message("Done. ", length(vignettes), " vignette(s) written.")

# Render the GitHub report from any working directory.
args <- commandArgs(FALSE)
file_arg <- args[grep("^--file=", args)]
rdir <- dirname(normalizePath(sub("^--file=", "", file_arg[1]),
                              winslash = "/", mustWork = TRUE))
project <- dirname(rdir)

# Avoid escaped <U+...> sequences in generated image alt text on Windows.
if (.Platform$OS.type == "windows") {
  Sys.setlocale("LC_CTYPE", "English_United States.utf8")
}

knitr::knit(
  input = file.path(project, "rapport", "rapport.Rmd"),
  output = file.path(project, "rapport", "rapport.md"),
  quiet = TRUE
)

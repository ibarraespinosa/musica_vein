options(encoding = "UTF-8")
library(vein) # vein
library(sf) # spatial data
library(cptcity) # colour palettes
library(ggplot2) # plots
library(data.table) # faster data.frames
sessionInfo()

source("config/paths.R", encoding = "UTF-8")
source("scripts/wrf_grid.R", encoding = "UTF-8")

# number of monthly files already written in a folder
n_months <- function(d, what = "grid") {
  if (!dir.exists(d)) return(0L)
  length(list.files(
    d,
    pattern = paste0("^emis_", what, "_[0-9]{2}\\.rds$")
  ))
}

run_year <- function(kk) {
  post_dir <- paste0("post_", kk)
  if (dir.exists(post_dir)) {
    message("Skipping ", kk, ": ", post_dir, " already exists")
    return(invisible(NULL))
  }

  # Streets ####
  emi_file <- file.path(emi_dir, paste0("emis_", kk, ".csv.gz"))
  if (!file.exists(emi_file)) stop("Emissions file not found: ", emi_file)
  crs <- 3857
  osm_name <- "highway"
  roads_path <- roads_dir
  language <- "spanish" # english spanish portuguese
  if (n_months("post/streets", "street") < 12) {
    source("scripts/post_roads.R", encoding = "UTF-8", local = TRUE)
  } else {
    message("Streets already complete for ", kk)
  }

  # release the large street objects before gridding
  drop <- intersect(
    c(
      "emi", "nonmhc_m", "nmhc_m", "roads", "na_roads", "emis_street",
      "x", "dt", "dtpol", "i", "j", "k"
    ),
    ls()
  )
  if (length(drop) > 0) rm(list = drop)
  gc()

  # Grids ####
  crs <- 3857
  language <- "spanish" # english spanish portuguese
  for (dd in domains) {
    out_dir <- paste0("post/grids_", dd)
    if (n_months(out_dir, "grid") < 12) {
      wrf_file <- file.path(wrf_dir, paste0("wrfinput_d", dd))
      if (!file.exists(wrf_file)) stop("WRF input not found: ", wrf_file)
      g <- wrf_grid_sf(wrf_file)
      source("scripts/post_grids.R", encoding = "UTF-8", local = TRUE)
      system(paste0("mv post/grids ", out_dir))
    } else {
      message("d", dd, " grids already complete for ", kk)
    }

    drop <- intersect(c("g", "x", "f", "meta", "gx"), ls())
    if (length(drop) > 0) rm(list = drop)
    gc()
  }

  system(paste0("mv post post_", kk))
  invisible(NULL)
}

for (kk in years) {
  run_year(kk)
  gc()
}

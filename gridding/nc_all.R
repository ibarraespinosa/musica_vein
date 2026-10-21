# Write one NetCDF per year and domain from post_<year>/grids_<domain> ####
#
# Run from this folder after grid.R:
#   Rscript nc_all.R
#
# Skips year/domain combinations that do not exist yet or are incomplete.

options(encoding = "UTF-8")

source("config/paths.R", encoding = "UTF-8")

nc_no_run <- TRUE
source("scripts/nc.R", encoding = "UTF-8")

done <- character()

for (yy in years) {
  for (dd in domains) {
    dir_grids <- file.path(paste0("post_", yy), paste0("grids_", dd))
    if (!dir.exists(dir_grids)) {
      message("Skipping missing ", dir_grids)
      next
    }
    n <- length(list.files(
      dir_grids, pattern = "^emis_grid_[0-9]{2}\\.rds$"
    ))
    if (n < 12) {
      message("Skipping ", dir_grids, " (", n, "/12 months)")
      next
    }
    f <- nc_write(
      year = yy,
      domain = dd,
      dir_grids = dir_grids,
      dir_nc = "nc",
      wrfinput_dir = wrf_dir,
      evap_scenario = evap_scenario
    )
    done <- c(done, f)
  }
}

message("\nFiles written:")
for (f in done) message("  ", f)

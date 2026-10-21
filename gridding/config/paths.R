# Paths and settings for gridding + NetCDF generation ####
#
# Edit the three paths below before running. No road-network (gpkg) or WRF
# input files are included in this repository.
#
# 1) Emissions CSV files, one per year, named emis_<year>.csv.gz.
#    If you checked out this repository's `emis/` folder, use "../emis".
#    If `emis/` was skipped by a sparse checkout, either fetch it with
#        git sparse-checkout add emis
#    or point emi_dir to a folder with your own copies.
emi_dir <- "../emis"

# 2) Folder with the road network files (*_roads.gpkg).
roads_dir <- "/path/to/brazil_roads"

# 3) Folder with the WRF input files (wrfinput_d01, wrfinput_d02, ...).
wrf_dir <- "/path/to/wrfinputs"

# Years and domains to process. Each domain is matched to
# wrfinput_d<domain> and post/grids_<domain>.
years <- 2023:2025
domains <- c("01", "02")

# Evaporative scenario used for the NMHC total. All three SSP components
# are kept as variables, but NMHC only adds the selected one.
evap_scenario <- "SSP 4.5"

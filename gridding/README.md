# Gridding and NetCDF generation

Scripts to turn the annual `emis/emis_<year>.csv.gz` files into monthly
gridded emission NetCDFs for the WRF domains used in MUSICA VEIN.

This folder contains **only scripts**. The road network (`*_roads.gpkg`) and
WRF input files (`wrfinput_d01`, `wrfinput_d02`, ...) are not included; set
their paths in `config/paths.R`.

## Requirements

R (>= 4.2) with:

```r
install.packages(c(
  "vein", "sf", "data.table", "eixport", "ncdf4",
  "units", "pbapply", "ggplot2", "cptcity"
))
```

`vein` and `eixport` may need to be installed from GitHub:

```r
remotes::install_github(c("atmoschem/vein", "atmoschem/eixport"))
```

## Setup

```bash
git clone https://github.com/ibarraespinosa/musica_vein.git
cd musica_vein/gridding
```

Edit `config/paths.R`:

```r
emi_dir   <- "../emis"              # annual emis_<year>.csv.gz files
roads_dir <- "/path/to/brazil_roads" # folder with *_roads.gpkg
wrf_dir   <- "/path/to/wrfinputs"    # wrfinput_d01, wrfinput_d02, ...
years     <- 2023:2025
domains   <- c("01", "02")
```

If the repository's `emis/` folder was skipped by a sparse checkout, either
fetch it:

```bash
git sparse-checkout add emis
```

or point `emi_dir` to your own folder.

## Run

From this `gridding/` folder:

```bash
Rscript grid.R      # distribute emissions on roads and grid them
Rscript nc_all.R    # write nc/emissions_d0X_YYYY.nc
```

Both scripts are resumable:

- `grid.R` skips years whose `post_<year>` folder exists, streets that are
  complete, and domains that already have 12 grids.
- `post_grids.R` skips an existing monthly grid when it is newer than its
  street file, so you can regenerate streets without rebuilding grids.
- `nc_all.R` skips missing or incomplete domain folders.

## Outputs

```
post_<year>/grids_<domain>/emis_grid_01.rds ... emis_grid_12.rds
nc/emissions_d<domain>_<year>.nc
```

One NetCDF per year and domain, with 12 monthly records.

## NetCDF contents

- `time = 12`, monthly records with `time_bnds`
- 18 species: `CO`, `HC`, `NOx`, `NO`, `NO2`, `NH3`, `PM2.5`, `SO2`,
  `CO2`, `CH4`, `N2O`, `ETOH`, `PM10`, and the `NMHC_*` components
- `NMHC` = exhaust + the evaporative scenario selected by `evap_scenario`
  in `config/paths.R` (default `"SSP 4.5"`). It is not `HC`.
- All three SSP evaporative components are kept as separate `NMHC_*`
  variables. They are alternatives: do not sum them together.
- `cell_area` (km²)
- `hours_in_month` and `days_in_month`

Values are **monthly totals in g km⁻² month⁻¹**, exactly as in the grids.
No hourly profile is applied. To obtain an hourly mean, divide by
`hours_in_month`, then apply your own diurnal profile.

## Notes

- NOx, NO and NO2 are distributed with `lengthHDV`, which gives weight only
  to primary/trunk/motorway roads, preserving the regional totals.
- `PM` from the exhaust inventory is renamed to `PM2.5` before gridding.
- The emissions files contain three alternative evaporative SSP scenarios
  (`SSP 1.9`, `SSP 4.5`, `SSP 8.5`). They are not additive. `NMHC` uses only
  `evap_scenario`; the other two remain as separate variables.
- The grid is the regular lon/lat approximation built with
  `wrf_grid_sf()`; it uses `sf::st_make_grid()` because
  `eixport::wrf_grid()` overflows R's protection stack on the 300 x 444
  d02 grid.
- Runtime for 2023–2025 and two domains is roughly 1–2 hours on a recent
  laptop, depending on disk and CPU.

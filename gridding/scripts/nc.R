# NetCDF export of the monthly gridded emissions ####
#
# Reads the 12 monthly grids in `post_<year>/grids_<domain>` and writes one
# NetCDF per year and domain, e.g. `nc/emissions_d01_2023.nc`.
#
# The values are stored exactly as in the grids: monthly totals in
# g km-2 month-1. No hourly conversion and no temporal profile is applied.
# `hours_in_month` and `days_in_month` are included so users can build their
# own hourly profiles and convert with `value / hours_in_month`.
#
# `NMHC` is added as the sum of every `NMHC_*` grid (not `HC`).
#
# Usage from the project root:
#   year <- 2023
#   domain <- "01"              # "01" or "d01"
#   source("scripts/nc.R", encoding = "UTF-8")
#
# Or as a function:
#   source("scripts/nc.R", encoding = "UTF-8")   # only defines nc_write()
#   nc_write(year = 2023, domain = "01")
#
# `nc_all.R` loops over 2023:2025 and both domains.

suppressMessages({
  library(ncdf4)
  library(sf)
  library(units)
})

source("scripts/wrf_grid.R", encoding = "UTF-8")

nc_write <- function(year, domain, dir_grids = NULL, dir_nc = "nc",
                     wrfinput_dir = NULL, compression = 4,
                     g = NULL, verbose = TRUE) {

  # domain: "01", "1" or "d01" -> "01"
  dom <- gsub("^d", "", as.character(domain))
  dom <- sprintf("%02d", as.integer(dom))

  if (is.null(wrfinput_dir)) {
    wrfinput_dir <- if (exists("wrf_dir", inherits = TRUE)) {
      wrf_dir
    } else {
      "../wrfinputs"
    }
  }

  if (is.null(dir_grids)) {
    dir_grids <- file.path(sprintf("post_%d", year), paste0("grids_", dom))
  }
  wrf_file <- file.path(wrfinput_dir, paste0("wrfinput_d", dom))

  dir.create(dir_nc, showWarnings = FALSE, recursive = TRUE)
  file_nc <- file.path(
    dir_nc,
    sprintf("emissions_d%s_%d.nc", dom, year)
  )

  # 1) input files ####
  lf <- sort(list.files(
    dir_grids,
    pattern = "^emis_grid_[0-9]{2}\\.rds$",
    full.names = TRUE
  ))
  if (length(lf) != 12) {
    stop(
      "Expected 12 monthly grids in ", dir_grids, ", found ", length(lf)
    )
  }
  months <- as.integer(sub("^emis_grid_([0-9]{2})\\.rds$", "\\1", basename(lf)))
  if (!identical(sort(months), 1:12)) {
    stop("Monthly files are not named 01..12 in ", dir_grids)
  }

  if (verbose) message("\nReading ", length(lf), " grids from ", dir_grids)

  x0 <- readRDS(lf[1])
  if (!inherits(x0, "sf")) stop(basename(lf[1]), " is not an sf object")
  if ("id" %in% names(x0)) x0$id <- NULL

  # 2) grid geometry from the WRF domain ####
  if (is.null(g)) {
    if (!file.exists(wrf_file)) stop("WRF input not found: ", wrf_file)
    g <- wrf_grid_sf(wrf_file)
  }
  if (nrow(g) != nrow(x0)) {
    stop(
      "Grid has ", nrow(g), " cells but ", basename(lf[1]),
      " has ", nrow(x0)
    )
  }

  # the saved grids are `g` transformed to 3857; check that row order matches
  g_cmp <- st_transform(g, st_crs(x0))
  c1 <- st_coordinates(st_centroid(st_geometry(x0)))
  c2 <- st_coordinates(st_centroid(st_geometry(g_cmp)))
  if (max(abs(c1 - c2)) > 1) {
    stop(
      "The grid saved in ", dir_grids,
      " does not match the WRF grid (row order or geometry differs)"
    )
  }

  ll <- st_coordinates(st_centroid(st_geometry(g)))
  lon_v <- sort(unique(round(ll[, 1], 6)))
  lat_v <- sort(unique(round(ll[, 2], 6)))
  nlon <- length(lon_v)
  nlat <- length(lat_v)
  if (nlat * nlon != nrow(g)) {
    stop(
      "The grid is not regular: ", nrow(g), " cells != ",
      nlat, " x ", nlon
    )
  }
  icol <- match(round(ll[, 1], 6), lon_v)
  irow <- match(round(ll[, 2], 6), lat_v)
  if (anyNA(icol) || anyNA(irow)) {
    stop("Could not map the cell centres to a regular lon/lat grid")
  }

  # 3) species columns ####
  d0 <- st_set_geometry(x0, NULL)
  meta <- c("id", "region", "length", "lengthHDV")
  if ("lengthHDV" %in% names(d0)) {
    warning(
      "lengthHDV found in ", basename(lf[1]),
      "; it will be ignored. Did you apply the post_grids.R fix?"
    )
  }
  species <- setdiff(names(d0), meta)
  species <- species[vapply(
    d0[species],
    function(z) is.numeric(z) || inherits(z, "units"),
    logical(1)
  )]
  if (length(species) == 0) {
    stop("No numeric species columns found in ", basename(lf[1]))
  }
  if ("NMHC" %in% species) {
    warning("A raw NMHC column is present; it will be replaced by the NMHC_* sum")
    species <- setdiff(species, "NMHC")
  }

  nmhc_components <- grep("^NMHC_", species, value = TRUE)
  if (length(nmhc_components) == 0) {
    warning("No NMHC_* columns found; NMHC will not be created")
  }
  vars <- c(species, if (length(nmhc_components) > 0) "NMHC")

  if (verbose) {
    message("Species: ", paste(species, collapse = ", "))
    if (length(nmhc_components) > 0) {
      message("NMHC = ", paste(nmhc_components, collapse = " + "))
    }
  }

  # 4) read months into [time, lat, lon] arrays ####
  out <- setNames(
    lapply(vars, function(v) array(0, dim = c(12, nlat, nlon))),
    vars
  )

  for (m in seq_along(lf)) {
    x <- readRDS(lf[m])
    if (!identical(st_geometry(x), st_geometry(x0))) {
      stop(basename(lf[m]), " has a different grid than ", basename(lf[1]))
    }

    d <- st_set_geometry(x, NULL)
    if ("id" %in% names(d)) d$id <- NULL
    miss <- setdiff(species, names(d))
    if (length(miss) > 0) {
      stop(basename(lf[m]), " is missing: ", paste(miss, collapse = ", "))
    }

    d <- as.data.frame(lapply(d[species], as.numeric))
    names(d) <- species
    if (length(nmhc_components) > 0) {
      d$NMHC <- rowSums(d[, nmhc_components, drop = FALSE])
    }

    for (v in vars) {
      mm <- matrix(0, nlat, nlon)
      mm[cbind(irow, icol)] <- d[[v]]
      out[[v]][m, , ] <- mm
    }

    if (verbose) message("  month ", sprintf("%02d", m), " ok")
  }

  # 5) cell area (same 3857 geometry used by emis_grid) ####
  cell_area <- as.numeric(st_area(x0)) / 1e6
  area_arr <- matrix(0, nlat, nlon)
  area_arr[cbind(irow, icol)] <- cell_area

  # 6) time axis ####
  t0 <- as.POSIXct(sprintf("%d-01-01 00:00:00", year), tz = "UTC")
  starts <- seq(t0, by = "month", length.out = 12)
  ends <- seq(t0, by = "month", length.out = 13)[-1]
  hours <- as.numeric(difftime(ends, starts, units = "hours"))
  mids <- starts + as.difftime(hours / 2, units = "hours")
  time_vals <- as.numeric(difftime(mids, t0, units = "hours"))
  time_bnds <- cbind(
    as.numeric(difftime(starts, t0, units = "hours")),
    as.numeric(difftime(ends, t0, units = "hours"))
  )

  # 7) dimensions and variables ####
  d_time <- ncdim_def(
    "time", sprintf("hours since %d-01-01 00:00:00", year), time_vals,
    longname = "time"
  )
  d_nv <- ncdim_def("nv", "", 1:2, create_dimvar = FALSE)
  d_lat <- ncdim_def("lat", "degrees_north", lat_v, longname = "latitude")
  d_lon <- ncdim_def("lon", "degrees_east", lon_v, longname = "longitude")

  long_names <- c(
    "CO" = "carbon monoxide",
    "CO2" = "carbon dioxide",
    "CH4" = "methane",
    "FC" = "fuel consumption",
    "HC" = "hydrocarbons",
    "NO" = "nitric oxide",
    "NO2" = "nitrogen dioxide",
    "NOx" = "nitrogen oxides",
    "NH3" = "ammonia",
    "N2O" = "nitrous oxide",
    "ETOH" = "ethanol",
    "PM2.5" = "particulate matter < 2.5 um",
    "PM10" = "particulate matter < 10 um",
    "SO2" = "sulfur dioxide",
    "NMHC" = "total non-methane hydrocarbons",
    "NMHC_G_EXHAUST" = "non-methane hydrocarbons, exhaust, gasoline",
    "NMHC_E_EXHAUST" = "non-methane hydrocarbons, exhaust, ethanol",
    "NMHC_D_EXHAUST" = "non-methane hydrocarbons, exhaust, diesel",
    "NMHC_G_EVAPORATIVES_HISTORIC" =
      "non-methane hydrocarbons, evaporative, gasoline",
    "NMHC_E_EVAPORATIVES_HISTORIC" =
      "non-methane hydrocarbons, evaporative, ethanol"
  )
  lname <- function(n) {
    if (n %in% names(long_names)) long_names[[n]] else n
  }

  vars_nc <- list(
    ncvar_def(
      "time_bnds", sprintf("hours since %d-01-01 00:00:00", year),
      list(d_nv, d_time), prec = "double",
      longname = "time bounds"
    ),
    ncvar_def(
      "hours_in_month", "h", list(d_time), prec = "double",
      longname = "number of hours in the calendar month"
    ),
    ncvar_def(
      "days_in_month", "days", list(d_time), prec = "double",
      longname = "number of days in the calendar month"
    ),
    ncvar_def(
      "cell_area", "km2", list(d_lon, d_lat), missval = NA,
      prec = "float", longname = "grid cell area"
    )
  )

  # ncdf4 stores the dimensions in reverse order of this list, so pass
  # (lon, lat, time) to get (time, lat, lon) in the file
  for (v in vars) {
    vars_nc[[v]] <- ncvar_def(
      name = v,
      units = "g km-2 month-1",
      dim = list(d_lon, d_lat, d_time),
      missval = NA,
      longname = lname(v),
      prec = "float",
      compression = compression
    )
  }

  nc <- nc_create(file_nc, vars_nc, force_v4 = TRUE)

  ncvar_put(nc, "time", time_vals)
  ncvar_put(nc, "time_bnds", t(time_bnds))
  ncvar_put(nc, "hours_in_month", hours)
  ncvar_put(nc, "days_in_month", hours / 24)
  ncvar_put(nc, "cell_area", t(area_arr))
  for (v in vars) {
    ncvar_put(nc, v, aperm(out[[v]], c(3, 2, 1)))
    ncatt_put(nc, v, "cell_methods", "time: sum", prec = "text")
  }

  # 8) attributes ####
  ncatt_put(nc, "time", "bounds", "time_bnds", prec = "text")
  ncatt_put(nc, "time", "calendar", "standard", prec = "text")

  if ("NMHC" %in% vars) {
    ncatt_put(
      nc, "NMHC", "comment",
      paste0("sum of ", paste(nmhc_components, collapse = " + ")),
      prec = "text"
    )
  }

  ncatt_put(nc, 0, "Conventions", "CF-1.8")
  ncatt_put(
    nc, 0, "title",
    sprintf(
      "SEBR road-transport emissions, domain d%s, %d", dom, year
    )
  )
  ncatt_put(nc, 0, "source", "vein (https://github.com/atmoschem/vein)")
  ncatt_put(
    nc, 0, "history",
    paste0(
      "Created ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      " by scripts/nc.R"
    )
  )
  ncatt_put(
    nc, 0, "comment",
    paste(
      "Monthly totals of gridded road-transport emissions.",
      "Values are g/month/km2 and apply to the whole calendar month.",
      "Apply a temporal profile and divide by hours_in_month",
      "to obtain g/h/km2."
    )
  )
  ncatt_put(nc, 0, "domain", paste0("d", dom))
  ncatt_put(
    nc, 0, "units_comment",
    paste(
      "'month' refers to the calendar month, not a fixed 30-day month;",
      "see hours_in_month for the exact number of hours."
    )
  )
  ncatt_put(
    nc, 0, "grid",
    paste(
      "regular lon/lat approximation built with eixport::wrf_grid;",
      "cell_area computed on the EPSG:3857 geometry used by emis_grid"
    )
  )

  if (file.exists(wrf_file)) {
    ncw <- tryCatch(nc_open(wrf_file), error = function(e) NULL)
    if (!is.null(ncw)) {
      for (a in c(
        "DX", "DY", "MAP_PROJ", "TRUELAT1", "TRUELAT2",
        "STAND_LON", "CEN_LAT", "CEN_LON"
      )) {
        att <- tryCatch(
          ncatt_get(ncw, 0, a),
          error = function(e) NULL
        )
        if (!is.null(att) && isTRUE(att$hasatt)) {
          ncatt_put(nc, 0, a, att$value)
        }
      }
      nc_close(ncw)
    }
  }

  nc_close(nc)

  if (verbose) {
    message("\nNetCDF: ", file_nc)
    message(
      "dims: time = 12, lat = ", nlat, ", lon = ", nlon
    )
    message("vars: ", paste(vars, collapse = ", "))
  }

  invisible(file_nc)
}

# auto-run when sourced with `year` and `domain` defined
if (!isTRUE(get0("nc_no_run", ifnotfound = FALSE)) &&
    exists("year") && exists("domain")) {
  nc_write(year = year, domain = domain)
}

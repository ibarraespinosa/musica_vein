# Build the same regular lon/lat grid as eixport::wrf_grid() ####
#
# eixport::wrf_grid() uses raster::rasterToPolygons(), which overflows R's
# protection stack on the 300 x 444 d02 grid. This version builds the same
# cells with sf::st_make_grid() and returns them in the same order as
# eixport::wrf_grid() (north to south, west to east).

wrf_grid_sf <- function(wrf_file) {
  suppressMessages({
    library(ncdf4)
    library(sf)
  })

  nc <- nc_open(wrf_file)
  on.exit(nc_close(nc), add = TRUE)
  lat <- ncvar_get(nc, "XLAT")
  lon <- ncvar_get(nc, "XLONG")
  nlat <- ncatt_get(nc, 0, "SOUTH-NORTH_PATCH_END_UNSTAG")$value
  nlon <- ncatt_get(nc, 0, "WEST-EAST_PATCH_END_UNSTAG")$value

  bb <- st_bbox(
    c(
      xmin = min(lon), xmax = max(lon),
      ymin = min(lat), ymax = max(lat)
    ),
    crs = 4326
  )

  g <- st_sf(
    geometry = st_make_grid(bb, n = c(nlon, nlat), what = "polygons")
  )

  # rasterToPolygons() returns cells north-to-south, west-to-east
  ll <- st_coordinates(st_centroid(st_geometry(g)))
  g <- g[order(-round(ll[, 2], 6), round(ll[, 1], 6)), , drop = FALSE]
  g$id <- seq_len(nrow(g))
  g
}

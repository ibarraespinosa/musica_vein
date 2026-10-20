dir.create("post")
dir.create("post/grids")

switch(
  language,
  "portuguese" = cat("Distribuindo os comprimentos na grade\n"),
  "english" = cat("Gridding lengths\n"),
  "spanish" = cat("Distribuyendo en la grilla\n")
)

f <- list.files(
  path = "post/streets/",
  pattern = "emis_street",
  full.names = T
)


# keep only the emission species; drop road metadata (region, length,
# lengthHDV) that was used to distribute the emissions but is not a pollutant
meta <- c(
  "osm_id", "name", "highway", "waterway", "aerialway", "barrier",
  "man_made", "z_order", "other_tags", "region", "length", "lengthHDV"
)

for (j in seq_along(f)) {
  out <- gsub("street", "grid", f[j])
  if (file.exists(out) && file.mtime(out) >= file.mtime(f[j])) {
    message("  skipping existing ", basename(out))
    next
  }

  x <- readRDS(f[j])

  x <- x[, setdiff(names(x), meta)]

  x <- st_crop(x, st_as_sfc(st_bbox(g)))

  gx <- emis_grid(spobj = x, g = g, sr = crs)

  saveRDS(gx, out)

  rm(gx)
  gc()
}

switch(
  language,
  "portuguese" = message("\n\nArquivos em:"),
  "english" = message("\n\nFiles in:"),
  "spanish" = message("\n\nArchivos en:")
)

message("post/grid/emi_grid_XX.rds\n")

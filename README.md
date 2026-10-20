# musica_vein
[A Century of Vehicular Emissions in Brazil: Unveiling the Impacts of Unique Fuel Mix on Air Quality](https://pubs.acs.org/doi/10.1021/acs.est.5c08400)

<img width="949" height="241" alt="image" src="https://github.com/user-attachments/assets/c4182567-965b-4425-a781-1b608a7e78d6" />

<img width="500" height="269" alt="image" src="https://github.com/user-attachments/assets/968d4102-017e-4366-9377-be77537977da" />

## Gridding and NetCDF generation

The [`gridding/`](gridding) folder contains the scripts that convert the
annual `emis/` files into monthly gridded emission NetCDFs. The scripts are
standalone: road-network (gpkg) and WRF input files are not included, and
their paths are set in [`gridding/config/paths.R`](gridding/config/paths.R).
See [`gridding/README.md`](gridding/README.md) for usage.

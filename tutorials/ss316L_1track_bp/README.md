# `ss316L_1track_bp` — single laser track on a bare SS316L plate

A `laserbeamFoam` case: one 800 µm laser track across a flat SS316L substrate,
no powder.

## Process conditions

| | |
| --- | --- |
| Material | SS316L |
| Laser power | 200 W |
| Scan speed | 200 mm/s |
| Track length | 800 µm (→ 4000 µs) |
| Spot radius | 36 µm (1/e² ), 1064 nm |
| Shielding gas | argon |

## Domain

Built in `system/blockMeshDict` with **z up**, then rotated by `Allrun` with
`transformPoints "rotate=((0 1 0) (0 0 1))"`, which maps `(x,y,z) → (x,-z,y)`.
The solver needs the laser to travel along `+y`.

| | as built | as the solver sees it |
| --- | --- | --- |
| Across the track (width) | x, 0 → 400 µm | x, 0 → 400 µm |
| Along the track (length) | y, 0 → 1000 µm | z, 0 → 1000 µm |
| Depth | z, 0 → 700 µm | y, −700 → 0 µm |

- Metal: 500 µm deep. Gas: 200 µm above it.
- Cells are 10 µm cubes: 40 × 100 × 70 = **280 000 cells**.
- The track runs `z = 100 µm → 900 µm` at `x = 200 µm`, so it is centred in
  both length and width.

The substrate is written by `setSolidFraction`, which reads
`system/bedPlateDict`. That utility applies the bed plate *inside* its loop
over particles, so `constant/location` must hold at least one particle even
for a bare plate — it holds one dummy particle of radius 0.

## Running

```bash
cd tutorials/ss316L_1track_bp
./Allrun
```

`Allrun` reads the rank count from `system/decomposeParDict` (currently 8), so
change it in that one place. It runs `blockMesh`, `setSolidFraction`,
`transformPoints`, `decomposePar`, the solver, `reconstructPar` and
`foamToVTK`.

Expect a long run: 4500 µs of physics with `maxDeltaT` at 5e-7 s is at least
9000 steps, and the Courant limit will normally push the step well below that.

## Material properties, and how they differ from the IN718 tutorials

`tutorials/ch_1x5_bp` and `tutorials/ch_5x5` use **IN718** properties, not
SS316L — the `ch_5x5/README.md` claim of SS316L is wrong. Every metal property
here was replaced. The IN718 column is kept only so the change is auditable;
none of those numbers appear in the dictionaries.

| Property | SS316L (this case) | IN718 (`ch_*`) | Where |
| --- | --- | --- | --- |
| `nu` (m²/s) | 7.9e-7 | 6.7e-7 | `physicalProperties.metal` |
| `rho` (kg/m³) | 7430 | 7600 | `physicalProperties.metal` |
| `elec_resistivity` (Ω·m) | 1.25e-6 | 5.78e-6 | `physicalProperties.metal` |
| `Tsolidus` (K) | 1658 | 1493 | `physicalProperties.metal` |
| `Tliquidus` (K) | 1723 | 1609 | `physicalProperties.metal` |
| `LatentHeat` (J/kg) | 2.70e5 | 2.70e5 | `physicalProperties.metal` |
| `beta` (1/K) | 5.85e-5 | 1.3e-5 | `physicalProperties.metal` |
| `table_kappa` | k = 9.25 + 0.0157·T, liquid 34 | 8.55 → 28 | `physicalProperties.metal` |
| `table_cp` | cp = 462 + 0.134·T, liquid 830 | 433.9 → 720 | `physicalProperties.metal` |
| `sigma` (N/m) | 1.60 | 1.89 | `phaseProperties` |
| `dsigmadT` (N/m/K) | −0.8e-4 | −1.1e-4 | `phaseProperties` |
| `Tvap` (K) | 3090 | 3186 | `phaseProperties` |
| `Mm` (kg/mol) | 0.0558 | 0.0585 | `phaseProperties` |
| `LatentHeatVap` (J/kg) | 7.45e6 | 6.30e6 | `phaseProperties` |
| `e_num_density` (1/m³) | 1.60e29 | 5e29 | `LaserProperties` |

Unchanged because they do not depend on the metal: `physicalProperties.gas`
(argon), `g`, `momentumTransport`, `fvSchemes`, `fvSolution`, and the laser
geometry settings `V_incident`, `laserRadius`, `N_sub_divisions`,
`wavelength`, `Radius_Flavour`.

### Absorptivity

`elec_resistivity` and `e_num_density` together set how much laser light the
metal absorbs, through the Drude model plus the Fresnel equations in
`laserHeatSource.C`. On a flat surface at normal incidence:

| resistivity (Ω·m) | n_e (1/m³) | absorptivity |
| --- | --- | --- |
| 5.78e-6 | 5e29 | 57.5% — the IN718 tutorials |
| 1.25e-6 | 5e29 | 31.5% |
| **1.25e-6** | **1.60e29** | **28.9% — this case** |

28.9% matches the measured 30–35% for SS316L at 1064 nm. The IN718 cases sit
much higher because their resistivity was raised roughly 4.6× above the
physical value (the dictionary comment there reads `original 1.25e-6`), which
absorbs more power than a flat surface physically would.

**If the melt pool comes out too shallow, `elec_resistivity` is the first
thing to revisit** — it moves absorptivity far more than `e_num_density` does.

`e_num_density` is derived from SS316L itself: `n = Z·ρ·N_A/M` with two free
electrons per atom, `2 × 7430 / 0.0558 × 6.022e23 = 1.60e29`.

### Two values worth checking against your own reference

- **`dsigmadT`** — published SS316L values span −0.8e-4 to −4.3e-4 N/m/K
  (the high end is Khairallah et al. 2016). More negative gives a wider,
  shallower pool. This case uses the low-sulfur end.
- **`beta`** — 5.85e-5 1/K is the volumetric expansion of liquid SS316L.
  Buoyancy is a minor effect here next to Marangoni and recoil pressure.

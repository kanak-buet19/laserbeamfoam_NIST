/*--------------------------------*- C++ -*----------------------------------*\
  =========                 |
  \\      /  F ield         | OpenFOAM: The Open Source CFD Toolbox
   \\    /   O peration     | Website:  https://openfoam.org
    \\  /    A nd           | Version:  10
\*---------------------------------------------------------------------------*/
FoamFile
{
    version     2.0;
    format      ascii;
    class       dictionary;
    location    "constant";
    object      physicalProperties.metal;
}
// * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * //
//
// Stainless steel 316L.
//
// Literature values for SS316L throughout. See README.md in this case folder
// for the sources and for how each value compares with the IN718 tutorials.
//
// ---------------------------------------------------------------------------

viscosityModel  constant;

// Liquid SS316L: mu ~ 5.9e-3 Pa.s at the melting point, nu = mu/rho.
nu               7.9e-7;

rho              7430;        // kg/m^3, liquid at Tm.

// Electrical resistivity of SS316L near melting, ohm.m. Feeds the Drude
// absorption model: with e_num_density it gives 29% absorptivity on a flat
// surface at normal incidence. This is the strongest single knob on absorbed
// power - if the melt pool comes out too shallow, revisit this first.
// See README.md.
elec_resistivity  1.25e-6;


// Thermal conductivity [W/(m.K)]
// Solid branch follows k = 9.25 + 0.0157*T ; liquid held at ~34 W/(m.K).
table_kappa
(
    (300    13.4)
    (400    15.5)
    (500    17.1)
    (600    18.7)
    (700    20.2)
    (800    21.8)
    (900    23.4)
    (1000   25.0)
    (1100   26.5)
    (1200   28.1)
    (1300   29.7)
    (1400   31.2)
    (1500   32.8)
    (1600   34.4)
    (1658   34.4)
    (1723   34.0)
    (2000   34.0)
    (3000   34.0)
    (5000   34.0)
);

// Specific heat capacity [J/(kg.K)]
// Solid branch follows cp = 462 + 0.134*T ; liquid ~ 830 J/(kg.K).
table_cp
(
    (300    470)
    (400    516)
    (500    529)
    (600    542)
    (700    556)
    (800    569)
    (900    583)
    (1000   596)
    (1100   609)
    (1200   623)
    (1300   636)
    (1400   650)
    (1500   663)
    (1600   676)
    (1658   684)
    (1723   830)
    (2000   830)
    (3000   830)
    (5000   830)
);

Tsolidus    1658;
Tliquidus   1723;
LatentHeat  2.70e5;           // J/kg, heat of fusion
beta        5.85e-5;          // 1/K, volumetric thermal expansion (Boussinesq).


// ************************************************************************* //

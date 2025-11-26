/*--------------------------------*- C++ -*----------------------------------*\
  =========                 |
  \\      /  F ield         | OpenFOAM: The Open Source CFD Toolbox
   \\    /   O peration     | Website:  https://openfoam.org
    \\  /    A nd           | Version:  10
     \\/     M anipulation  |
\*---------------------------------------------------------------------------*/
FoamFile
{
    format      ascii;
    class       dictionary;
    location    "constant";
    object      physicalProperties.water;
}
// * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * //

viscosityModel  constant;

nu               6.7e-7;

rho              7500; // original 7578

elec_resistivity        2.5e-6; //original 1.25e-6



table_kappa
(
    (300    9.0)
    (400    11.0)
    (500    13.0)
    (600    18.0)
    (800    21.0)
    (1000   27.0)
    (1100   27.0)
    (1300   33.36)
    (1533   34.48)
    (1609   34.48)
    (2500   36.72)
    (5000   36.72)
);

// Specific heat capacity table [J/(kg·K)]
table_cp
(
    (300    440)
    (400    460)
    (500    480)
    (600    500)
    (800    540)
    (1100   630) // previous 680
    (1200   630)
    (1300   640)
    (1533   710)
    (1609   710)
    (2500   770)
    (5000   770) //changed from 800, to increase width
);



   
        Tsolidus 1533;
        Tliquidus 1609;
    LatentHeat 230e3;
    beta    1.3e-5;


// ************************************************************************* //

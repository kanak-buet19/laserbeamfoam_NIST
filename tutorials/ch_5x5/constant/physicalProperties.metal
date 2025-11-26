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

nu               6.7e-7;       //Kinematic viscositu (mu/rho)

rho              7600;      //Used polynomial in paper

elec_resistivity  5.78e-6; //original 1.25e-6




// Thermal conductivity table [W/(m·K)]

table_kappa
(
    (300    8.55)
    (400    10.45)
    (500    12.35)
    (600    17.10)
    (800    19.95)
    (1000   25.65)
    (1100   25.65)
    (1300   27)
    (1531   28)
    (1612   28)
    (2500   28)
    (5000   28)
);

// table_kappa
table_cp
(
    (298   433.9)
    (400   463.8)
    (500   484.0)
    (600   500.4)
    (700   517.0)
    (800   536.2)
    (1100   611.3)
    (1200   635.5)
    (1300   652.2)
    (1400   654.9)
    (1493   637.9)
    (1609   720)
    (2000   720)
    (5000   720)
);

    Tsolidus 1493;
    Tliquidus 1609;
    LatentHeat 270e3; //Latent Heat of Fusion
    beta    1.3e-5;     //Thermal expansion co-efficient


// ************************************************************************* //
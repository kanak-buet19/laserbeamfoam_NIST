{
    const scalarField& alpha1I = alpha1;
    const scalarField& TI = T;
    scalarField& kappaI = kappa;
    scalarField& cpI = cp;
    
    forAll(kappaI, celli)
    {
        if (isPowder[celli] > 0.5)
        {
            // Cell is powder - check if it's above liquidus
            if (TI[celli] > Tliquidus1.value())
            {
                // Above liquidus: use tabular thermal conductivity for metal
                kappaI[celli] = kappaTab_m(TI[celli]);
            }
            else
            {
                // Below liquidus: use powder thermal conductivity
                kappaI[celli] = kappaPowder.value();
            }
        }
        else
        {
            // Standard mixture rule for non-powder regions (gas, substrate, etc.)
            kappaI[celli] =
                (
                    max(min(alpha1I[celli], 1.0), 0.0)
                  *kappaTab_m(TI[celli])
                )
              + (
                    (1.0 - max(min(alpha1I[celli], 1.0), 0.0))
                  *polykappa_g.value(TI[celli])
                );
        }
        
        // Specific heat capacity (same for all regions, uses tabular value)
        cpI[celli] =
            (
                max(min(alpha1I[celli], 1.0), 0.0)
              *cpTab_m(TI[celli])
            )
          + (
                (1.0 - max(min(alpha1I[celli], 1.0), 0.0))
              *polycp_g.value(TI[celli])
            );
    }
    
    kappa.correctBoundaryConditions();
    cp.correctBoundaryConditions();
}
# Telemetry limits

The project uses public spacecraft engineering references together with clearly identified mission settings for an educational 6U Earth-observation satellite. These values are realistic demonstration limits. They are not live limits copied from an operational NASA or ISRO spacecraft.

| Parameter | Normal | Warning band | Critical band | Basis |
|---|---:|---:|---:|---|
| Processor temperature | 10 to 60 °C | -10 to 10 or 60 to 80 | Outside -10 to 80 | Public NASA telemetry-limit example |
| Battery temperature | 0 to 35 °C | -10 to 0 or 35 to 40 | Outside -10 to 40 | NASA lithium-ion component range with an inner project warning band |
| Payload temperature | -20 to 40 °C | -30 to -20 or 40 to 50 | Outside -30 to 50 | NASA instrument operating and survival ranges |
| Attitude pointing error | 0 to 0.2° | 0.2 to 1° | Above 1° | Earth-observation pointing-mode setting |
| Battery state of charge | 30 to 100% | 20 to 30 | Below 20 | Mission setting |
| Battery voltage | 7.2 to 8.3 V | 6.4 to 7.2 or 8.3 to 8.4 | Outside 6.4 to 8.4 | Two-cell lithium-ion mission setting |
| Regulated power bus | 4.75 to 5.25 V | 4.5 to 4.75 or 5.25 to 5.5 | Outside 4.5 to 5.5 | Five-volt bus mission setting |
| Solar-array current | 0.5 to 4.3 A | 0.1 to 0.5 or 4.3 to 4.8 | Outside 0.1 to 4.8 while in sunlight | NASA instrumentation example plus project warning bands |
| Battery current | -3.5 to 0.5 A | -4 to -3.5 or 0.5 to 0.75 | Outside -4 to 0.75 | NASA charge/discharge monitoring example |
| Computer resets in current orbit | 0 | 1 to 2 | Above 2 | Watchdog and reset diagnostic setting |
| Reaction-wheel speed | -4000 to 4000 rpm | 4000 to 5000 in either direction | Beyond 5000 | Published NASA reaction-wheel survey |
| Spacecraft angular rate | -0.5 to 0.5 °/s | 0.5 to 1 in either direction | Beyond 1 | Nominal pointing-mode setting |
| Onboard storage used | 0 to 80% | 80 to 95 | Above 95 | Mission operations setting |
| Payload operational status | Idle, ready, or imaging | None | Fault | Mission-unique payload health setting |
| Communication-link health | 90 to 100% | 70 to 90% | Below 70% during contact | Receiver-lock and valid-packet setting |

## Public references

- NASA component temperature requirements: https://ntrs.nasa.gov/api/citations/20010091676/downloads/20010091676.pdf
- NASA processor telemetry-limit example: https://ntrs.nasa.gov/api/citations/20230001722/downloads/OnAIR%20%28Smith%20Mar%202%202023%29.pdf?attachment=true
- NASA reaction-wheel survey: https://discovery.larc.nasa.gov/PDF_FILES/ATR-2011%285389%29-2_ReactionWheelSurvey.pdf
- NASA spacecraft instrumentation: https://ntrs.nasa.gov/api/citations/19650020180/downloads/19650020180.pdf
- NASA spacecraft power telemetry: https://ntrs.nasa.gov/api/citations/19710001181/downloads/19710001181.pdf?attachment=true
- ISRO battery telemetry example: https://new1.isro.gov.in/ISRO_EN/FlightDemonstration_Si-Gr_anode.html

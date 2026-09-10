from __future__ import annotations

import math

SCIENTIFIC_CONSTANTS: dict[str, float] = {
    "pi": math.pi,
    "e": math.e,
    "tau": math.tau,
    "g": 9.80665,
    "c": 299_792_458.0,
    "G": 6.67430e-11,
    "h": 6.62607015e-34,
    "k": 1.380649e-23,
    "mu0": 1.25663706212e-6,
    "eps0": 8.8541878128e-12,
    "NA": 6.02214076e23,
    "R": 8.31446261815324,
    "F": 96485.33212331001,
    "atm": 101325.0,
    "Vm": 22.413969545014137,
}

CONSTANT_ALIASES: dict[str, str] = {
    "epsilon0": "eps0",
    "varepsilon0": "eps0",
}

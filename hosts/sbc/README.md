# SBC hosts

- [ROCK 5C / 5C Lite](rock5c.md): `alluvium` and `basidium`, running Klipper.
- [Google Tomato](tomato.md): `colluvium`, headless MT8195, booting a USB installer and installing to eMMC.

The host group describes the board form factor. Common defaults and shared Wi-Fi
secrets live in `modules/sbc.nix` and `secrets/sbc.yaml`.
`modules/printer.nix` imports the SBC defaults and enables Klipper, Moonraker
and Mainsail. Alluvium and Basidium opt into printer services by importing this
role and set their own `printerConfig`; Colluvium imports only the SBC defaults.
Wi-Fi is enabled by default for SBCs and can be disabled per host. Firmware
is selected by each hardware module (Tomato AX200, ROCK 5C AIC8800).
